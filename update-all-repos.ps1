#Requires -Version 5.1
# Installs gitleaks pre-commit hooks in existing repositories (Windows).
# Usage:
#   .\update-all-repos.ps1                    # All local drives (C:\, D:\, E:\, etc.) - single command for all repos
#   .\update-all-repos.ps1 C:\Projects        # Only repos under C:\Projects
#   .\update-all-repos.ps1 C:\Projects C:\Sites
# Optional: $MAX_DEPTH = 3; .\update-all-repos.ps1 C:\  # Limit depth on a drive

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$TargetPaths
)

$ErrorActionPreference = "Stop"
$TEMPLATE_DIR = Join-Path $env:USERPROFILE ".git-template"
$TEMPLATE_HOOKS = Join-Path $TEMPLATE_DIR "hooks"

function Write-Step { param($Message) Write-Host $Message -ForegroundColor Cyan }
function Write-Ok    { param($Message) Write-Host "  OK  $Message" -ForegroundColor Green }
function Write-Warn  { param($Message) Write-Host "  !!  $Message" -ForegroundColor Yellow }
function Write-Fail  { param($Message) Write-Host "  X   $Message" -ForegroundColor Red }

if (-not (Get-Command gitleaks -ErrorAction SilentlyContinue)) {
    Write-Fail "gitleaks is not installed or not in PATH."
    Write-Host "Run .\install-gitleaks-global.ps1 first, or install from https://github.com/gitleaks/gitleaks/releases"
    exit 1
}

if (-not (Test-Path (Join-Path $TEMPLATE_HOOKS "pre-commit"))) {
    Write-Fail "Git template hooks not found at $TEMPLATE_HOOKS"
    Write-Host "Run .\install-gitleaks-global.ps1 first."
    exit 1
}

$preCommitSrc = Join-Path $TEMPLATE_HOOKS "pre-commit"
$commitMsgSrc = Join-Path $TEMPLATE_HOOKS "commit-msg"

# No path given = scan all local fixed drives (C:\, D:\, E:\, etc.)
if ($TargetPaths.Count -eq 0) {
    # Use .Name (e.g. "C:") to avoid null .Root on some Windows setups
    $TargetPaths = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { $_.Name + '\' }
    if ($TargetPaths.Count -eq 0) {
        Write-Fail "No local drives found."
        exit 1
    }
    Write-Host "No path specified: scanning all local drives ( $($TargetPaths -join ', ') )" -ForegroundColor Cyan
    Write-Host "This may take a while on large drives. Press Ctrl+C to cancel." -ForegroundColor Gray
    Write-Host ""
}

$script:Updated = 0
$script:Skipped = 0
$script:Failed = 0

function Get-GitRepos {
    param([string]$Root, [int]$MaxDepth = 0)
    $repos = @()
    # Include root if it is itself a git repo (Get-ChildItem -Recurse only returns subdirs, not root)
    if (Test-Path (Join-Path $Root ".git")) {
        $repos += $Root
    }
    $params = @{ Path = $Root; Directory = $true; Recurse = $true; ErrorAction = 'SilentlyContinue' }
    if ($MaxDepth -gt 0) { $params['Depth'] = $MaxDepth }
    $subdirs = Get-ChildItem @params | Where-Object { Test-Path (Join-Path $_.FullName ".git") }
    $repos += ($subdirs | ForEach-Object { $_.FullName })
    $repos | Sort-Object -Unique
}

function Install-Hooks {
    param([string]$RepoDir)
    $hooksDir = Join-Path $RepoDir ".git\hooks"
    if (-not (Test-Path $hooksDir)) { return $false }
    try {
        Copy-Item -Path $preCommitSrc -Destination (Join-Path $hooksDir "pre-commit") -Force
        Copy-Item -Path $commitMsgSrc -Destination (Join-Path $hooksDir "commit-msg") -Force
        return $true
    } catch {
        return $false
    }
}

foreach ($target in $TargetPaths) {
    $root = $target
    if (-not [System.IO.Path]::IsPathRooted($root)) {
        $root = Join-Path (Get-Location).Path $root
    }
    if (-not (Test-Path $root -PathType Container)) {
        Write-Fail "Directory does not exist: $root"
        continue
    }

    $maxDepth = if ($env:MAX_DEPTH) { [int]$env:MAX_DEPTH } else { 0 }
    Write-Step "Scanning $root for git repositories..."
    $repos = Get-GitRepos -Root $root -MaxDepth $maxDepth
    $i = 0
    foreach ($repo in $repos) {
        $i++
        Write-Host "  [$i] $repo" -ForegroundColor Gray
        if (Install-Hooks -RepoDir $repo) {
            $script:Updated++
            Write-Ok "Hooks installed"
        } else {
            $script:Failed++
            Write-Fail "Failed to install hooks"
        }
    }
}

Write-Host ""
Write-Host "Done. Updated: $($script:Updated), Failed: $($script:Failed)" -ForegroundColor Cyan
if ($script:Updated -eq 0 -and $script:Failed -eq 0) {
    Write-Host ""
    Write-Warn "No git repositories were found in the scanned path(s)."
    Write-Host "  To scan only a specific folder: .\update-all-repos.ps1 C:\Projects" -ForegroundColor Gray
}
if ($script:Failed -gt 0) { exit 1 }
