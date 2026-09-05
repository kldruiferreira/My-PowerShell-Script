# Current certificates
dir Cert:\LocalMachine\My

# List the current listeners
winrm enumerate winrm/config/listener

read-host "Paused..."

# Remove OLD certs that start with WIN-
Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -match 'CN=WIN-' } | Remove-Item -Force

write-host "Removing current WinRM listener"
winrm delete winrm/config/listener?Address=*+Transport=HTTPS

write-host "Reconfiguring WinRM HTTPS listener"
winrm quickconfig -transport:https

write-host "Complete. Server reboot may be required." 