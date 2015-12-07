param (
    [parameter(Mandatory=$true)]
    [string]$SubscriptionId,

    [parameter(Mandatory=$false)]
    [switch]$ResetPassword
)

$ErrorActionPreference = "Stop"

# Check for Azure Powershell installations
Try {
    Import-Module Azure
}
Catch
{
    Write-Host
    Write-Host "ERROR: You must install Azure Powershell 1.0 or higher to run this script."
    Write-Host "Visit here to download the installer: https://github.com/Azure/azure-powershell/releases/latest"
    Break
}

$module = Get-Module Azure
if ($module.Version.Major -lt 1) {
    Write-Host
    Write-Host "ERROR: You must update Azure Powershell to version 1.0 or higher to run this script."
    Write-Host "You have version" $module.Version "installed."
    Write-Host "Uninstall your current version and visit here to download the installer:"
    Write-Host "https://github.com/Azure/azure-powershell/releases/latest"
    Break
}

function SetupAzureAccount() {
    # Prompt user for credentials
    Write-Host
    $account = Get-AzureAccount -WarningAction SilentlyContinue
    if ($account -eq $null) {
        Login-AzureRmAccount -ErrorAction Stop -WarningAction SilentlyContinue
    } else {
        $accountTest = Get-AzureRmSubscription -ErrorAction Ignore -WarningAction SilentlyContinue
        if ($accountTest -eq $null) {
            Write-Host "Azure credentials have expired, please re-enter them."
            Login-AzureRmAccount -ErrorAction Stop -WarningAction SilentlyContinue
        }
        Write-Host "Using Azure account '$($account.Id)'"
    }

    Select-AzureRmSubscription -SubscriptionId $SubscriptionId | Out-Null
}

function SetupRoleDefinition() {
    $roleDef = Get-AzureRmRoleDefinition -Name $roleDefinitionName

    if ($roleDef -eq $null) {
        $roleDef = New-Object Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleDefinition
        $roleDef.Name = $roleDefinitionName
    }

    $roleDef.Actions = @(
        "Microsoft.Compute/virtualMachines/delete",
        "Microsoft.Compute/virtualMachines/read",
        "Microsoft.Compute/virtualMachines/*/read",
        "Microsoft.Compute/virtualMachines/*/action",
        "Microsoft.Compute/locations/vmSizes/read",
        "Microsoft.Storage/storageAccounts/read",
        "Microsoft.Storage/storageAccounts/listKeys/action",
        "Microsoft.Network/virtualNetworks/read",
        "Microsoft.Network/virtualNetworks/*/read",
        "Microsoft.Network/networkInterfaces/delete",
        "Microsoft.Resources/subscriptions/resourceGroups/*",
        "Microsoft.Resources/deployments/*"
        )
    $roleDef.Description = "For use by a Unidesk " + $elmVersion + " Enterprise Layer Manager only."

    $scope = "/subscriptions/" + $SubscriptionId
    if ($roleDef.AssignableScopes -eq $null) {
        $roleDef.AssignableScopes = @($scope)
    } else {
        if (-not $roleDef.AssignableScopes.Contains($scope)) {
            $roleDef.AssignableScopes.Add($scope)
        }
    }

    if ($roleDef.Id -eq $null) {
        return New-AzureRmRoleDefinition -Role $roleDef
    } else {
        return Set-AzureRmRoleDefinition -Role $roleDef
    }
}

function GetPlainTextPassword() {
    Write-Host "Enter a Client Secret for your Unidesk ELM credentials, at least " + $passwordMinLength + " characters long."

    $passwordMinLength = 12
    $passwordPrompt = "-->REMEMBER THIS VALUE, it will never be displayed again and will be needed to set up Unidesk!<--"
    do {
        Write-Host $passwordPrompt

        $SecurePassword = Read-Host -Prompt "Client Secret: " -AsSecureString
        $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword))

        if ($plainPassword.Length -lt $passwordMinLength) {
            $passwordPrompt = "Password is not long enough, try again."
            continue
        }

        $ConfirmPassword = Read-Host -Prompt "Confirm: " -AsSecureString
        $plainConfirm = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($ConfirmPassword))

        $passwordPrompt = "Passwords do not match, try again."
    }
    while (-not ($plainConfirm -ceq $plainPassword))

    return $plainPassword
}

$identifierUri = "http://unideskaccess"
$servicePrincipalName = "Unidesk ELM Access"
$roleDefinitionName = "Unidesk Enterprise Layer Manager for subscription " + $SubscriptionId
$elmVersion = "4.0"

SetupAzureAccount
$roleDefinition = SetupRoleDefinition

$existingServicePrincipal = Get-AzureRmADServicePrincipal -ServicePrincipalName $identifierUri
if ($existingServicePrincipal -ne $null) {
    Write-Host
    Write-Host "Your Unidesk credentials have been updated to support version:" $elmVersion

    if ($ResetPassword) {
        Write-Host
        Write-Host "WARNING: Your password has not been changed. You have already set up your Azure credentials."
        Write-Host "To change your password or set up your credentials again, please follow these instructions at the Unidesk Support Center: [TODO: PUT LINK HERE]"
        Break
    }
}

if ($existingServicePrincipal -eq $null) {
    $password = GetPlainTextPassword
    $adApp = New-AzureRmADApplication -DisplayName "Unidesk ELM Access" -HomePage "http://unused" -IdentifierUris $identifierUri -Password $password
    $adServicePrincipal = New-AzureRmADServicePrincipal -ApplicationId $adApp.ApplicationId
}

$existingRoleAssignment = Get-AzureRmRoleAssignment -RoleDefinitionName $roleDefinitionName -ErrorAction Ignore
if ($existingRoleAssignment -eq $null) {
    $roleAssignment = New-AzureRmRoleAssignment -ServicePrincipalName $identifierUri -RoleDefinitionName $roleDefinitionName
    Write-Host
    Write-Host "Unidesk credentials have been assigned to subscription:" $SubscriptionId
}

Write-Host
Write-Host "Your Unidesk credentials have been set up successfully."
Write-Host
Write-Host "Subscription ID:" $SubscriptionId
Write-Host "Client ID:" $identifierUri
Write-Host "Client Secret: ********"
