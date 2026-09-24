<#
.SYNOPSIS
    Pulls Data Size, Backup Size, Dedupe Ratio, and Compression Ratio for all
    (or selected) Veeam Backup & Replication jobs, and calculates overall
    space savings - works across VMware, Hyper-V, and mixed multi-VM jobs.

.NOTES
    Run this directly on the Veeam Backup & Replication server (or a machine
    with the Veeam PowerShell module installed and console connectivity).
    Tested against Veeam Backup & Replication v12.3.2.

    VMware jobs expose storages via GetAllStorages(). Hyper-V jobs don't
    populate that method - they use GetAllChildrenStorages() instead, which
    returns one row per VM per restore point. This script tries the VMware
    method first and falls back automatically.

.EXAMPLE
    .\Get-VeeamDedupeCompressionRatios.ps1 | Format-Table -AutoSize

.EXAMPLE
    .\Get-VeeamDedupeCompressionRatios.ps1 -JobName "UKT-Hyper-V" | Format-Table -AutoSize

.EXAMPLE
    .\Get-VeeamDedupeCompressionRatios.ps1 | Export-Csv -Path "C:\Temp\VeeamRatios.csv" -NoTypeInformation

.NOTES
    The script returns plain objects (no Format-Table baked in), so it plays
    nicely with Export-Csv. Add "| Format-Table -AutoSize" yourself when you
    just want to eyeball it on screen.
#>

[CmdletBinding()]
param(
    # Optional: filter to one job name (wildcards allowed). Leave blank for all jobs.
    [string]$JobName = "*",

    # Show one row per VM instead of one summed row per job
    [switch]$PerVM
)

# Load the Veeam PowerShell module if it isn't already loaded
if (-not (Get-Module -Name Veeam.Backup.PowerShell)) {
    Import-Module Veeam.Backup.PowerShell -ErrorAction Stop
}

function Get-VMKeyFromPath {
    param($Path)
    # Pulls a VM/host identifier out of the storage file path, e.g.
    # ...\UKT-Hyper-V\UK1T1EVEADBZ001.57355de6-....vib  ->  UK1T1EVEADBZ001
    $leaf = Split-Path $Path -Leaf
    return $leaf.Split('.')[0]
}

$results = @()

$jobs = Get-VBRJob | Where-Object { $_.Name -like $JobName }

foreach ($job in $jobs) {

    $backups = Get-VBRBackup | Where-Object { $_.JobName -eq $job.Name }
    if (-not $backups) { continue }

    foreach ($b in $backups) {

        # Try the VMware-style method first
        $storages = $b.GetAllStorages()

        # Fall back to the Hyper-V-style method if that came back empty
        if (-not $storages) {
            $storages = $b.GetAllChildrenStorages()
        }

        if (-not $storages) {
            Write-Warning "No storages found for job '$($job.Name)' - skipping."
            continue
        }

        # Group by VM so multi-VM jobs are summed/reported correctly,
        # and within each VM keep only the most recent restore point
        $latestPerVM = $storages |
            Group-Object { Get-VMKeyFromPath $_.FilePath } |
            ForEach-Object { $_.Group | Sort-Object CreationTime -Descending | Select-Object -First 1 }

        if ($PerVM) {
            foreach ($s in $latestPerVM) {
                $stats = $s.Stats
                $results += [PSCustomObject]@{
                    JobName        = $job.Name
                    VM             = Get-VMKeyFromPath $s.FilePath
                    'DataSize(GB)' = [math]::Round($stats.DataSize / 1GB, 2)
                    'BackupSize(GB)' = [math]::Round($stats.BackupSize / 1GB, 2)
                    DedupeRatio    = "$($stats.DedupRatio)%"
                    CompressRatio  = "$($stats.CompressRatio)%"
                    OverallRatioX  = if ($stats.BackupSize -gt 0) { "{0:N2}:1" -f ($stats.DataSize / $stats.BackupSize) } else { "n/a" }
                }
            }
        }
        else {
            $totalData    = ($latestPerVM | ForEach-Object { $_.Stats.DataSize } | Measure-Object -Sum).Sum
            $totalBackup  = ($latestPerVM | ForEach-Object { $_.Stats.BackupSize } | Measure-Object -Sum).Sum

            $overallRatio = if ($totalBackup -gt 0) { [math]::Round($totalData / $totalBackup, 2) } else { 0 }
            $spaceSavedPct = if ($totalData -gt 0) { [math]::Round((1 - ($totalBackup / $totalData)) * 100, 1) } else { 0 }

            $results += [PSCustomObject]@{
                JobName          = $job.Name
                VMCount          = $latestPerVM.Count
                'DataSize(GB)'   = [math]::Round($totalData / 1GB, 2)
                'BackupSize(GB)' = [math]::Round($totalBackup / 1GB, 2)
                OverallRatioX    = "$overallRatio`:1"
                SpaceSavedPct    = "$spaceSavedPct%"
            }
        }
    }
}

$results
