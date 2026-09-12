<#
.SYNOPSIS
  上流サーバ証明書検証用の CA バンドル (Mozilla / curl.se) を D:\Squid\etc\squid\ssl\cacert.pem に取得・更新する。
.DESCRIPTION
  Cygwin 版 Squid は OS の証明書ストアを参照しないため、squid.conf の tls_outgoing_options cafile= で明示する。
  更新後は deploy-config.ps1 (サービス再起動) で反映する。
.PARAMETER Force
  既存ファイルがあっても再取得する
#>
[CmdletBinding()]
param([switch]$Force)
. (Join-Path $PSScriptRoot 'common.ps1')

if ((Test-Path $CaBundle) -and -not $Force) {
    $age = (Get-Date) - (Get-Item $CaBundle).LastWriteTime
    if ($age.TotalDays -lt 30) { Write-Step "CA bundle is up to date ($([int]$age.TotalDays) days old): $CaBundle"; return }
}
New-Item -ItemType Directory -Force -Path $SslDir | Out-Null
Write-Step "Downloading $CaBundleUrl"
$tmp = "$CaBundle.tmp"
Invoke-WebRequest -Uri $CaBundleUrl -OutFile $tmp -UseBasicParsing
$count = @(Select-String -Path $tmp -Pattern '-----BEGIN CERTIFICATE-----' -SimpleMatch).Count
if ($count -lt 100) { Remove-Item $tmp; throw "Downloaded bundle looks broken ($count certs)" }
Move-Item -Force $tmp $CaBundle
Write-Step "Saved: $CaBundle ($count certificates)"
