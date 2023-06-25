@description('Cosmos DB account name, max length 44 characters, lowercase')
param cosmosAccountName string = 'cosmospay${suffix}'

@description('EventHub namespace, max length 44 characters, lowercase')
param eventHubNamespace string = 'eventhubpay${suffix}'

@description('Function App name')
param functionAppName string = 'functionpay${suffix}'

@description('Storage account name, max length 24 characters, lowercase')
param storageAccountName string = 'blobpay${suffix}'

@description('Front Door name')
param frontDoorName string = 'apipaymentsfd${suffix}'

@description('Enable Cosmos Multi Master')
param enableCosmosMultiMaster bool = true

@description('Locations for resource deployment')
param locations string = 'SouthCentralUS, NorthCentralUS, EastUS'

@description('Suffix for resource deployment')
param suffix string = uniqueString(resourceGroup().id)

@description('Static website storage account name, max length 24 characters, lowercase')
param websiteStorageAccountName string = 'webpaysa${suffix}'

@description('OpenAI service name')
param openAiName string = 'openaipayments${suffix}'

@description('OpenAi Deployment')
param openAiDeployment string = 'completions'

@description('OpenAI Resource Group')
param openAiResourceGroup string

var locArray = split(replace(locations, ' ', ''), ',')

module eventHub 'eventhub.bicep' = {
  scope: resourceGroup()
  name: 'eventHubDeploy'
  params: {
    eventHubNamespace: eventHubNamespace
    location: locArray[0]
  }
}

module cosmosdb 'cosmos.bicep' = {
  scope: resourceGroup()
  name: 'cosmosDeploy'
  params: {
    accountName: cosmosAccountName
    locations: locArray
    enableCosmosMultiMaster: enableCosmosMultiMaster
  }
}

// TODO: Deploy via Bicep. Presently, attempting this results in the following error:
//   {"code": "ApiSetDisabledForCreation", "message": "It's not allowed to create new accounts with type 'OpenAI'."}
// module openAi 'openai.bicep' = {
//   name: 'openAiDeploy'
//   params: {
//     openAiName: openAiName
//     location: locArray[0]
//     deployments: [
//       {
//         name: 'completions'
//         model: 'text-davinci-003'
//         version: '1'
//         sku: {
//           name: 'Standard'
//           capacity: 60
//         }
//       }
//     ]
//   }
// }

module blob 'blob.bicep' = [for (location, i) in locArray: {
  name: 'blobDeploy-${location}'
  params: {
    storageAccountName: '${storageAccountName}${i}'
    location: location
  }
}]

@batchSize(1)
module function 'functions.bicep' = [for (location, i) in locArray: {
  name: 'functionDeploy-${location}'
  params: {
    cosmosAccountName: cosmosdb.outputs.cosmosAccountName
    eventHubNamespaceName: eventHubNamespace
    functionAppName: '${functionAppName}${i}'
    storageAccountName: '${storageAccountName}${i}'
    paymentsDatabase: cosmosdb.outputs.cosmosDatabaseName
    transactionsContainer: cosmosdb.outputs.cosmosTransactionsContainerName
    customerContainer: cosmosdb.outputs.cosmosCustomerContainerName
    memberContainer: cosmosdb.outputs.cosmosMemberContainerName
    preferredRegions: join(concat(array(location), filter(locArray, l => l != location)), ',')
    isMasterRegion: i == 0 || enableCosmosMultiMaster ? true : false
    location: location
    openAiName: openAiName
    openAiDeployment: openAiDeployment
    openAiResourceGroup: openAiResourceGroup
  }
  dependsOn: [
    blob
  ]
}]

module frontdoor 'frontdoor.bicep' = {
  name: 'frontdoorDeploy'
  params: {
    enableMultiMaster: enableCosmosMultiMaster
    frontDoorName: frontDoorName
    functionNames: [for i in range(0, length(locArray)): function[i].outputs.functionName]
  }
}

module staticwebsite 'staticwebsite.bicep' = {
  name: 'staticwebsiteDeploy'
  params: {
    storageAccountName: websiteStorageAccountName
    location: locArray[0]
  }
}
