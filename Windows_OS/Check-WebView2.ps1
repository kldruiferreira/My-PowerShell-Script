<#
==============================================================================
 Check-WebView2.ps1
==============================================================================

 PURPOSE
   Checks a list of Windows machines to see whether the Microsoft Edge
   WebView2 "Evergreen" Runtime is installed, and writes the results to a
   CSV report.

 WHY
   The Adventus application depends on WebView2. Newer Windows ships with it,
   but many Windows 10 pods may not have it (or may have picked it up later
   via an Edge update). This lets you scope exactly which machines have it.

 HOW IT WORKS
   1. Reads a list of computer names from a text file (one per line).
   2. Connects to each machine remotely over WinRM (PowerShell remoting).
   3. On each machine, inspects the documented WebView2 registry locations.
   4. Records whether it's installed, which version, and where it was found.
   5. Exports everything (including machines that couldn't be reached) to CSV.

 REQUIREMENTS
   - WinRM / PowerShell remoting must be enabled on the target machines.
   - You must run this from an account with remote admin rights on the pods.

 USAGE
   .\Check-WebView2.ps1 -ComputerListPath .\pods.txt -OutputCsv .\report.csv

   With alternate credentials:
     $cred = Get-Credential
     .\Check-WebView2.ps1 -ComputerListPath .\pods.txt -OutputCsv .\report.csv -Credential $cred
==============================================================================
#>

# The param() block defines the inputs the script accepts when you run it.
[CmdletBinding()]
param(
    # Path to the text file that lists the machines to check (one name per line).
    # Mandatory = you must supply it, or PowerShell will prompt you for it.
    [Parameter(Mandatory = $true)]
    [string]$ComputerListPath,

    # Where to save the CSV report. If you don't supply one, it auto-generates
    # a filename with the current date and time so runs don't overwrite each other.
    [Parameter(Mandatory = $false)]
    [string]$OutputCsv = ".\WebView2Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",

    # Optional alternate credentials for connecting to the machines.
    # Leave this out to connect as the account you're currently logged in as.
    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$Credential,

    # How many machines to check at the same time (parallelism). Higher = faster
    # but heavier on the network. Lower it if you have a very large list.
    [Parameter(Mandatory = $false)]
    [int]$ThrottleLimit = 32
)

# --------------------------------------------------------------------------
# STEP 1: Read and validate the list of machines
# --------------------------------------------------------------------------

# Make sure the file the user pointed us at actually exists. If not, stop.
if (-not (Test-Path $ComputerListPath)) {
    Write-Error "Computer list not found: $ComputerListPath"
    exit 1
}

# Read the file and clean it up:
#   - Trim whitespace from each line
#   - Drop blank lines and any line starting with '#' (treated as a comment)
#   - Remove duplicates so we don't check the same machine twice
$computers = Get-Content $ComputerListPath |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') } |
    Select-Object -Unique

# If, after cleaning, we have no machines left, there's nothing to do.
if (-not $computers) {
    Write-Error "No computer names found in $ComputerListPath"
    exit 1
}

Write-Host "Loaded $($computers.Count) machine(s). Starting sweep..." -ForegroundColor Cyan

# --------------------------------------------------------------------------
# STEP 2: Define the check that will run ON EACH remote machine
# --------------------------------------------------------------------------
# Everything inside this script block executes on the remote pod, not locally.
# It looks for the WebView2 runtime in the three registry spots Microsoft
# documents, and returns a small object describing what it found.
$scriptBlock = {
    # This GUID is Microsoft's fixed identifier for the WebView2 Runtime.
    # It never changes, so the registry key path is stable across versions.
    $guid  = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'

    # The three places WebView2 can register itself, in priority order:
    $paths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$guid",  # 64-bit machine-wide install
        "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$guid",              # 32-bit machine-wide install
        "HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$guid"               # per-user install
    )

    # We'll fill these in if/when we find the runtime.
    $version   = $null
    $foundPath = $null

    # Check each location in turn.
    foreach ($p in $paths) {
        if (Test-Path $p) {
            # The 'pv' value holds the installed version string (e.g. 118.0.2088.46).
            $pv = (Get-ItemProperty -Path $p -Name pv -ErrorAction SilentlyContinue).pv

            # A version that exists and isn't "0.0.0.0" means it's genuinely installed.
            if ($pv -and $pv -ne '0.0.0.0') {
                $version   = $pv
                $foundPath = $p
                break   # Found it, no need to keep checking other locations.
            }
        }
    }

    # Return a tidy object with the results for this one machine.
    # (Get-CimInstance grabs the OS name so you can see Win10 vs newer in the report.)
    [PSCustomObject]@{
        OSCaption = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
        Installed = [bool]$version
        Version   = if ($version) { $version } else { 'N/A' }
        FoundIn   = if ($foundPath) { $foundPath } else { 'N/A' }
    }
}

