#Requires -Version 5.1
# Script to uninstall global gitleaks configuration and hooks (Windows)
# Run in PowerShell: .\uninstall-gitleaks-global.ps1

$ErrorActionPreference = "Stop"
$CONFIG_DIR = Join-Path $env:USERPROFILE ".config\gitleaks"
$TEMPLATE_DIR = Join-Path $env:USERPROFILE ".git-template"
$GITLEAKS_BIN_DIR = Join-Path $env:LOCALAPPDATA "gitleaks\bin"

function Write-Step { param($Message) Write-Host $Message -ForegroundColor Cyan }
function Write-Ok    { param($Message) Write-Host "  OK  $Message" -ForegroundColor Green }
function Write-Fail  { param($Message) Write-Host "  X   $Message" -ForegroundColor Red }

Write-Host "`nUninstalling Gitleaks global configuration...`n" -ForegroundColor Cyan

# Remove config directory
if (Test-Path $CONFIG_DIR) {
    Remove-Item -Path $CONFIG_DIR -Recurse -Force
    Write-Ok "Removed $CONFIG_DIR"
} else {
    Write-Fail "Config directory not found: $CONFIG_DIR"
}

# Remove git template directory and unset config
if (Test-Path $TEMPLATE_DIR) {
    Remove-Item -Path $TEMPLATE_DIR -Recurse -Force
    Write-Ok "Removed $TEMPLATE_DIR"
    try {
        git config --global --unset init.templateDir
        Write-Ok "Unset global git template directory"
    } catch {}
} else {
    Write-Fail "Template directory not found: $TEMPLATE_DIR"
}

# Optionally remove binary and PATH entry
if (Test-Path $GITLEAKS_BIN_DIR) {
    $reply = Read-Host "Remove gitleaks binary from $GITLEAKS_BIN_DIR and PATH? (y/N)"
    if ($reply -match '^[Yy]$') {
        Remove-Item -Path $GITLEAKS_BIN_DIR -Recurse -Force -ErrorAction SilentlyContinue
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if (-not [string]::IsNullOrEmpty($userPath)) {
            $newPath = ($userPath -split ';' | Where-Object { $_ -ne $GITLEAKS_BIN_DIR }) -join ';'
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        }
        Write-Ok "Removed gitleaks binary and PATH entry"
    }
}

Write-Host "`nUninstallation complete!`n" -ForegroundColor Green
Write-Host "Note: Existing repositories still have the hooks installed." -ForegroundColor Cyan
Write-Host "To remove hooks from individual repos, delete:"
Write-Host "  * .git\hooks\pre-commit"
Write-Host "  * .git\hooks\commit-msg"
Write-Host ""
