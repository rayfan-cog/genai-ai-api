import base64
import html
import logging
import re
from collections.abc import Iterable
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse

import requests
from google.cloud import storage
from google.genai import types

from gemini_config import GeminiConfig
from schemas import (
    Grounding,
    HarmBlockThreshold,
    HarmCategory,
    RequestBody,
)
from url_validator import safe_get
from utils import get_mime_type

logger = logging.getLogger(__name__)

_JST = timezone(timedelta(hours=9))


def _append_datetime_to_instruction(instruction: str) -> str:
    """system_instruction の末尾に現在の日時（JST）を付与する。"""
    now = datetime.now(_JST).strftime("%Y-%m-%d %H:%M JST")
    return f"{instruction}\n\n現在の日時: {now}"


# ---- URL Formatting Constants ----
ALLOWED_SCHEMES = {"http", "https"}
REDIRECT_HOSTS = {"vertexaisearch.cloud.google.com"}
STRIP_SUBDOMAIN_PREFIXES = ("www.",)


def _download_blob_into_memory(gcs_uri: str, storage_client: storage.Client) -> bytes:
    """Downloads a file from GCS into memory given its full gs:// URI."""
    parsed_uri = urlparse(gcs_uri)
    bucket_name = parsed_uri.netloc
    blob_name = parsed_uri.path.lstrip("/")

    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(blob_name)
    contents = blob.download_as_bytes()
    logger.debug(f"Successfully downloaded {gcs_uri} into memory.")
    return contents


def merge_generation_parameters(
    request_body: RequestBody, default_config: GeminiConfig
) -> dict[str, any]:
    """
    Merges generation parameters from the request with default values.
    Request values take precedence.
    """
    # 1. Start with defaults from the deployed config
    merged_params = {
        "temperature": default_config.temperature,
        "max_output_tokens": default_config.max_output_tokens,
        "top_p": default_config.top_p,
        "top_k": default_config.top_k,
        "candidate_count": default_config.candidate_count,
        "system_instruction": default_config.system_instruction,
    }

    # 2. Get validated parameters from the request body.
    #    `exclude_unset=True` ensures we only get parameters that were actually in the request.
    request_params = request_body.dict(include=merged_params.keys(), exclude_unset=True)

    # 3. Override defaults with request parameters
    merged_params.update(request_params)

    return merged_params


def _upload_single_file(
    file_content: str, filename: str, bucket_name: str, storage_client: storage.Client
) -> str:
    """Uploads a single base64 encoded file to GCS and returns its URI."""
    file_data = base64.b64decode(file_content)
    mime_type = get_mime_type(filename)
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(f"uploads/{filename}")

    logger.debug(f"Uploading file: {filename} ({mime_type}) to GCS.")
    blob.upload_from_string(file_data, content_type=mime_type)

    gcs_uri = f"gs://{bucket_name}/{blob.name}"
    logger.debug(f"Successfully uploaded file to GCS: {gcs_uri}")
    return gcs_uri


