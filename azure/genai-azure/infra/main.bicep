targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string
param resourceGroupName string = ''

@description('Deploy vLLM supported model resources (VMSS, Automation)')
param deployVllmSupportModel bool = false
@description('vLLM model name to deploy (e.g. pfnet/plamo-2-translate)')
param vllmModelName string = 'pfnet/plamo-2-translate'
@description('vLLM max model length for context window')
param vllmMaxModelLen int = 4096
@description('vLLM max number of batched tokens')
param vllmMaxNumBatchedTokens int = 4096
@description('vLLM container image (e.g. vllm/vllm-openai:latest)')
param vllmContainerImage string = 'vllm/vllm-openai:latest'
@description('Enable vLLM API transform for Plamo translation format. If false, passthrough OpenAI-compatible API.')
param enablePlamoCustomApiTransform bool = false
@description('Enable password authentication for VMSS VMs (in addition to SSH key)')
param enableVmssPasswordAuth bool = false
@secure()
@description('Admin password for VMSS VMs (required when enableVmssPasswordAuth is true)')
param vmssAdminPassword string = ''
@description('Deploy Code Interpreter resources (Functions, OpenAI)')
param deployCodeInterpreter bool = false
@description('Deploy OpenAI Direct resources (OpenAI)')
param deployOpenAiDirect bool = false

param storageAccountName string = ''
param storageResourceGroupLocation string = location
param storageContainerName string = 'content'

// API Manangement 
param applicationInsightsDashboardName string = ''
param applicationInsightsName string = ''
param logAnalyticsName string = ''
param apimServiceName string = ''
@description('APIM で生成AI入出力を含む全ログカテゴリ (categoryGroup 利用) を有効化する場合 true')
param enableGenAiIoLogging bool
@description('Allowed caller source IPs for APIM ip-filter. Empty disables filtering.')
param apiAllowedSourceIps array = []

// Network & VMSS & Automation optional override names
@description('Virtual Network name (optional override)')
param vnetName string = ''
@description('VM Scale Set name (optional override)')
param vmssName string = ''
@description('Automation Account name (optional override)')
param automationAccountName string = ''

// Network detailed parameters
@description('CIDR for VNet')
param addressSpace string = '10.10.0.0/16'
@description('App Gateway SKU (Basic or Standard_v2 or WAF_v2)')
param appGatewaySku string = 'WAF_v2'
@description('App Gateway subnet name')
param appGatewaySubnetName string = 'appGatewaySubnet'
@description('App Gateway subnet prefix')
param appGatewaySubnetPrefix string = '10.10.0.0/24'

@description('Private Endpoint subnet name')
param peSubnetName string = 'peSubnet'
@description('Private Endpoint subnet prefix')
param peSubnetPrefix string = '10.10.4.0/24'
@description('Backend subnet name')
param vmssSubnetName string = 'backendSubnet'
@description('Backend subnet prefix')
param vmssSubnetPrefix string = '10.10.1.0/24'
@description('Subnet for Function App integration')
param functionSubnetName string = 'functionSubnet'
@description('CIDR prefix for Function App subnet')
param functionSubnetPrefix string = '10.10.3.0/24'
@description('Static Private IP for Function Private Endpoint (must be in peSubnetPrefix). Empty string for dynamic allocation.')
param functionPrivateEndpointStaticIp string = '10.10.4.10'
@description('Backend NSG name')
param backendNsgName string = 'nsg-backend'
@description('APIM outbound VNet integration subnet name (dedicated)')
param apimIntegrationSubnetName string = 'apimIntegrationSubnet'
@description('APIM outbound VNet integration subnet prefix (min /27)')
param apimIntegrationSubnetPrefix string = '10.10.2.0/27'
@description('Static private IP for AppGW private frontend (must be in appGatewaySubnetPrefix)')
param appGatewayPrivateIpAddress string = '10.10.0.4'
@description('Application Gateway name')
param appGatewayName string = ''

