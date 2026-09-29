[日本語](README.md) | English

# Purpose and Structure of This Repository

## Table of Contents

- [Purpose and Structure of This Repository](#purpose-and-structure-of-this-repository)
- [Prerequisites](#prerequisites)
  - [Tool Installation](#tool-installation)
  - [Resource Provider Registration](#resource-provider-registration)
  - [Quota and Available Zone Verification](#quota-and-available-zone-verification)
- [Usage Instructions](#usage-instructions)
  - [1. Download This Repository](#1-download-this-repository)
  - [2. Configure Parameters](#2-configure-parameters)
  - [3. Azure Developer CLI Login](#3-azure-developer-cli-login)
  - [4. Deployment](#4-deployment)
  - [5. Configure VMSS Auto Start/Stop](#5-configure-vmss-auto-startstop)
- [Removing the Environment](#removing-the-environment)
- [vLLM API - API Specification](#vllm-api---api-specification)
  - [API Mode Switching](#api-mode-switching)
  - [Transform Mode (enablePlamoCustomApiTransform = true)](#transform-mode-enableplamocustomapitransform--true)
  - [Passthrough Mode (enablePlamoCustomApiTransform = false)](#passthrough-mode-enableplamocustomapitransform--false)
- [Azure OpenAI Direct API - API Specification](#azure-openai-direct-api---api-specification)
  - [Endpoint 1: Chat Completions API](#endpoint-1-chat-completions-api)
  - [Endpoint 2: Responses API](#endpoint-2-responses-api)
- [Azure OpenAI Code Interpreter - API Specification](#azure-openai-code-interpreter---api-specification)
- [Metrics and Logging](#metrics-and-logging)
- [Accessing VMSS VMs and Troubleshooting](#accessing-vmss-vms-and-troubleshooting)
  - [VM Access Preparation](#vm-access-preparation)
  - [Troubleshooting](#troubleshooting)
    - [CUDA Driver/Runtime Mismatch Error](#cuda-driverruntime-mismatch-error)
- [Additional Resources](#additional-resources)
  - [APIM Policy Customization Guide](#apim-policy-customization-guide)
  - [Adding Python Libraries to vLLM Container](#adding-python-libraries-to-vllm-container)
  - [Third-Party Licenses](#third-party-licenses)

---

This repository is a template for efficiently hosting and providing APIs for Hugging Face models compatible with vLLM and Azure OpenAI models on Microsoft Azure.

This repository uses the [PLaMo Translation Model](https://huggingface.co/pfnet/plamo-2-translate) as an example vLLM implementation. Please refer to the [plamo-community-license](https://plamo.preferredai.jp/info/plamo-community-license-en) for terms of use.

The architecture is as follows:

![Overall Architecture Diagram](assets/Overall_Architecture.png "Overall Architecture Diagram")

This architecture consists of the following Microsoft Azure services:


**Common Components**
*   **Azure API Management (APIM):**
    Provides a single endpoint that accepts external requests. Manages source IP restrictions, API key authentication, and request routing. Forwards received requests to APGW via HTTP over private IP communication through the virtual network.
*   **Azure Application Gateway (APGW):**
    Receives requests from APIM and performs load balancing to backend inference VMs. APIM adds the x-apim-secret header with backend authorization credentials when requesting to APGW, and APGW's WAF policy validates the x-apim-secret header. This mechanism restricts which APIM instances can send requests to APGW.

**vLLM-Compatible Model API Group**
* **Virtual Machine Scale Set (VMSS) / Virtual Machine (VM):**
    Retrieves inference target models from Hugging Face and creates and runs inference containers accessible via REST API. The inference containers are configured as VMSS, allowing flexible scaling by simply adding VMs.
*   **Azure Automation:**
    Periodically starts/stops VMs.

**OpenAI API Group**
* **Azure Functions**
    A serverless execution environment that executes Azure OpenAI APIs and orchestrates the entire process. Communication to Azure OpenAI is via private endpoint for secure access.
* **Azure OpenAI Service**
    Provides OpenAI APIs. Offers APIs for Code Interpreter-based Excel/CSV file data analysis functionality and Chat Completions/Responses APIs.

> **Note:**   
> vLLM is an open-source engine for accelerating inference of large language models (LLMs).    
>  [Github Repos: vllm-project/vllm](https://github.com/vllm-project/vllm)   
> [Doc: vLLM](https://docs.vllm.ai/en/latest/)   
> Using the vllm/vllm-openai Docker image, you can use popular Hugging Face models via OpenAI-compatible APIs with a single command.    
> [Doc: Using Docker](https://docs.vllm.ai/en/stable/deployment/docker.html)   
> Models supported by vLLM are listed here:   
> [Doc: Supported Models](https://docs.vllm.ai/en/latest/models/supported_models.html)

# Prerequisites

## Tool Installation

Please install the following tools:

[Azure Developer CLI](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd)

[Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)

## Resource Provider Registration

Before using this template, ensure that the required Azure resource providers are registered.

### Verification and Registration Steps via Azure Portal

1. Log in to the [Azure Portal](https://portal.azure.com).

2. Enter "Subscriptions" in the search bar and select **Subscriptions**.

3. Click the subscription you want to use.

4. From the left menu, select **Settings** > **Resource providers**.

5. Verify that the following resource providers are "Registered":

- Microsoft.Web
- Microsoft.App
- Microsoft.ApiManagement
- Microsoft.Network
- Microsoft.Compute
- Microsoft.Automation
- Microsoft.OperationalInsights
- Microsoft.Insights

6. If any provider is **Not registered**, register it by:
   - Clicking the provider to select it
   - Clicking the **Register** button at the top
   - Waiting for the status to change from "Registering" to "Registered" (may take a few minutes)


## Quota and Available Zone Verification

From the [official documentation](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/overview?tabs=breakdownseries%2Cgeneralsizelist%2Ccomputesizelist%2Cmemorysizelist%2Cstoragesizelist%2Cgpusizelist%2Cfpgasizelist%2Chpcsizelist#gpu-accelerated), select an Azure N-series VM size powered by NVIDIA GPUs (excluding NV or NVv3) that meets the specifications required by the model you intend to run.
Use Azure CLI to verify if quotas exist and which zones are available for the selected VM size.

Log in to your Microsoft Entra ID tenant using Azure CLI:
```bash
az login
```

**Note:** For environments without a browser, use the `--use-device-code` parameter. To explicitly specify a tenant, use the `--tenant` parameter.

Execute the following command to verify quotas. If the Limit is insufficient, [request quota increase](https://learn.microsoft.com/en-us/azure/quotas/per-vm-quota-requests). Note that `Total Regional Low-priority vCPUs` is the quota for spot VMs, and creating spot VMs will consume this quota regardless of VM size.

```bash
az vm list-usage --location japaneast --output table
```
#### Execution Result
```bash
Name                                      CurrentValue    Limit
----------------------------------------  --------------  -------
Total Regional Low-priority vCPUs         0               100
Standard NCADS_A100_v4 Family vCPUs       0               24
```

Next, verify which zones allow creation of the specified VM. The numbers listed in Zones in the execution result are the applicable values.

```bash
az vm list-skus --location japaneast --resource-type virtualmachines --zone --all --output table --size Standard_NC24ads_A100_v4
```
#### Execution Result
```bash
ResourceType     Locations    Name                      Zones    Restrictions
---------------  -----------  ------------------------  -------  --------------
virtualMachines  japaneast    Standard_NC24ads_A100_v4  3        None
```

# Usage Instructions

## 1. Download This Repository

Clone or download this repository as a zip file and extract it.

## 2. Configure Parameters

All deployment parameters are consolidated in `infra/main.parameters.json`.

The main parameters in `infra/main.parameters.json` are as follows. You do not need to modify values not listed in this table.

| Name | Type | Required | Description | Default Value | Example |
|------|------|----------|-------------|---------------|---------|
| corsOriginUrl | string | No | Specifies the domain of the single-page application (SPA) for authentication. If the SPA domain is not finalized, you can specify the default "*", but it is recommended to specify a concrete domain once finalized. | * | *, example.com, yourapp.azurewebsites.net |
| apiAllowedSourceIps | array | No | IP addresses allowed to access APIM. If this value is set, requests from other IPs will be rejected. An empty list means no restrictions. | [] | ["153.240.146.131", "198.51.101.25"] |
| deployVllmSupportModel | bool | No | Specifies whether to deploy the API for vLLM-compatible models. VMSS and Automation will be deployed. | true | true |
| vllmModelName | string | No | Specifies the model name to run on vLLM. Specify a Hugging Face model name. | pfnet/plamo-2-translate | pfnet/plamo-2-translate |
| vllmMaxModelLen | integer | No | Specifies the maximum model length of vLLM's context window. | 4096 | 4096 |
| vllmMaxNumBatchedTokens | integer | No | Specifies the maximum number of tokens to be batched in vLLM. | 4096 | 4096 |
| enablePlamoCustomApiTransform | bool | No | Specifies whether to enable request/response transformation for vLLM API. `true` uses custom format for Plamo translation, `false` passes through OpenAI-compatible API as is. | false | false |
| enableVmssPasswordAuth | bool | No | Specifies whether to enable password authentication for VMSS VMs. If `true`, password authentication is enabled in addition to SSH key authentication. The password is supplied via `vmssAdminPassword`. | false | false |
| vmssAdminPassword | securestring | No | Admin password for VMSS VMs, used when `enableVmssPasswordAuth` is `true`. `main.parameters.json` reads it from the `VMSS_ADMIN_PASSWORD` environment variable. Set a long random value with `azd env set` (see "Accessing VMSS VMs and Troubleshooting"). | '' | - |
| vmssInstanceCount | integer | Yes | Specifies the number of VMs to create in VMSS. | None | 1 |
| vmssSku | string | Yes | Specifies the VM size to create in VMSS. | Standard_NC24ads_A100_v4 | Standard_NC24ads_A100_v4 |
| vmZones | array | Yes | Specifies the zones where the VMSS VM size is available, as a string array. | None | ["1", "2", "3"] |
| useSpot | bool | Yes | Specifies whether to create as spot VMs. You can specify `true` for development environments to create spot VMs for cost savings, and `false` for production environments to create regular VMs with SLA. | true | true |
| deployCodeInterpreter | bool | No | Specifies whether to deploy the API for data analysis/visualization using Azure OpenAI's Code Interpreter feature. | true | true |
| deployOpenAiDirect | bool | No | Specifies whether to deploy Azure OpenAI's Chat Completions/Responses API. | true | true |
| openaiPublicNetworkAccess | string | Disabled | Specifies whether to allow public network access to Azure OpenAI. If `Disabled` is specified, public network access is not allowed. If `Enabled` is specified, public access is allowed. | Disabled | Disabled |
| openaiAllowedIpAddresses | array | No | IP addresses allowed to access Azure OpenAI. If openaiPublicNetworkAccess is `Enabled` and this value is set, requests from other IPs will be rejected. | [] | ["153.240.146.131", "198.51.101.25"] |
| functionPublicNetworkAccess | string | Disabled | Specifies whether to allow public network access to Azure Functions. If `Disabled` is specified, public network access is not allowed. If `Enabled` is specified, public access is allowed. Must be set to Enabled when deploying apps from outside the VNet. | Enabled | Disabled |
| functionAllowedIpAddresses | array | No | IP addresses allowed to access Azure Functions in CIDR notation. If functionPublicNetworkAccess is `Enabled` and this value is set, requests from other IPs will be rejected. Must include the Global IP address of the deployment device when deploying apps from outside the VNet. | [] | ["153.240.146.131/32", "198.51.101.25/32"] |
| openaiDeploymentType | string | No | Specifies the deployment type for Azure OpenAI. Choose from Standard, GlobalStandard, ProvisionedManaged, GlobalProvisionedManaged, DataZoneStandard, DataZoneProvisionedManaged. | Standard | GlobalStandard |
| enableGenAiIoLogging | bool | No | Specifies whether to save input/output logs to generative AI. If `true` is specified, logs are saved in the ApiManagementGatewayLogs table of the Log Analytics workspace. | None | true |
| environmentName | string | Yes | Specifies the environment name. If specified, creates a resource group with the naming convention rg-\<environmentName\>. No need to edit as it is specified during deployment. | None | dev, prod, etc. |
| location | string | Yes | Specifies the region where resources will be created. No need to edit as it is specified during deployment. | None | japaneast |

## 3. Azure Developer CLI Login

Log in to your Microsoft Entra ID tenant using Azure Developer CLI:
```bash
azd auth login
```

## 4. Deployment

The deployment method differs depending on whether you deploy the API for Excel/CSV file data analysis using Code Interpreter. Follow the deployment steps below based on whether you set `deployCodeInterpreter` to `true` or `false` in `infra/main.parameters.json`.

| deployCodeInterpreter | Deployment Steps |
|:---------------------:|-----------------|
| `true` | [4.2. Deploy Both Azure Environment and App](#42-deploy-both-azure-environment-and-app) |
| `false` | [4.1. Deploy Azure Environment Only](#41-deploy-azure-environment-only) |

> **Note:** If `deployCodeInterpreter` is `false`, set at least one of `deployVllmSupportModel` or `deployOpenAiDirect` to `true`.

After deploying once, you can add APIs by changing other API flags to `true` and redeploying. However, you cannot delete existing APIs and deploy different APIs. If you want to delete existing APIs, [remove the environment](#removing-the-environment) first and then redeploy.

### 4.1. Deploy Azure Environment Only

Execute the following command:
```bash
azd provision
```

Azure environment deployment takes approximately 30-40 minutes. If `deployVllmSupportModel` is set to `true`, it will take an additional 20-30 minutes after deployment for environment setup within the VM.

The specified environment name and other details are saved under the `.azure` directory, so you don't need to specify them again. If you want to redefine the environment and create it from scratch with different resource names, delete the `.azure` directory.

### 4.2. Deploy Both Azure Environment and App

After building the Azure environment with IaC, you need direct communication from the deployment device to Azure Functions/Azure OpenAI to:
- Deploy the application to Azure Functions
- Upload font files for Japanese support to Azure OpenAI

Therefore, deploy in the following two steps as needed:
- Deploy with public access allowed for Azure Functions/Azure OpenAI, with source IP restrictions if necessary
- Change to disallow public access for Azure Functions/Azure OpenAI (Optional)

#### 4.2.1. Deploy with Public Access Allowed for Azure Functions/OpenAI (with Source IP Restrictions Possible)

To deploy applications and upload font files to Azure Functions/OpenAI, allow public access and restrict source IPs if necessary.

#### 4.2.2. Modify Parameter File

Set `openaiPublicNetworkAccess` and `functionPublicNetworkAccess` to `Enabled` in `infra/main.parameters.json`, and if source IP restrictions are needed, specify the allowed global IPs in `openaiAllowedIpAddresses` and `functionAllowedIpAddresses`.

#### 4.2.3. Execute Deployment

Execute the following command:
```bash
azd up
```

#### 4.2.4. Change to Disallow Public Access to Azure Functions/OpenAI (Optional)

(If you want to strictly ensure secure access, perform this step after deployment completion)
After deployment is complete, change the settings to disallow public access to Azure Functions/OpenAI.

#### 4.2.5. Modify Parameter File

Set `openaiPublicNetworkAccess` and `functionPublicNetworkAccess` to `Disabled` in `infra/main.parameters.json`, and empty the settings for `openaiAllowedIpAddresses` and `functionAllowedIpAddresses`.

#### 4.2.6. Execute Azure Environment Only Deployment

Execute the following command:
```bash
azd provision
```

## 5. Configure VMSS Auto Start/Stop
Configure automatic start/stop for VMSS. Inject (copy) scripts to the deployed Azure Automation and set schedules.

> **Note:** 
> The Azure CLI command to upload Azure Runbook scripts is in "experimental development" status at the time of writing, so this is a manual setup.  
> [Azure CLI - az automation runbook replace-content](https://learn.microsoft.com/en-us/cli/azure/automation/runbook?view=azure-cli-latest#az-automation-runbook-replace-content)



## Configuration Steps
### Inject (Copy) Scripts to Runbook Resources
1. Enter "Automation" in the Azure Portal search bar and select Automation Accounts.
    <p>
      <img src="assets/automation1.png" alt="automation_1" width="60%">
    </p>

    Navigate to the deployed Azure Automation resource page.
    <p>
      <img src="assets/automation2.png" alt="automation_2" width="60%">
    </p>

2. Select Runbooks from the left pane of the Azure Automation page.
    <p>
      <img src="assets/automation3.png" alt="automation_3" width="30%">
    </p>

    Immediately after deployment, two Runbooks are displayed with creation status "New".  
    Click the displayed Runbook.
    <p>
      <img src="assets/automation4.png" alt="automation_4" width="70%">
    </p>
3. Select Overview -> Edit -> Edit in Portal.
    <p>
      <img src="assets/automation5.png" alt="automation_5" width="70%">
    </p>

4. Copy and paste the script onto the canvas and "Publish" it.  
**Note:** Perform the same operation for both Runbooks.

    Description of each Runbook and script storage location:

    | Runbook Name | Description | Script Path |
    |--|--|--|
    |rb-start-vmss|VMSS start script|infra\core\automation\runbooks\runbook-start-vmss.ps1|
    |rb-stop-vmss|VMSS stop script|infra\core\automation\runbooks\runbook-stop-vmss.ps1|

    <p>
      <img src="assets/automation6.png" alt="automation_6" width="90%">
    </p>

5. Verify that the Runbook creation status is "Published".
    <p>
      <img src="assets/automation7.png" alt="automation_7" width="70%">
    </p>

### Configure Auto-Execution Schedule for Runbooks
1. Next, configure the schedule.
2. From the left pane of the Automation resource, click Schedules -> Add a schedule.
**Note:** Prepare two schedules for VMSS start and stop.
    <p>
      <img src="assets/automation8.png" alt="automation_8" width="60%">
    </p>

    This is an example configuration; please configure according to your desired execution time and timing.  
    <p>
      <img src="assets/automation9.png" alt="automation_9" width="30%">
    </p>

3. Link Runbooks and schedules. Click Overview -> Link to schedule for each Runbook.
    <p>
      <img src="assets/automation10.png" alt="automation_10" width="60%">
    </p>

4. Select the corresponding schedule for each Runbook.
    <p>
      <img src="assets/automation11.png" alt="automation_11" width="60%">
    </p>

5. In parameter settings, enter the resource group name and VMSS resource name where VMSS belongs.
     <p>
      <img src="assets/automation12.png" alt="automation_12" width="60%">
    </p>


6. Configure schedules and parameters for both VMSS start/stop Runbooks to complete the setup.


# Removing the Environment

If you want to remove the deployed environment, follow these steps:

## 1. Remove Environment via Azure Developer CLI

```bash
azd down
```

This command will delete all deployed Azure resources.

> **Warning:**  
> This operation cannot be undone. Thoroughly verify the resources to be deleted before execution.

APIM and Azure OpenAI will be soft-deleted, so to completely delete them, enter `y` to the following question to purge:

```bash
These resources have soft delete enabled allowing them to be recovered for a period or time after deletion. During this period, their names may not be reused. In the future, you can use the argument --purge to skip this confirmation.
? Would you like to permanently delete these resources instead, allowing their names to be reused? (y/N) y
  (✓) Done: Purging apim: apim-xxxx
  (✓) Done: Purging Cognitive Account: cog-xxxx
```

> **Note:** 
> The latest Azure Developer CLI can perform purging after resource deletion with `azd down`, but older versions may not. In that case, you can purge with the following commands:

* APIM purge command
```bash
az apim deletedservice purge --service-name <apim_service_name> --location japaneast
```
* Azure OpenAI purge command
```bash
az cognitiveservices account purge --name <aoai_service_name> --resource-group <resource_group_name> --location japaneast
```
# vLLM API - API Specification

This API provides access to models running on vLLM. The `enablePlamoCustomApiTransform` parameter allows switching between two modes.

## API Mode Switching

| enablePlamoCustomApiTransform | Mode | Description |
|------------------------|--------|------|
| `true` | Transform Mode | Transforms request/response in custom format for Plamo translation |
| `false` | Passthrough Mode | Passes through vLLM OpenAI-compatible API as is |

---

## Transform Mode (enablePlamoCustomApiTransform = true)

### Endpoint

-   **Method:** `POST`
-   **URL:** `{APIM URL}/vllm/v1/completions`

### Authentication

Specify the API key in the HTTP request header.

-   **Key:** `x-api-key`
-   **Value:** `{APIM subscription key}`

> **Note:**   
> For APIM subscription key issuance and management procedures, refer to the following. Select ```GenAI Product``` as the product for scope.    
> [Create subscriptions in Azure API Management](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-create-subscriptions)

### Request Format

Fields to specify in the request body:

| Name        | Type       | Required | Description                                                                   | Default Value | Example |
|-------------|----------|------|--------------------------------------------------------------------------|--------------|--------|
| inputs.input_text       | string   | Yes  | Input text to provide to the model. Includes translation or generation instructions.                     | None         | It's nice weather today |
| inputs.option  | string  | Yes   | Specifies source and target languages for translation. Use ```Jp2En``` for Japanese to English, ```En2Jp``` for English to Japanese.                          | None           | Jp2En |



### Request Example

Japanese->English
```bash
curl -X POST https://apim-xyz.azure-api.net/vllm/v1/completions \
  -H "Content-Type: application/json" -H "x-api-key: xxxxxxxxxxxxxxxxxxxxxxxxxxx" \
  -d '{"inputs": {"input_text": "今日はいい天気です", "option": "Jp2En"}}'
```

English->Japanese
```bash
curl -X POST https://apim-xyz.azure-api.net/vllm/v1/completions \
  -H "Content-Type: application/json" -H "x-api-key: xxxxxxxxxxxxxxxx" \
  -d '{"inputs": {"input_text": "Hi, this is a red pen.", "option": "En2Jp"}}'
```

Requests in the following format that VMSS accepts are also possible:
```json
{
  "model": "pfnet/plamo-2-translate",
  "max_tokens": 1024,
  "temperature": 0,
  "stop": "<|plamo:op|>",
  "prompt": "<|plamo:op|>dataset translation <|plamo:op|>input lang=English Write the text to be translated here. <|plamo:op|>output lang=Japanese"
}
```

## Response Example

Japanese->English
```json
{"statusCode": 200,"outputs": "It's nice weather today."}
```

English->Japanese
```json
{"statusCode": 200,"outputs": "こちらは赤ペンです。"}
```

VMSS itself returns a response in the following format, which is edited by APIM to the above format (only for 200 responses):
```json
{
  "id": "cmpl-bb461f5146d44d13bb2cb4296b719e34",
  "object": "text_completion",
  "created": 1758264203,
  "model": "pfnet/plamo-2-translate",
  "choices": [
    {
      "index": 0,
      "text": " ここに翻訳対象のテキストを入力してください。\n",
      "logprobs": null,
      "finish_reason": "stop",
      "stop_reason": "<|plamo:op|>",
      "prompt_logprobs": null
    }
  ],
  "service_tier": null,
  "system_fingerprint": null,
  "usage": {
    "prompt_tokens": 22,
    "total_tokens": 32,
    "completion_tokens": 10,
    "prompt_tokens_details": null
  },
  "kv_transfer_params": null
}
```

---

## Passthrough Mode (enablePlamoCustomApiTransform = false)

In passthrough mode, you can directly use vLLM's OpenAI-compatible API. No request/response transformation is performed, and requests are forwarded directly to vLLM.

### Available Endpoints

You can use the OpenAI-compatible API endpoints supported by vLLM. For details, refer to [vLLM OpenAI Compatible Server](https://docs.vllm.ai/en/latest/serving/openai_compatible_server/).

-   **Completions:** `POST {APIM URL}/vllm/v1/completions`
-   **Chat Completions:** `POST {APIM URL}/vllm/v1/chat/completions`
-   **Models:** `GET {APIM URL}/vllm/v1/models`

### Authentication

Specify the API key in the HTTP request header.

-   **Key:** `x-api-key`
-   **Value:** `{APIM subscription key}`

### Request Example (Completions)

```bash
curl -X POST https://apim-xyz.azure-api.net/vllm/v1/completions \
  -H "Content-Type: application/json" \
  -H "x-api-key: your-subscription-key" \
  -d '{
    "model": "pfnet/plamo-2-translate",
    "max_tokens": 1024,
    "temperature": 0,
    "stop": "<|plamo:op|>",
    "prompt": "<|plamo:op|>dataset translation <|plamo:op|>input lang=English Write the text to be translated here. <|plamo:op|>output lang=Japanese"
  }'
```

### Response Example (Completions)

```json
{
  "id": "cmpl-xxx",
  "object": "text_completion",
  "created": 1758264203,
  "model": "pfnet/plamo-2-translate",
  "choices": [
    {
      "index": 0,
      "text": "ここに翻訳対象のテキストを入力してください。",
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 22,
    "total_tokens": 32,
    "completion_tokens": 10
  }
}
```

---

# Azure OpenAI Direct API - API Specification

This system provides OpenAI-compatible APIs that are routed directly to Azure OpenAI.

## Common Authentication

For all endpoints, specify the API key in the HTTP request header.

-   **Key:** `x-api-key`
-   **Value:** `{APIM subscription key}`

---

## Endpoint 1: Chat Completions API

### Overview
-   **Method:** `POST`
-   **URL:** `{APIM URL}/openai/v1/chat/completions`
-   **Description:** OpenAI-compatible chat completion API. Routed directly to Azure OpenAI.

### Request Example

```bash
curl -X POST "https://apim-xyz.azure-api.net/openai/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "x-api-key: your-subscription-key" \
  -d '{
    "model": "gpt-4o",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "What is the capital of France?"}
    ]
  }'
```

### Response Example

```json
{
  "choices": [
    {
      "finish_reason": "stop",
      "index": 0,
      "message": {
        "content": "The capital of France is Paris.",
        "role": "assistant"
      }
    }
  ],
  "created": 1764584192,
  "id": "chatcmpl-...",
  "model": "gpt-4o-2024-11-20",
  "object": "chat.completion",
  "usage": {
    "completion_tokens": 8,
    "prompt_tokens": 25,
    "total_tokens": 33
  }
}
```

---

## Endpoint 2: Responses API

### Overview
-   **Method:** `POST`
-   **URL:** `{APIM URL}/openai/v1/responses`
-   **Description:** OpenAI-compatible Responses API. Supports structured output and JSON Schema-based response generation.

### Request Example

```bash
curl -X POST "https://apim-xyz.azure-api.net/openai/v1/responses" \
  -H "Content-Type: application/json" \
  -H "x-api-key: your-subscription-key" \
  -d '{
    "model": "gpt-4o",
    "instructions": "You are a helpful assistant.",
    "input": "What is 2+2?"
  }'
```

### Response Example

```json
{
  "id": "resp_...",
  "object": "response",
  "created_at": 1764584192,
  "status": "completed",
  "model": "gpt-4o",
  "output": [
    {
      "type": "message",
      "content": [
        {
          "type": "output_text",
          "text": "2 + 2 equals 4!"
        }
      ],
      "role": "assistant"
    }
  ],
  "usage": {
    "input_tokens": 24,
    "output_tokens": 11,
    "total_tokens": 35
  }
}
```

---

# Azure OpenAI Code Interpreter - API Specification

This API provides Code Interpreter functionality hosted on Azure Functions.

## Endpoint

-   **Method:** `POST`
-   **URL:** `{APIM URL}/code-interpreter/responses`
-   **Description:** Data analysis/visualization API using Azure OpenAI's Code Interpreter feature

## Authentication

Specify the API key in the HTTP request header.

-   **Key:** `x-api-key`
-   **Value:** `{APIM subscription key}`

## Request Format

Fields to specify in the request body:

| Name        | Type       | Required | Description                                                                   | Default Value | Example |
|-------------|----------|------|--------------------------------------------------------------------------|--------------|--------|
| inputs.input_text       | string   | Yes  | Input text to provide to the model. Provides specific analysis instructions.                     | None         | Calculate the average price by category and visualize it with a horizontal bar chart. |
| inputs.files.key  | string  | Yes   | Specified to align with GENAI's standard interface. Not used by this API, so an empty string is acceptable.                          | None           | excel_file |
| inputs.files.files.filename | string    | No   | Specifies the filename of the file to be analyzed.                    | None            | sample_data1.xlsx |
| inputs.files.files.content | string    | No   | Specifies the Base64-encoded text of the filename to be analyzed.                    | None            | iVBORw0K... |

## Request Example

```json
{
  "inputs": {
    "input_text": "Calculate the average price by category and visualize it with a horizontal bar chart.",
    "files": [
      {
        "key": "excel_file",
        "files": [
          {
            "filename": "sample_data1.xlsx",
            "content": "<base64_data>"
          },
          {
            "filename": "sample_data2.xlsx",
            "content": "<base64_data>"
          }
        ]
      }
    ]
  }
}
```

## Response Example

```json
{
    "outputs": "I calculated the average price by category and visualized it with a horizontal bar chart. Looking at the graph, the 'Electronics' category shows the highest average price.",
    "artifacts": [
        {
            "display_name": "cfile_691d8b5458288190886a3909acc28933.png",
            "content": "<base64_data>"
        }
    ]
}
```

# Metrics and Logging

Metrics can be viewed in Azure Monitor and Application Insights.

* Viewing Azure Monitor: Accessible from API Management instance > Monitoring > Metrics.

* Viewing Application Insights: Accessible from the Application Insights resource in the resource group created by this template.

Request logs are stored in Log Analytics Workspace.

* Viewing Log Analytics Workspace: Accessible from API Management instance > Monitoring > Logs. For example, if you set `enableGenAiIoLogging` to `true` in `infra/main.parameters.json`, you can retrieve logs from the last 3 days by executing the following KQL against the ApiManagementGatewayLogs table. Verify that request body, response body, and (in BackendRequestHeader) user ID are included:
    ```
    ApiManagementGatewayLogs | where TimeGenerated > ago(3d)
    ```

# Accessing VMSS VMs and Troubleshooting

This section explains how to perform operations and maintenance within VMSS VMs and troubleshoot issues when APIs do not work properly after deployment.

## VM Access Preparation

### 1. Enable Password Authentication

Generate a random password, store it in the azd environment, set `enableVmssPasswordAuth` to `true` in `infra/main.parameters.json`, and deploy.

```bash
azd env set VMSS_ADMIN_PASSWORD "$(openssl rand -base64 32)"
```

```json
"enableVmssPasswordAuth": {
  "value": true
}
```

After you finish, it is recommended to set `enableVmssPasswordAuth` back to `false` and redeploy.

### 2. Enable Boot Diagnostics

Enable boot diagnostics for VMSS in the Azure Portal.

1. Open the corresponding VMSS resource in the Azure Portal
2. From the left menu, select **Support + troubleshooting** > **Boot diagnostics**
3. In the **Settings** tab, select **Enable with managed storage account** and save

### 3. Log in to VM via Serial Console

1. Select the target VM instance from **Instances** in the VMSS resource
2. From the left menu, select **Support + troubleshooting** > **Serial console**
3. When the console is displayed, press Enter to display the login prompt
4. Enter the username (default: `azureuser`) and password (retrieve it with `azd env get-value VMSS_ADMIN_PASSWORD`) to log in

## Troubleshooting

If the Application Gateway backend health is abnormal and not working after deployment, check the logs with the following steps.

### Check cloud-init logs

VM initial setup is executed by cloud-init. Check for errors.

```bash
# Overall cloud-init log
cat /var/log/cloud-init.log

# cloud-init output log (command execution results, etc.)
cat /var/log/cloud-init-output.log
```

### post-reboot.sh Execution Log

Check the log of the script executed after reboot.

```bash
# post-reboot.sh execution log
cat /var/log/post-reboot.log
```

### Check vLLM Container Logs

Check if the vLLM container has started successfully and if there are any issues with model loading.

```bash
# Check container status
docker ps -a

# Check vLLM container logs (container name: vllm-server)
docker logs vllm-server

# Track logs in real-time
docker logs -f vllm-server
```

### CUDA Driver/Runtime Mismatch Error

If the following error occurs when starting the vLLM container, there is a version mismatch between the NVIDIA driver (CUDA Toolkit) on the VM and the CUDA runtime version required by the container image.

#### Typical Error Messages

```
RuntimeError: CUDA error: system has unsupported display driver / cuda driver combination
CUDA kernel errors might be asynchronously reported at some other API call...
Error 803: system has unsupported display driver / cuda driver combination
```

Or, even if `nvidia-smi` works normally but the GPU is not recognized inside the container, the same cause is likely.

#### Cause

The NVIDIA driver automatically installed by `ubuntu-drivers install` on the VM may be the latest version (e.g., Driver 590.x / CUDA 13.1). On the other hand, if the CUDA runtime version built internally in the vLLM container image `vllm/vllm-openai:latest` (e.g., CUDA 12.x) is not compatible with the host-side driver's CUDA version, this error occurs.

> **Note:** CUDA has forward compatibility for drivers. It works if host-side CUDA version ≥ container-side CUDA version, but compatibility can be lost if the host side is significantly newer or the container side is older.

#### Verification Steps

Log in to the serial console and check versions with the following commands:

```bash
# Check host-side NVIDIA driver and CUDA version
nvidia-smi

# Check container-side CUDA version (if container is running)
docker exec vllm-server nvcc --version
```

The **CUDA Version** displayed in the upper right of `nvidia-smi` is the host-side version. Compare it with the container-side CUDA version to verify compatibility.

#### Solution: Change vLLM Container Image Tag

Change to a vLLM container image corresponding to the host-side CUDA version.

**Step 1:** Change `vllmContainerImage` in `infra/main.parameters.json` to an appropriate image tag.

```json
"vllmContainerImage": {
  "value": "vllm/vllm-openai:v0.15.1-cu130"
}
```

> **Available Image Tag Examples:**
>
> | Tag | Supported CUDA | Usage |
> |------|----------|------|
> | `latest` | Default at build time | Normal use (caution if CUDA version unknown) |
> | `v0.15.1-cu130` | CUDA 13.0 | For host-side CUDA 13.x driver environments |
> | `v0.15.1` | CUDA 12.x | For host-side CUDA 12.x driver environments |
>
> For the latest tag list, check [Docker Hub: vllm/vllm-openai](https://hub.docker.com/r/vllm/vllm-openai/tags).

**Step 2:** Execute redeployment.

```bash
azd provision
```

**Step 3:** The new cloud-init is not reflected on existing VMSS instances. Reflect it using one of the following methods:

- **Reimage instances (recommended):** In Azure Portal, select VMSS > Instances > select corresponding instance > execute **Reimage**
- **Scale in/out:** Scale down the number of instances to 0, then scale out again to create new instances

# Additional Resources

## APIM Policy Customization Guide

This explains how to customize Azure API Management policies to transform from OpenAI-compatible APIs to custom request/response formats. For detailed APIM policy customization methods, refer to the following documentation:

→ [APIM Policy Customization Guide](docs/APIM_POLICY_CUSTOMIZATION_GUIDE.md)

## Adding Python Libraries to vLLM Container

If you want to install additional Python libraries in the `vllm/vllm-openai` Docker container running on VMSS, describe the package names in the following file.

**File path:** `infra/core/vmss/cloudinit/requirements.txt`

```
# Example: Describe libraries to add, one per line
scipy
transformers==4.48.2
```

Libraries described in this file will be `pip install`ed into the Docker container during VM initial setup (cloud-init execution). After adding new libraries, execute redeployment (`azd provision`) and recreate the VM.

## Third-Party Licenses

This project includes the Noto Sans JP (Source Han Sans) font (© 2014-2021 Adobe).
The font is provided under the SIL Open Font License 1.1. See `app/font/OFL.txt` for details.
