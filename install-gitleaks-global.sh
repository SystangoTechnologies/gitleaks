#!/bin/bash

# Script to install gitleaks globally with pre-commit hooks for all repos
# This sets up:
# 1. Gitleaks binary in /usr/local/bin/
# 2. Global gitleaks config in ~/.config/gitleaks/
# 3. Git template directory for automatic hook installation in new repos
# 4. Instructions for updating existing repos

set -e

HIGHLIGHT="\e[01;34m"
SUCCESS="\e[01;32m"
ERROR="\e[01;31m"
WARNING="\e[01;33m"
NORMAL='\e[00m'

GITLEAKS_VERSION="8.24.2"

echo -e "${HIGHLIGHT}Installing Gitleaks globally...${NORMAL}\n"

# Step 1: Check and install gitleaks binary
echo -e "${HIGHLIGHT}Step 1: Installing gitleaks binary...${NORMAL}"

if command -v gitleaks &> /dev/null; then
    CURRENT_VERSION=$(gitleaks version 2>&1 || echo "unknown")
    echo -e "${WARNING}⚠${NORMAL}  Gitleaks is already installed: $CURRENT_VERSION"
    read -p "Do you want to reinstall/update to v${GITLEAKS_VERSION}? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${SUCCESS}✓${NORMAL} Keeping existing gitleaks installation"
        SKIP_BINARY_INSTALL=true
    fi
fi

if [ "$SKIP_BINARY_INSTALL" != "true" ]; then
    echo -e "${HIGHLIGHT}Downloading gitleaks v${GITLEAKS_VERSION}...${NORMAL}"
    
    # Create temp directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Download and extract
    if curl -sSfL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" -o gitleaks.tar.gz; then
        echo -e "${SUCCESS}✓${NORMAL} Downloaded gitleaks"
    else
        echo -e "${ERROR}✗${NORMAL} Failed to download gitleaks"
        exit 1
    fi
    
    tar -xzf gitleaks.tar.gz
    chmod +x gitleaks
    
    # Test the binary
    if ./gitleaks version > /dev/null 2>&1; then
        DOWNLOADED_VERSION=$(./gitleaks version)
        echo -e "${SUCCESS}✓${NORMAL} Verified gitleaks binary: $DOWNLOADED_VERSION"
    else
        echo -e "${ERROR}✗${NORMAL} Downloaded binary is not working"
        exit 1
    fi
    
    # Install to /usr/local/bin (requires sudo)
    echo -e "${HIGHLIGHT}Installing to /usr/local/bin/ (requires sudo)...${NORMAL}"
    if sudo mv gitleaks /usr/local/bin/gitleaks; then
        echo -e "${SUCCESS}✓${NORMAL} Installed gitleaks to /usr/local/bin/gitleaks"
        
        # Verify installation
        INSTALLED_VERSION=$(gitleaks version)
        echo -e "${SUCCESS}✓${NORMAL} Verified installation: $INSTALLED_VERSION"
    else
        echo -e "${ERROR}✗${NORMAL} Failed to install gitleaks (sudo required)"
        exit 1
    fi
    
    # Cleanup
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    echo -e "${SUCCESS}✓${NORMAL} Cleaned up temporary files"
fi

echo ""

# Step 2: Create config directory and copy config
echo -e "${HIGHLIGHT}Step 2: Setting up global configuration...${NORMAL}"

CONFIG_DIR="$HOME/.config/gitleaks"
mkdir -p "$CONFIG_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/.gitleaks.toml" "$CONFIG_DIR/gitleaks.toml"
echo -e "${SUCCESS}✓${NORMAL} Copied gitleaks config to $CONFIG_DIR/gitleaks.toml"

echo ""

# Step 3: Create git template directory
echo -e "${HIGHLIGHT}Step 3: Creating git template directory...${NORMAL}"

TEMPLATE_DIR="$HOME/.git-template"
mkdir -p "$TEMPLATE_DIR/hooks"

