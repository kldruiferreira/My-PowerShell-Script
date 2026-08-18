
New-NetFirewallRule -DisplayName "Allow Zabbix Agent 10052" `
    -Direction Inbound `
    -LocalPort 10052 `
    -Protocol TCP `
    -Action Allow
