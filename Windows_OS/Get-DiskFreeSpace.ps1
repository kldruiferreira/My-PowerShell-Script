# Get-DiskFreeSpace.ps1

# Checks free space on all fixed disks (PowerShell 5.1 compatible)

    # Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    #     $freeGB  = [math]::Round($_.FreeSpace / 1GB, 2)
    #     $sizeGB  = [math]::Round($_.Size / 1GB, 2)
    #     $usedGB  = [math]::Round($sizeGB - $freeGB, 2)
    #     $pctFree = if ($_.Size -gt 0) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 2) } else { 0 }

    #     [PSCustomObject]@{
    #         Drive       = $_.DeviceID
    #         Label       = $_.VolumeName
    #         'Size(GB)'  = $sizeGB
    #         'Used(GB)'  = $usedGB
    #         'Free(GB)'  = $freeGB
    #         'FreePct'   = "$pctFree%"
    #     }
    # } | Format-Table -AutoSize


# Checks free space on all fixed disks (PowerShell 7+ compatible)

Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $freeGB  = [math]::Round($_.FreeSpace / 1GB, 2)
    $sizeGB  = [math]::Round($_.Size / 1GB, 2)
    $usedGB  = [math]::Round($sizeGB - $freeGB, 2)
    $pctFree = if ($_.Size -gt 0) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 2) } else { 0 }

    [PSCustomObject]@{
        Drive       = $_.DeviceID
        Label       = $_.VolumeName
        'Size(GB)'  = $sizeGB
        'Used(GB)'  = $usedGB
        'Free(GB)'  = $freeGB
        'FreePct'   = "$pctFree%"
    }
} | Format-Table -AutoSize