<#
.SYNOPSIS
  Squid Local CA を Windows の信頼されたルート証明機関に登録する (他端末用)。
.DESCRIPTION
  同じフォルダの squid-ca.crt を LocalMachine\Root へインポートする。
  Firefox がインストールされていればポリシー ImportEnterpriseRoots=1 も設定する。
  管理者 PowerShell で実行:  powershell -ExecutionPolicy Bypass -File .\install-ca.ps1
.PARAMETER Remove
  登録を解除する
#>
[CmdletBinding()]
param([switch]$Remove)
$ErrorActionPreference = 'Stop'

$crt = Join-Path $PSScriptRoot 'squid-ca.crt'
if (-not (Test-Path $crt)) { throw "squid-ca.crt not found next to this script" }

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated (Administrator) PowerShell.'
}

$cert = Get-PfxCertificate -FilePath $crt
$thumb = $cert.Thumbprint
$existing = Get-ChildItem Cert:\LocalMachine\Root | Where-Object Thumbprint -eq $thumb

if ($Remove) {
    if ($existing) { $existing | Remove-Item; Write-Host "Removed $($cert.Subject) from LocalMachine\Root" }
    else { Write-Host 'Not installed' }
    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox\Certificates' -Name 'ImportEnterpriseRoots' -ErrorAction SilentlyContinue
    return
}

if ($existing) {
    Write-Host "Already trusted: $($cert.Subject) ($thumb)"
} else {
    Import-Certificate -FilePath $crt -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    Write-Host "Installed into LocalMachine\Root: $($cert.Subject) ($thumb)"
}

$ffPaths = @("$env:ProgramFiles\Mozilla Firefox\firefox.exe", "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe", "$env:LOCALAPPDATA\Mozilla Firefox\firefox.exe")
if ($ffPaths | Where-Object { Test-Path $_ }) {
    $key = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox\Certificates'
    New-Item -Path $key -Force | Out-Null
    New-ItemProperty -Path $key -Name 'ImportEnterpriseRoots' -PropertyType DWord -Value 1 -Force | Out-Null
    Write-Host 'Firefox policy ImportEnterpriseRoots=1 set (restart Firefox)'
}

Write-Host ''
Write-Host 'Next: set your proxy to the address in README.txt (Settings > Network > Proxy).'
