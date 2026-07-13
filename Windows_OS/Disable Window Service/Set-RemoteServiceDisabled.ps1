<#
.SYNOPSIS
    Gets a Windows service on one or more remote machines and sets its startup type to Disabled.

.PARAMETER ComputerName
    One or more machine names or IP addresses. Accepts an array or pipeline input.

.PARAMETER ServiceName
    The name of the service to disable.

.PARAMETER Credential
    Optional PSCredential for the remote machines. Prompts if not provided.

.EXAMPLE
    .\Set-RemoteServiceDisabled.ps1 -ComputerName "SERVER01" -ServiceName "Spooler"

.EXAMPLE
    .\Set-RemoteServiceDisabled.ps1 -ComputerName "SERVER01","SERVER02","SERVER03" -ServiceName "Spooler"

.EXAMPLE
    $cred = Get-Credential
    "SERVER01","SERVER02" | .\Set-RemoteServiceDisabled.ps1 -ServiceName "Spooler" -Credential $cred
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory, ValueFromPipeline)]
    [string[]]$ComputerName,

    [Parameter(Mandatory)]
    [string]$ServiceName,

    [Parameter()]
    [PSCredential]$Credential
)

begin {
    $invokeParams = @{ ErrorAction = 'Stop' }
    if ($Credential) {
        $invokeParams.Credential = $Credential
    }

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
}

process {
    foreach ($computer in $ComputerName) {
        Write-Host "`nProcessing [$computer]..." -ForegroundColor Cyan

        try {
            $result = Invoke-Command @invokeParams -ComputerName $computer -ScriptBlock {
                param($SvcName)

                $svc = Get-Service -Name $SvcName -ErrorAction Stop

                $before = $svc.StartType

                Set-Service -Name $SvcName -StartupType Disabled -ErrorAction Stop

                $svc.Refresh()

                [PSCustomObject]@{
                    Name        = $svc.Name
                    DisplayName = $svc.DisplayName
                    Status      = $svc.Status
                    StartType   = $svc.StartType
                    StartBefore = $before
                }
            } -ArgumentList $ServiceName

            Write-Host "  Name        : $($result.Name)"
            Write-Host "  Display Name: $($result.DisplayName)"
            Write-Host "  Status      : $($result.Status)"
            Write-Host "  Start Type  : $($result.StartBefore) -> " -NoNewline
            Write-Host "$($result.StartType)" -ForegroundColor Green

            $results.Add([PSCustomObject]@{
                ComputerName = $computer
                ServiceName  = $result.Name
                DisplayName  = $result.DisplayName
                Status       = $result.Status
                StartBefore  = $result.StartBefore
                StartAfter   = $result.StartType
                Success      = $true
                Error        = $null
            })
        }
        catch [Microsoft.PowerShell.Commands.ServiceCommandException] {
            Write-Warning "  Service '$ServiceName' not found on '$computer'."
            $results.Add([PSCustomObject]@{
                ComputerName = $computer
                ServiceName  = $ServiceName
                DisplayName  = $null
                Status       = $null
                StartBefore  = $null
                StartAfter   = $null
                Success      = $false
                Error        = "Service not found"
            })
        }
        catch {
            Write-Warning "  Failed on '$computer': $_"
            $results.Add([PSCustomObject]@{
                ComputerName = $computer
                ServiceName  = $ServiceName
                DisplayName  = $null
                Status       = $null
                StartBefore  = $null
                StartAfter   = $null
                Success      = $false
                Error        = $_.Exception.Message
            })
        }
    }
}

end {
    Write-Host "`n--- Summary ---" -ForegroundColor Cyan
    $results | Format-Table -AutoSize
}