def prepare_gemini_request(
    request_body: RequestBody, config: GeminiConfig, storage_client: storage.Client
) -> tuple[list[types.Content], types.GenerateContentConfig]:
    """Prepares all components required for the Gemini API call."""
    # 1. Prepare contents (history, files, and current input)
    contents = []
    if request_body.chat_history:
        for item in request_body.chat_history:
            parts = item.get("parts", [])
            if isinstance(parts, str):
                parts = [types.Part(text=parts)]
            else:
                parts = [types.Part(**part) for part in parts]
            contents.append(types.Content(role=item["role"], parts=parts))
        logger.debug(f"Added {len(request_body.chat_history)} messages from chat history.")

    user_parts = []
    if request_body.files:
        for file_info in request_body.files:
            mime_type = get_mime_type(file_info.filename)
            file_part = None

            if file_info.content:
                # Case 1: File content is provided in the request payload
                if config.pass_file_by_uri:
                    # Upload is required to get a GCS URI
                    if not config.gcs_bucket_name:
                        raise ValueError("GCS bucket name not configured for file upload.")
                    gcs_uri = _upload_single_file(
                        file_content=file_info.content,
                        filename=file_info.filename,
                        bucket_name=config.gcs_bucket_name,
                        storage_client=storage_client,
                    )
                    logger.debug(f"Preparing file part using uploaded GCS URI: {gcs_uri}")
                    file_part = types.Part.from_uri(file_uri=gcs_uri, mime_type=mime_type)
                else:
                    # Use the provided content directly, no GCS interaction needed
                    logger.debug(
                        f"Preparing file part using direct content for {file_info.filename}"
                    )
                    file_bytes = base64.b64decode(file_info.content)
                    file_part = types.Part.from_bytes(data=file_bytes, mime_type=mime_type)

            elif file_info.gcs_uri:
                # Case 2: GCS URI is provided in the request payload
                if config.pass_file_by_uri:
                    # Use the provided GCS URI directly
                    logger.debug(f"Preparing file part using provided GCS URI: {file_info.gcs_uri}")
                    file_part = types.Part.from_uri(file_uri=file_info.gcs_uri, mime_type=mime_type)
                else:
                    # Download the file content from GCS URI
                    logger.debug(f"Preparing file part by downloading from: {file_info.gcs_uri}")
                    file_bytes = _download_blob_into_memory(file_info.gcs_uri, storage_client)
                    file_part = types.Part.from_bytes(data=file_bytes, mime_type=mime_type)

            else:
                raise RuntimeError(
                    f"Invalid FileInput for {file_info.filename}: no content or gcs_uri."
                )

            if file_part:
                user_parts.append(file_part)

    user_parts.append(types.Part.from_text(text=request_body.input_text))
    contents.append(types.Content(role="user", parts=user_parts))

    # 2. Prepare tools
    tools = []
    if request_body.grounding and Grounding.WEB.value in str(request_body.grounding):
        logger.debug("Web grounding is enabled. Preparing Google Search tool.")
        tools.append(types.Tool(google_search=types.GoogleSearch()))
    if request_body.grounding and Grounding.URL_CONTEXT.value in str(request_body.grounding):
        logger.debug("URL context is enabled. Preparing URL context tool.")
        tools.append(types.Tool(url_context=types.UrlContext))

    # 3. Prepare generation config
    final_generation_params = merge_generation_parameters(request_body, config)

    # 現在の日時を system_instruction に付与する
    if final_generation_params.get("system_instruction"):
        final_generation_params["system_instruction"] = _append_datetime_to_instruction(
            final_generation_params["system_instruction"]
        )

    safety_settings = {
        HarmCategory.HARM_CATEGORY_HATE_SPEECH.value: HarmBlockThreshold.BLOCK_NONE.value,
        HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT.value: HarmBlockThreshold.BLOCK_NONE.value,
        HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT.value: HarmBlockThreshold.BLOCK_NONE.value,
        HarmCategory.HARM_CATEGORY_HARASSMENT.value: HarmBlockThreshold.BLOCK_NONE.value,
    }
    safety_settings_list = [
        types.SafetySetting(category=category, threshold=threshold)
        for category, threshold in safety_settings.items()
    ]

    config_kwargs: dict = {
        **final_generation_params,
        "safety_settings": safety_settings_list,
        "tools": tools,
    }
    if request_body.thinking_budget is not None:
        config_kwargs["thinking_config"] = types.ThinkingConfig(
            thinking_budget=request_body.thinking_budget
        )

    final_config = types.GenerateContentConfig(**config_kwargs)
    logger.debug(f"Final generation config: {final_config}")

    return contents, final_config


def call_gemini_api(
    model_id: str,
    contents: list[types.Content],
    generation_config: types.GenerateContentConfig,
    genai_client,
) -> types.GenerateContentResponse:
    """Calls the Gemini API with the prepared components."""
    logger.info(f"Generating content with model: {model_id}")
    response = genai_client.models.generate_content(
        model=model_id,
        contents=contents,
        config=generation_config,
    )
    logger.info("Successfully generated content.")
    return response


