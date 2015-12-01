param (
    [parameter()]
    [string]$SubscriptionName = "BizSpark Plus",

    [parameter()]
    [string]$ResourceGroup = "unidesk-test-resources",

    [parameter()]
    [string]$StorageAccount = "unideskintegrationtest",

    [parameter()]
    [string]$StorageContainer = "resources-do-not-delete",

    [parameter()]
    [string]$ScriptFile = "SetupFileShare.ps1"
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

$keys = Get-AzureStorageAccountKey -ResourceGroupName $ResourceGroup -Name $StorageAccount
$context = New-AzureStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $keys.Key1
Set-AzureStorageBlobContent -Context $context -Container $StorageContainer -Blob $ScriptFile -BlobType Block -File $ScriptFile -Force -ErrorAction Stop

Write-Host
Write-Host "File uploaded successfully."
