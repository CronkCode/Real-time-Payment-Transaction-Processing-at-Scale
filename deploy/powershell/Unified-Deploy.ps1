#!/usr/bin/pwsh

Param(
    [parameter(Mandatory=$true)][string]$resourceGroup,
    [parameter(Mandatory=$false)][string]$locations="SouthCentralUS, NorthCentralUS, EastUS",
    [parameter(Mandatory=$false)][string]$openAiLocation="EastUS",
    [parameter(Mandatory=$true)][string]$subscription,
    [parameter(Mandatory=$false)][string]$template="main.bicep",
    [parameter(Mandatory=$false)][string]$suffix=$null,
    [parameter(Mandatory=$false)][bool]$stepDeployBicep=$true,
    [parameter(Mandatory=$false)][bool]$stepBuildPush=$true,
    [parameter(Mandatory=$false)][bool]$stepDeployCertManager=$true,
    [parameter(Mandatory=$false)][bool]$stepDeployTls=$true,
    [parameter(Mandatory=$false)][bool]$stepDeployImages=$true,
    [parameter(Mandatory=$false)][bool]$stepPublishSite=$true,
    [parameter(Mandatory=$false)][bool]$stepLoginAzure=$true
)

az extension add --name  application-insights
az extension update --name  application-insights

az extension add --name storage-preview
az extension update --name storage-preview

winget install --id=Kubernetes.kubectl  -e --accept-package-agreements --accept-source-agreements --silent
winget install --id=Microsoft.Azure.Kubelogin  -e --accept-package-agreements --accept-source-agreements --silent

$gValuesFile="configFile.yaml"

Push-Location $($MyInvocation.InvocationName | Split-Path)

if (-not $suffix) {
    $crypt = New-Object -TypeName System.Security.Cryptography.SHA256Managed
    $utf8 = New-Object -TypeName System.Text.UTF8Encoding
    $hash = [System.BitConverter]::ToString($crypt.ComputeHash($utf8.GetBytes($resourceGroup)))
    $hash = $hash.replace('-','').toLower()
    $suffix = $hash.Substring(0,5)
}

Write-Host "Resource suffix is $suffix" -ForegroundColor Yellow

if ($stepLoginAzure) {
    az login
}

az account set --subscription $subscription

$rg = $(az group show -g $resourceGroup -o json | ConvertFrom-Json)
if (-not $rg) {
    $rg=$(az group create -g $resourceGroup -l $locations.Split(',')[0] --subscription $subscription)
}

# Waiting to make sure resource group is available
Start-Sleep -Seconds 10

if ($stepDeployBicep) {
    & ./Deploy-Bicep.ps1 -resourceGroup $resourceGroup -locations $locations -template $template -suffix $suffix -openAiName $openAiName -openAiRg $openAiRg -openAiDeployment $openAiDeployment
}

# Connecting kubectl to AKS
Write-Host "Retrieving Aks Name" -ForegroundColor Yellow
$aksNames = $(az aks list -g $resourceGroup -o json | ConvertFrom-Json).name
Write-Host "The name of your AKS: $aksName" -ForegroundColor Yellow

az aks enable-addons -g $resourceGroup -n $aksNames[0] --addons http_application_routing
az aks enable-addons -g $resourceGroup -n $aksNames[1] --addons http_application_routing
az aks enable-addons -g $resourceGroup -n $aksNames[2] --addons http_application_routing

# Generate Config
New-Item -ItemType Directory -Force -Path $(./Join-Path-Recursively.ps1 -pathParts ..,..,__values)
$gValuesLocation=$(./Join-Path-Recursively.ps1 -pathParts ..,..,__values,$gValuesFile)
& ./Generate-Config.ps1 -resourceGroup $resourceGroup -openAiName $openAiName -openAiRg $openAiRg -openAiDeployment $openAiDeployment

# Create Secrets
if ([string]::IsNullOrEmpty($acrName))
{
    $acrName = $(az acr list --resource-group $resourceGroup -o json | ConvertFrom-Json).name
}

Write-Host "The Name of your ACR: $acrName" -ForegroundColor Yellow

if ($stepDeployCertManager) {
    # Deploy Cert Manager
    & ./DeployCertManager.ps1
}

if ($stepDeployTls) {
    # Deploy TLS
    & ./DeployTlsSupport.ps1 -sslSupport prod -resourceGroup $resourceGroup -aksName $aksName
}

if ($stepBuildPush) {
    # Build an Push
    & ./BuildPush.ps1 -resourceGroup $resourceGroup -acrName $acrName
}

if ($stepDeployImages) {
    # Deploy images in AKS
    $gValuesLocation=$(./Join-Path-Recursively.ps1 -pathParts ..,..,__values,$gValuesFile)
    $chartsToDeploy = "*"
    & ./Deploy-Images-Aks.ps1 -aksNames $aksNames -resourceGroup $resourceGroup -charts $chartsToDeploy -acrName $acrName -valuesFile $gValuesLocation
}

if ($stepPublishSite) {
    & ./Publish-Site.ps1 -resourceGroup $resourceGroup -storageAccount "webpaysa$suffix"
}

Pop-Location