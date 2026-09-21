<#
	.SYNOPSIS
		Checks Enabled status of AD accounts in Altegrity and corp.eddom.org
	
	.DESCRIPTION
		This script will use the csv suppiled by HR to check the enabled status of the users listed in there 
	
	.PARAMETER csv
		the path to the csv suppiled by HR

	.PARAMETER OutFile
		specify the name of the csv file you want the results exported to (Optional)
		
	.EXAMPLE
		./Check-TerminatedUserAccount.ps1 -Path "C:\scripts\05-29-2022 to 06-05-2022 Weekly IT Terms.csv"
		This example will check the enabled status of the users listed in 05-29-2022 to 06-05-2022 Weekly IT Terms.csv

	.EXAMPLE
		./Check-TerminatedUserAccount.ps1 -Path "C:\scripts\05-29-2022 to 06-05-2022 Weekly IT Terms.csv" -OutFile results.csv
		This example will check the enabled status of the users listed in 05-29-2022 to 06-05-2022 Weekly IT Terms.csv and save the results to a csv called results.csv
		
	.INPUTS
		String
		
	.OUTPUTS
		Stuff
	
	.NOTES
		By Phillip Bland
	
	.LINK
		http://www.nd-it.com
#>

# Declare parameters, csv mandatory, outfile optional
Param
(
	[Parameter(Mandatory=$True,Position=0)]
	[string]$csv,
	[Parameter(Mandatory=$False,Position=1)]
	[string]$OutFile
)

# Declare Constants
$AltegrityDC = "uk1p1ainfmad001.corp.altegrity.com"
$EDDOMDC = "osuk1pads2adc01.corp.eddom.org"
$Results = @()

# Get and test credentials for altegrity
$AltegrityCreds = Get-Credential -Title "Altegrity Creds" -Message "Please enter your credentials for the Altegrity domain"
try
{
	Get-ADUser $AltegrityCreds.UserName -Credential $AltegrityCreds -Server $AltegrityDC | Out-Null
}
catch
{
	Write-Host "Invaild credentials, exiting script"
	Exit
}

# Get and test credentials for corp.eddom.org
$EDDOMCreds = Get-Credential -Title "corp.eddom.org Creds" -Message "Please enter your credentials for the corp.eddom.org domain"
try
{
	Get-ADUser $EDDOMCreds.UserName -Credential $EDDOMCreds -Server $EDDOMDC | Out-Null
}
catch
{
	Write-Host "Invaild credentials, exiting script"
	Exit
}

# Import csv
$Users = Import-Csv $csv

# Run through each user in csv
foreach ($User in $Users)
{
    # Build filter string for Get-ADuser
	$GivenName = $User."First Name"
	$Surname = $User."Last Name"
	$Filter = "GivenName -eq ""$GivenName"" -and Surname -eq ""$Surname"""
	
	# Seach for user in altegrity
	try
	{
		$Results += Get-ADUser -Filter $Filter -Server $AltegrityDC -Credential $AltegrityCreds -Properties * | Select GivenName, Surname, SamAccountName, Enabled, CanonicalName
	}
	catch
	{
		$Results += New-Object psobject -Property @{"GivenName" = $GivenName; "Surname" = $Surname; "SamAccountName" = "Not Found"; "Enabled" = "Not Found"; "CanonicalName" = "Not Found"}
	}

	# Search for user in corp.eddom.org
	try
	{
		$Results += Get-ADUser -Filter $Filter -Server $EDDOMDC -Credential $EDDOMCreds -Properties * | Select GivenName, Surname, SamAccountName, Enabled, CanonicalName
	}
	catch
	{
		$Results += New-Object psobject -Property @{"GivenName" = $GivenName; "Surname" = $Surname; "SamAccountName" = "Not Found"; "Enabled" = "Not Found"; "CanonicalName" = "Not Found"}
	}
}

# Display results
$Results | Select GivenName, Surname, SamAccountName, enabled, CanonicalName |  Out-GridView

# If outfile parameter is specified output results to csv
if ($Outfile)
{
	$Results | Export-Csv $Outfile
}
