<#
	.SYNOPSIS
		Checks Enabled status of AD accounts in Altegrity and corp.eddom.org

	.DESCRIPTION
		This script uses a CSV supplied by HR (with "First Name" / "Last Name" columns) to check
		whether the corresponding AD accounts in the Altegrity and corp.eddom.org domains are still
		enabled. Any account found to still be Enabled is flagged in the Status column, since a
		terminated employee's account being enabled is the condition this script exists to catch.

	.PARAMETER Csv
		The path to the csv supplied by HR. Must exist and contain "First Name" and "Last Name" columns.

	.PARAMETER OutFile
		Specify the path of the csv file you want the results exported to (Optional)

	.EXAMPLE
		./Check-TerminatedUserAccount.ps1 -Csv "C:\scripts\05-29-2022 to 06-05-2022 Weekly IT Terms.csv"
		This example will check the enabled status of the users listed in the given csv.

	.EXAMPLE
		./Check-TerminatedUserAccount.ps1 -Csv "C:\scripts\05-29-2022 to 06-05-2022 Weekly IT Terms.csv" -OutFile results.csv
		This example will check the enabled status of the users listed in the given csv and save the results to results.csv

	.INPUTS
		String

	.OUTPUTS
		Objects with GivenName, Surname, SamAccountName, Enabled, CanonicalName, Domain, and Status
		(Status flags accounts that are still Enabled, Disabled, Not Found, or errored).

	.NOTES
		By Phillip Bland

	.LINK
		http://www.nd-it.com
#>

#Requires -Modules ActiveDirectory

[CmdletBinding()]
Param
(
	[Parameter(Mandatory = $true, Position = 0)]
	[ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
	[string]$Csv,

	[Parameter(Mandatory = $false, Position = 1)]
	[string]$OutFile
)

$ErrorActionPreference = 'Stop'

# Domains to check. Add/remove entries here if the domains being checked ever change.
$Domains = @(
	[pscustomobject]@{ Name = 'Altegrity'; Server = 'uk1p1ainfmad001.corp.altegrity.com'; Credential = $null }
	[pscustomobject]@{ Name = 'corp.eddom.org'; Server = 'osuk1pads2adc01.corp.eddom.org'; Credential = $null }
)

function Test-AdCredential
{
	param
	(
		[string]$Server,
		[System.Management.Automation.PSCredential]$Credential
	)

	try
	{
		# Get-ADDomain just needs to bind - unlike Get-ADUser -Identity it doesn't depend
		# on the entered username being in a specific (SamAccountName/UPN/DN) format.
		Get-ADDomain -Server $Server -Credential $Credential | Out-Null
		return $true
	}
	catch
	{
		Write-Warning "Credential validation against $Server failed: $($_.Exception.Message)"
		return $false
	}
}

# Prompt for and validate credentials for each domain up front
foreach ($Domain in $Domains)
{
	$Credential = Get-Credential -Title "$($Domain.Name) Creds" -Message "Please enter your credentials for the $($Domain.Name) domain"
	if (-not $Credential)
	{
		Write-Error "No credentials supplied for $($Domain.Name), exiting script."
		return
	}
	if (-not (Test-AdCredential -Server $Domain.Server -Credential $Credential))
	{
		Write-Error "Invalid credentials for $($Domain.Name), exiting script."
		return
	}
	$Domain.Credential = $Credential
}

# Import csv
try
{
	$Users = Import-Csv -LiteralPath $Csv
}
catch
{
	Write-Error "Failed to read csv '$Csv': $($_.Exception.Message)"
	return
}

$RequiredColumns = 'First Name', 'Last Name'
$CsvColumns = if ($Users) { $Users[0].PSObject.Properties.Name } else { @() }
$MissingColumns = $RequiredColumns | Where-Object { $_ -notin $CsvColumns }
if ($MissingColumns)
{
	Write-Error "CSV is missing required column(s): $($MissingColumns -join ', ')"
	return
}

$Results = [System.Collections.Generic.List[psobject]]::new()

# Run through each user in csv
foreach ($User in $Users)
{
	$GivenName = if ($User.'First Name') { $User.'First Name'.Trim() } else { $null }
	$Surname = if ($User.'Last Name') { $User.'Last Name'.Trim() } else { $null }

	if (-not $GivenName -or -not $Surname)
	{
		Write-Warning "Skipping row with missing First Name/Last Name."
		continue
	}

	# Escape embedded double quotes so a stray character in the CSV can't alter the AD filter
	$SafeGivenName = $GivenName.Replace('"', '')
	$SafeSurname = $Surname.Replace('"', '')
	$Filter = "GivenName -eq ""$SafeGivenName"" -and Surname -eq ""$SafeSurname"""

	foreach ($Domain in $Domains)
	{
		try
		{
			$AdMatches = Get-ADUser -Filter $Filter -Server $Domain.Server -Credential $Domain.Credential -Properties Enabled, CanonicalName |
				Select-Object GivenName, Surname, SamAccountName, Enabled, CanonicalName

			if ($AdMatches)
			{
				foreach ($Match in $AdMatches)
				{
					$Results.Add([pscustomobject]@{
						GivenName      = $Match.GivenName
						Surname        = $Match.Surname
						SamAccountName = $Match.SamAccountName
						Enabled        = $Match.Enabled
						CanonicalName  = $Match.CanonicalName
						Domain         = $Domain.Name
						Status         = if ($Match.Enabled) { 'STILL ENABLED - ACTION REQUIRED' } else { 'Disabled' }
					})
				}
			}
			else
			{
				# Get-ADUser -Filter returns nothing (no exception) when there's no match,
				# so "not found" has to be detected explicitly rather than via catch.
				$Results.Add([pscustomobject]@{
					GivenName      = $GivenName
					Surname        = $Surname
					SamAccountName = 'Not Found'
					Enabled        = 'N/A'
					CanonicalName  = 'Not Found'
					Domain         = $Domain.Name
					Status         = 'Not Found'
				})
			}
		}
		catch
		{
			Write-Warning "Error querying $($Domain.Name) for '$GivenName $Surname': $($_.Exception.Message)"
			$Results.Add([pscustomobject]@{
				GivenName      = $GivenName
				Surname        = $Surname
				SamAccountName = 'Error'
				Enabled        = 'N/A'
				CanonicalName  = 'Error'
				Domain         = $Domain.Name
				Status         = "Error: $($_.Exception.Message)"
			})
		}
	}
}

# Display results
$Results | Out-GridView -Title "Terminated User Account Check Results"

# If OutFile parameter is specified, export results to csv
if ($OutFile)
{
	$Results | Export-Csv -LiteralPath $OutFile -NoTypeInformation
}