@description('Backend pool name')
param backendPoolName string = 'vmssPool'
@description('HTTP settings name for App Gateway backend')
param httpSettingsName string = 'appGatewayBackendHttpSettings'
@description('Probe resource name')
param probeName string = 'probe-http'
@description('Routing rule priority')
param rulePriority int
@description('Routing rule name')
param ruleName string = 'rule1'
@description('Frontend listener port')
param frontendPort int
@description('Probe path')
param probePath string
@description('Probe interval seconds')
param probeInterval int
@description('Probe timeout seconds')
param probeTimeout int
@description('Probe unhealthy threshold')
param probeUnhealthyThreshold int
@description('App Gateway capacity units')
param appGatewayCapacity int

// VMSS parameters (surface subset; rest inside module defaults)
@description('Admin username for VMSS VMs')
param vmssAdminUsername string
@secure()
@description('SSH public key for VMSS')
param vmssAdminPublicKey string
@description('Initial VMSS instance count')
param vmssInstanceCount int
@description('VM size SKU for VMSS')
param vmssSku string = 'Standard_NC24ads_A100_v4'
@description('VMSS upgrade policy mode (e.g. Automatic, Rolling)')
param upgradePolicyMode string
@description('Enable overprovisioning of VMs')
param overprovision bool
@description('Single placement group setting (true/false)')
param singlePlacementGroup bool
@description('Platform fault domain count (-1 = provider default)')
param platformFaultDomainCount int
@description('Linux image publisher (from vmImage)')
param linuxImagePublisher string
@description('Linux image offer')
param linuxImageOffer string
@description('Linux image SKU')
param linuxImageSku string = 'server'
@description('Linux image version or latest')
param linuxImageVersion string = 'latest'
@description('OS disk size in GB (0 omit)')
param osDiskSizeGB int
@description('OS disk storage account type (e.g. Standard_LRS)')
param osDiskStorageAccountType string
@description('Trusted Launch enable flag')
param enableTrustedLaunch bool
@description('Provision VM agent flag')
param provisionVMAgent bool

// Functions and Storage
param apiUserAssignedIdentityName string = ''
param appServicePlanName string = ''

param vnetEnabled bool = true
param apiServiceName string = ''
@description('Id of the user identity to be used for testing and debugging. This is not required in production. Leave empty if not needed.')
param principalId string = ''

// params for api policy settings
@description('CORSオリジンとして許可するドメインを指定してください(*でも可)')
param corsOriginUrl string = '*'

@description('Availability zones to spread VM instances across (e.g. ["1","2","3"])')
param vmZones array = ['1', '2', '3']

@description('Provision VMSS instances as Spot (eviction possible)')
param useSpot bool = true

@description('Max price for Spot instances as JSON number literal or "-1" for on-demand price (e.g. "0.5").')
param spotMaxPrice string

// Azure OpenAI parameters
@description('Azure OpenAI account name (optional override)')
param openaiAccountName string = ''
@description('Azure OpenAI SKU name')
param openaiSkuName string = 'S0'
@description('Azure OpenAI deployment name for GPT-4o model')
param openaiDeploymentName string = 'gpt-4o'
@description('Azure OpenAI deployment type (Standard, GlobalStandard, ProvisionedManaged, GlobalProvisionedManaged, DataZoneStandard, DataZoneProvisionedManaged)')
param openaiDeploymentType string = 'Standard'
@description('Azure OpenAI model name')
param openaiModelName string = 'gpt-4o'
@description('Azure OpenAI model version')
param openaiModelVersion string = '2024-11-20'
@description('Azure OpenAI model capacity (TPM in thousands)')
param openaiCapacity int = 10
@description('Azure OpenAI API version')
param openaiApiVersion string = '2024-10-21'
@description('Azure OpenAI public network access (Enabled or Disabled)')
@allowed(['Enabled', 'Disabled'])
param openaiPublicNetworkAccess string = 'Disabled'
@description('Enable Private Endpoint for Azure OpenAI')
param enableOpenaiPrivateEndpoint bool = true
@description('Allowed IP addresses for Azure OpenAI access (CIDR format). Empty array denies all public access when publicNetworkAccess is Disabled.')
param openaiAllowedIpAddresses array = []

@description('Azure Functions public network access (Enabled or Disabled)')
@allowed(['Enabled', 'Disabled'])
param functionPublicNetworkAccess string = 'Enabled'

