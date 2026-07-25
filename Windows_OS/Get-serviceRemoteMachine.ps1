$computers = "jp1p1loteapz005.ldi.ldiscovery.com";
$creds = Get-Credential

Invoke-Command -ComputerName $computers -ScriptBlock {get-service -name "OpsTaskService" | Select-Object Name, Status, StartType } -Credential $creds