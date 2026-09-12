<#
.SYNOPSIS
  SSL Bump 用のローカル CA を生成し、Windows の信頼されたルート証明機関に登録する。
.DESCRIPTION
  出力先: D:\Squid\etc\squid\ssl\squid-ca.{key,pem,crt}
    - squid-ca.key : 秘密鍵 (squid.conf の tls-key)。リポジトリに含めないこと
    - squid-ca.pem : 証明書 PEM (squid.conf の tls-cert)
    - squid-ca.crt : 証明書 DER (クライアント配布 / 信頼ストア登録用)
.PARAMETER Force
  既存の CA を上書きして再生成する (旧 CA で発行した動的証明書は無効になるので init-storage.ps1 -Force も実行する)
.PARAMETER SkipImport
  Windows 信頼ストアへの登録を行わない
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$SkipImport,
    [int]$Days = 3650
)
. (Join-Path $PSScriptRoot 'common.ps1')

if ((Test-Path $CaKey) -and (Test-Path $CaPem) -and -not $Force) {
    Write-Step "CA already exists: $CaPem (use -Force to regenerate)"
} else {
    $openssl = Find-OpenSsl
    Write-Step "Generating CA (openssl: $openssl)"
    New-Item -ItemType Directory -Force -Path $SslDir | Out-Null

    $cnf = Join-Path $env:TEMP 'squid-ca.cnf'
    $cnfBody = @(
        '[req]',
        'distinguished_name = dn',
        'x509_extensions = v3_ca',
        'prompt = no',
        '[dn]',
        'C  = JP',
        'O  = Local Squid Proxy',
        'CN = Squid Local CA',
        '[v3_ca]',
        'basicConstraints = critical, CA:TRUE',
        'keyUsage = critical, keyCertSign, cRLSign, digitalSignature',
        'subjectKeyIdentifier = hash',
        'authorityKeyIdentifier = keyid:always'
    ) -join "`n"
    Set-Content -Path $cnf -Value $cnfBody -Encoding ascii

    $rc = Invoke-Native $openssl @('req', '-x509', '-new', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-days', "$Days", '-config', $cnf, '-keyout', $CaKey, '-out', $CaPem)
    if ($rc -ne 0) { throw "openssl req failed (exit $rc)" }
    $rc = Invoke-Native $openssl @('x509', '-in', $CaPem, '-outform', 'DER', '-out', $CaCrt)
    if ($rc -ne 0) { throw "openssl x509 failed (exit $rc)" }
    Remove-Item $cnf -ErrorAction SilentlyContinue

    # 秘密鍵は SYSTEM と Administrators のみ読める
    Invoke-Native 'icacls.exe' @($CaKey, '/inheritance:r', '/grant:r', 'SYSTEM:(R)', '/grant:r', 'Administrators:(R)') -Quiet | Out-Null
    Write-Step "Generated: $CaPem"
}

Invoke-Native (Find-OpenSsl) @('x509', '-in', $CaPem, '-noout', '-subject', '-enddate', '-fingerprint', '-sha256') | Out-Null

if (-not $SkipImport) {
    Assert-Admin
    $thumb = (Get-PfxCertificate -FilePath $CaCrt).Thumbprint
    if (Get-ChildItem Cert:\LocalMachine\Root | Where-Object Thumbprint -eq $thumb) {
        Write-Step "Already trusted in LocalMachine\Root (thumbprint $thumb)"
    } else {
        Write-Step 'Importing into LocalMachine\Root'
        Import-Certificate -FilePath $CaCrt -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    }
    if (Test-FirefoxInstalled) { & (Join-Path $PSScriptRoot 'trust-ca-firefox.ps1') }
}
