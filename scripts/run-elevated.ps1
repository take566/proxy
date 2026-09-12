<#
.SYNOPSIS
  非管理者のシェルから scripts/*.ps1 を管理者権限で実行し、出力とエラーをログファイル経由で表示する。
.EXAMPLE
  .\scripts\run-elevated.ps1 deploy-config.ps1
  .\scripts\run-elevated.ps1 init-storage.ps1 -Force
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Script,
    [Parameter(ValueFromRemainingArguments)][string[]]$ScriptArgs = @()
)
$ErrorActionPreference = 'Stop'
$target = Join-Path $PSScriptRoot $Script
if (-not (Test-Path $target)) { throw "Script not found: $target" }
$log = Join-Path $env:TEMP ("squid-elevated-{0}-{1}.log" -f ([IO.Path]::GetFileNameWithoutExtension($Script)), (Get-Date -Format 'yyyyMMdd-HHmmss'))

$argText = ($ScriptArgs | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ' '
$inner = "try { & '$target' $argText *>&1 | ForEach-Object { `$_ | Out-String -Stream } | Tee-Object -FilePath '$log' | Out-Null } catch { ('ERROR: ' + `$_.Exception.Message) | Add-Content -Path '$log'; `$_.ScriptStackTrace | Add-Content -Path '$log'; exit 1 }"
$p = Start-Process -Verb RunAs -Wait -PassThru -FilePath powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $inner
if (Test-Path $log) { Get-Content $log } else { Write-Warning "No output log ($log)" }
exit $p.ExitCode
