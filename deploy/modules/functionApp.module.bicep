param name string
param location string = resourceGroup().location
param tags object = {}
param funcWorkerRuntime string = 'java'
param funcExtensionVersion string = '~4'
param funcAppSettings array = []
param managedIdentity bool = false
param linux bool = false

@allowed([
  'Y1'
  'EP1'
  'EP2'
  'EP3'
])
param skuName string = 'Y1'

param funcDeployRepoUrl string = ''
param funcDeployBranch string = ''
param subnetIdForIntegration string = ''
param includeSampleFunction bool = false
param appInsInstrumentationKey string = ''

var skuTier = skuName == 'Y1' ? 'Dynamic' : 'Elastic'
var funcAppServicePlanName = 'plan-${name}'
var funcStorageName = 's${replace(name, '-', '')}'
var funcAppInsName = 'appins-${name}'
var createSourceControl = !empty(funcDeployRepoUrl)
var createNetworkConfig = !empty(subnetIdForIntegration)
var existingAppInsights = !empty(appInsInstrumentationKey)
var siteConfigAddin = linux ? {
  linuxFxVersion:  'Java|11'
  javaVersion: '11'
} : { 
  javaVersion: '11'
}

module funcStorage './storage.module.bicep' = {
  name: funcStorageName
  params: {
    name: funcStorageName
    location: location
    tags: tags
  }
}

module funcAppIns './appInsights.module.bicep' = if (!existingAppInsights) {
  name: funcAppInsName
  params: {
    name: funcAppInsName
    location: location
    tags: tags
    project: name
  }
}

resource funcAppServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: funcAppServicePlanName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    reserved: linux
  }
}

resource funcApp 'Microsoft.Web/sites@2022-09-01' = {
  name: name
  location: location
  kind: linux ? 'functionapp,linux' : 'functionapp'
  identity: {
    type: managedIdentity ? 'SystemAssigned' : 'None'
  }
  properties: {
    serverFarmId: funcAppServicePlan.id
    siteConfig: union({
      appSettings: concat([
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: funcExtensionVersion
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: funcWorkerRuntime
        }
        {
          name: 'AzureWebJobsDashboard'
          value: funcStorage.outputs.connectionString
        }
        {
          name: 'AzureWebJobsStorage'
          value: funcStorage.outputs.connectionString
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: funcStorage.outputs.connectionString
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(name)
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: existingAppInsights ? appInsInstrumentationKey : funcAppIns.outputs.instrumentationKey 
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: 'InstrumentationKey=${existingAppInsights ? appInsInstrumentationKey : funcAppIns.outputs.instrumentationKey}'
        }
      ], funcAppSettings)
    }, siteConfigAddin)
    httpsOnly: true
    clientAffinityEnabled: false
    reserved: linux
  }
  tags: tags
}

resource networkConfig 'Microsoft.Web/sites/networkConfig@2022-09-01' = if (createNetworkConfig) {
  parent: funcApp
  name: 'virtualNetwork'
  properties: {
    subnetResourceId: subnetIdForIntegration
  }
}

resource funcAppSourceControl 'Microsoft.Web/sites/sourcecontrols@2022-09-01' = if (createSourceControl) {
  parent: funcApp
  name: 'web'
  properties: {
    branch: funcDeployBranch
    repoUrl: funcDeployRepoUrl
    isManualIntegration: true
  }
}

resource sampleFunction 'Microsoft.Web/sites/functions@2022-09-01' = if (includeSampleFunction) {
  parent: funcApp
  name: 'sampleFunction'
  properties: {
    config: {
      bindings: [
        {
          name: 'req'
          authLevel: 'anonymous'
          type: 'httpTrigger'
          direction: 'in'
          methods: [
            'get'
            'post'
          ]
        }
        {
          name: '$return'
          type: 'http'
          direction: 'out'
        }
      ]
      files:{
        'run.csx': '#r "Newtonsoft.Json"\n\nusing System.Net;\nusing Microsoft.AspNetCore.Mvc;\nusing Microsoft.Extensions.Primitives;\nusing Newtonsoft.Json;\n\npublic static async Task<IActionResult> Run(HttpRequest req, ILogger log)\n{\n    log.LogInformation("C# HTTP trigger function processed a request.");\n\n    string name = req.Query["name"];\n\n    string requestBody = await new StreamReader(req.Body).ReadToEndAsync();\n    dynamic data = JsonConvert.DeserializeObject(requestBody);\n    name = name ?? data?.name;\n\n    string responseMessage = string.IsNullOrEmpty(name)\n        ? "This HTTP triggered function executed successfully. Pass a name in the query string or in the request body for a personalized response."\n                : $"Hello, {name}. This HTTP triggered function executed successfully.";\n\n            return new OkObjectResult(responseMessage);\n}\n'
      }  
    }
  }
}

output id string = funcApp.id
output name string = funcApp.name
output appServicePlanId string = funcAppServicePlan.id
output identity object = {
  tenantId: funcApp.identity.tenantId
  principalId: funcApp.identity.principalId
  type: funcApp.identity.type
}
output applicationInsights object = existingAppInsights ? {} : funcAppIns
output storage object = funcStorage
