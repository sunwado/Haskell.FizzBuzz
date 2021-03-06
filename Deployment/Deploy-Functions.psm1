Set-StrictMode -Version latest
$ErrorActionPreference = "Stop"

function New-AzureResourceGroup
(
    [Parameter(Mandatory=$true)][string]$name,
    [Parameter(Mandatory=$true)][string]$location
)
{
    $resourceGroup = Get-AzureRmResourceGroup -Name $Name -Location $Location -ErrorAction Ignore

    if (!$resourceGroup)
    {
        $null = `
            New-AzureRmResourceGroup `
                -Name $name `
                -Location $location
        Write-Output  "'$name' Resource Group located in '$location' has been created"
    }
    else
    {
        Write-Warning "'$name' Resource Group located in '$location' already exists"
    }
}

function Remove-AzureResourceGroup
(
    [Parameter(Mandatory=$true)][string]$name,
    [Parameter(Mandatory=$true)][string]$location
)
{
    $resourceGroup = (Get-AzureRmResourceGroup -Name $Name -Location $Location -ErrorAction Ignore)

    if ($resourceGroup)
    {
        Write-Output  "Removing '$name' Resource Group located in '$location'"
        $null = Remove-AzureRmResourceGroup -Name $name -Force
        Write-Output  "'$name' Resource Group located in '$location' has been removed"
    }
    else
    {
        Write-Warning "'$name' Resource Group located in '$location' does not exist"
    }
}

function New-AzureKeyVault
(
    [Parameter(Mandatory=$true)][string]$name,
    [Parameter(Mandatory=$true)][string]$resourceGroupName,
    [Parameter(Mandatory=$true)][string]$location
)
{
    $keyVault = Get-AzureRmKeyVault -VaultName $Name -ErrorAction Ignore

    if ($null -eq $keyVault)
    {
        $null =
            New-AzureRmKeyVault  `
                -name $name `
                -resourceGroupName $resourceGroupName `
                -location $location `
                -EnabledForDeployment

        Write-Output  "'$name' Key Vault in '$resourceGroupName' Resource Group located in '$location' has been created"
    }
    else
    {
        Write-Warning  "'$name' Key Vault in '$resourceGroupName' Resource Group located in '$location' already exists"
    }
}

function New-SelfSignedCertificateForDevelopment
(
    [Parameter(Mandatory=$true)][string]$domainNameServiceName
)
{
    $certificate = get-childitem -path Cert:\LocalMachine\My -dnsname $domainNameServiceName

    if ($null -eq $certificate)
    {
        $certificate =
            New-SelfSignedCertificate `
                -DnsName $domainNameServiceName `
                -CertStoreLocation Cert:\LocalMachine\My `
                -KeySpec KeyExchange

        Write-Output "Created certificate in LocalMatchine store with DNS Name of '$domainNameServiceName', and Thumbprint '$($certificate.Thumbprint)'"
    }
    else
    {
        Write-Warning "Certificate in LocalMatchine store with DNS Name of '$domainNameServiceName', and Thumbprint '$($certificate.Thumbprint)' already exists"
    }

    return $certificate.Thumbprint
}

function Remove-AzureKeyVault
(
    [Parameter(Mandatory=$true)][string]$name,
    [Parameter(Mandatory=$true)][string]$resourceGroupName,
    [Parameter(Mandatory=$true)][string]$location
)
{
    $keyVault = Get-AzureRmKeyVault -VaultName $Name -ErrorAction Ignore

    if ($null -ne $keyVault)
    {
        Write-Output  "Removing'$name' Key Vault in '$resourceGroupName' Resource Group located in '$location'"
        $null =
            Remove-AzureRmKeyVault `
                -VaultName $name `
                -resourceGroupName $resourceGroupName `
                -location $location `
                -Force

        Write-Output  "'$name' Key Vault in '$resourceGroupName' Resource Group located in '$location' has been removed"
    }
    else
    {
        Write-Warning  "'$name' Key Vault in '$resourceGroupName' Resource Group located in '$location' does not exist"
    }
}

function Test-UserLoggedOn()
{
    return $null -ne (Get-AzureRmContext).Account
}