@description('Allowed IP addresses for Function App access (CIDR format). Empty array allows all.')
param functionAllowedIpAddresses array = []

@description('Enable Private Endpoint for Azure Functions')
param enableFunctionPrivateEndpoint bool = false

@description('OpenAI request timeout in seconds')
param openaiTimeout string = '300.0'

@description('OpenAI maximum retries')
param openaiMaxRetries string = '3'

@description('System prompt for Code Interpreter')
param systemPrompt string = ''

var plamoApiName = 'PlamoCompletionsAPI'
var codeInterpreterApiName = 'AzureOpenAIProxyAPI'
var aoaiDirectApiName = 'AzureOpenAIChatCompletionsDirect'

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }

var apimSecret = uniqueString(tenant().tenantId, subscription().id, rg.id, environmentName, 'seed-for-apim-secret')

// Azure OpenAI public FQDN (used as TLS hostname via private DNS override)
var openaiPublicFqdn = format('{0}.openai.azure.com', !empty(openaiAccountName) ? openaiAccountName : '${abbrs.cognitiveServicesAccounts}${resourceToken}')

// Reference optional storage parameters to avoid unused warnings (future use placeholder)
var _storageParamsReference = {
  name: storageAccountName
  rgLocation: storageResourceGroupLocation
  container: storageContainerName
}

var storageEndpointConfig = {
  enableBlob: true  // Required for AzureWebJobsStorage, .zip deployment, Event Hubs trigger and Timer trigger checkpointing
  enableQueue: false  // Required for Durable Functions and MCP trigger
  enableTable: false  // Required for Durable Functions and OpenAI triggers and bindings
  enableFiles: false   // Not required, used in legacy scenarios
  allowUserIdentityPrincipal: true   // Allow interactive user identity to access for testing and debugging
}

var functionAppName = !empty(apiServiceName) ? apiServiceName : '${abbrs.webSitesFunctions}api-${resourceToken}'
var functionAppHostname = '${functionAppName}.azurewebsites.net'

var deploymentStorageContainerName = 'app-package-${take(functionAppName, 32)}-${take(toLower(uniqueString(functionAppName, resourceToken)), 7)}'

// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// Monitor application with Azure Monitor
module monitoring './core/monitor/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    tags: tags
    logAnalyticsName: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
    applicationInsightsDashboardName: !empty(applicationInsightsDashboardName) ? applicationInsightsDashboardName : '${abbrs.portalDashboards}${resourceToken}'
  }
}

// ------------------------------
// Azure OpenAI Service
// ------------------------------
module openai './core/ai/openai.bicep' = if (deployCodeInterpreter || deployOpenAiDirect) {
  name: 'openai'
  scope: rg
  params: {
    name: !empty(openaiAccountName) ? openaiAccountName : '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    location: location
    tags: tags
    skuName: openaiSkuName
    deploymentName: openaiDeploymentName
    deploymentType: openaiDeploymentType
    modelName: openaiModelName
    modelVersion: openaiModelVersion
    modelCapacity: openaiCapacity
    publicNetworkAccess: openaiPublicNetworkAccess
    privateEndpointSubnetId: network.outputs.peSubnetId
    enablePrivateEndpoint: enableOpenaiPrivateEndpoint
    allowedIpRules: openaiAllowedIpAddresses
  }
}

// Creates Azure API Management (APIM) service to mediate the requests between the frontend and the backend API
module apim './core/gateway/apim.bicep' = {
  name: 'apim-deployment'
  scope: rg
  params: {
    name: !empty(apimServiceName) ? apimServiceName : '${abbrs.apiManagementService}${resourceToken}'
    location: location
    tags: tags
    sku: 'StandardV2'
    skuCount: 1
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    workspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    publisherEmail: 'apim-${resourceToken}@example.com'
    publisherName: 'apim-${environmentName}'
    enableGenAiIoLogging: enableGenAiIoLogging
    vnetIntegrationSubnetId: network.outputs.apimIntegrationSubnetId
    apimSecret: apimSecret
  }
}

