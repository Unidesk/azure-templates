
$dataDisks = Get-PhysicalDisk | Where CanPool
$storSub = Get-StorageSubSystem
$totalSize = ($dataDisks | Select -ExpandProperty Size | Measure-Object -Sum).Sum

$storagePool = New-StoragePool -FriendlyName UnideskStoragePool -PhysicalDisks $dataDisks -StorageSubSystemFriendlyName $storSub.FriendlyName
New-VirtualDisk -StoragePoolFriendlyName $storagePool.FriendlyName -ResiliencySettingName Simple -Size $totalSize -ProvisioningType Thin -FriendlyName UnideskVirtualDisk

$newDisk = Get-Disk | Where FriendlyName -eq "Microsoft Storage Space Device"
$newDisk | Initialize-Disk -PartitionStyle MBR
$newPartition = $newDisk | New-Partition -AssignDriveLetter -UseMaximumSize
$newVolume = $newPartition | Format-Volume -FileSystem NTFS -NewFileSystemLabel "UnideskFileShare" -Confirm:$false

$sharePath = $newVolume.DriveLetter + ":\"
New-SmbShare -Name Share -Path $sharePath -FullAccess Users