function Remove-AzureKeyVaultExistingCertificate
(
    [Parameter(Mandatory=$true)][string]$KeyVaultName,
    [Parameter(Mandatory=$true)][string]$domainNameServiceName
)
{
    $azureCertificate = Get-AzureKeyVaultCertificate -VaultName $KeyVaultName -Name $domainNameServiceName -ErrorAction SilentlyContinue

    if ($null -ne $azureCertificate)
    {
        Remove-AzureKeyVaultCertificate `
            -VaultName $KeyVaultName `
            -Name $domainNameServiceName `
            -Force
        Write-Output "Removed '$domainNameServiceName' certificate from the '$KeyVaultName' Key Vault"
    }
    else
    {
        Write-Warning "'Can not remove the $domainNameServiceName' certificate from the '$KeyVaultName' Key Vault as it does not exist"
    }
}

function Import-AzureKeyVaultIfCertificateExists
(
    [Parameter(Mandatory=$true)][string]$KeyVaultName,
    [Parameter(Mandatory=$true)][string]$domainNameServiceName
)
{
    $localCertificate = get-childitem -path Cert:\LocalMachine\My -dnsname $domainNameServiceName

    if($null -eq $localCertificate)
    {
        throw "Could not find '$localCertificate' certificate in LocalMachine Store"
    }

    $fileName = New-TemporaryFile

    $password = [System.Web.Security.Membership]::GeneratePassword(30,10)
    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force

    $azureCertificate = Get-AzureKeyVaultCertificate -VaultName $KeyVaultName -Name $domainNameServiceName -ErrorAction SilentlyContinue

    if ($null -eq $azureCertificate)
    {
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

        $null =
            Export-PfxCertificate `
                -Cert (Get-ChildItem -Path "cert:\LocalMachine\My\$($localCertificate.Thumbprint)") `
                -FilePath $fileName `
                -Password $securePassword -Force

        $null =
            Import-AzureKeyVaultCertificate `
                -VaultName $KeyVaultName `
                -Name $domainNameServiceName `
                -FilePath $fileName `
                -Password $securePassword

        Write-Output "Imported Certificate '$domainNameServiceName' into the '$KeyVaultName' Key Vault"
    }
    else
    {
        Write-Warning "Certificate '$domainNameServiceName' in the '$KeyVaultName' Key Vault has already been imported"
    }
}

function New-Application
(
    [Parameter(Mandatory=$true)][string]$resourceGroupName,
    [Parameter(Mandatory=$true)][string]$KeyVaultName,
    [Parameter(Mandatory=$true)][string]$location,
    [Parameter(Mandatory=$true)][string]$storageAccount,    
    [Parameter(Mandatory=$true)][string]$queueName,  
    [Parameter(Mandatory=$true)][string]$domainNameServiceName,
    [Parameter(Mandatory=$true)][string]$templateFilePath,
    [Parameter(Mandatory=$true)][string]$parametersFilePath
)
{
    New-AzureResourceGroup `
        -name $resourceGroup `
        -location $location

    New-AzureKeyVault `
        -name $keyVault `
        -resourceGroupName $resourceGroup `
        -location $location

    New-SelfSignedCertificateForDevelopment `
        -domainNameServiceName $domainNameServiceName

    Import-AzureKeyVaultIfCertificateExists `
        -KeyVaultName $KeyVaultName `
        -domainNameServiceName $domainNameServiceName

    New-AzureStorageAccount `
        -name $storageAccount `
        -resourceGroupName $resourceGroup `
        -location $location

    New-AzureQueue `
        -queueName $queueName `
        -resourceGroupName $resourceGroupName `
        -storageAccount $storageAccount

    #New-AzureRmResourceGroupDeployment `
    #    -ResourceGroupName $resourceGroup `
    #    -TemplateFile $templateFilePath `
    #    -TemplateParameterFile $parametersFilePath `
    #    -Mode Complete `
    #    -Force `
    #    -DeploymentDebugLogLevel All -Verbose
}