// ------------------------------
// Core Network (VNet + App Gateway)
// ------------------------------
module network './core/network/network.bicep' = {
  name: 'network'
  scope: rg
  params: {
    location: location
    vnetName: !empty(vnetName) ? vnetName : '${abbrs.networkVirtualNetworks}${resourceToken}'
    addressSpace: addressSpace
    appGatewaySku: appGatewaySku
    appGatewaySubnetName: appGatewaySubnetName
    appGatewaySubnetPrefix: appGatewaySubnetPrefix
    peSubnetName: peSubnetName
    peSubnetPrefix: peSubnetPrefix
    vmssSubnetName: vmssSubnetName
    vmssSubnetPrefix: vmssSubnetPrefix
    functionSubnetName: functionSubnetName
    functionSubnetPrefix: functionSubnetPrefix
    apimIntegrationSubnetName: apimIntegrationSubnetName
    apimIntegrationSubnetPrefix: apimIntegrationSubnetPrefix
    backendNsgName: backendNsgName
    appGatewayPrivateIpAddress: appGatewayPrivateIpAddress
    appGatewayName: !empty(appGatewayName) ? appGatewayName : '${abbrs.networkApplicationGateways}${resourceToken}'
    backendPoolName: backendPoolName
    httpSettingsName: httpSettingsName
    probeName: probeName
    rulePriority: rulePriority
    ruleName: ruleName
    frontendPort: frontendPort
    probePath: probePath
    probeInterval: probeInterval
    probeTimeout: probeTimeout
    probeUnhealthyThreshold: probeUnhealthyThreshold
    appGatewayCapacity: appGatewayCapacity
    functionAppHostname: functionAppHostname
    // 静的IPが設定されている場合は自動的にApp Gatewayバックエンドプールに追加
    // 動的割り当ての場合は手動更新が必要
    functionPrivateEndpointIp: functionPrivateEndpointStaticIp
    wafRequiredHeaderValue: apimSecret
    openaiPublicFqdn: openaiPublicFqdn
  }
}

// ------------------------------
// VM Scale Set (joined to App Gateway backend pool)
// ------------------------------
module vmss './core/vmss/vmss.bicep' = if (deployVllmSupportModel) {
  name: 'vmss'
  scope: rg
  params: {
    location: location
    vmssName: !empty(vmssName) ? vmssName : '${abbrs.computeVirtualMachineScaleSets}${resourceToken}'
    adminUsername: vmssAdminUsername
    adminPublicKey: vmssAdminPublicKey
    subnetId: network.outputs.vmssSubnetId
    appGatewayBackendPoolId: network.outputs.appGatewayBackendPoolId
    instanceCount: vmssInstanceCount
    vmSku: vmssSku
    vmZones: vmZones
    useSpot: useSpot
    spotMaxPrice: spotMaxPrice
    upgradePolicyMode: upgradePolicyMode
    overprovision: overprovision
    singlePlacementGroup: singlePlacementGroup
    platformFaultDomainCount: platformFaultDomainCount
    linuxImagePublisher: linuxImagePublisher
    linuxImageOffer: linuxImageOffer
    linuxImageSku: linuxImageSku
    linuxImageVersion: linuxImageVersion
    osDiskSizeGB: osDiskSizeGB
    osDiskStorageAccountType: osDiskStorageAccountType
    enableTrustedLaunch: enableTrustedLaunch
    provisionVMAgent: provisionVMAgent
    vllmModelName: vllmModelName
    vllmMaxModelLen: vllmMaxModelLen
    vllmMaxNumBatchedTokens: vllmMaxNumBatchedTokens
    vllmContainerImage: vllmContainerImage
    enablePasswordAuth: enableVmssPasswordAuth
    adminPassword: enableVmssPasswordAuth ? vmssAdminPassword : ''
    tags: tags
  }
}

// ------------------------------
// Automation Account
// ------------------------------
module automation './core/automation/automationAccount.bicep' = if (deployVllmSupportModel) {
  name: 'automation'
  scope: rg
  params: {
    name: !empty(automationAccountName) ? automationAccountName : '${abbrs.automationAutomationAccounts}${resourceToken}'

    location: location
  }
}

