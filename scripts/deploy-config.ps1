<#
.SYNOPSIS
  リポジトリの squid/squid.conf と squid/nobump.txt を D:\Squid\etc\squid へ配備し、構文検証後にサービスを再起動する。
.PARAMETER NoRestart
  配備と parse のみ行い、サービスを再起動しない
#>
[CmdletBinding()]
param([switch]$NoRestart)
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-Admin

function Copy-Lf([string]$src, [string]$dst) {
    # Cygwin 版 squid は CRLF も読めるが LF に揃える
    $text = (Get-Content $src -Raw) -replace "`r`n", "`n"
    [IO.File]::WriteAllText($dst, $text, (New-Object Text.UTF8Encoding $false))
}

$dstConf = Join-Path $SquidEtc 'squid.conf'
$bak = $null
if (Test-Path $dstConf) {
    $bak = "$dstConf.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $dstConf $bak
    Write-Step "Backup: $bak"
}

Write-Step "Deploy: $RepoConf -> $dstConf"
Copy-Lf $RepoConf $dstConf
Copy-Lf $RepoNobump (Join-Path $SquidEtc 'nobump.txt')

Write-Step 'Validate: squid -k parse'
$rc = Invoke-Squid @('-k', 'parse', '-f', '/etc/squid/squid.conf')
if ($rc -ne 0) {
    if ($bak) { Copy-Item $bak $dstConf -Force; Write-Warning 'parse failed; restored previous squid.conf' }
    throw "squid -k parse failed (exit $rc)"
}

if ($NoRestart) { Write-Step '(-NoRestart) skipping service restart'; return }

Write-Step "Restarting service $ServiceName"
Restart-Service $ServiceName
Start-Sleep 3
$svc = Get-Service $ServiceName
Write-Host "Status: $($svc.Status)"
Write-Step 'cache.log tail'
Get-Content $CacheLog -Tail 8
if ($svc.Status -ne 'Running') { throw "Service is not running. Check $CacheLog" }
