param
(
    [Parameter(Mandatory = $true)]
    [string]$InfrastructureOutputsPath
)

$InfrastructureOutputs = Get-Content -Path $InfrastructureOutputsPath -Raw | ConvertFrom-Json

$AzureLocation = $InfrastructureOutputs.environmentInfo.value.azureLocation
$AzureResourceGroup = $InfrastructureOutputs.environmentInfo.value.azureResourceGroup
$WorkloadName = $InfrastructureOutputs.environmentInfo.value.workloadName
$ContainerRegistryName = $InfrastructureOutputs.environmentInfo.value.containerRegistryName
$AzureOpenAIChatDeployment = $InfrastructureOutputs.environmentInfo.value.azureOpenAIChatDeployment
$AppConfigurationName = $InfrastructureOutputs.environmentInfo.value.appConfigurationName

$ContainerName = "ai-document-pipeline"
$ContainerVersion = (Get-Date -Format "yyMMddHHmm")
$ContainerImageName = "${ContainerName}:${ContainerVersion}"
$AzureContainerImageName = "${ContainerRegistryName}.azurecr.io/${ContainerImageName}"

Push-Location -Path $PSScriptRoot

Write-Host "Starting ${ContainerName} deployment..."

az --version

Write-Host "Building ${ContainerImageName} image..."

az acr login --name $ContainerRegistryName --resource-group $AzureResourceGroup

docker build -t $ContainerImageName -f ../../../src/AIDocumentPipeline/Dockerfile ../../../src/AIDocumentPipeline/.

Write-Host "Pushing ${ContainerImageName} image to Azure..."

docker tag $ContainerImageName $AzureContainerImageName
docker push $AzureContainerImageName

Write-Host "Deploying Azure Container Apps for ${ContainerName}..."

$DeploymentOutputs = (az deployment group create --name ai-document-pipeline-app --resource-group $AzureResourceGroup --template-file './app.bicep' `
        --parameters './app.bicepparam' `
        --parameters workloadName=$WorkloadName `
        --parameters appConfigurationName=$AppConfigurationName `
        --parameters location=$AzureLocation `
        --parameters containerImageName=$ContainerImageName `
        --parameters chatModelDeployment=$AzureOpenAIChatDeployment `
        --query properties.outputs -o json) | ConvertFrom-Json

$DeploymentOutputs | ConvertTo-Json | Out-File -FilePath './AppOutputs.json' -Encoding utf8

Write-Host "Cleaning up old ${ContainerName} images in Azure Container Registry..."

az acr run --cmd "acr purge --filter '${ContainerName}:.*' --untagged --ago 1h" --registry $ContainerRegistryName --resource-group $AzureResourceGroup /dev/null

Pop-Location

return $DeploymentOutputs
