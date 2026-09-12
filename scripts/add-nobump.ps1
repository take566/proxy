<#
.SYNOPSIS
  SSL Bump しない (splice する) ドメインを squid/nobump.txt に追加し、必要なら配備する。
.DESCRIPTION
  - スキーム / ポート / パスを取り除き、先頭に "." を補って サブドメインも含める (-Exact で補わない)
  - 既に同じ行がある、または親ドメイン (.example.com) でカバー済みなら追加しない
  - -Deploy で deploy-config.ps1 を実行 (管理者でなければ run-elevated.ps1 経由)
.EXAMPLE
  .\scripts\add-nobump.ps1 -Domain www.gnu.org, api.github.com -Deploy
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][string[]]$Domain,
    [switch]$Exact,
    [switch]$Deploy
)
. (Join-Path $PSScriptRoot 'common.ps1')

$lines = @([IO.File]::ReadAllLines($RepoNobump, [Text.Encoding]::UTF8))
$entries = $lines | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() }

function Test-Covered([string]$h) {
    foreach ($n in $entries) {
        if ($n -eq $h) { return $true }
        if ($n.StartsWith('.') -and ($h -eq $n -or $h.EndsWith($n) -or $h -eq $n.Substring(1))) { return $true }
    }
    return $false
}

$added = @()
foreach ($d in $Domain) {
    $h = $d.Trim().ToLowerInvariant()
    $h = $h -replace '^[a-z]+://', ''          # scheme
    $h = ($h -split '[/?#]')[0]                 # path
    $h = ($h -split ':')[0]                     # port
    if (-not $h -or $h -notmatch '^[a-z0-9.-]+$') { Write-Warning "Invalid domain: $d"; continue }
    if ($h -match '^\d+\.\d+\.\d+\.\d+$') { $entry = $h }
    elseif ($Exact -or $h.StartsWith('.')) { $entry = $h }
    else { $entry = ".$h" }
    if (Test-Covered $entry.TrimStart('.')) { Write-Step "Already covered: $entry"; continue }
    $lines += $entry
    $entries += $entry
    $added += $entry
    Write-Step "Added: $entry"
}

if ($added.Count -eq 0) { Write-Host 'Nothing to add.'; if (-not $Deploy) { return } }
else {
    [IO.File]::WriteAllText($RepoNobump, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
    Write-Host "Updated $RepoNobump ($($added.Count) added). Commit it to keep the change."
}

if ($Deploy) {
    if (Test-IsAdmin) { & (Join-Path $PSScriptRoot 'deploy-config.ps1') }
    else { & (Join-Path $PSScriptRoot 'run-elevated.ps1') 'deploy-config.ps1' }
}
