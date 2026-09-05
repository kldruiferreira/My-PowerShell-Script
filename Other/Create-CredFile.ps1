<#
.SYNOPSIS
    Reads a CSV of secrets and writes one encrypted credential (.xml) file per row.

.DESCRIPTION
    Expects a CSV with the columns 'Secret Name', 'Username' and 'Password'
    (as produced by Export-SecretServerFolder.ps1). The optional 'Domain' and
    'Qualified Username' columns are used when present to build a DOMAIN\user
    value, which remote authentication requires.

    The Password column may hold either a DPAPI-encrypted string (as written by
    Export-SecretServerFolder.ps1) or a plain-text password. The format is
    auto-detected by default; use -PasswordFormat to force one.

    IMPORTANT: if the CSV holds DPAPI-encrypted passwords, this script must run
    as the same Windows user, on the same machine, that produced the export -
    otherwise decryption fails.

    Each row is converted to a PSCredential and serialised with Export-Clixml,
    which re-encrypts the password using DPAPI. The resulting .xml files are
    likewise only readable by the current user on the current machine.

.PARAMETER CredentialFile
    Path to the source CSV.

.PARAMETER OutputDirectory
    Where to write the .xml files. Defaults to a 'CredFiles' folder next to this script.

.PARAMETER PasswordFormat
    How to interpret the Password column:
      Auto      - detect per row (default)
      Encrypted - DPAPI ciphertext from ConvertFrom-SecureString
      PlainText - literal password text

.EXAMPLE
    .\Create-CredFile.ps1 -CredentialFile .\SecretExport.csv

.EXAMPLE
    .\Create-CredFile.ps1 -CredentialFile .\SecretExport.csv -PasswordFormat Encrypted
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateScript({
        if (-not (Test-Path -LiteralPath $_ -PathType Leaf)) {
            throw "CSV file not found: $_"
        }
        $true
    })]
    [string]$CredentialFile = (Join-Path $PSScriptRoot 'creds.csv'),

    [Parameter()]
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'CredFiles'),

    [Parameter()]
    [ValidateSet('Auto', 'Encrypted', 'PlainText')]
    [string]$PasswordFormat = 'Auto'
)

$ErrorActionPreference = 'Stop'


#region ----------------------------- Helpers -----------------------------

function ConvertTo-SecurePassword {
    <#
        Turns a CSV password cell into a SecureString.

        A DPAPI-encrypted value (produced by ConvertFrom-SecureString) must be
        passed to ConvertTo-SecureString WITHOUT -AsPlainText, which decrypts it.
        A plain-text value needs -AsPlainText -Force, which just wraps it.

        Getting this backwards is silent and damaging: -AsPlainText on ciphertext
        stores the hex blob itself as the password, producing credential files
        that look fine but never authenticate.
    #>
    param(
        [string]$Value,
        [string]$Format
    )

    # ConvertFrom-SecureString emits a long, purely hexadecimal string. Anything
    # matching that shape is treated as ciphertext.
    $looksEncrypted = $Value -match '^[0-9a-fA-F]{100,}$'

    $treatAsEncrypted = switch ($Format) {
        'Encrypted' { $true }
        'PlainText' { $false }
        default     { $looksEncrypted }
    }

    if ($treatAsEncrypted) {
        try {
            # No -AsPlainText: this DECRYPTS the DPAPI blob back to a SecureString.
            return ConvertTo-SecureString -String $Value
        }
        catch {
            # Most common cause is running as a different user or on a different
            # machine than the one that created the export.
            throw "Could not decrypt the password. If the CSV was produced by another user or on another machine, DPAPI cannot read it here. Underlying error: $($_.Exception.Message)"
        }
    }

    return ConvertTo-SecureString -String $Value -AsPlainText -Force
}

#endregion


# Build a regex matching every character Windows disallows in a filename, so
# secret names like 'CONTOSO\svc_backup' or 'SQL: prod' don't break the path.
$invalidChars   = [RegEx]::Escape(-join [System.IO.Path]::GetInvalidFileNameChars())
$invalidPattern = "[$invalidChars]"

