param (
    [parameter()]
    [string]$SubscriptionName = "BizSpark Plus",

    [parameter()]
    [string]$ResourceGroup = "unidesk-test-resources",

    [parameter()]
    [string]$TestFolder = "DeployAzureFileShare.template.tests"
)

Write-Host

# Prompt user for credentials
$account = Get-AzureAccount -WarningAction SilentlyContinue
if ($account -eq $null) {
    Add-AzureAccount -ErrorAction Stop -WarningAction SilentlyContinue
} else {
    $accountTest = Get-AzureLocation -ErrorAction Ignore -WarningAction SilentlyContinue
    if ($accountTest -eq $null) {
        Write-Host "Azure credentials have expired, please re-enter them."
        Add-AzureAccount -ErrorAction Stop -WarningAction SilentlyContinue
    }
    Write-Host "Using Azure account '$($account.Id)'"
}

Select-AzureSubscription $SubscriptionName -ErrorAction Stop -WarningAction SilentlyContinue
Switch-AzureMode AzureResourceManager -WarningAction SilentlyContinue

$numFailed = 0

Foreach ($paramFile in (Get-ChildItem $TestFolder)) {

    $expectFailure = $paramFile.ToString().StartsWith("fail.")

    $fullParamFilePath = Join-Path $TestFolder $paramFile
    Write-Host "Testing with file:", $fullParamFilePath, "( expecting failure:", $expectFailure, ")"
    
    $result = Test-AzureResourceGroupTemplate -ResourceGroupName $ResourceGroup -TemplateFile .\DeployAzureFileShare.template.json -TemplateParameterFile $fullParamFilePath -ErrorAction Stop -WarningAction SilentlyContinue
    
    if ($result) {
        if (-not $expectFailure) {
            Write-Host ($result | Out-String)
            $numFailed += 1
        }
    } else {
        if ($expectFailure) {
            Write-Host "Template passed when failure was expected."
            $numFailed += 1
        }
    }
}

if ($numFailed -gt 0) {
    Write-Host $numFailed, "test(s) failed."
} else {
    Write-Host "All tests passed."
}

Write-Host
