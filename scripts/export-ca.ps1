<#
.SYNOPSIS
  他端末向けの Squid CA 配布パッケージ (証明書 + 登録スクリプト + README) を dist/ に出力し zip 化する。
.DESCRIPTION
  出力: dist/squid-ca/{squid-ca.crt, squid-ca.pem, install-ca.ps1, install-ca.sh, README.txt} と dist/squid-ca.zip
  秘密鍵 (squid-ca.key) は含めない。dist/ は .gitignore 済み。
.PARAMETER ProxyHost
  README に記載するプロキシのホスト名/IP。既定はこのホストの LAN IPv4 (Tailscale 等の仮想 NIC は除外)
#>
[CmdletBinding()]
param(
    [string]$ProxyHost,
    [int]$ProxyPort = 3128
)
. (Join-Path $PSScriptRoot 'common.ps1')

foreach ($f in @($CaCrt, $CaPem)) { if (-not (Test-Path $f)) { throw "$f not found. Run gen-ca.ps1 first." } }

if (-not $ProxyHost) {
    $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.PrefixOrigin -in 'Dhcp', 'Manual' -and $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' } |
        Where-Object { (Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue).InterfaceDescription -notmatch 'Tailscale|Hyper-V|VirtualBox|VMware|WSL|Loopback' } |
        Sort-Object InterfaceMetric | Select-Object -First 1 -ExpandProperty IPAddress
    $ProxyHost = if ($ip) { $ip } else { $env:COMPUTERNAME }
}

$distRoot = Join-Path $RepoRoot 'dist'
$pkg = Join-Path $distRoot 'squid-ca'
$zip = Join-Path $distRoot 'squid-ca.zip'
if (Test-Path $pkg) { Remove-Item -Recurse -Force $pkg }
New-Item -ItemType Directory -Force -Path $pkg | Out-Null

Copy-Item $CaCrt (Join-Path $pkg 'squid-ca.crt')
Copy-Item $CaPem (Join-Path $pkg 'squid-ca.pem')
Copy-Item (Join-Path $RepoRoot 'client\install-ca.ps1') $pkg
# .sh は LF で書き出す
$sh = (Get-Content (Join-Path $RepoRoot 'client\install-ca.sh') -Raw) -replace "`r`n", "`n"
[IO.File]::WriteAllText((Join-Path $pkg 'install-ca.sh'), $sh, (New-Object Text.UTF8Encoding $false))

$fp = (Get-PfxCertificate -FilePath $CaCrt)
$readme = @"
Squid Local CA - client setup
=============================

Proxy:    http://${ProxyHost}:${ProxyPort}
CA:       $($fp.Subject)
Expires:  $($fp.NotAfter.ToString('yyyy-MM-dd'))
SHA1:     $($fp.Thumbprint)

This proxy decrypts HTTPS (SSL Bump) to cache responses. Each client must
trust the CA below, otherwise HTTPS sites will show certificate errors.

Windows (Administrator PowerShell):
    powershell -ExecutionPolicy Bypass -File .\install-ca.ps1
  Then: Settings > Network & Internet > Proxy > Manual proxy
        Address: ${ProxyHost}   Port: ${ProxyPort}

macOS / Linux:
    sudo ./install-ca.sh
  macOS: System Settings > Network > (interface) > Details > Proxies > Web/Secure Web Proxy
  Linux: export http_proxy=http://${ProxyHost}:${ProxyPort} https_proxy=http://${ProxyHost}:${ProxyPort}

iOS / Android:
    Send squid-ca.crt to the device, open it, install the profile, then
    iOS:     Settings > General > About > Certificate Trust Settings > enable
    Android: Settings > Security > Encryption & credentials > Install a certificate > CA certificate
    Wi-Fi settings > Proxy: Manual, ${ProxyHost}:${ProxyPort}

Remove:   install-ca.ps1 -Remove  /  sudo ./install-ca.sh --remove
"@
[IO.File]::WriteAllText((Join-Path $pkg 'README.txt'), ($readme -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding $false))

if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path "$pkg\*" -DestinationPath $zip
Write-Step "Package: $pkg"
Get-ChildItem $pkg | ForEach-Object { Write-Host ("  {0,-16} {1,7} bytes" -f $_.Name, $_.Length) }
Write-Step "Zip: $zip"
Write-Host "Proxy address written to README: http://${ProxyHost}:${ProxyPort}"