# Step 4: Create pre-commit hook (smart auto-detecting)
cat > "$TEMPLATE_DIR/hooks/pre-commit" << 'EOF'
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
    # Add common gitleaks installation paths to PATH
    export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"
    
    # Try to find gitleaks executable
    GITLEAKS_BIN=""
    for gitleaks_path in /usr/local/bin/gitleaks /opt/homebrew/bin/gitleaks /usr/bin/gitleaks $(which gitleaks 2>/dev/null); do
      if [ -x "$gitleaks_path" ] 2>/dev/null; then
        GITLEAKS_BIN="$gitleaks_path"
        break
      fi
    done
    
    if [ -z "$GITLEAKS_BIN" ]; then
        echo -e "${RED}Error: gitleaks is not installed or not found in PATH${NC}"
        echo "Install it from: https://github.com/gitleaks/gitleaks"
        echo "Or run: brew install gitleaks (macOS) or go install github.com/gitleaks/gitleaks/v8@latest"
        echo "Searched paths: /usr/local/bin, /opt/homebrew/bin, /usr/bin"
        return 1
    fi

    # Use global config if exists, otherwise use default
    GITLEAKS_CONFIG="$HOME/.config/gitleaks/gitleaks.toml"
    if [ ! -f "$GITLEAKS_CONFIG" ]; then
        GITLEAKS_CONFIG=""
    fi

    # Run gitleaks on staged changes
    echo -e "${YELLOW}🔍 Scanning for secrets with gitleaks...${NC}"
    echo -e "${YELLOW}Using: $GITLEAKS_BIN${NC}"

    if [ -n "$GITLEAKS_CONFIG" ]; then
        "$GITLEAKS_BIN" protect --staged --redact --config="$GITLEAKS_CONFIG" --verbose
    else
        "$GITLEAKS_BIN" protect --staged --redact --verbose
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
EOF

chmod +x "$TEMPLATE_DIR/hooks/pre-commit"
echo -e "${SUCCESS}✓${NORMAL} Created pre-commit hook in $TEMPLATE_DIR/hooks/pre-commit"

# Step 5: Create commit-msg hook (secondary check with smart detection)
cat > "$TEMPLATE_DIR/hooks/commit-msg" << 'EOF'
#!/bin/bash
# Gitleaks commit-msg hook (Smart Auto-Detecting)
# This is a secondary check in case pre-commit was bypassed

# Add common gitleaks installation paths to PATH
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

# Find gitleaks executable
GITLEAKS_BIN=""
for gitleaks_path in /usr/local/bin/gitleaks /opt/homebrew/bin/gitleaks /usr/bin/gitleaks; do
  if [ -x "$gitleaks_path" ] 2>/dev/null; then
    GITLEAKS_BIN="$gitleaks_path"
    break
  fi
done

# Skip if gitleaks not found
if [ -z "$GITLEAKS_BIN" ]; then
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
    "$GITLEAKS_BIN" protect --staged --redact --config="$GITLEAKS_CONFIG" > /dev/null 2>&1
else
    "$GITLEAKS_BIN" protect --staged --redact > /dev/null 2>&1
fi

if [ $? -ne 0 ]; then
    echo "Error: Secrets detected in commit. Aborting."
    exit 1
fi

exit 0
EOF

chmod +x "$TEMPLATE_DIR/hooks/commit-msg"
echo -e "${SUCCESS}✓${NORMAL} Created commit-msg hook in $TEMPLATE_DIR/hooks/commit-msg"

echo ""

# Step 6: Configure git to use template directory
echo -e "${HIGHLIGHT}Step 4: Configuring git to use template directory...${NORMAL}"
git config --global init.templateDir "$TEMPLATE_DIR"
echo -e "${SUCCESS}✓${NORMAL} Set global git template directory"

echo -e "\n${SUCCESS}========================================${NORMAL}"
echo -e "${SUCCESS}Installation Complete!${NORMAL}"
echo -e "${SUCCESS}========================================${NORMAL}\n"

echo -e "${HIGHLIGHT}What was installed:${NORMAL}"
echo "  • Gitleaks binary: /usr/local/bin/gitleaks"
echo "  • Global config:   $CONFIG_DIR/gitleaks.toml"
echo "  • Git template:    $TEMPLATE_DIR/hooks/"
echo "  • Hooks:           pre-commit, commit-msg"

echo -e "\n${HIGHLIGHT}Next steps:${NORMAL}"
echo "  1. All NEW git repositories will automatically get gitleaks hooks"
echo "  2. To add hooks to EXISTING repos, run:"
echo -e "     ${HIGHLIGHT}./update-all-repos.sh [directory]${NORMAL}"
echo ""
echo "  3. To update a single repo manually:"
echo -e "     ${HIGHLIGHT}cd /path/to/repo && git init${NORMAL}"
echo ""

echo -e "${HIGHLIGHT}Test installation:${NORMAL}"
echo "  • Create a new repo and try committing a secret"
echo "  • The hook should block commits containing blockchain private keys or any other secrets"
echo ""
