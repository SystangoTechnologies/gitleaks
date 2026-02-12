# IT Deployment Guide

## Overview
Deploy gitleaks secret scanning across developer machines. IT team runs once per machine.

## Quick Installation

### Linux / macOS

#### 1. Install Gitleaks Globally
```bash
cd /path/to/gitleaks
chmod +x install-gitleaks-global.sh && ./install-gitleaks-global.sh
```
*Requires sudo. Installs gitleaks binary and global configuration.*

#### 2. Update All Repositories
```bash
chmod +x update-all-repos.sh && ./update-all-repos.sh ~
```
*Installs hooks in all repos. Detects Husky automatically.*

#### 3. Uninstall
```bash
chmod +x uninstall-gitleaks-global.sh && ./uninstall-gitleaks-global.sh
```

### Windows (PowerShell)

#### 1. Install Gitleaks Globally
```powershell
cd C:\path\to\gitleaks
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser   # if needed
.\install-gitleaks-global.ps1
```
*No admin required. Installs gitleaks to `%LOCALAPPDATA%\gitleaks\bin` and adds it to your user PATH.*

#### 2. Update All Repositories
Run with **no arguments** to scan all local drives (C:\, D:\, E:\, etc.) and install hooks in every repo. One command for the whole machine.
```powershell
.\update-all-repos.ps1
```
Optional: limit to one drive or folder (faster):
```powershell
.\update-all-repos.ps1 C:\Projects
.\update-all-repos.ps1 C:\ D:\
$env:MAX_DEPTH = 4; .\update-all-repos.ps1 C:\   # limit depth on C:
```

#### 3. Uninstall
```powershell
.\uninstall-gitleaks-global.ps1
```

---

## Verify Installation (all platforms)

```bash
gitleaks version

# Test in any repository
cd /path/to/any/repo
echo 'const key = "ADD_AWS_KEY"' > test.js
git add test.js
git commit -m "test"
# Should BLOCK the commit
```

## Security Note

Client-side hooks can be bypassed with `--no-verify`. For complete protection, add server-side scanning (GitHub Actions, GitLab CI).
