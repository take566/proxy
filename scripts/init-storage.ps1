<#
.SYNOPSIS
  SSL 動的証明書 DB (/var/cache/squid_ssldb) とディスクキャッシュ (/var/cache/squid) を初期化する。
.PARAMETER Force
  既存の ssl_db を削除して作り直す (CA を再生成したときに必要)
#>
[CmdletBinding()]
param([switch]$Force)
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-Admin

$sslDb = Join-Path $SquidRoot 'var\cache\squid_ssldb'

$svc = Get-Service $ServiceName -ErrorAction SilentlyContinue
$wasRunning = ($null -ne $svc) -and ($svc.Status -eq 'Running')
if ($wasRunning) { Write-Step "Stopping service $ServiceName"; Stop-Service $ServiceName; Start-Sleep 2 }

if ((Test-Path (Join-Path $sslDb 'index.txt')) -and -not $Force) {
    Write-Step "ssl_db already initialized: $sslDb (use -Force to recreate)"
} else {
    if (Test-Path $sslDb) { Remove-Item -Recurse -Force $sslDb }
    Write-Step "Initializing ssl_db: $sslDb"
    $rc = Invoke-Native $CertgenExe @('-c', '-s', '/var/cache/squid_ssldb', '-M', '16MB')
    if ($rc -ne 0) { throw "security_file_certgen -c failed (exit $rc)" }
}

Write-Step 'Initializing cache_dir (squid -z)'
$rc = Invoke-Squid @('-z', '-f', '/etc/squid/squid.conf')
if ($rc -ne 0) { throw "squid -z failed (exit $rc)" }

if ($wasRunning) { Write-Step "Starting service $ServiceName"; Start-Service $ServiceName }
