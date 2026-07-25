# List of IP addresses to ping
$ipList = @("Server01", "server02", "server03")

foreach ($ip in $ipList) {
    Write-Host "Pinging $ip ..." -ForegroundColor Cyan
    
    if (Test-Connection -ComputerName $ip -Count 1 -Quiet) {
        Write-Host "$ip is reachable." -ForegroundColor Green
    } else {
        Write-Host "$ip is NOT reachable." -ForegroundColor Red
    }
    
    Write-Host "------------------------"
}