// ------------------------------
// Role assignment: Automation Account -> VMSS Contributor
// ------------------------------
module automationVmssContributor './core/automation/roleAssignments.bicep' = if (deployVllmSupportModel) {
  name: 'automation-vmss-ra'
  scope: rg
  params: {
    automationPrincipalId: deployVllmSupportModel ? automation.outputs.automationAccountPrincipalId : ''
    vmssName: deployVllmSupportModel ? vmss.outputs.vmssNameOut : '' //ハードコードされていた名前を修正
  }
}

// ------------------------------
// Runbooks on Automation
// ------------------------------
module runbooks './core/automation/runbooks.bicep' = if (deployVllmSupportModel) {
  name: 'runbooks'
  scope: rg
  params: {
    automationAccountName: !empty(automationAccountName) ? automationAccountName : '${abbrs.automationAutomationAccounts}${resourceToken}'
    location: location
    startRunbookName: 'rb-start-vmss'
    stopRunbookName: 'rb-stop-vmss'
  }
  dependsOn: [ automation ]
}

// Functions
module apiUserAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = if (deployCodeInterpreter) {
  name: 'apiUserAssignedIdentity'
  scope: rg
  params: {
    location: location
    tags: tags
    name: !empty(apiUserAssignedIdentityName) ? apiUserAssignedIdentityName : '${abbrs.managedIdentityUserAssignedIdentities}api-${resourceToken}'
  }
}


module appServicePlan 'br/public:avm/res/web/serverfarm:0.1.1' = if (deployCodeInterpreter) {
  name: 'appserviceplan'
  scope: rg
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
    sku: {
      name: 'FC1'
      tier: 'FlexConsumption'
    }
    reserved: true
    location: location
    tags: tags
  }
}




module storage 'br/public:avm/res/storage/storage-account:0.8.3' = if (deployCodeInterpreter) {
  name: 'storage'
  scope: rg
  params: {
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false // Disable local authentication methods as per policy
    dnsEndpointType: 'Standard'
    publicNetworkAccess: 'Enabled'

    networkAcls: vnetEnabled ? {
      defaultAction: 'Deny'
      bypass: 'AzureServices' 
      virtualNetworkRules: [
        {
          id: network.outputs.functionSubnetId
        }
      ]
    } : {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }

    blobServices: {
      containers: [{name: deploymentStorageContainerName}]
    }
    privateEndpoints: vnetEnabled ? [
      {
        name: 'pe-blob-${resourceToken}'
        subnetResourceId: network.outputs.peSubnetId
        service: 'blob'
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: '' // AVMモジュールが自動で作成
            }
          ]
        }
      }
    ] : []    
    minimumTlsVersion: 'TLS1_2'  // Enforcing TLS 1.2 for better security
    location: location
    tags: tags
  }
}

module api './app/function.bicep' = if (deployCodeInterpreter) {
  name: 'api'
  scope: rg
  params: {
    name: functionAppName
    location: location
    tags: tags
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    appServicePlanId: deployCodeInterpreter ? appServicePlan.outputs.resourceId : ''
    runtimeName: 'python'
    runtimeVersion: '3.12'
    storageAccountName: deployCodeInterpreter ? storage.outputs.name : ''
    enableBlob: storageEndpointConfig.enableBlob
    enableQueue: storageEndpointConfig.enableQueue
    enableTable: storageEndpointConfig.enableTable
    deploymentStorageContainerName: deploymentStorageContainerName
    identityId: deployCodeInterpreter ? apiUserAssignedIdentity.outputs.resourceId : ''
    identityClientId: deployCodeInterpreter ? apiUserAssignedIdentity.outputs.clientId : ''
    appSettings: {
      AZURE_OPENAI_ENDPOINT: (deployCodeInterpreter || deployOpenAiDirect) ? openai.outputs.openaiEndpoint : ''
      AZURE_OPENAI_API_VERSION: openaiApiVersion
      AZURE_OPENAI_DEPLOYMENT_NAME: (deployCodeInterpreter || deployOpenAiDirect) ? openai.outputs.deploymentName : ''
      AZURE_CLIENT_ID: deployCodeInterpreter ? apiUserAssignedIdentity.outputs.clientId : ''
      OPENAI_TIMEOUT: openaiTimeout
      OPENAI_MAX_RETRIES: openaiMaxRetries
      SYSTEM_PROMPT: systemPrompt
    }
    virtualNetworkSubnetId: vnetEnabled ? network.outputs.functionSubnetId : ''
    publicNetworkAccess: functionPublicNetworkAccess
    allowedIpAddresses: functionAllowedIpAddresses
  }
}

