#Requires -Version 5.1
# Script to install gitleaks globally with pre-commit hooks for all repos (Windows)
# This sets up:
# 1. Gitleaks binary in %LOCALAPPDATA%\gitleaks\bin (added to user PATH)
# 2. Global gitleaks config in %USERPROFILE%\.config\gitleaks\
# 3. Git template directory for automatic hook installation in new repos
# 4. Instructions for updating existing repos
#
# Run in PowerShell: .\install-gitleaks-global.ps1
# If you get execution policy error: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

$ErrorActionPreference = "Stop"
$GITLEAKS_VERSION = "8.24.2"
$GITLEAKS_BIN_DIR = Join-Path $env:LOCALAPPDATA "gitleaks\bin"
$CONFIG_DIR = Join-Path $env:USERPROFILE ".config\gitleaks"
$TEMPLATE_DIR = Join-Path $env:USERPROFILE ".git-template"
$TEMPLATE_HOOKS = Join-Path $TEMPLATE_DIR "hooks"

function Write-Step { param($Message) Write-Host $Message -ForegroundColor Cyan }
function Write-Ok    { param($Message) Write-Host "  OK  $Message" -ForegroundColor Green }
function Write-Warn  { param($Message) Write-Host "  !!  $Message" -ForegroundColor Yellow }
function Write-Fail  { param($Message) Write-Host "  X   $Message" -ForegroundColor Red }

Write-Host "`nInstalling Gitleaks globally...`n" -ForegroundColor Cyan

# Step 1: Check and install gitleaks binary
Write-Step "Step 1: Installing gitleaks binary..."

$SkipBinary = $false
$existing = Get-Command gitleaks -ErrorAction SilentlyContinue
if ($existing) {
    try {
        $currentVer = (gitleaks version 2>&1) -join " "
        Write-Warn "Gitleaks is already installed: $currentVer"
        $reply = Read-Host "Reinstall/update to v$GITLEAKS_VERSION? (y/N)"
        if ($reply -notmatch '^[Yy]$') {
            Write-Ok "Keeping existing gitleaks installation"
            $SkipBinary = $true
        }
    } catch {}
}

