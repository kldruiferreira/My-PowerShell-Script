<#
    .SYNOPSIS
        Script to create a new groups and add users to it.
   
    .DESCRIPTION
        This script will remove all licences from the users specificed in a text file
   
    .PARAMETER Users
        Path to text file that contains the list of users that you wish to remove all licences for.  Users listed in UPN format
       
    .EXAMPLE
        .\Get-VMDatastoreLocation.ps1 -UserList C:\scripts\Users.txt
        This example will remove all licences from all users specified in the specified text file
       
    .INPUTS
        CSV File
       
    .OUTPUTS
        Stuff
   
    .NOTES
        By Rui Ferreira
   
    .LINK
       
#>


#Enviroment Setup
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false
Import-Module -Name VMware.PowerCLI



#ScriptInputs
Param(
    [Parameter(Mandatory=$true)]
    [String]$vCenterAddress,

    [Parameter(Mandatory=$true)]
    [pscredential]$Credentials,

    [Parameter()]
    [string]$outputfile = ".\results.csv"
)


#Script Logic



#Script Output




#Disconnect from vCenter

Disconnect-VIServer -Server $vCenterAddress -Confirm:$false