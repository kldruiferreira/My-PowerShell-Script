<#
.SYNOPSIS
    Reports each VM's virtual disk usage per datastore on a vCenter Server.

.DESCRIPTION
    Connects to a vCenter Server, enumerates all VMs, and for each VM
    determines which datastore(s) its virtual disks reside on and how much
    space (GB) it occupies on each one. VMs with disks spread across
    multiple datastores produce one row per VM/datastore pair. Results are
    shown in a console table and exported to a timestamped CSV.

.PARAMETER Server
    vCenter Server FQDN or IP address. Prompted for if not supplied.

.PARAMETER Credential
    PSCredential to authenticate to vCenter. Prompted for if not supplied.

.PARAMETER OutputPath
    Directory to write the CSV report to. Defaults to the current directory.

.PARAMETER IgnoreCertErrors
    When set, configures PowerCLI to ignore invalid/self-signed certificates
    for this session. Off by default so strict cert validation environments
    are not silently overridden.

.EXAMPLE
    .\Get-VMDatastoreUsage.ps1

.EXAMPLE
    .\Get-VMDatastoreUsage.ps1 -Server vcenter.contoso.com -OutputPath "C:\Reports" -IgnoreCertErrors

.EXAMPLE
    $cred = Get-Credential
    .\Get-VMDatastoreUsage.ps1 -Server vcenter.contoso.com -Credential $cred -OutputPath "C:\Reports"
#>
#Requires -Modules VMware.PowerCLI
[CmdletBinding()]
param(
    [string]$Server,
    [PSCredential]$Credential,
    [string]$OutputPath = ".",
    [switch]$IgnoreCertErrors
)

function Initialize-PowerCLIModule {
    if (Get-Module -ListAvailable -Name VMware.PowerCLI) {
        return
    }

    Write-Warning "VMware.PowerCLI module is not installed."
    $answer = Read-Host "Install it now for the current user? (Install-Module -Name VMware.PowerCLI -Scope CurrentUser) [y/N]"

    if ($answer -notmatch '^[Yy]') {
        Write-Error "VMware.PowerCLI is required. Exiting."
        exit 1
    }

    try {
        Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Confirm:$false -Force -ErrorAction Stop
        Write-Host "VMware.PowerCLI installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install VMware.PowerCLI: $_"
        exit 1
    }
}

function Connect-ToVCenter {
    param(
        [string]$Server,
        [PSCredential]$Credential,
        [switch]$IgnoreCertErrors
    )

    Write-Host "=== vCenter Connection ===" -ForegroundColor Cyan

    if ([string]::IsNullOrWhiteSpace($Server)) {
        $Server = Read-Host "vCenter Server FQDN or IP"
    }
    if ([string]::IsNullOrWhiteSpace($Server)) {
        Write-Error "vCenter name cannot be empty."
        exit 1
    }

    if ($null -eq $Credential) {
        $Credential = Get-Credential -Message "Enter credentials for $Server"
    }
    if ($null -eq $Credential) {
        Write-Error "No credentials provided."
        exit 1
    }

    if ($IgnoreCertErrors) {
        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
    }

    try {
        Write-Host "Connecting to $Server..." -ForegroundColor Yellow
        $connection = Connect-VIServer -Server $Server -Credential $Credential -ErrorAction Stop
        Write-Host "Connected to $($connection.Name) (version $($connection.Version))" -ForegroundColor Green
        return $connection
    }
    catch [VMware.VimAutomation.Sdk.Types.V1.ErrorHandling.VimException.ViServerConnectionException] {
        Write-Error "Could not reach vCenter '$Server'. Check the address and network connectivity: $_"
        exit 1
    }
    catch {
        if ($_.Exception.Message -match 'incorrect user name or password|authentication|login') {
            Write-Error "Authentication failed for '$Server'. Check the username/password: $_"
        }
        elseif ($_.Exception.Message -match 'certificate') {
            Write-Error "Certificate validation failed for '$Server'. Re-run with -IgnoreCertErrors if this is a trusted lab environment: $_"
        }
        else {
            Write-Error "Failed to connect to '$Server': $_"
        }
        exit 1
    }
}

function Get-VMDatastoreInfo {
    param(
        [Parameter(Mandatory)]
        $VM
    )

    $results = @()

    try {
        $hardDisks = Get-HardDisk -VM $VM -ErrorAction Stop

        if (-not $hardDisks) {
            return [PSCustomObject]@{
                VMName    = $VM.Name
                Datastore = $null
                SizeGB    = $null
                Status    = "No virtual disks found"
            }
        }

        $byDatastore = $hardDisks | Group-Object { ($_.FileName -split '\]')[0].TrimStart('[') }

        foreach ($group in $byDatastore) {
            $sizeGB = ($group.Group | Measure-Object -Property CapacityGB -Sum).Sum

            $results += [PSCustomObject]@{
                VMName    = $VM.Name
                Datastore = $group.Name
                SizeGB    = [math]::Round($sizeGB, 2)
                Status    = "OK"
            }
        }
    }
    catch {
        $results += [PSCustomObject]@{
            VMName    = $VM.Name
            Datastore = $null
            SizeGB    = $null
            Status    = "Error: $_"
        }
    }

    return $results
}

function Export-VMDatastoreReport {
    param(
        [Parameter(Mandatory)]
        [array]$Results,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $Results | Format-Table -AutoSize

    if (-not (Test-Path -Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $csvPath = Join-Path -Path $OutputPath -ChildPath "VMDatastoreUsage_$timestamp.csv"

    $Results | Export-Csv -Path $csvPath -NoTypeInformation

    Write-Host "`nReport exported to: $csvPath" -ForegroundColor Green
}

# --- Main ---

Initialize-PowerCLIModule

$connection = $null
$allResults = @()

try {
    $connection = Connect-ToVCenter -Server $Server -Credential $Credential -IgnoreCertErrors:$IgnoreCertErrors

    $vms = Get-VM -ErrorAction SilentlyContinue

    if (-not $vms) {
        Write-Warning "No VMs found in the vCenter inventory."
    }

    foreach ($vm in $vms) {
        try {
            $allResults += Get-VMDatastoreInfo -VM $vm
        }
        catch {
            Write-Warning "Failed to process VM '$($vm.Name)': $_"
            $allResults += [PSCustomObject]@{
                VMName    = $vm.Name
                Datastore = $null
                SizeGB    = $null
                Status    = "Error: $_"
            }
        }
    }

    if ($allResults.Count -gt 0) {
        Export-VMDatastoreReport -Results $allResults -OutputPath $OutputPath
    }
    else {
        Write-Warning "No results to export."
    }
}
finally {
    if ($connection) {
        Disconnect-VIServer -Server $connection -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "Disconnected from vCenter." -ForegroundColor Cyan
    }
}
