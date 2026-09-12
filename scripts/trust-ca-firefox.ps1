<#
.SYNOPSIS
  Firefox が Windows の証明書ストア (Squid CA を登録済み) を参照するようエンタープライズポリシーを設定する。
.DESCRIPTION
  HKLM\SOFTWARE\Policies\Mozilla\Firefox\Certificates\ImportEnterpriseRoots = 1 を設定する。
  about:config の security.enterprise_roots.enabled を手で変更する必要がなくなる。Firefox 再起動後に有効。
.PARAMETER Remove
  ポリシーを削除する
#>
[CmdletBinding()]
param([switch]$Remove)
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-Admin

$policyKey = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox\Certificates'

if ($Remove) {
    if (Test-Path $policyKey) {
        Remove-ItemProperty -Path $policyKey -Name 'ImportEnterpriseRoots' -ErrorAction SilentlyContinue
        Write-Step 'Removed Firefox policy ImportEnterpriseRoots'
    }
    return
}

if (-not (Test-FirefoxInstalled)) {
    Write-Step 'Firefox is not installed; skipping'
    return
}

New-Item -Path $policyKey -Force | Out-Null
New-ItemProperty -Path $policyKey -Name 'ImportEnterpriseRoots' -PropertyType DWord -Value 1 -Force | Out-Null
$v = (Get-ItemProperty -Path $policyKey -Name 'ImportEnterpriseRoots').ImportEnterpriseRoots
Write-Step "Firefox policy ImportEnterpriseRoots = $v (restart Firefox to apply; check about:policies)"
