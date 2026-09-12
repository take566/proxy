<#
.SYNOPSIS
  sslbump.log を集計し、SSL Bump で壊れている可能性が高いドメイン (nobump.txt 候補) を表示する。
.DESCRIPTION
  判定:
    - ClientAbort : bump した CONNECT の後にそのホストへの HTTP リクエストが 1 件も無い
                    → クライアントが Squid の動的証明書を拒否した可能性 (証明書ピンニング等)
    - Errors      : err_code が記録された (上流 TLS 失敗 ERR_SECURE_CONNECT_FAIL など)
  既に nobump.txt でカバーされているホストは除外する。
.PARAMETER SinceMinutes
  直近 N 分のログのみ対象 (既定 1440 = 24h)
.PARAMETER Top
  表示件数
.PARAMETER All
  問題の無いホストも含めて全件表示
#>
[CmdletBinding()]
param(
    [int]$SinceMinutes = 1440,
    [int]$Top = 30,
    [switch]$All
)
. (Join-Path $PSScriptRoot 'common.ps1')

$log = Join-Path $SquidRoot 'var\log\squid\sslbump.log'
if (-not (Test-Path $log)) { throw "$log not found. Deploy squid.conf with the sslbump logformat first (deploy-config.ps1)." }

$nobump = [IO.File]::ReadAllLines($RepoNobump, [Text.Encoding]::UTF8) | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() }
function Test-Covered([string]$h) {
    foreach ($n in $nobump) {
        if ($n.StartsWith('.')) { if ($h -eq $n.Substring(1) -or $h.EndsWith($n)) { return $true } }
        elseif ($h -eq $n) { return $true }
    }
    return $false
}

$cutoff = [DateTimeOffset]::UtcNow.AddMinutes(-$SinceMinutes).ToUnixTimeSeconds()
# ts tr client Ss/Hs size method url bump_mode sni err
$re = '^(?<ts>\d+)\.\d+\s+(?<tr>\d+)\s+(?<client>\S+)\s+(?<status>\S+)\s+(?<size>\d+)\s+(?<method>\S+)\s+(?<url>\S+)\s+(?<mode>\S+)\s+(?<sni>\S+)\s+(?<err>\S+)$'

$hosts = @{}
foreach ($line in Get-Content $log) {
    if ($line -notmatch $re) { continue }
    if ([long]$Matches.ts -lt $cutoff) { continue }
    $h = $Matches.sni
    if ($h -eq '-') {
        if ($Matches.method -eq 'CONNECT') { $h = ($Matches.url -split ':')[0] }
        else { try { $h = ([Uri]$Matches.url).Host } catch { continue } }
    }
    if (-not $hosts.ContainsKey($h)) {
        $hosts[$h] = [ordered]@{ Host = $h; Bump = 0; Splice = 0; Requests = 0; Errors = 0; ErrCodes = @{}; LastSeen = 0 }
    }
    $e = $hosts[$h]
    if ($Matches.method -eq 'CONNECT') {
        if ($Matches.mode -eq 'bump') { $e.Bump++ } elseif ($Matches.mode -eq 'splice') { $e.Splice++ }
    } else { $e.Requests++ }
    if ($Matches.err -ne '-/-') {
        $e.Errors++
        $code = ($Matches.err -split '/')[0]
        $e.ErrCodes[$code] = 1 + [int]$e.ErrCodes[$code]
    }
    if ([long]$Matches.ts -gt $e.LastSeen) { $e.LastSeen = [long]$Matches.ts }
}

$rows = foreach ($e in $hosts.Values) {
    $covered = Test-Covered $e.Host
    $clientAbort = ($e.Bump -gt 0 -and $e.Requests -eq 0)
    $verdict = if ($covered) { 'nobump' } elseif ($clientAbort -and $e.Errors -gt 0) { 'ClientAbort+Errors' } elseif ($clientAbort) { 'ClientAbort' } elseif ($e.Errors -gt 0) { 'Errors' } else { 'ok' }
    [pscustomobject]@{
        Host     = $e.Host
        Verdict  = $verdict
        Bump     = $e.Bump
        Splice   = $e.Splice
        Requests = $e.Requests
        Errors   = $e.Errors
        ErrCodes = ($e.ErrCodes.GetEnumerator() | ForEach-Object { "$($_.Key)x$($_.Value)" }) -join ','
        LastSeen = [DateTimeOffset]::FromUnixTimeSeconds($e.LastSeen).LocalDateTime.ToString('MM-dd HH:mm')
    }
}

$suspects = $rows | Where-Object { $_.Verdict -notin 'ok', 'nobump' } | Sort-Object -Property @{e='Bump';d=$true}, Host
$shown = if ($All) { $rows | Sort-Object Verdict, Host } else { $suspects }
Write-Step "sslbump.log: last $SinceMinutes min, $($hosts.Count) hosts, $(@($suspects).Count) suspect(s)"
$shown | Select-Object -First $Top | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

if (@($suspects).Count -gt 0) {
    Write-Step 'Add to nobump.txt (review first; ClientAbort can also be a user cancelling a request):'
    foreach ($s in ($suspects | Select-Object -First $Top)) { Write-Host "  .\scripts\add-nobump.ps1 -Domain $($s.Host)" }
    Write-Host '  ... then: .\scripts\add-nobump.ps1 -Domain <host> -Deploy   (or deploy-config.ps1)'
}