function Remove-Application
(
    [Parameter(Mandatory=$true)][string]$resourceGroupName,
    [Parameter(Mandatory=$true)][string]$location,
    [Parameter(Mandatory=$true)][string]$storageAccount, 
    [Parameter(Mandatory=$true)][string]$queueName,          
    [Parameter(Mandatory=$true)][string]$KeyVaultName,
    [Parameter(Mandatory=$true)][string]$domainNameServiceName
)
{
    Remove-AzureQueue `
        -queueName $queueName `
        -resourceGroupName $resourceGroupName `
        -storageAccount $storageAccount

    Remove-AzureStorageAccount `
        -name $storageAccount `
        -resourceGroupName $resourceGroupName

    Remove-AzureKeyVaultExistingCertificate  `
        -KeyVaultName $keyVaultName `
        -domainNameServiceName $domainNameServiceName

    Remove-AzureKeyVault `
        -name $keyVaultName `
        -resourceGroupName $resourceGroup `
        -location $location

    Remove-AzureResourceGroup `
        -name $resourceGroup `
        -location $location     
}

function New-AzureStorageAccount
(
    [Parameter(Mandatory=$true)][string]$name,
    [Parameter(Mandatory=$true)][string]$resourceGroupName,
    [Parameter(Mandatory=$true)][string]$location
)
{
    $storageAccount = `
        get-AzureRmStorageAccount `
            -ResourceGroupName $resourceGroupName `
            -Name $name `
            -ErrorAction SilentlyContinue

    if ($null -eq $storageAccount)
    {
        $null = New-AzureRmStorageAccount `
            -ResourceGroupName $resourceGroupName `
            -AccountName $name `
            -Location $location `
            -SkuName Standard_GRS

        Write-Output "Created Azure Storage Account '$name' in the '$resourceGroupName' located in '$location'"
    }
    else 
    {
        Write-Warning "Azure Storage Account '$name' in the '$resourceGroupName' located in '$location' is already created"
    }
}

function Remove-AzureStorageAccount
(
    [Parameter(Mandatory=$true)][string]$name,
    [Parameter(Mandatory=$true)][string]$resourceGroupName   
)
{
    $storageAccount = `
        get-AzureRmStorageAccount `
            -ResourceGroupName $resourceGroupName `
            -Name $name `
            -ErrorAction SilentlyContinue


    if ($null -ne $storageAccount)
    {
        $null = Remove-AzureRmStorageAccount `
            -ResourceGroupName $resourceGroupName `
            -AccountName $name `
            -Force       

        Write-Output "Removed Azure Storage Account '$name' in the '$resourceGroupName' located in '$location'"
    }
    else 
    {
        Write-Warning "Azure Storage Account '$name' in the '$resourceGroupName' located in '$location' does not exist"
    }
}

function New-AzureQueue
(
    [Parameter(Mandatory=$true)][string]$queueName,
    [Parameter(Mandatory=$true)][string]$resourceGroupName, 
    [Parameter(Mandatory=$true)][string]$storageAccount
)
{
    $context = `
        (get-AzureRmStorageAccount `
            -Name $storageAccount `
            -ResourceGroupName $resourceGroupName).Context 
    
    $queue = Get-AzureStorageQueue `
            -Context $context `
            -Name $queueName `
            -ErrorAction SilentlyContinue

    if ($null -eq $queue)            
    {
        $null = New-AzureStorageQueue  `
            -name $queueName `
            -Context $context `

        Write-Output "Created the queue '$queueName' on storage account '$storageAccount' for resource group '$resourceGroupName'"
    }
    else
    {
        Write-Warning "Unable to create the queue '$queueName' on storage account '$storageAccount' for resource group '$resourceGroupName' as it already exists"        
    }
}

function Remove-AzureQueue
(
    [Parameter(Mandatory=$true)][string]$queueName,
    [Parameter(Mandatory=$true)][string]$resourceGroupName, 
    [Parameter(Mandatory=$true)][string]$storageAccount
)
{
    $context = `
        (get-AzureRmStorageAccount `
            -Name $storageAccount `
            -ResourceGroupName $resourceGroupName).Context 
    
    $queue = Get-AzureStorageQueue `
            -Context $context `
            -Name $queueName `
            -ErrorAction SilentlyContinue

    if ($null -ne $queue)            
    {
        $null = Remove-AzureStorageQueue `
            -name $queueName `
            -Context $context `
            -Force

        Write-Output "Removed the queue '$queueName' on storage account '$storageAccount' for resource group '$resourceGroupName'"
    }
    else
    {
        Write-Warning "Unable to remove the queue '$queueName' on storage account '$storageAccount' for resource group '$resourceGroupName' as it does not exist"        
    }
}