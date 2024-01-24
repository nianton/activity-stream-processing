param name string
param location string = resourceGroup().location
param tags object = {}
param eventHubName string
param consumerGroupName string

@allowed([
  'Standard'
  'Basic'
])
param eventHubSku string = 'Standard'

@allowed([
  1
  2
  4
])
param skuCapacity int = 1

resource namespace 'Microsoft.EventHub/namespaces@2021-06-01-preview' = {
  name: name
  location: location
  sku: {
    name: eventHubSku
    tier: eventHubSku
    capacity: skuCapacity
  }
  properties: {}
  tags: tags
}

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2021-06-01-preview' = {
  parent: namespace
  name: eventHubName
  properties: {}
}

resource authRule 'Microsoft.EventHub/namespaces/authorizationRules@2021-06-01-preview' = {
  parent: namespace
  name: 'AppAuthRule'
  properties: {
    rights: [
      'Listen'
      'Send'
    ]
  }
}

resource consumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2021-06-01-preview' = {
  parent: eventHub
  name: consumerGroupName
  properties: {}  
}

output eventHubNamespaceId string = namespace.id
output eventHubId string = eventHub.id
output namespaceConnectionString string = listkeys(authRule.id, authRule.apiVersion).primaryConnectionString
