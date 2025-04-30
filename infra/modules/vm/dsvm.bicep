param location string
param name string
param tags object = {}
param subnetId string
param bastionSubId string
@secure()
param vmUserPassword string
param vmUserName string
param authenticationType string = 'password' //'sshPublicKey'
@secure()
param vmUserPasswordKey string
param keyVaultName string
param principalId string
param azdEnvironmentName string

var vmSize = {
  'CPU-4GB': 'Standard_B2s'
  'CPU-7GB': 'Standard_D2s_v3'
  'CPU-8GB': 'Standard_D2s_v3'
  'CPU-14GB': 'Standard_D4s_v3'
  'CPU-16GB': 'Standard_D4s_v3'
  'GPU-56GB': 'Standard_NC6_Promo'
}
var publicIpName = '${name}PublicIp'
var nicName = '${name}Nic'
var diskName = '${name}Disk'
var bastionName = '${name}Bastion'

var bastionZones = [
  '1'
  '2'
  '3'
]


var linuxConfiguration = {
  disablePasswordAuthentication: true
  ssh: {
    publicKeys: [
      {
        path: '/home/${vmUserName}/.ssh/authorized_keys'
        keyData: vmUserPassword
      }
    ]
  }
}

resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  zones: bastionZones
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAddressVersion: 'IPv4'
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }  
        }
      }
    ]
  }
}

resource virtualMachine 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize['CPU-16GB']
    }
    storageProfile: {
      imageReference: {
        publisher: 'microsoft-dsvm'
        offer: 'dsvm-win-2022'
        sku: 'winserver-2022'
        version: 'latest'
      }
      osDisk: {
        name: diskName
        createOption: 'FromImage'
      }
    }
    osProfile: {
      computerName: 'adp-vm'
      adminUsername: vmUserName
      adminPassword: vmUserPassword
      linuxConfiguration: ((authenticationType == 'password') ? json('null') : linuxConfiguration)
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

var fileUris = [
  'https://raw.githubusercontent.com/givenscj/ai-document-processor/refs/heads/cjg-zta-durable/infra/install.ps1'
]

resource cse 'Microsoft.Compute/virtualMachines/extensions@2024-11-01' = {
  parent: virtualMachine
  name: 'cse'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    forceUpdateTag: 'alwaysRun'
    settings: {
      fileUris: fileUris
      commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -File install.ps1 -AzureTenantId ${subscription().tenantId} -AzureSubscriptionId ${subscription().subscriptionId} -AzureResourceGroupName ${resourceGroup().name} -AzdEnvName ${azdEnvironmentName}'
    }
    protectedSettings: {
      
    }
  }
}

output vmPrincipalId string = virtualMachine.identity.principalId

resource cy 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: bastionName
  location: location
  sku: {
    name: 'Standard'
  }
  zones : bastionZones
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: bastionSubId
          }
          publicIPAddress: {
            id: bastionPublicIp.id // use a public IP address for the bastion
          }
        }
      }
    ]
  }
}


resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, 'Contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: virtualMachine.identity.principalId
  }
}

// Using key vault to store the password.
// Not using the application key vault as it is set with no public network access for zero trust, but Bastion need the public network access
// to pul the secret from the key vault.
resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'standard'
      family: 'A'
    }
    tenantId: subscription().tenantId
    accessPolicies: [
    ]
    enableRbacAuthorization: true
  }
}

resource vmUserPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: vmUserPasswordKey
  properties: {
    value: vmUserPassword
  }
}

resource KeyVaultAccessRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, principalId, keyVault.id, 'Key Vault Secrets Officer')
  scope: keyVault
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  }
}
