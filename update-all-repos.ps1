#Requires -Version 5.1
# Installs gitleaks pre-commit hooks in existing repositories (Windows).
# Usage:
#   .\update-all-repos.ps1                    # Current directory only
#   .\update-all-repos.ps1 C:\Projects        # All repos under C:\Projects
#   .\update-all-repos.ps1 C:\Projects C:\Sites
# Optional: $MAX_DEPTH = 3; .\update-all-repos.ps1 C:\Projects

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

if ($TargetPaths.Count -eq 0) {
    $TargetPaths = @(Get-Location).Path
}

$script:Updated = 0
$script:Skipped = 0
$script:Failed = 0

function Get-GitRepos {
    param([string]$Root, [int]$MaxDepth = 0)
    $params = @{ Path = $Root; Directory = $true; Recurse = $true; ErrorAction = 'SilentlyContinue' }
    if ($MaxDepth -gt 0) { $params['Depth'] = $MaxDepth }
    $dirs = Get-ChildItem @params | Where-Object { Test-Path (Join-Path $_.FullName ".git") }
    $dirs | ForEach-Object { $_.FullName }
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
    $repos = $repos | Sort-Object -Unique
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
if ($script:Failed -gt 0) { exit 1 }
