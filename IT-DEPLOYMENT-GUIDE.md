# IT Deployment Guide

## Overview
Deploy gitleaks secret scanning across developer machines. IT team runs once per machine.

## Quick Installation

### 1. Install Gitleaks Globally
```bash
cd /path/to/sysgitleaks
chmod +x install-gitleaks-global.sh && ./install-gitleaks-global.sh
```
*Requires sudo. Installs gitleaks binary and global configuration.*

### 2. Update All Repositories
```bash
chmod +x update-all-repos.sh && ./update-all-repos.sh ~
```
*Installs hooks in all repos. Detects Husky automatically.*

### 3. Verify Installation
```bash
gitleaks version

# Test in any repository
cd /path/to/any/repo
echo 'const key = "ADD_AWS_KEY"' > test.js
git add test.js
git commit -m "test"
# Should BLOCK the commit
```
## Uninstall

```bash
chmod +x uninstall-gitleaks-global.sh && ./uninstall-gitleaks-global.sh
```

## Security Note

Client-side hooks can be bypassed with `--no-verify`. For complete protection, add server-side scanning (GitHub Actions, GitLab CI).
