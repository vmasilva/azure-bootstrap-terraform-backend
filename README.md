# azure-bootstrap-terraform-backend
Helper script to initialize all resources pre-required to start using terraform

# Backend Initialization

Helper script to initialize a terraform, creating the backend configuration and all the required cloud resources.  

## What does it do?

This powershell script deploys the initial configuration required to use terraform. It creates the following resources in Azure:  
    - 1 Resource Group where the resources will be deployed into.  
    - 1 storage account and a blob container where terraform state will be stored.  
    - Optional: 1 key vault with a customized secrets list

### Security/Compliance aspects
Network control access: Storage account and keyvault are configured to allow access only from your IP. If you need to access from another location, you need to adjust this configuration. 

## Deploy diagram

![Resources deployed by this script](documentation/tf-helper-script.drawio.png)

## How to use it ? 
1. Setup the script variables for your environment
Open the file initial-setup.ps1 and setup your environment in the following block:  
```
####################################################################
### Variables - You should setup your environment on this block
####################################################################

## Account details:
$subscriptionId = "1111111f-111f-1111-111f-11111ff111ff"    # Your subscription id
$subscriptionName = 'vmasilva-account' # it will be used as precedent
## Optional Tags
$optionalTag = "ENV=DEV"

$location='westeurope'              # location to deploy the storage account
$deploy_keyVault = 'yes'            # Should deploy a KeyVault? values: 'yes' or 'no' (if already deployed, switch to 'no' will not destroy - it will just skip...)
$deploy_keyVaultSecrets = 'yes'     # Should populate the KeyVault with secrets? values: yes or no (if already deployed, switch to 'no' will not destroy, it will just skip)
$keyVaultSecrets = ("api-key","username","password")    # Set the KeyVault Secrets list which you want to deploy - it will depend in the use case. ex.: ("api-key","username","password","other-secret")
```
2. Run the script  
Open PowerShell and run the script:  
```
.\initial-setup.ps1 

(you should get an output like this:)
(...)
Generating terraform backend config file: backend.conf
DONE: Initial Setup has been successfully executed! You dont need to run this script anymore.
Now you can initialize Terraform, typing:
##> terraform init -backend-config="backend.conf"
```

3. Run again?  
You can run this command the times you want, it will not destroy any configuration.  
It could be usefull to run again, to update the network firewall rules (case your external IP changed), and also, to setup the terraform authentication as this command exports the necessary environment variables.  123