if (-not $SkipBinary) {
    # Prefer TLS 1.2 for GitHub (avoids "could not create SSL/TLS secure channel" on older Windows)
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    $zipUrl = "https://github.com/gitleaks/gitleaks/releases/download/v$GITLEAKS_VERSION/gitleaks_${GITLEAKS_VERSION}_windows_x64.zip"
    $tempDir = Join-Path $env:TEMP "gitleaks-install-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    try {
        Write-Step "Downloading gitleaks v$GITLEAKS_VERSION..."
        $zipPath = Join-Path $tempDir "gitleaks.zip"
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
        Write-Ok "Downloaded gitleaks"

        Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force
        $exeSource = Join-Path $tempDir "gitleaks.exe"
        if (-not (Test-Path $exeSource)) {
            $exeSource = Get-ChildItem -Path $tempDir -Filter "gitleaks.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        }
        if (-not $exeSource -or -not (Test-Path $exeSource)) {
            Write-Fail "gitleaks.exe not found in archive"
            exit 1
        }

        New-Item -ItemType Directory -Path $GITLEAKS_BIN_DIR -Force | Out-Null
        Copy-Item -Path $exeSource -Destination (Join-Path $GITLEAKS_BIN_DIR "gitleaks.exe") -Force
        Write-Ok "Installed gitleaks to $GITLEAKS_BIN_DIR"

        # Add to user PATH if not already present
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ([string]::IsNullOrEmpty($userPath)) { $userPath = "" }
        if ($userPath -notlike "*$GITLEAKS_BIN_DIR*") {
            $newPath = if ($userPath -eq "") { $GITLEAKS_BIN_DIR } else { "$userPath;$GITLEAKS_BIN_DIR" }
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
            $env:Path = "$env:Path;$GITLEAKS_BIN_DIR"
            Write-Ok "Added gitleaks to user PATH (new terminals will pick it up)"
        }

        # Verify
        $ver = & (Join-Path $GITLEAKS_BIN_DIR "gitleaks.exe") version 2>&1
        Write-Ok "Verified: $ver"
    } finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""

# Step 2: Global config
Write-Step "Step 2: Setting up global configuration..."
New-Item -ItemType Directory -Path $CONFIG_DIR -Force | Out-Null
$configSource = Join-Path $PSScriptRoot ".gitleaks.toml"
if (Test-Path $configSource) {
    Copy-Item -Path $configSource -Destination (Join-Path $CONFIG_DIR "gitleaks.toml") -Force
    Write-Ok "Copied gitleaks config to $CONFIG_DIR\gitleaks.toml"
} else {
    Write-Warn ".gitleaks.toml not found in script dir; config not copied. Create $CONFIG_DIR\gitleaks.toml manually if needed."
}

Write-Host ""

# Step 3: Git template and hooks
Write-Step "Step 3: Creating git template directory..."
New-Item -ItemType Directory -Path $TEMPLATE_HOOKS -Force | Out-Null

$preCommitHook = @'
#!/bin/bash

# Gitleaks pre-commit hook (Smart Auto-Detecting)
# Prevents committing secrets to git repository
# Automatically detects and adapts to Husky or native Git hooks

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to run gitleaks scan
run_gitleaks_scan() {
    # Check if gitleaks is installed
    if ! command -v gitleaks &> /dev/null; then
        echo -e "${RED}Error: gitleaks is not installed${NC}"
        echo "Install it from: https://github.com/gitleaks/gitleaks"
        echo "Or run: brew install gitleaks (macOS) or go install github.com/gitleaks/gitleaks/v8@latest"
        return 1
    fi

    # Use global config if exists, otherwise use default
    GITLEAKS_CONFIG="$HOME/.config/gitleaks/gitleaks.toml"
    if [ ! -f "$GITLEAKS_CONFIG" ]; then
        GITLEAKS_CONFIG=""
    fi

    # Run gitleaks on staged changes
    echo -e "${YELLOW}🔍 Scanning for secrets with gitleaks...${NC}"

    if [ -n "$GITLEAKS_CONFIG" ]; then
        gitleaks protect --staged --redact --config="$GITLEAKS_CONFIG" --verbose
    else
        gitleaks protect --staged --redact --verbose
    fi

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ No secrets detected${NC}"
        return 0
    else
        echo -e "${RED}✗ Secrets detected! Commit blocked.${NC}"
        return 1
    fi
}

# SMART DETECTION: Check if Husky is managing hooks
if [ -d ".husky" ] && [ -f ".husky/pre-commit" ]; then
    # Husky detected - check if it already has gitleaks
    if grep -q "gitleaks" ".husky/pre-commit" 2>/dev/null; then
        # Husky already has gitleaks, let it handle everything
        exit 0
    else
        # Husky exists but doesn't have gitleaks - run scan here
        run_gitleaks_scan
        exit $?
    fi
else
    # No Husky detected - run gitleaks in native mode
    run_gitleaks_scan
    exit $?
fi
'@

$commitMsgHook = @'
#!/bin/bash
# Gitleaks commit-msg hook (Smart Auto-Detecting)
# This is a secondary check in case pre-commit was bypassed

# Skip if gitleaks not installed
if ! command -v gitleaks &> /dev/null; then
    exit 0
fi

# Skip if Husky is managing hooks and already has gitleaks configured
if [ -d ".husky" ] && [ -f ".husky/pre-commit" ]; then
    if grep -q "gitleaks" ".husky/pre-commit" 2>/dev/null; then
        # Husky is handling gitleaks, no need to run again
        exit 0
    fi
fi

# Run gitleaks check
GITLEAKS_CONFIG="$HOME/.config/gitleaks/gitleaks.toml"
if [ ! -f "$GITLEAKS_CONFIG" ]; then
    GITLEAKS_CONFIG=""
fi

# Silent check on commit
if [ -n "$GITLEAKS_CONFIG" ]; then
    gitleaks protect --staged --redact --config="$GITLEAKS_CONFIG" > /dev/null 2>&1
else
    gitleaks protect --staged --redact > /dev/null 2>&1
fi

if [ $? -ne 0 ]; then
    echo "Error: Secrets detected in commit. Aborting."
    exit 1
fi

exit 0
'@

# Write hooks with LF line endings (Git for Windows runs them with bash)
$preCommitPath = Join-Path $TEMPLATE_HOOKS "pre-commit"
$commitMsgPath = Join-Path $TEMPLATE_HOOKS "commit-msg"
[System.IO.File]::WriteAllText($preCommitPath, $preCommitHook.Replace("`r`n", "`n"))
[System.IO.File]::WriteAllText($commitMsgPath, $commitMsgHook.Replace("`r`n", "`n"))
Write-Ok "Created pre-commit and commit-msg hooks in $TEMPLATE_HOOKS"

Write-Host ""

# Step 4: Configure git template
Write-Step "Step 4: Configuring git to use template directory..."
$templateDirNorm = $TEMPLATE_DIR -replace '\\', '/'
git config --global init.templateDir $templateDirNorm
Write-Ok "Set global git template directory"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Installation Complete!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "What was installed:" -ForegroundColor Cyan
Write-Host "  * Gitleaks binary: $GITLEAKS_BIN_DIR\gitleaks.exe"
Write-Host "  * Global config:   $CONFIG_DIR\gitleaks.toml"
Write-Host "  * Git template:    $TEMPLATE_HOOKS"
Write-Host "  * Hooks:           pre-commit, commit-msg"

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "  1. All NEW git repositories will automatically get gitleaks hooks."
Write-Host "  2. For EXISTING repos, run (updates all repos on all local drives):"
Write-Host "     .\update-all-repos.ps1" -ForegroundColor Gray
Write-Host "  3. Or in each repo: git init  (re-run to apply template)"
Write-Host "`nNote: If gitleaks is not found in a new terminal, close and reopen PowerShell, or run:"
Write-Host "  `$env:Path += `";$GITLEAKS_BIN_DIR`""
Write-Host ""