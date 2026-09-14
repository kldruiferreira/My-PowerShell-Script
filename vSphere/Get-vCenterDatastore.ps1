<#
    .SYNOPSIS
        List vCenter datastore information

    .DESCRIPTION
        This script gathers information on all datastores listed in vCenter, including device ID, clusters attached, and size information.

    .PARAMETER vCenterAddress
        vCenter server name or IP.

    .PARAMETER Credentials
        PSCredential object for authentication.

    .PARAMETER outputfile
        Path to export the CSV results.

    .EXAMPLE
        .\Get-vCenterDatastore.ps1 -vCenterAddress VC1.local -Credentials $myCred -outputfile .\result.csv
        This example gathers all the datastores into a CSV file.

    .INPUTS
        vCenter Name
        Credentials

    .OUTPUTS
        CSV file

    .NOTES
        By Rui Ferreira

    .LINK

#>

#ScriptInputs

Param(
    [Parameter(Mandatory=$true)]
    [String]$vCenterAddress,

    [Parameter(Mandatory=$true)]
    [pscredential]$Credentials,

    [Parameter()]
    [string]$outputfile = ".\results.csv"
)

#Enviroment Setup

Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false
Import-Module -Name VMware.PowerCLI

#Script Logic

#Connection to vCenter

Connect-VIServer -Server $vCenterAddress -Credential $Credentials

#Build a host-to-cluster lookup table once, to avoid re-querying per datastore

$hostClusterMap = @{}
Get-VMHost | ForEach-Object {
    $hostClusterMap[$_.Name] = ($_ | Get-Cluster).Name
}

#Get datastore information grouped by cluster

$datastoreReport = Get-Datastore | Where-Object {$_.Type -eq "VMFS"} | ForEach-Object {
    $ds = $_
    $dsHosts = $ds | Get-VMHost
    $clusters = $dsHosts | ForEach-Object { $hostClusterMap[$_.Name] } | Select-Object -Unique

    [PSCustomObject]@{
        Datastore   = $ds.Name
        NAA_ID      = $ds.ExtensionData.Info.Vmfs.Extent[0].DiskName
        Cluster     = ($clusters -join ", ")
        CapacityGB  = [math]::Round($ds.CapacityGB, 2)
        FreeSpaceGB = [math]::Round($ds.FreeSpaceGB, 2)
    }
}

#Script Output

$datastoreReport | Export-Csv -Path $outputfile -NoTypeInformation

#Disconnect from vCenter

Disconnect-VIServer -Server $vCenterAddress -Confirm:$false