// Function App name output for postprovision scripts
output FUNCTION_APP_NAME string = deployCodeInterpreter ? api.outputs.SERVICE_API_NAME : ''
// Resource group & APIM service name outputs for azd env convenience
output RESOURCE_GROUP_NAME string = rg.name
output APIM_SERVICE_NAME string = apim.outputs.apimServiceName

// Private Endpoint for Azure Functions (conditional)
module functionPrivateEndpoint './app/function-privateendpoint.bicep' = if (deployCodeInterpreter && enableFunctionPrivateEndpoint && vnetEnabled) {
  name: 'function-private-endpoint'
  scope: rg
  params: {
    functionAppName: deployCodeInterpreter ? api.outputs.SERVICE_API_NAME : ''
    functionAppId: deployCodeInterpreter ? resourceId(subscription().subscriptionId, rg.name, 'Microsoft.Web/sites', api.outputs.SERVICE_API_NAME) : ''
    location: location
    tags: tags
    privateEndpointSubnetId: network.outputs.peSubnetId
    virtualNetworkId: network.outputs.vnetId
    staticPrivateIpAddress: functionPrivateEndpointStaticIp
  }
}


module rbac 'app/rbac.bicep' = if (deployCodeInterpreter || deployOpenAiDirect) {
  name: 'rbacAssignments'
  scope: rg
  params: {
    storageAccountName: deployCodeInterpreter ? storage.outputs.name : ''
    appInsightsName: monitoring.outputs.applicationInsightsName
    managedIdentityPrincipalId: deployCodeInterpreter ? apiUserAssignedIdentity.outputs.principalId : ''
    userIdentityPrincipalId: principalId
    enableBlob: storageEndpointConfig.enableBlob
    enableQueue: storageEndpointConfig.enableQueue
    enableTable: storageEndpointConfig.enableTable
    allowUserIdentityPrincipal: storageEndpointConfig.allowUserIdentityPrincipal
    openaiAccountName: openai.outputs.openaiName
    apimPrincipalId: apim.outputs.identityPrincipalId
  }
}


// APIM Settings
module backend './core/gateway/apim-backend.bicep' = {
  name: 'apim-backend-deployment'
  scope: rg
  params: {
    apiManagementServiceName: apim.outputs.apimServiceName
    name: 'appgw-backend'
    title: 'AI API Backend on APPGW'
    description: 'AI API Backend on APPGW'
    credentials: {
      header: {
        'x-apim-secret': [
          apimSecret
        ]
      }
      authorization: {
        scheme: 'Basic'
        parameter: apimSecret
      }
    }

  url: 'http://${appGatewayPrivateIpAddress}:80' 
    protocol: 'http'
  }
}

// Configures the API in the Azure API Management (APIM) service
module apimApi './app/apim-api.bicep' = if (deployVllmSupportModel) {
  name: 'apim-api-deployment'
  scope: rg
  params: {
    name: apim.outputs.apimServiceName
    apiName: plamoApiName
    apiDisplayName: 'vLLM API for Completions'
    apiDescription: 'This is proxy endpoints for vLLM OpenAI-compatible API'
    apiPath: 'vllm'
    
    //API Policy parameters
    corsOriginUrl: corsOriginUrl
    apiBackendId: backend.outputs.name
    apiAllowedSourceIps: apiAllowedSourceIps
    enablePlamoCustomApiTransform: enablePlamoCustomApiTransform
    vllmModelName: vllmModelName
  }
}