def call_gemini_api_structured(
    model_id: str,
    contents: list[types.Content],
    generation_config: types.GenerateContentConfig,
    genai_client,
    response_schema: any,
) -> types.GenerateContentResponse:
    """Calls the Gemini API with structured output schema."""
    logger.info(f"Generating structured content with model: {model_id}")

    try:
        # Pydanticスキーマをdict形式に変換
        if hasattr(response_schema, "model_json_schema"):
            schema_dict = response_schema.model_json_schema()
            logger.info(f"Converted Pydantic schema to JSON: {schema_dict}")
        else:
            schema_dict = response_schema
            logger.info(f"Using provided schema dict: {schema_dict}")

        # 新しいGenerateContentConfigを作成（元のconfigをコピー）
        structured_config = types.GenerateContentConfig(
            temperature=generation_config.temperature,
            max_output_tokens=generation_config.max_output_tokens,
            top_p=generation_config.top_p,
            top_k=generation_config.top_k,
            candidate_count=generation_config.candidate_count,
            safety_settings=generation_config.safety_settings,
            # toolsは構造化出力と併用できないため除外
            response_schema=schema_dict,
            response_mime_type="application/json",
        )

        logger.info(
            f"Structured config created - response_mime_type: {structured_config.response_mime_type}"  # noqa: E501
        )

        response = genai_client.models.generate_content(
            model=model_id,
            contents=contents,
            config=structured_config,
        )

        logger.info(f"Raw structured response: {response.text}")
        logger.info("Successfully generated structured content.")
        return response

    except Exception as e:
        logger.error(f"Structured output failed with error: {e}", exc_info=True)
        logger.warning("Falling back to regular API call without structured output.")

        # フォールバック: 構造化出力が失敗した場合は通常の呼び出しに戻す
        fallback_config = types.GenerateContentConfig(
            temperature=generation_config.temperature,
            max_output_tokens=generation_config.max_output_tokens,
            top_p=generation_config.top_p,
            top_k=generation_config.top_k,
            candidate_count=generation_config.candidate_count,
            safety_settings=generation_config.safety_settings,
        )

        return call_gemini_api(model_id, contents, fallback_config, genai_client)


def extract_text_without_thinking(response: types.GenerateContentResponse) -> str:
    """Gemini レスポンスからthinkingパートを除いたテキストを返す。

    gemini-2.5-flash 等のthinkingモデルは response.text にthought=True のパートを
    含める場合があるため、利用者向け出力には必ずこの関数を使う。
    """
    parts = []
    for candidate in getattr(response, "candidates", []) or []:
        for part in getattr(getattr(candidate, "content", None), "parts", []) or []:
            if not getattr(part, "thought", False):
                text = getattr(part, "text", None)
                if text:
                    parts.append(text)
    return "".join(parts)


def format_gemini_response(response: types.GenerateContentResponse, grounding_enabled: bool) -> str:
    """Formats the raw Gemini API response into a final string."""
    output = response.text
    if grounding_enabled:
        output += "\n### 参照した情報\n" + urls_markdown_grouped_by_domain(response)
    return output


# ---- URL Formatting Helpers ----
def _is_http_url(u: str | None) -> bool:
    if not isinstance(u, str):
        return False
    try:
        p = urlparse(u)
    except Exception:
        return False
    return p.scheme in ALLOWED_SCHEMES and bool(p.netloc)


def _normalize_domain_from_netloc(netloc: str) -> str:
    host = netloc.split("@")[-1]
    host = host.split(":")[0].lower()
    for prefix in STRIP_SUBDOMAIN_PREFIXES:
        if host.startswith(prefix):
            return host[len(prefix) :]
    return host


def _domain_for_web_chunk(web: object) -> str | None:
    d = getattr(web, "domain", None)
    if isinstance(d, str) and d.strip():
        return d.strip().lower()
    uri = getattr(web, "uri", None)
    if _is_http_url(uri):
        netloc = urlparse(uri).netloc
        if isinstance(netloc, bytes):
            netloc = netloc.decode("utf-8")
        return _normalize_domain_from_netloc(netloc)
    t = getattr(web, "title", None)
    if isinstance(t, str) and "." in t and " " not in t:
        return t.lower().removeprefix("www.")
    return None


