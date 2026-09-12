# 共通定義 (dot-source して使う)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SquidRoot   = 'D:\Squid'
$SquidExe    = Join-Path $SquidRoot 'bin\squid.exe'
$CertgenExe  = Join-Path $SquidRoot 'lib\squid\security_file_certgen.exe'
$SquidEtc    = Join-Path $SquidRoot 'etc\squid'
$SslDir      = Join-Path $SquidEtc  'ssl'
$CaKey       = Join-Path $SslDir    'squid-ca.key'
$CaPem       = Join-Path $SslDir    'squid-ca.pem'
$CaCrt       = Join-Path $SslDir    'squid-ca.crt'
$CaBundle    = Join-Path $SslDir    'cacert.pem'
$CaBundleUrl = 'https://curl.se/ca/cacert.pem'
$CacheLog    = Join-Path $SquidRoot 'var\log\squid\cache.log'
$AccessLog   = Join-Path $SquidRoot 'var\log\squid\access.log'
$ServiceName = 'squidsrv'
$ProxyUrl    = 'http://127.0.0.1:3128'

$RepoRoot    = Split-Path -Parent $PSScriptRoot
$RepoConf    = Join-Path $RepoRoot 'squid\squid.conf'
$RepoNobump  = Join-Path $RepoRoot 'squid\nobump.txt'

function Write-Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    if (-not (Test-IsAdmin)) { throw 'Run this script from an elevated (Administrator) PowerShell.' }
}

function Find-OpenSsl {
    $cmd = Get-Command openssl.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "$env:ProgramFiles\Git\mingw64\bin\openssl.exe",
        "$env:ProgramFiles\Git\usr\bin\openssl.exe",
        "$env:ProgramFiles\OpenSSL-Win64\bin\openssl.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    throw 'openssl.exe not found. Install Git for Windows or `choco install openssl`.'
}

# ネイティブ exe を実行し出力を表示、終了コードを返す
# (PS 5.1 では $ErrorActionPreference=Stop 下で stderr 出力が終了エラー扱いになるためローカルで Continue にする)
function Invoke-Native([string]$Exe, [string[]]$Arguments, [switch]$Quiet) {
    $ErrorActionPreference = 'Continue'
    & $Exe @Arguments 2>&1 | ForEach-Object { if (-not $Quiet) { Write-Host "$_" } }
    return $LASTEXITCODE
}

function Invoke-Squid([string[]]$SquidArgs) { return (Invoke-Native $SquidExe $SquidArgs) }
