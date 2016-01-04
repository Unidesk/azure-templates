# Copyright (c) 2015 Unidesk Corporation

# This software includes components from Microsoft Azure PowerShell which is licensed under the Apache License, Version 2.0.  Visit  https://github.com/Azure/azure-powershell for additional information.
# Microsoft Azure PowerShell includes the AutoMapper library ("AutoMapper") which is license under the MIT License.

Param(
    # Parameters are for developer use only
    [string]$clientIdPrefix = "unideskaccess", 
    [switch]$noLogin
)

$ErrorActionPreference = "Stop"

Write-Host
Write-Host "Loading required module (AzureRM.Profile)..."

Import-Module -Name .\AzureRM.Profile

Write-Host "Loading required module (AzureRM.Resources)..."

Import-Module -Name .\AzureRM.Resources

function ReadFromList($prompt, $options, $displayProperties) 
{
    Write-Host
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

    do {
        $selection = Read-Host "Enter the number of your selection"
        $selectionIndex = ($selection -as [int]) - 1
    } while ($selectionIndex -lt 0 -or $selectionIndex -ge $optionList.Length)

    return $options[$selectionIndex]
}

function SetupAzureAccount() {
    # Prompt user for credentials
    Write-Host "Logging into Azure..."
    Login-AzureRmAccount | Out-Null
}

