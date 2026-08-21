[CmdletBinding()]
param(
    [switch]$Push,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Branch = "linux-rga-multi"
$UpstreamUrl = "https://github.com/JeffyCN/mirrors.git"
$UpstreamUrlAlt = "https://github.com/JeffyCN/mirrors"
$UpstreamRef = "refs/remotes/upstream/$Branch"

function Invoke-Git {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [switch]$Capture
    )

    if ($Capture) {
        $Output = & git @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
        }
        return (($Output | ForEach-Object { [string]$_ }) -join "`n").Trim()
    }

    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

if ($Help) {
    @"
Usage:
  powershell -ExecutionPolicy Bypass -File tools/rebase-upstream-rga.ps1
  powershell -ExecutionPolicy Bypass -File tools/rebase-upstream-rga.ps1 -Push

Fetch JeffyCN/mirrors:linux-rga-multi and rebase the local StableKite
linux-rga-multi commits onto it. No merge commit is created.

Without -Push, the rebased branch remains local for review/testing.
With -Push, the result is pushed with --force-with-lease.
"@
    exit 0
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git.exe is not available in PATH."
}

& git rev-parse --git-dir *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Run this inside a Git checkout."
}

$CurrentBranch = Invoke-Git -Arguments @("branch", "--show-current") -Capture
if ($CurrentBranch -ne $Branch) {
    throw "Expected branch '$Branch', got '$CurrentBranch'."
}

& git diff --quiet
if ($LASTEXITCODE -ne 0) {
    throw "Working tree is not clean. Commit or stash changes first."
}

& git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
    throw "Index is not clean. Commit or stash changes first."
}

& git remote get-url origin *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Remote 'origin' is missing."
}

$RemoteText = Invoke-Git -Arguments @("remote") -Capture
$RemoteNames = @(
    $RemoteText -split "`r?`n" |
        Where-Object { $_ }
)

if ($RemoteNames -contains "upstream") {
    $Configured = Invoke-Git -Arguments @("remote", "get-url", "upstream") -Capture
    if ($Configured -ne $UpstreamUrl -and $Configured -ne $UpstreamUrlAlt) {
        throw "Remote 'upstream' points to unexpected URL: $Configured`nExpected: $UpstreamUrl"
    }
}
else {
    Invoke-Git -Arguments @("remote", "add", "upstream", $UpstreamUrl)
}

$Before = Invoke-Git -Arguments @("rev-parse", "HEAD") -Capture
Write-Host "local before: $Before"

Invoke-Git -Arguments @(
    "fetch",
    "--no-tags",
    "upstream",
    "+refs/heads/${Branch}:${UpstreamRef}"
)

$UpstreamTip = Invoke-Git -Arguments @("rev-parse", $UpstreamRef) -Capture
Write-Host "upstream tip: $UpstreamTip"

& git merge-base --is-ancestor $UpstreamTip HEAD
$AlreadyContainsUpstream = ($LASTEXITCODE -eq 0)

if ($AlreadyContainsUpstream) {
    Write-Host "Local branch already contains the current upstream tip; no rebase needed."
}
else {
    $OldBase = Invoke-Git -Arguments @("merge-base", "HEAD", $UpstreamTip) -Capture
    Write-Host "old merge-base: $OldBase"
    Invoke-Git -Arguments @("rebase", $UpstreamTip)
}

$After = Invoke-Git -Arguments @("rev-parse", "HEAD") -Capture
Write-Host "local after:  $After"

& git merge-base --is-ancestor $UpstreamTip HEAD
if ($LASTEXITCODE -ne 0) {
    throw "Current upstream tip is not an ancestor of the rebased branch."
}

$MergeCountText = Invoke-Git -Arguments @(
    "rev-list",
    "--count",
    "--merges",
    "${UpstreamTip}..HEAD"
) -Capture
$MergeCount = [int]$MergeCountText
Write-Host "StableKite-only merge commits: $MergeCount"

if ($MergeCount -ne 0) {
    throw "Refusing to continue: merge commits exist above upstream."
}

if ($Push) {
    Invoke-Git -Arguments @(
        "push",
        "--force-with-lease",
        "origin",
        "${Branch}:${Branch}"
    )
    Write-Host "Rebased branch pushed with --force-with-lease."
}
else {
    Write-Host "Rebase check complete. Review/test this tree, then run:"
    Write-Host "  tools/rebase-upstream-rga.ps1 -Push"
}
