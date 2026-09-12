<#
.SYNOPSIS
  一括セットアップ: choco install squid → CA 生成/登録 → conf 配備 → ストレージ初期化 → サービス起動 → キャッシュ検証
#>
[CmdletBinding()]
param([switch]$SkipTest)
. (Join-Path $PSScriptRoot 'common.ps1')
try {
Assert-Admin

if (-not (Get-Command choco -ErrorAction SilentlyContinue)) { throw 'Chocolatey not found: https://chocolatey.org/install' }

if (Test-Path $SquidExe) {
    Write-Step "Squid already installed: $SquidExe"
} else {
    Write-Step 'choco install squid'
    $rc = Invoke-Native 'choco' @('install', 'squid', '-y')
    if ($rc -ne 0) { throw "choco install squid failed (exit $rc)" }
    if (-not (Test-Path $SquidExe)) { throw "$SquidExe not found after install (adjust SquidRoot in common.ps1 if installed elsewhere)" }
}

& (Join-Path $PSScriptRoot 'gen-ca.ps1')
& (Join-Path $PSScriptRoot 'update-cacert.ps1')
& (Join-Path $PSScriptRoot 'deploy-config.ps1') -NoRestart
& (Join-Path $PSScriptRoot 'init-storage.ps1')

Write-Step "Starting service $ServiceName"
Set-Service $ServiceName -StartupType Automatic
Restart-Service $ServiceName
Start-Sleep 3
Get-Content $CacheLog -Tail 5

if (-not $SkipTest) { & (Join-Path $PSScriptRoot 'test-cache.ps1') }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ($_.ScriptStackTrace)
    exit 1
}
