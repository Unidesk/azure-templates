param (
    [parameter()]
    [string]$SubscriptionName = "BizSpark Plus",

    [parameter()]
    [string]$ResourceGroup = "unidesk-test-resources",

    [parameter()]
    [string]$TemplateFolder = "."
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

function RunTests($templateFile) {

    $testFolder = Join-Path $templateFile.Directory.FullName "tests"

    if (-not (Test-Path $testFolder)) {
        Write-Host "WARNING: test folder", $testFolder, "not found."
        return
    }

    Foreach ($paramFile in (Get-ChildItem $testFolder)) {

        $expectFailure = $paramFile.ToString().StartsWith("fail.")

        $fullParamFilePath = Join-Path $testFolder $paramFile
        Write-Host "Testing:", $fullParamFilePath, "( expecting failure:", $expectFailure, ")"
        
        $result = Test-AzureResourceGroupTemplate -ResourceGroupName $ResourceGroup -TemplateFile $templateFile.FullName -TemplateParameterFile $fullParamFilePath -ErrorAction Stop -WarningAction SilentlyContinue
        
        if ($result) {
            if (-not $expectFailure) {
                Write-Host ($result | Out-String)
                $numFailed += 1
            }
        } else {
            if ($expectFailure) {
                Write-Host "TEST FAILED: Template passed when failure was expected."
                $numFailed += 1
            }
        }
    }
}

function RunTestsOnTemplates($folder) {

    Foreach ($child in (Get-ChildItem $folder)) {

        if ($child.PSIsContainer) {
            RunTestsOnTemplates($child.FullName)
        }
        else {
            if ($child.Name.EndsWith(".template.json")) {
                Write-Host
                Write-Host "Found template:", $child
                RunTests($child)
            }
        }
    }
}

RunTestsOnTemplates($TemplateFolder)

Write-Host
