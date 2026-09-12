<#
.SYNOPSIS
  プロキシ経由で HTTP / HTTPS を 2 回取得し、2 回目がキャッシュ HIT になることを確認する。
#>
[CmdletBinding()]
param(
    [string[]]$Urls = @(
        'http://example.com/',
        'https://example.com/',
        'https://www.gnu.org/graphics/heckert_gnu.transp.small.png'
    )
)
. (Join-Path $PSScriptRoot 'common.ps1')

$curl = (Get-Command curl.exe).Source
$failed = 0
foreach ($u in $Urls) {
    Write-Step $u
    $results = @()
    foreach ($i in 1..2) {
        $ErrorActionPreference = 'Continue'
        # --ssl-no-revoke: Squid の動的証明書には CRL 配布点が無く Schannel の失効確認が失敗するため
        $hdr = & $curl -sS --ssl-no-revoke -o NUL -D - -x $ProxyUrl $u 2>&1 | ForEach-Object { "$_" }
        $ErrorActionPreference = 'Stop'
        if ($LASTEXITCODE -ne 0) { Write-Warning "curl failed (exit $LASTEXITCODE): $hdr"; $failed++; break }
        # CONNECT 経由だと "200 Connection established" が先頭に来るので最後のステータス行を採用
        $status = (($hdr | Where-Object { $_ -match '^HTTP/' }) | Select-Object -Last 1).Trim()
        $xcache = ($hdr | Where-Object { $_ -match '^X-Cache:' }) -join ''
        $results += "$status | $xcache"
        Write-Host ("  #{0}: {1}" -f $i, $results[-1])
    }
    if ($results.Count -eq 2 -and $results[1] -notmatch 'X-Cache: HIT') { Write-Warning '  2nd request was not a HIT'; $failed++ }
}

Write-Step 'access.log tail'
Get-Content $AccessLog -Tail 6

if ($failed -gt 0) { Write-Host "NG: $failed" -ForegroundColor Red; exit 1 }
Write-Host 'OK: 2nd request was HIT for all URLs' -ForegroundColor Green