def _get_normalized_domain(u: str) -> str:
    """Parses a URL, gets the netloc, decodes if needed, and normalizes it."""
    netloc = urlparse(u).netloc
    if isinstance(netloc, bytes):
        netloc = netloc.decode("utf-8")
    return _normalize_domain_from_netloc(netloc)


def _iter_candidate_pairs(cand: types.Candidate) -> Iterable[tuple[str, str]]:
    gm = getattr(cand, "grounding_metadata", None)
    if gm:
        for ch in getattr(gm, "grounding_chunks", []) or []:
            web = getattr(ch, "web", None)
            if web:
                d = _domain_for_web_chunk(web)
                u = getattr(web, "uri", None)
                if d and _is_http_url(u):
                    yield (d, u)
            rc = getattr(ch, "retrieved_context", None)
            if rc:
                u = getattr(rc, "uri", None)
                if _is_http_url(u):
                    yield (_get_normalized_domain(u), u)
    cm = getattr(cand, "citation_metadata", None)
    if cm:
        for cit in getattr(cm, "citations", []) or []:
            u = getattr(cit, "uri", None)
            if _is_http_url(u):
                yield (_get_normalized_domain(u), u)
    ucm = getattr(cand, "url_context_metadata", None)
    if ucm:
        for um in getattr(ucm, "url_metadata", []) or []:
            u = getattr(um, "retrieved_url", None)
            if _is_http_url(u):
                yield (_get_normalized_domain(u), u)


def _choose_representative(urls: list[str]) -> str:
    def _host(u: str) -> str:
        netloc = urlparse(u).netloc
        if isinstance(netloc, bytes):
            netloc = netloc.decode("utf-8")
        return netloc.lower()

    non_redirect = [u for u in urls if _host(u) not in REDIRECT_HOSTS]
    pool = non_redirect if non_redirect else urls
    return min(pool, key=len)


def _decode_response_body(resp: requests.Response) -> str:
    """レスポンスボディを適切な文字コードでデコードする。

    requests はデフォルトで Content-Type ヘッダーの charset を使うが、
    日本語サイトは Shift-JIS / EUC-JP を誤検出することがある。
    UTF-8 で試みてから apparent_encoding にフォールバックする。
    """
    raw = resp.content[:8192]
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        encoding = resp.apparent_encoding or "shift_jis"
        return raw.decode(encoding, errors="replace")


def _fetch_page_info(url: str, fallback_domain: str) -> tuple[str, str]:
    """Follow a redirect URL and return (final_url, page_title).

    Falls back to (https://domain, domain) on any failure.
    """
    fallback_url = f"https://{fallback_domain}" if fallback_domain else url
    try:
        resp = safe_get(url, max_redirects=5, timeout=6)
        final_url = resp.url
        body = _decode_response_body(resp)
        m = re.search(r"<title[^>]*>(.*?)</title>", body, re.IGNORECASE | re.DOTALL)
        page_title = html.unescape(m.group(1).strip()) if m else fallback_domain
        return final_url, page_title
    except Exception:
        return fallback_url, fallback_domain