# --------------------------------------------------------------------------
# STEP 3: Run the check against all machines (in parallel over WinRM)
# --------------------------------------------------------------------------

# Build up the parameters for Invoke-Command in a hashtable ("splatting").
# This keeps the actual call clean and lets us optionally add credentials.
$icmParams = @{
    ComputerName  = $computers          # the full list of pods
    ScriptBlock   = $scriptBlock        # the check defined above
    ThrottleLimit = $ThrottleLimit      # how many to run at once
    ErrorAction   = 'SilentlyContinue'  # don't halt on machines that fail
    ErrorVariable = 'remotingErrors'    # collect those failures into a variable
}

# Only add credentials if the user actually supplied them.
if ($Credential) { $icmParams['Credential'] = $Credential }

# Fire off the sweep. $results holds one object per machine that responded.
$results = Invoke-Command @icmParams

# --------------------------------------------------------------------------
# STEP 4: Turn the raw results into clean report rows
# --------------------------------------------------------------------------

# For every machine that responded, build a friendly row for the CSV.
# PSComputerName is added automatically by remoting and tells us which
# machine each result came from.
$report = foreach ($r in $results) {
    [PSCustomObject]@{
        ComputerName = $r.PSComputerName
        Reachable    = $true
        OS           = $r.OSCaption
        WebView2     = if ($r.Installed) { 'Installed' } else { 'Missing' }
        Version      = $r.Version
        FoundIn      = $r.FoundIn
        TimeChecked  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }
}

# --------------------------------------------------------------------------
# STEP 5: Account for machines that never responded
# --------------------------------------------------------------------------
# We don't want silent gaps in the report. Work out which machines from the
# original list did NOT come back with a result, and add a row for each so
# you can see they were unreachable rather than simply missing.

$responded   = $report.ComputerName
$unreachable = $computers | Where-Object { $_ -notin $responded }

foreach ($c in $unreachable) {
    # Try to pull the specific error message for this machine (e.g. WinRM refused).
    $errMsg = ($remotingErrors |
        Where-Object { $_.TargetObject -eq $c } |
        Select-Object -First 1).Exception.Message

    $report += [PSCustomObject]@{
        ComputerName = $c
        Reachable    = $false
        OS           = 'N/A'
        WebView2     = 'Unknown (unreachable)'
        Version      = 'N/A'
        FoundIn      = if ($errMsg) { $errMsg } else { 'No response / WinRM error' }
        TimeChecked  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }
}

# --------------------------------------------------------------------------
# STEP 6: Write the CSV report
# --------------------------------------------------------------------------
# Sort by name for readability, then export. -NoTypeInformation keeps the
# CSV clean (no extra type header row); UTF8 avoids encoding surprises.
$report | Sort-Object ComputerName | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8

# --------------------------------------------------------------------------
# STEP 7: Print a quick summary to the screen
# --------------------------------------------------------------------------
$installed = ($report | Where-Object WebView2 -eq 'Installed').Count
$missing   = ($report | Where-Object WebView2 -eq 'Missing').Count
$unreach   = ($report | Where-Object Reachable -eq $false).Count

Write-Host ""
Write-Host "===== WebView2 Sweep Complete =====" -ForegroundColor Green
Write-Host "  Installed:    $installed"
Write-Host "  Missing:      $missing"
Write-Host "  Unreachable:  $unreach"
Write-Host "  Total:        $($report.Count)"
Write-Host "  Report saved: $OutputCsv" -ForegroundColor Cyan