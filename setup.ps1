# Enables the OpenSSH server on this Windows machine and authorizes the
# SSH keys published at https://github.com/Cheracpp.keys.
# Run from an elevated (Administrator) PowerShell.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Please run this in PowerShell opened as Administrator." -ForegroundColor Red
    return
}

# 1. Install OpenSSH Server
Step "Installing OpenSSH Server"
if (Get-Service sshd -ErrorAction SilentlyContinue) {
    Write-Host "Already installed."
} else {
    try {
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
        Write-Host "Installed via Windows optional features."
    } catch {
        Write-Host "Windows feature install failed ($($_.Exception.Message)). Falling back to the official MSI from GitHub..." -ForegroundColor Yellow
        $rel = Invoke-RestMethod https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases/latest
        $asset = $rel.assets | Where-Object { $_.name -match 'Win64.*\.msi$' } | Select-Object -First 1
        $msi = Join-Path $env:TEMP $asset.name
        Invoke-WebRequest $asset.browser_download_url -OutFile $msi -UseBasicParsing
        Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn" -Wait
        Write-Host "Installed $($asset.name)."
    }
}

# 2. Start it now and on every boot
Step "Starting the sshd service"
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd

# 3. Open port 22 in Windows Firewall (all profiles: domain, private, public)
Step "Opening port 22 in Windows Firewall"
if (-not (Get-NetFirewallRule -Name 'sshd-in-22' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'sshd-in-22' -DisplayName 'OpenSSH Server (port 22)' `
        -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Any | Out-Null
}
Write-Host "Done."

# 4. PowerShell as the default SSH shell
Step "Setting PowerShell as the default SSH shell"
New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell `
    -Value "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force | Out-Null

# 5. Authorize the GitHub-published keys
Step "Adding authorized SSH keys from github.com/Cheracpp.keys"
$keys = (Invoke-WebRequest https://github.com/Cheracpp.keys -UseBasicParsing).Content.Trim()
if (-not $keys) { throw "No keys found at github.com/Cheracpp.keys" }

# Admin accounts only read the shared ProgramData file; write the per-user file too in case.
$adminFile = "$env:ProgramData\ssh\administrators_authorized_keys"
New-Item -ItemType Directory -Force -Path (Split-Path $adminFile) | Out-Null
Add-Content -Path $adminFile -Value $keys
# SIDs so this also works on non-English Windows (Administrators / SYSTEM)
icacls.exe $adminFile /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F' | Out-Null

$userFile = "$env:USERPROFILE\.ssh\authorized_keys"
New-Item -ItemType Directory -Force -Path (Split-Path $userFile) | Out-Null
Add-Content -Path $userFile -Value $keys
Write-Host "Keys written to $adminFile and $userFile"

Restart-Service sshd

# 6. Report how to connect
Step "All set. Connection details:"
$user = $env:USERNAME
$ips = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
    Select-Object -ExpandProperty IPAddress
Write-Host "  Computer : $env:COMPUTERNAME"
Write-Host "  User     : $user"
foreach ($ip in $ips) { Write-Host "  Connect  : ssh $user@$ip" -ForegroundColor Green }
if ($env:USERDOMAIN -and $env:USERDOMAIN -ne $env:COMPUTERNAME) {
    Write-Host "  (domain account; if the above is refused, try: ssh `"$env:USERDOMAIN\$user`"@<ip>)"
}
Write-Host "`nIf the connection times out, a domain Group Policy may be overriding the firewall rule."