def extract_grounding_web_hits(
    response: types.GenerateContentResponse,
    follow_redirects: bool = True,
) -> list:
    """Extracts web URLs from grounding metadata as web_hits format.

    When follow_redirects=True (default), vertexaisearch redirect URLs are
    followed in parallel to obtain the real page URL and title.
    """
    # --- Phase 1: collect raw data ---
    raw: list[dict] = []  # {url, domain, title}
    seen_urls: set[str] = set()

    for cand in getattr(response, "candidates", []) or []:
        gm = getattr(cand, "grounding_metadata", None)

        # chunk_index -> title (from web.title) and url
        chunk_info: dict[int, tuple[str, str]] = {}  # idx -> (url, title)
        if gm:
            for j, ch in enumerate(getattr(gm, "grounding_chunks", []) or []):
                web = getattr(ch, "web", None)
                if web:
                    u = getattr(web, "uri", None)
                    t = getattr(web, "title", None)
                    if u:
                        chunk_info[j] = (u, t or "")

        # url -> title (lookup by URL)
        url_to_title: dict[str, str] = {u: t for u, t in chunk_info.values() if u}

        for domain, url in _iter_candidate_pairs(cand):
            if url in seen_urls:
                continue
            seen_urls.add(url)
            title = url_to_title.get(url) or domain
            raw.append({"url": url, "domain": domain, "title": title})

    if not raw:
        return []

    if not follow_redirects:
        return [{"title": r["title"], "snippet": "", "url": r["url"]} for r in raw]

    # --- Phase 2: follow redirect URLs in parallel ---
    redirect_raw = [r for r in raw if _get_normalized_domain(r["url"]) in REDIRECT_HOSTS]
    url_resolution: dict[str, tuple[str, str]] = {}  # redirect_url -> (final_url, page_title)

    if redirect_raw:
        with ThreadPoolExecutor(max_workers=8) as executor:
            futures = {
                executor.submit(_fetch_page_info, r["url"], r["domain"]): r["url"]
                for r in redirect_raw
            }
            for future in as_completed(futures):
                orig_url = futures[future]
                final_url, page_title = future.result()
                url_resolution[orig_url] = (final_url, page_title)

    # --- Phase 3: build final web_hits ---
    web_hits = []
    for r in raw:
        if r["url"] in url_resolution:
            final_url, page_title = url_resolution[r["url"]]
            web_hits.append({"title": page_title, "snippet": "", "url": final_url})
        else:
            web_hits.append({"title": r["title"], "snippet": "", "url": r["url"]})

    return web_hits


def resolve_redirect_web_hits(web_hits: list[dict]) -> list[dict]:
    """vertexaisearch リダイレクト URL を並列解決して最終 URL とタイトルに置き換える。

    follow_redirects=False で取得した web_hits を受け取り、
    リダイレクトホストの URL のみ解決して返す。
    """
    redirect_indices = [
        i for i, hit in enumerate(web_hits) if _get_normalized_domain(hit["url"]) in REDIRECT_HOSTS
    ]
    if not redirect_indices:
        return web_hits

    url_resolution: dict[str, tuple[str, str]] = {}
    with ThreadPoolExecutor(max_workers=8) as executor:
        futures = {
            executor.submit(
                _fetch_page_info,
                web_hits[i]["url"],
                _get_normalized_domain(web_hits[i]["url"]),
            ): web_hits[i]["url"]
            for i in redirect_indices
        }
        for future in as_completed(futures):
            orig_url = futures[future]
            final_url, page_title = future.result()
            url_resolution[orig_url] = (final_url, page_title)

    resolved = list(web_hits)
    for i in redirect_indices:
        orig_url = web_hits[i]["url"]
        if orig_url in url_resolution:
            final_url, page_title = url_resolution[orig_url]
            resolved[i] = {"title": page_title, "snippet": "", "url": final_url}
    return resolved


def urls_markdown_grouped_by_domain(resp: types.GenerateContentResponse) -> str:
    domain_to_urls: dict[str, list[str]] = {}
    domain_order: list[str] = []
    seen_urls: set[str] = set()
    for cand in getattr(resp, "candidates", []) or []:
        for domain, url in _iter_candidate_pairs(cand):
            if not _is_http_url(url):
                continue
            if url in seen_urls:
                continue
            seen_urls.add(url)
            if domain not in domain_to_urls:
                domain_to_urls[domain] = []
                domain_order.append(domain)
            domain_to_urls[domain].append(url)
    lines: list[str] = []
    for domain in domain_order:
        rep = _choose_representative(domain_to_urls[domain])
        lines.append(f"- [{domain}]({rep})")
    return "\n".join(lines)