# Ensure the destination exists before we start writing.
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

# Import the CSV.
$rows = @(Import-Csv -Path $CredentialFile)

if ($rows.Count -eq 0) {
    Write-Warning "'$CredentialFile' contains no rows. Nothing to do."
    return
}

# Verify the expected columns are present rather than failing per-row later.
# Domain / Qualified Username are optional - used only if the export included them.
$columns  = $rows[0].PSObject.Properties.Name
$required = @('Secret Name', 'Username', 'Password')
$missing  = $required | Where-Object { $_ -notin $columns }

if ($missing) {
    throw "CSV is missing required column(s): $($missing -join ', '). Found: $($columns -join ', ')"
}

if ('Domain' -notin $columns -and 'Qualified Username' -notin $columns) {
    Write-Warning "CSV has no Domain or Qualified Username column. Usernames will be used as-is, which may fail against remote hosts."
}

$written = 0
$skipped = New-Object System.Collections.Generic.List[string]
$index   = 0

foreach ($row in $rows) {

    $index++
    $secretName = $row.'Secret Name'

    try {
        # Prefer the pre-qualified DOMAIN\user column if the export produced one,
        # otherwise combine Domain + Username, otherwise fall back to Username.
        # A bare username causes remote authentication to fail with the unhelpful
        # error "The parameter is incorrect".
        $userName = if (-not [string]::IsNullOrWhiteSpace($row.'Qualified Username')) {
            $row.'Qualified Username'.Trim()
        }
        elseif (-not [string]::IsNullOrWhiteSpace($row.Domain) -and $row.Username -notmatch '[\\@]') {
            "$($row.Domain.Trim())\$($row.Username.Trim())"
        }
        else {
            "$($row.Username)".Trim()
        }

        # PSCredential rejects a null/empty username, and ConvertTo-SecureString
        # rejects an empty string - so validate before constructing.
        if ([string]::IsNullOrWhiteSpace($userName)) {
            $skipped.Add("$secretName - no username")
            continue
        }

        if ([string]::IsNullOrWhiteSpace($row.Password)) {
            $skipped.Add("$secretName - no password")
            continue
        }

        # Flag anything still unqualified so it doesn't fail silently later.
        # Local machine accounts legitimately have no domain.
        if ($userName -notmatch '[\\@]') {
            Write-Warning "'$secretName' has no domain on the username ('$userName') - remote authentication may fail."
        }

        # Decrypt the DPAPI value (or wrap a plain-text one) into a SecureString.
        # The password is never materialised as a plain string in this path.
        $securePassword = ConvertTo-SecurePassword -Value $row.Password -Format $PasswordFormat
        $credential     = [System.Management.Automation.PSCredential]::new($userName, $securePassword)

        # Strip illegal characters, then trim trailing spaces/dots which Windows
        # also refuses in filenames.
        $safeName = ($secretName -replace $invalidPattern, '_').Trim(' ', '.')

        # Fall back to a row number if the name was blank or entirely illegal.
        if ([string]::IsNullOrWhiteSpace($safeName)) {
            $safeName = "secret_$index"
        }

        $outputPath = Join-Path $OutputDirectory "$safeName.xml"

        # Two secrets in different sub-folders can share a name - don't let the
        # second one silently overwrite the first.
        if (Test-Path -LiteralPath $outputPath) {
            $outputPath = Join-Path $OutputDirectory "$safeName ($index).xml"
        }

        $credential | Export-Clixml -Path $outputPath
        $written++
        Write-Verbose "Wrote '$outputPath'"
    }
    catch {
        # Keep going - one malformed row shouldn't abort the whole batch.
        Write-Warning "Failed on '$secretName': $($_.Exception.Message)"
        $skipped.Add("$secretName - $($_.Exception.Message)")
    }
}

Write-Host ""
Write-Host "Created $written credential file(s) in '$OutputDirectory'." -ForegroundColor Green

if ($skipped.Count -gt 0) {
    Write-Host "Skipped $($skipped.Count) row(s):" -ForegroundColor Yellow
    $skipped | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}