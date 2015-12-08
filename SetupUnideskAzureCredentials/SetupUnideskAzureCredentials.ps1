
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

function ReadFromList($prompt, $options, $displayProperties) 
{
    Write-Host "---------------------------------------------"
    Write-Host
    Write-Host $prompt

    For ($i =0; $i -lt $options.Length; $i++) {
        $options[$i] | Add-Member -MemberType NoteProperty -Name "Num" -Value ($i + 1)
    }

    [System.Collections.ArrayList]$displayProperties = $displayProperties
    $displayProperties.Insert(0, "Num")

    if ($displayProperties -ne $null) {
        $optionList = $options | Select -ExpandProperty $displayProperties[0]
    } else {
        Write-Host "".PadLeft($prompt.Length, '-')
        Write-Host
        $optionList = $options
    }
    $options | Select $displayProperties | Format-Table -AutoSize | Out-Host

    if ($displayProperties -eq $null) {
        Write-Host
    }

    do {
        $selection = Read-Host "Enter the number of your selection"
        $selectionIndex = ($selection -as [int]) - 1
    } while ($selectionIndex -lt 0 -or $selectionIndex -ge $optionList.Length)

    Write-Host
    return $options[$selectionIndex]
}

function SetupAzureAccount() {
    # Prompt user for credentials
    Write-Host
    Login-AzureRmAccount | Out-Null
    Write-Host "Using Azure account '$($account.Id)'"
}

function SetupRoleDefinition($subId) {
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

    $scope = "/subscriptions/" + $subId
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
    $passwordMinLength = 12
    
    Write-Host "---------------------------------------------"
    Write-Host
    Write-Host "Enter a Client Secret for your Unidesk ELM credentials, at least" $passwordMinLength "characters long."

    $passwordPrompt = "-->REMEMBER AND SAFEGUARD THIS VALUE, it will never be displayed again and will be needed to set up Unidesk!<--"
    do {
        Write-Host
        Write-Host $passwordPrompt
        Write-Host

        $SecurePassword = Read-Host -Prompt "Client Secret" -AsSecureString
        $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword))

        if ($plainPassword.Length -lt $passwordMinLength) {
            $passwordPrompt = "Client secret is not long enough, please try again."
            continue
        }

        $ConfirmPassword = Read-Host -Prompt "      Confirm" -AsSecureString
        $plainConfirm = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($ConfirmPassword))

        $passwordPrompt = "Client secrets do not match, please try again."
    }
    while (-not ($plainConfirm -ceq $plainPassword))

    return $plainPassword
}

SetupAzureAccount

# Pick subscription
$subscriptions = Get-AzureRmSubscription
$selectedSubscription = ReadFromList "Choose the Azure subscription you want to use with Unidesk: " $subscriptions @("SubscriptionName", "SubscriptionId")
$SubscriptionId = $selectedSubscription.SubscriptionId

Select-AzureRmSubscription -SubscriptionId $SubscriptionId | Out-Null

$identifierUri = "http://unideskaccess"
$servicePrincipalName = "Unidesk ELM Access"
$roleDefinitionName = "Unidesk Enterprise Layer Manager for subscription " + $SubscriptionId
$elmVersion = "4.0"
$roleDefinition = SetupRoleDefinition $SubscriptionId

$existingServicePrincipal = Get-AzureRmADServicePrincipal -ServicePrincipalName $identifierUri
if ($existingServicePrincipal -eq $null) {
    $password = GetPlainTextPassword
    $adApp = New-AzureRmADApplication -DisplayName "Unidesk ELM Access" -HomePage "http://unused" -IdentifierUris $identifierUri -Password $password
    $adServicePrincipal = New-AzureRmADServicePrincipal -ApplicationId $adApp.ApplicationId
    
    # Give Azure a moment to set up the service principal
    Write-Host
    Write-Host "Setting up Azure Active Directory application..."
    Sleep 10
}
else {
    Write-Host
    Write-Host "You have already set up your Client Secret."
    Write-Host "If you wish to change your Client Secret, please follow these instructions at the Unidesk Support Center:"
    Write-Host "[TODO: PUT LINK HERE]"
}

$existingRoleAssignment = Get-AzureRmRoleAssignment -ServicePrincipalName $identifierUri -ErrorAction Ignore
if ($existingRoleAssignment -eq $null) {
    $roleAssignment = New-AzureRmRoleAssignment -ServicePrincipalName $identifierUri -RoleDefinitionName $roleDefinitionName
    Write-Host
    Write-Host "Unidesk credentials have been assigned to subscription:" $selectedSubscription.SubscriptionName
}

Write-Host
Write-Host "---------------------------------------------"
Write-Host "Your Unidesk credentials have been set up successfully. Enter these values into the connector configuration page:"
Write-Host
Write-Host "Subscription ID: " $SubscriptionId
Write-Host "Tenant ID:       " $selectedSubscription.TenantId
Write-Host "Client ID:       " $identifierUri
Write-Host "Client Secret:    ********"
Write-Host "Storage Account:  [Use the name of a storage account you wish to deploy to.]"
Write-Host 
Write-Host "Manage your storage accounts in the Azure portal here:"
Write-Host "https://portal.azure.com/#blade/HubsExtension/BrowseResourceBlade/resourceType/Microsoft.Storage%2FStorageAccounts/scope/"
Write-Host
