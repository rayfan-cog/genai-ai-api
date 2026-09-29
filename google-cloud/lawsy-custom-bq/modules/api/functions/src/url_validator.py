"""URL validation module for SSRF prevention.

Validates that outbound HTTP requests target only public IP addresses,
preventing access to internal networks, cloud metadata services, and
other private infrastructure.
"""

import ipaddress
import logging
import socket
from dataclasses import dataclass
from urllib.parse import urljoin, urlparse

import requests

logger = logging.getLogger(__name__)

_MAX_REDIRECTS_DEFAULT = 5
_TIMEOUT_DEFAULT = 6


class SsrfBlockedError(Exception):
    pass


@dataclass(frozen=True)
class ValidatedTarget:
    url: str
    host_header: str
    hostname: str
    connect_url: str
    pinned: bool


def is_private_ip(ip_str: str) -> bool:
    """Check if an IP address is private, loopback, link-local, or reserved."""
    try:
        addr = ipaddress.ip_address(ip_str)
    except ValueError:
        return True

    if hasattr(addr, "ipv4_mapped") and addr.ipv4_mapped:
        addr = addr.ipv4_mapped

    return (
        addr.is_private
        or addr.is_loopback
        or addr.is_link_local
        or addr.is_reserved
        or addr.is_multicast
    )


def validate_url_target(url: str) -> ValidatedTarget:
    """Normalize a URL and return its public, validated connection target.

    Raises SsrfBlockedError if the URL targets a private address or blocked port.
    """
    if any(char == "\\" or char.isspace() or ord(char) < 0x20 or ord(char) == 0x7F for char in url):
        raise SsrfBlockedError("URL contains a backslash, whitespace, or control character")

    try:
        prepared = requests.PreparedRequest()
        prepared.prepare_url(url, None)
    except (requests.exceptions.RequestException, ValueError, UnicodeError) as e:
        raise SsrfBlockedError(f"Invalid URL: {e}") from e

    normalized_url = prepared.url
    parsed = urlparse(normalized_url)
    try:
        hostname = parsed.hostname
    except ValueError as e:
        raise SsrfBlockedError(f"Invalid hostname in URL: {e}") from e

    try:
        port = parsed.port
    except ValueError as e:
        raise SsrfBlockedError(f"Invalid port in URL: {e}") from e

    if not hostname:
        raise SsrfBlockedError(f"No hostname in URL: {normalized_url}")

    if parsed.scheme not in ("http", "https"):
        raise SsrfBlockedError(f"Blocked scheme: {parsed.scheme}")

    if parsed.username is not None or parsed.password is not None or "@" in parsed.netloc:
        raise SsrfBlockedError("User information is not allowed in URL")

    if port is not None:
        raise SsrfBlockedError(f"Explicit port not allowed: {port}")

    try:
        addr = ipaddress.ip_address(hostname)
        if is_private_ip(str(addr)):
            raise SsrfBlockedError(f"SSRF blocked: {hostname} is a private IP")
        return ValidatedTarget(
            url=normalized_url,
            host_header=parsed.netloc,
            hostname=hostname,
            connect_url=normalized_url,
            pinned=False,
        )
    except ValueError:
        pass

    try:
        addrinfos = socket.getaddrinfo(
            hostname,
            443 if parsed.scheme == "https" else 80,
            proto=socket.IPPROTO_TCP,
        )
    except socket.gaierror as e:
        raise SsrfBlockedError(f"DNS resolution failed for {hostname}: {e}") from e

    if not addrinfos:
        raise SsrfBlockedError(f"No DNS results for {hostname}")

    resolved_ips = []
    for _family, _type, _proto, _canonname, sockaddr in addrinfos:
        ip_str = sockaddr[0]
        if is_private_ip(ip_str):
            logger.warning(f"SSRF blocked: {hostname} resolved to private address {ip_str}")
            raise SsrfBlockedError(f"SSRF blocked: {hostname} resolved to private address {ip_str}")
        resolved_ips.append(ipaddress.ip_address(ip_str))

    first_ip = resolved_ips[0]
    ip_literal = f"[{first_ip}]" if first_ip.version == 6 else str(first_ip)
    connect_url = f"{parsed.scheme}://{ip_literal}{parsed.path or '/'}"
    if parsed.query:
        connect_url += f"?{parsed.query}"

    return ValidatedTarget(
        url=normalized_url,
        host_header=parsed.netloc,
        hostname=hostname,
        connect_url=connect_url,
        pinned=True,
    )


class _PinnedHostAdapter(requests.adapters.HTTPAdapter):
    def __init__(self, hostname: str):
        super().__init__()
        self._hostname = hostname

    def build_connection_pool_key_attributes(self, request, verify, cert=None):
        host_params, pool_kwargs = super().build_connection_pool_key_attributes(
            request, verify, cert
        )
        if host_params["scheme"] == "https":
            pool_kwargs["server_hostname"] = self._hostname
            pool_kwargs["assert_hostname"] = self._hostname
        return host_params, pool_kwargs


def safe_get(
    url: str,
    *,
    max_redirects: int = _MAX_REDIRECTS_DEFAULT,
    timeout: float = _TIMEOUT_DEFAULT,
) -> requests.Response:
    """Perform a pinned HTTP GET and validate each redirect target.

    Each redirect hop is resolved and checked independently before connecting.
    """
    current_url = url

    for _ in range(max_redirects + 1):
        target = validate_url_target(current_url)

        with requests.Session() as session:
            session.trust_env = False
            if target.pinned:
                adapter = _PinnedHostAdapter(target.hostname)
                session.mount("https://", adapter)
                session.mount("http://", adapter)
            resp = session.get(
                target.connect_url,
                headers={
                    "User-Agent": "Mozilla/5.0",
                    "Host": target.host_header,
                },
                timeout=timeout,
                allow_redirects=False,
            )

        if resp.is_redirect or resp.status_code in (301, 302, 303, 307, 308):
            location = resp.headers.get("Location")
            if not location:
                resp.url = target.url
                return resp
            current_url = urljoin(target.url, location)
            continue

        resp.url = target.url
        return resp

    raise SsrfBlockedError(f"Too many redirects (max {max_redirects})")