// Configures the OpenAI API in APIM (routes to App Gateway -> Functions)
module apimApiOpenai './app/apim-api-openai.bicep' = if (deployCodeInterpreter) {
  name: 'apim-api-openai-deployment'
  scope: rg
  params: {
    name: apim.outputs.apimServiceName
    apiName: codeInterpreterApiName
    apiDisplayName: 'Code Interpreter API via OpenAI API'
    apiDescription: 'Code Interpreter API for Azure OpenAI via App Gateway and Functions'
    apiPath: 'code-interpreter'
    
    //API Policy parameters
    corsOriginUrl: corsOriginUrl
    apiBackendId: backend.outputs.name
    apiAllowedSourceIps: apiAllowedSourceIps
  }
}

// Configures AOAI direct chat completions API in APIM (APIM MI -> AppGW -> AOAI)
module apimApiAoaiDirect './app/apim-api-aoai-direct.bicep' = if (deployOpenAiDirect) {
  name: 'apim-api-aoai-direct-deployment'
  scope: rg
  params: {
    name: apim.outputs.apimServiceName
    apiName: aoaiDirectApiName
    apiDisplayName: 'Azure OpenAI Chat Completions (Direct)'
    apiDescription: 'Azure OpenAI chat completions API via App Gateway using Azure OpenAI API Key.'
    apiPath: 'openai'

    // API Policy parameters
    corsOriginUrl: corsOriginUrl
    apiBackendId: backend.outputs.name
    apiAllowedSourceIps: apiAllowedSourceIps
    openaiAccountName: !empty(openaiAccountName) ? openaiAccountName : '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    openaiApiKey: openai.outputs.openaiKey
    vnetId: network.outputs.vnetId
  }
}

module apimProduct './app/apim-product.bicep' = {
  name: 'apim-product-deployment'
  scope: rg
  params: {
    name: apim.outputs.apimServiceName
    productId: 'genai-product'
    productDisplayName: 'GenAI Product'
    productDescription: 'GenAIのAPI群'
    apiNames: union(
      deployVllmSupportModel ? [plamoApiName] : [],
      deployCodeInterpreter ? [codeInterpreterApiName] : [],
      deployOpenAiDirect ? [aoaiDirectApiName] : []
    )
  }
  dependsOn: [
    apimApi
    apimApiOpenai
    apimApiAoaiDirect
  ]
}

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId

output APIM_BACKEND_ID string = backend.outputs.resourceId
output APIM_BACKEND_NAME string = backend.outputs.name
// Network outputs
output NETWORK_VNET_ID string = network.outputs.vnetId
output NETWORK_APPGW_ID string = network.outputs.appGatewayId
output NETWORK_APPGW_NAME string = network.outputs.appGatewayNameOut

// VMSS outputs (conditional)
output VMSS_ID string = deployVllmSupportModel ? vmss.outputs.vmssId : ''
output VMSS_NAME string = deployVllmSupportModel ? vmss.outputs.vmssNameOut : ''

// Automation outputs (conditional)
output AUTOMATION_ACCOUNT_ID string = deployVllmSupportModel ? automation.outputs.automationAccountId : ''
output AUTOMATION_PRINCIPAL_ID string = deployVllmSupportModel ? automation.outputs.automationAccountPrincipalId : ''
output AUTOMATION_VMSS_ROLE_ASSIGNMENT_ID string = deployVllmSupportModel ? automationVmssContributor.outputs.vmssRoleAssignmentId : ''

// Azure OpenAI outputs
output AZURE_OPENAI_ID string = (deployCodeInterpreter || deployOpenAiDirect) ? openai.outputs.openaiId : ''
output AZURE_OPENAI_NAME string = (deployCodeInterpreter || deployOpenAiDirect) ? openai.outputs.openaiName : ''
output AZURE_OPENAI_ENDPOINT string = (deployCodeInterpreter || deployOpenAiDirect) ? openai.outputs.openaiEndpoint : ''
output AZURE_OPENAI_DEPLOYMENT_NAME string = (deployCodeInterpreter || deployOpenAiDirect) ? openai.outputs.deploymentName : ''
output AZURE_OPENAI_API_VERSION string = openaiApiVersion

// Debug output referencing storage params (non-secret)
output STORAGE_PARAMS_REFERENCE object = _storageParamsReference

