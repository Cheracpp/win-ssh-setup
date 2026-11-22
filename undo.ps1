# Removes the SSH access set up by setup.ps1. Run as Administrator.
$ErrorActionPreference = 'Continue'
Stop-Service sshd -ErrorAction SilentlyContinue
Set-Service sshd -StartupType Disabled -ErrorAction SilentlyContinue
Remove-NetFirewallRule -Name 'sshd-in-22' -ErrorAction SilentlyContinue
Remove-Item "$env:ProgramData\ssh\administrators_authorized_keys" -ErrorAction SilentlyContinue
Remove-Item "$env:USERPROFILE\.ssh\authorized_keys" -ErrorAction SilentlyContinue
Write-Host "SSH server stopped and disabled, firewall rule and authorized keys removed." -ForegroundColor Green