function GetPlainTextPassword() {
    $passwordMinLength = 16
    
    Write-Host "---------------------------------------------"
    Write-Host
    Write-Host "Enter a Client Secret for your Unidesk ELM credentials, at least" $passwordMinLength "characters long."
    Write-Host
    Write-Host "!!! KEEP THIS SECRET SAFE! It can be used to access to your Azure subscription."

    $passwordPrompt = "!!! REMEMBER THIS VALUE, it will never be displayed again and will be needed to set up Unidesk."
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

if (-not $noLogin) {
    SetupAzureAccount
}

# Pick subscription
$subscriptions = Get-AzureRmSubscription
$selectedSubscription = ReadFromList "Choose the Azure subscription you want to use with Unidesk: " $subscriptions @("SubscriptionName", "SubscriptionId")
$SubscriptionId = $selectedSubscription.SubscriptionId

Select-AzureRmSubscription -SubscriptionId $SubscriptionId | Out-Null

$identifierUri = "http://" + $clientIdPrefix + "-" + $SubscriptionId
$applicationDisplayName = "Unidesk ELM Access for " + $selectedSubscription.SubscriptionName

if ($clientIdPrefix -ne "unideskaccess") {
    $applicationDisplayName = $applicationDisplayName + " (" + $clientIdPrefix + ")"
}

$elmVersion = "4.0"

$roleDefinitionName = "Contributor"

$alreadySetup = $false

Try {
    $existingServicePrincipal = Get-AzureRmADServicePrincipal -ServicePrincipalName $identifierUri -ErrorAction Stop
    if ($existingServicePrincipal -eq $null) {

        # This will throw if the account does not have the correct authorization
        Get-AzureRmADServicePrincipal | Out-Null

        $password = GetPlainTextPassword
        $adApp = New-AzureRmADApplication -DisplayName $applicationDisplayName -HomePage "http://unused" -IdentifierUris $identifierUri -Password $password
        $adServicePrincipal = New-AzureRmADServicePrincipal -ApplicationId $adApp.ApplicationId
    }
    else {
        $alreadySetup = $true
    }
}
Catch {
    if ($_.Exception[0].Error.OriginalMessage.Contains("Authorization_RequestDenied")) {
        Write-Host
        Write-Host "Checking if credentials have already been configured for this subscription..."
        $existingRoleAssignment = Get-AzureRmRoleAssignment -RoleDefinitionName $roleDefinitionName | Where DisplayName -EQ $applicationDisplayName
        if ($existingRoleAssignment -eq $null) {
            Write-Host
            Write-Host "ERROR: This Azure account does not have the required Azure Active Directory authorization needed to setup credentials for Unidesk."
            Write-Host "Please contact your primary Azure administrator and ask them to run this tool."
            Write-Host
            Return
        }
        if ($existingRoleAssignment.Length -gt 1) {
            Write-Host
            Write-Host "ERROR: found multiple role assignments with the name'" $applicationDisplayName "', will exit with original error."
            Throw $_
        }
        $alreadySetup = $true
    } else {
        Throw $_
    }
}

if ($existingRoleAssignment -eq $null) {
    $existingRoleAssignment = Get-AzureRmRoleAssignment -ServicePrincipalName $identifierUri -RoleDefinitionName $roleDefinitionName -ErrorAction Ignore
    if ($existingRoleAssignment -eq $null) {
        Write-Host
        Write-Host "Creating role assignment..."
        Sleep 5

        $completed = $false
        $retries = 6;
    
        While (-not $completed) {
            Try {
                $roleAssignment = New-AzureRmRoleAssignment -ServicePrincipalName $identifierUri -RoleDefinitionName $roleDefinitionName -ErrorAction Continue
                $completed = $true
            }
            Catch {
                $retries--
                if ($retries -ge 0 -and $_.Exception[0].Error.Code -eq "PrincipalNotFound") {
                    Write-Host "Waiting for the service principal to finish creating..."
                    Sleep 5
                } else {
                    Throw $_
                }
            }
        }
    }
}

Write-Host
Write-Host "---------------------------------------------"
Write-Host

if ($alreadySetup) {
    Write-Host "You have already set up your Client Secret for this subscription."
    Write-Host "If you wish to change your Client Secret, please follow these instructions at the Unidesk Support Center:"
    Write-Host "  http://www.unidesk.com/support/learn/for_Azure/app_layers/connector_config#Client_ID_and_Client_Secret"
} else {
    Write-Host "Your Unidesk credentials have been set up successfully."
}

Write-Host
Write-Host "Enter these values into the connector configuration page:"
Write-Host
Write-Host "Subscription ID: " $SubscriptionId
Write-Host "Tenant ID:       " $selectedSubscription.TenantId
Write-Host "Client ID:       " $identifierUri
Write-Host "Client Secret:    ********"
Write-Host "Storage Account:  [Use the name of a storage account you wish to deploy to.]"
Write-Host 
Write-Host "Manage your storage accounts in the Azure portal here:"
Write-Host "  https://portal.azure.com/#blade/HubsExtension/BrowseResourceBlade/resourceType/Microsoft.Storage%2FStorageAccounts/scope/"
Write-Host

# SIG # Begin signature block
# MIIOLQYJKoZIhvcNAQcCoIIOHjCCDhoCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUd5KZs5FLrL+4mVfBD+cjtO76
# nRmgggssMIIFGjCCBAKgAwIBAgIQWZnH6hKnLLp8qq7uxT0DAjANBgkqhkiG9w0B
# AQUFADCBtDELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDlZlcmlTaWduLCBJbmMuMR8w
# HQYDVQQLExZWZXJpU2lnbiBUcnVzdCBOZXR3b3JrMTswOQYDVQQLEzJUZXJtcyBv
# ZiB1c2UgYXQgaHR0cHM6Ly93d3cudmVyaXNpZ24uY29tL3JwYSAoYykxMDEuMCwG
# A1UEAxMlVmVyaVNpZ24gQ2xhc3MgMyBDb2RlIFNpZ25pbmcgMjAxMCBDQTAeFw0x
# NTA4MjUwMDAwMDBaFw0xNzA5MTMyMzU5NTlaMHcxCzAJBgNVBAYTAlVTMRYwFAYD
# VQQIEw1NYXNzYWNodXNldHRzMRQwEgYDVQQHEwtNYXJsYm9yb3VnaDEcMBoGA1UE
# ChQTVW5pZGVzayBDb3Jwb3JhdGlvbjEcMBoGA1UEAxQTVW5pZGVzayBDb3Jwb3Jh
# dGlvbjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAIVWgpPhHqFGz11k
# LyZU6La9kdLNku7VNWSaEJznmhgfGooQt0XM9e1wLHs7aQnOhAV7/Gt/YE4xCwQj
# kvorHI1N4IOrfDyayQga/cASEElc3GI3xNWzKRwswsAbcPCNmdtyrOPE7ysp8c1f
# wiQ2ZwWKLJpE0fr+vXZ+PYOo55eE4AhttDpfwo2B22pKBq8KilB1eaK7h017cwhy
# ilsWUK+wsYA9F38PYZWkRpQcmIQcgxFf3D9xdW0JkLkQojutdB0y9ogHdDVhyRl1
# LX3Fp1FrpmsdHrxxTMi8C+a9SZWxj1qwqedFBrd48Fzq0Vsj3hnyanSbjNHlvuI4
# kozMNUsCAwEAAaOCAWIwggFeMAkGA1UdEwQCMAAwDgYDVR0PAQH/BAQDAgeAMCsG
# A1UdHwQkMCIwIKAeoByGGmh0dHA6Ly9zZi5zeW1jYi5jb20vc2YuY3JsMGYGA1Ud
# IARfMF0wWwYLYIZIAYb4RQEHFwMwTDAjBggrBgEFBQcCARYXaHR0cHM6Ly9kLnN5
# bWNiLmNvbS9jcHMwJQYIKwYBBQUHAgIwGQwXaHR0cHM6Ly9kLnN5bWNiLmNvbS9y
# cGEwEwYDVR0lBAwwCgYIKwYBBQUHAwMwVwYIKwYBBQUHAQEESzBJMB8GCCsGAQUF
# BzABhhNodHRwOi8vc2Yuc3ltY2QuY29tMCYGCCsGAQUFBzAChhpodHRwOi8vc2Yu
# c3ltY2IuY29tL3NmLmNydDAfBgNVHSMEGDAWgBTPmanqeyb0S8mOj9fwBSbv49Kn
# nTAdBgNVHQ4EFgQUfXMHfqr+7HQSavkyvIxjevIyXuMwDQYJKoZIhvcNAQEFBQAD
# ggEBANW4iekmgvt9NeolK0vSr1qU+xz57REqSRmS2NDqqceyPeVOP7ei0fjnxCzh
# tevBt/BrZDRuODutIyiP2xxFoVPEL+Z7HAhx9QybDiNyaDYun/89NK2wyHVvp5FL
# 3q+Rxxcc/L5eC2tz7RKDpfm99tP1mFWEzhbkeJBPw8kK42RgFVq/Ew62p+rz+oCJ
# jNGC+qGLmM3dVMrgEWHAlfq67SaVObl0LpgCc72P9vjikV0YrM2vwY3vmeim79bJ
# lTV2SFo3uewtSbVp86mWhSt9SaMlCp910nZz9R/ZD1SxWtCrzaTU3xLnARq+uIt0
# NA+NttKMFoSY9s2zED2qKZVqGk0wggYKMIIE8qADAgECAhBSAOWqJVb8GobtlsnU
# SzPHMA0GCSqGSIb3DQEBBQUAMIHKMQswCQYDVQQGEwJVUzEXMBUGA1UEChMOVmVy
# aVNpZ24sIEluYy4xHzAdBgNVBAsTFlZlcmlTaWduIFRydXN0IE5ldHdvcmsxOjA4
# BgNVBAsTMShjKSAyMDA2IFZlcmlTaWduLCBJbmMuIC0gRm9yIGF1dGhvcml6ZWQg
# dXNlIG9ubHkxRTBDBgNVBAMTPFZlcmlTaWduIENsYXNzIDMgUHVibGljIFByaW1h
# cnkgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkgLSBHNTAeFw0xMDAyMDgwMDAwMDBa
# Fw0yMDAyMDcyMzU5NTlaMIG0MQswCQYDVQQGEwJVUzEXMBUGA1UEChMOVmVyaVNp
# Z24sIEluYy4xHzAdBgNVBAsTFlZlcmlTaWduIFRydXN0IE5ldHdvcmsxOzA5BgNV
# BAsTMlRlcm1zIG9mIHVzZSBhdCBodHRwczovL3d3dy52ZXJpc2lnbi5jb20vcnBh
# IChjKTEwMS4wLAYDVQQDEyVWZXJpU2lnbiBDbGFzcyAzIENvZGUgU2lnbmluZyAy
# MDEwIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA9SNLXqXXirsy
# 6dRX9+/kxyZ+rRmY/qidfZT2NmsQ13WBMH8EaH/LK3UezR0IjN9plKc3o5x7gOCZ
# 4e43TV/OOxTuhtTQ9Sc1vCULOKeMY50Xowilq7D7zWpigkzVIdob2fHjhDuKKk+F
# W5ABT8mndhB/JwN8vq5+fcHd+QW8G0icaefApDw8QQA+35blxeSUcdZVAccAJkpA
# PLWhJqkMp22AjpAle8+/PxzrL5b65Yd3xrVWsno7VDBTG99iNP8e0fRakyiF5UwX
# Tn5b/aSTmX/fze+kde/vFfZH5/gZctguNBqmtKdMfr27Tww9V/Ew1qY2jtaAdtcZ
# LqXNfjQtiQIDAQABo4IB/jCCAfowEgYDVR0TAQH/BAgwBgEB/wIBADBwBgNVHSAE
# aTBnMGUGC2CGSAGG+EUBBxcDMFYwKAYIKwYBBQUHAgEWHGh0dHBzOi8vd3d3LnZl
# cmlzaWduLmNvbS9jcHMwKgYIKwYBBQUHAgIwHhocaHR0cHM6Ly93d3cudmVyaXNp
# Z24uY29tL3JwYTAOBgNVHQ8BAf8EBAMCAQYwbQYIKwYBBQUHAQwEYTBfoV2gWzBZ
# MFcwVRYJaW1hZ2UvZ2lmMCEwHzAHBgUrDgMCGgQUj+XTGoasjY5rw8+AatRIGCx7
# GS4wJRYjaHR0cDovL2xvZ28udmVyaXNpZ24uY29tL3ZzbG9nby5naWYwNAYDVR0f
# BC0wKzApoCegJYYjaHR0cDovL2NybC52ZXJpc2lnbi5jb20vcGNhMy1nNS5jcmww
# NAYIKwYBBQUHAQEEKDAmMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC52ZXJpc2ln
# bi5jb20wHQYDVR0lBBYwFAYIKwYBBQUHAwIGCCsGAQUFBwMDMCgGA1UdEQQhMB+k
# HTAbMRkwFwYDVQQDExBWZXJpU2lnbk1QS0ktMi04MB0GA1UdDgQWBBTPmanqeyb0
# S8mOj9fwBSbv49KnnTAfBgNVHSMEGDAWgBR/02Wnwt3su/AwCfNDOfoCrzMxMzAN
# BgkqhkiG9w0BAQUFAAOCAQEAViLmNKTEYctIuQGtVqhkD9mMkcS7zAzlrXqgIn/f
# RzhKLWzRf3EafOxwqbHwT+QPDFP6FV7+dJhJJIWBJhyRFEewTGOMu6E01MZF6A2F
# JnMD0KmMZG3ccZLmRQVgFVlROfxYFGv+1KTteWsIDEFy5zciBgm+I+k/RJoe6WGd
# zLGQXPw90o2sQj1lNtS0PUAoj5sQzyMmzEsgy5AfXYxMNMo82OU31m+lIL006ybZ
# rg3nxZr3obQhkTNvhuhYuyV8dA5Y/nUbYz/OMXybjxuWnsVTdoRbnK2R+qztk7pd
# yCFTwoJTY68SDVCHERs9VFKWiiycPZIaCJoFLseTpUiR0zGCAmswggJnAgEBMIHJ
# MIG0MQswCQYDVQQGEwJVUzEXMBUGA1UEChMOVmVyaVNpZ24sIEluYy4xHzAdBgNV
# BAsTFlZlcmlTaWduIFRydXN0IE5ldHdvcmsxOzA5BgNVBAsTMlRlcm1zIG9mIHVz
# ZSBhdCBodHRwczovL3d3dy52ZXJpc2lnbi5jb20vcnBhIChjKTEwMS4wLAYDVQQD
# EyVWZXJpU2lnbiBDbGFzcyAzIENvZGUgU2lnbmluZyAyMDEwIENBAhBZmcfqEqcs
# unyqru7FPQMCMAkGBSsOAwIaBQCgeDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAA
# MBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgor
# BgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBQjSaH54dHWv7PHtqq1F5LfEJ6oVjAN
# BgkqhkiG9w0BAQEFAASCAQBngW/V9oDstKowllN0d4UkJQEtlOJX3Wpky8PAHCv+
# Qr6Q+4Dv9XQWfvSIUzWB911ZIW7mRF7y0trcuxI6MK403SO9QUmX6XrXZUn4Fd0w
# U6FsvW8LFMqXvG7kIFeYvZcTX5i/8HjYaR34ewZXT8hrACTNeT9pGDMPsHyb2Q+L
# CkZX7pRyW1XcmeKJEwnJBw5e7/EhYXEUU/7qFZ0ByaIXsJE2CCnZvY4GKdc0MG3c
# LAxhzkuufqV46wTl/+ZsWbqfIiiYsSW4zSK0qNk9tVURfmkAuoR7zfwbB9uLx+vu
# zT0i1CLALDKrpiTkK8usp7B6V+7DIfCpOHIyc5KrqOCP
# SIG # End signature block
