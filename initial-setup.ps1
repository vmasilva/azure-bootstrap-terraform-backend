<#
This powershell script deploys the initial configuration required to use terraform. It creates the following resources in Azure:
    - 1 Resource Group where the resources will be deployed into.
    - 1 storage account and a blob container where terraform state will be stored.
    - Optional: 1 KeyVault, with a custom list of secrets

documentation resources official reference: https://docs.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage?tabs=powershell
#>
####################################################################
### Variables - You should setup your environment on this block
####################################################################

## Account details:
# Set the correct tennantID:
#$tennantId = "1111aaaa-11aa-11aa-11aa-11111111aaaa"
$subscriptionId = "1111111f-111f-1111-111f-11111ff111ff"    # Your subscription id
$subscriptionId = "69bca278-71de-4b9a-bde0-e8f9601adae0"    
$subscriptionName = 'vmsilva'                      # it will be used as precedent - Used for help to identify the resources
$location = 'westeurope'                                    # Location to deploy the storage account
## Optional tags
$optionalTag = "ENV=DEV"
$deploy_keyVault = 'yes'                                    # Should deploy a KeyVault? values: 'yes' or 'no' (if already deployed, switch to 'no' will not destroy, it will just skip)
$deploy_keyVaultSecrets = 'yes'                             # Should populate the KeyVault with secrets? values: yes or no (if already deployed, switch to 'no' will not destroy, it will just skip)
$keyVaultSecrets = ("api-key","username","password")        # Set the KeyVault Secrets list which you want to deploy - it will depend in the use case. ex.: ("api-key","username","password","other-secret")

### Script internal variables - you shouldnt need to change these...
$resourceGroupName = 'rg-tfstate-secrets'
$keyVaultName = 'kv-'+$subscriptionName+'-secrets'
$storageAccountName = $subscriptionName+'tfstate'
$containerName = 'tfstate'
$terrafomBackendConfigFile = "backend.conf"
####################################################################
### Script block - You shouldnt modify anything below this line.... 
####################################################################

function Check-ScriptVariables{
    $inputErrors=0

    Write-Output "Subscription name: $subscriptionName"
    Write-Output $subscriptionName.Length

    if (!('yes','no',1,0).contains($deploy_keyVault)){
        Write-Output "INPUT-ERROR: The provided value for variable 'deploy_keyVault' is not allowed. Please provide one of the following values: ['yes', 'no', 1 or 0]"
        $inputErrors=1
    }
    if (!('yes','no',1,0).contains($deploy_keyVaultSecrets)){
        Write-Output "INPUT-ERROR: The provided value for variable 'deploy_keyVaultSecrets' is not allowed. Please provide one of the following values: ['yes', 'no', 1 or 0]"
        $inputErrors=1
    }
    if ($inputErrors) { exit 1 }
}
function Get-ExternalIP{
    return (Invoke-WebRequest -uri "https://ipinfo.io/ip").content
}

Check-ScriptVariables
$myIP=Get-ExternalIP
Write-Output "Detected External IP: $myIP"

az account clear # Force to clean az authentication. (it avoids some errors from IAM access cache...)
az login 
# For Multi-Tenant
#az login -t $tennantId --output none # Authenticate and Set Context

az account set -s $subscriptionId
# 1st access verification - Checking access to the specified account
# Causes: missing access to the subscription
if ( $? -eq $false ) {
    Write-Output "ERROR: Failing while accessing to subscription. Possible causes: wrong subscriptionId, wrong tennatID or missing permissions."
    Write-Output "FAILED: Initial Setup has been failed! Check the errors above and then try again."
    exit 1 
}

# Create resource group
az group create --name $resourceGroupName --location $location --tags $tagAcpLevel $tagFactId
# 2nd access verification, because, when using PIM you are able to set the subscription, but not to use it
# Causes: PIM not enabled yet
if ( $? -eq $false ) {
    Write-Output "ERROR: Failing accessing to subscription resources. Possible causes: PIM not enabled yet or missing permissions."
    Write-Output "FAILED: Initial Setup has been failed! Check the errors above and then try again."
    exit 1 
}
Write-Output "Created resource group"
# Create storage account
az storage account create --resource-group $resourceGroupName --name $storageAccountName --kind StorageV2 --access-tier Hot --sku Standard_LRS --encryption-services blob --https-only true --min-tls-version "TLS1_2" --allow-blob-public-access false
Write-Output "Created storage account"
#enforce firewall on storage account
az storage account update --resource-group $resourceGroupName --name $storageAccountName --default-action Deny
az storage account network-rule add --resource-group $resourceGroupName --account-name $storageAccountName --ip-address $myIP
# Get storage account key 
$accountKeyName = $(az storage account keys list --resource-group $resourceGroupName --account-name $storageAccountName --query [0].keyName -o tsv)
$accountKeyValue = $(az storage account keys list --resource-group $resourceGroupName --account-name $storageAccountName --query [0].value -o tsv)
$env:ARM_ACCESS_KEY = $accountKeyValue
# Create blob container
az storage container create --name $containerName --account-name $storageAccountName --account-key $accountKeyValue
Write-Output "Created Container"
#Create key vault to store some pre-required secrets 
if ($deploy_keyVault -eq 'yes' -or $deploy_keyVault -eq 1 ){
    az keyvault create --name $keyVaultName --resource-group $resourceGroupName --location $location --sku Standard  --enabled-for-disk-encryption --enable-purge-protection true
    Write-Output "Created Keyvault"
    # Update Firewall settings and add local IP
    az keyvault update --name $keyVaultName --resource-group $resourceGroupName --default-action "Deny"
    az keyvault network-rule add --resource-group $resourceGroupName --name $keyVaultName --ip-address $myIP
    Write-Output "Created Keyvault firewall rule"
}

if ($deploy_keyVaultSecrets -eq 'yes' -or $deploy_keyVaultSecrets -eq 1 ){
    #Create key vault Secrets
    foreach ($keyVaultSecret in $keyVaultSecrets)
    {
        $secretValue = Read-Host "Secret '$keyVaultSecret' - Please enter the secret value"
        az keyvault secret set --vault-name $keyVaultName --name $keyVaultSecret --value $secretValue
    }
}

# Generate backend configuration file
Write-Output "Generating terraform backend config file: $terrafomBackendConfigFile"
$terrafomBackendConfigFileContent=@'
# This file has been auto-generated by the initial-setup script file.
# You can change this file, but, keep in mind that if you run initial-setup script file again, this file will be overwrited'
resource_group_name   = "{0}"
storage_account_name  = "{1}"
container_name        = "{2}"
key                   = "{3}"
'@ -f $resourceGroupName, $storageAccountName, $containerName, $accountKeyName
Set-Content -Path $terrafomBackendConfigFile -Value $terrafomBackendConfigFileContent

# Successfull message
Write-Warning "Be aware that the resource group '$resourceGroupName' will store sensitive information! You should restrict as possible the access to this resource group."
Write-Output "DONE: Initial Setup has been successfully executed! You dont need to run this script again."
Write-Output "Now you can initialize Terraform (the account key is already defined in the ENV variable ARM_ACCESS_KEY). You only need to type:"
Write-Output "##> terraform init -backend-config=""$terrafomBackendConfigFile"""  