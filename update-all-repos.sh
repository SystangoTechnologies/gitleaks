#!/bin/bash

# Script to install gitleaks pre-commit hooks in existing repositories
# Supports both Husky-managed repos and native Git hooks
# Based on git-secrets update-all-repos.sh

# Usage examples:
#   ./update-all-repos.sh                    # Updates all repos in current directory
#   ./update-all-repos.sh ~/Projects         # Updates all repos in ~/Projects
#   ./update-all-repos.sh ~/Sites ~/Projects # Updates repos in multiple directories

HIGHLIGHT="\e[01;34m"
SUCCESS="\e[01;32m"
ERROR="\e[01;31m"
WARNING="\e[01;33m"
NORMAL='\e[00m'

# Check if gitleaks is installed
if ! command -v gitleaks &> /dev/null; then
    echo -e "${ERROR}Error: gitleaks is not installed${NORMAL}"
    echo "Please install gitleaks first:"
    echo "  • macOS: brew install gitleaks"
    echo "  • Linux: Download from https://github.com/gitleaks/gitleaks/releases"
    echo "  • Go: go install github.com/gitleaks/gitleaks/v8@latest"
    exit 1
fi

# Check if global template is set up
TEMPLATE_DIR="$HOME/.git-template"
if [ ! -d "$TEMPLATE_DIR/hooks" ]; then
    echo -e "${ERROR}Error: Git template directory not found${NORMAL}"
    echo "Please run ./install-gitleaks-global.sh first"
    exit 1
fi

# Function to check if gitleaks is already in a file
function has_gitleaks {
  local file="$1"
  grep -q "gitleaks" "$file" 2>/dev/null
}

# Function to safely inject gitleaks into Husky pre-commit hook
function inject_gitleaks_husky {
  local hook_file="$1"
  
  # Check if gitleaks is already present
  if has_gitleaks "$hook_file"; then
    echo -e "  ${SUCCESS}✓${NORMAL} Gitleaks already configured in Husky pre-commit"
    return 0
  fi
  
  # Create temporary file with injected gitleaks
  local temp_file=$(mktemp)
  
  # Read the file and inject gitleaks after the husky.sh line
  local injected=false
  while IFS= read -r line; do
    echo "$line" >> "$temp_file"
    
    # Inject after the husky.sh sourcing line
    if [[ ! "$injected" == true ]] && [[ "$line" =~ \.\s+.*husky\.sh ]] || [[ "$line" =~ source.*husky\.sh ]]; then
      cat >> "$temp_file" << 'GITLEAKS_INJECT'

# Gitleaks secret scanning (auto-injected by gitleaks)
# Add common gitleaks installation paths to PATH for Husky non-login shell
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

if command -v gitleaks &> /dev/null; then
  echo "🔍 Scanning for secrets with gitleaks..."
  GITLEAKS_CONFIG="$HOME/.config/gitleaks/gitleaks.toml"
  if [ -f "$GITLEAKS_CONFIG" ]; then
    gitleaks protect --staged --redact --verbose --config="$GITLEAKS_CONFIG" || exit 1
  else
    gitleaks protect --staged --redact --verbose || exit 1
  fi
  echo "✓ No secrets detected"
else
  echo "⚠ Warning: gitleaks not found, skipping secret scan"
fi
GITLEAKS_INJECT
      injected=true
    fi
  done < "$hook_file"
  
  # If we didn't find the husky.sh line, append at the end
  if [ "$injected" != true ]; then
    cat >> "$temp_file" << 'GITLEAKS_INJECT'

# Gitleaks secret scanning (auto-injected by sysgitleaks)
if command -v gitleaks &> /dev/null; then
  echo "🔍 Scanning for secrets with gitleaks..."
  GITLEAKS_CONFIG="$HOME/.config/gitleaks/gitleaks.toml"
  if [ -f "$GITLEAKS_CONFIG" ]; then
    gitleaks protect --staged --redact --verbose --config="$GITLEAKS_CONFIG" || exit 1
  else
    gitleaks protect --staged --redact --verbose || exit 1
  fi
  echo "✓ No secrets detected"
else
  echo "⚠ Warning: gitleaks not found, skipping secret scan"
fi
GITLEAKS_INJECT
  fi
  
  # Replace original file with modified version
  mv "$temp_file" "$hook_file" 2>/dev/null || {
    echo -e "  ${ERROR}✗${NORMAL} Failed to update $hook_file"
    rm -f "$temp_file"
    return 1
  }
  
  # Ensure it's executable
  chmod +x "$hook_file" 2>/dev/null || {
    echo -e "  ${WARNING}⚠${NORMAL}  Warning: Could not make hook executable"
  }
  
  echo -e "  ${SUCCESS}✓${NORMAL} Injected gitleaks into Husky pre-commit hook"
  return 0
}

# Function to create Husky pre-commit hook if it doesn't exist
function create_husky_precommit {
  local hook_file="$1"
  
  mkdir -p "$(dirname "$hook_file")" 2>/dev/null || {
    echo -e "  ${ERROR}✗${NORMAL} Failed to create .husky directory"
    return 1
  }
  
  cat > "$hook_file" << 'HUSKY_HOOK'
# Gitleaks secret scanning (auto-injected by sysgitleaks)
if command -v gitleaks &> /dev/null; then
  echo "🔍 Scanning for secrets with gitleaks..."
  GITLEAKS_CONFIG="$HOME/.config/gitleaks/gitleaks.toml"
  if [ -f "$GITLEAKS_CONFIG" ]; then
    gitleaks protect --staged --redact --verbose --config="$GITLEAKS_CONFIG" || exit 1
  else
    gitleaks protect --staged --redact --verbose || exit 1
  fi
  echo "✓ No secrets detected"
else
  echo "⚠ Warning: gitleaks not found, skipping secret scan"
fi
HUSKY_HOOK
  
  chmod +x "$hook_file" 2>/dev/null || {
    echo -e "  ${WARNING}⚠${NORMAL}  Warning: Could not make hook executable"
  }
  
  echo -e "  ${SUCCESS}✓${NORMAL} Created Husky pre-commit hook with gitleaks"
  return 0
}

# Function to install native Git hooks
function install_native_hooks {
  mkdir -p .git/hooks 2>/dev/null || {
    echo -e "  ${ERROR}✗${NORMAL} Failed to create hooks directory"
    return 1
  }
  
  local success=true
  
  # Check if pre-commit already exists and has gitleaks
  if [ -f .git/hooks/pre-commit ]; then
    if has_gitleaks .git/hooks/pre-commit; then
      echo -e "  ${SUCCESS}✓${NORMAL} Native pre-commit hook already has gitleaks"
    else
      # Backup existing hook
      cp .git/hooks/pre-commit .git/hooks/pre-commit.backup.$(date +%s) 2>/dev/null
      echo -e "  ${WARNING}⚠${NORMAL}  Existing pre-commit hook backed up"
      
      # Install new hook (overwriting)
      if [ -f "$TEMPLATE_DIR/hooks/pre-commit" ]; then
        cp "$TEMPLATE_DIR/hooks/pre-commit" .git/hooks/pre-commit 2>/dev/null && \
        chmod +x .git/hooks/pre-commit 2>/dev/null && \
        echo -e "  ${SUCCESS}✓${NORMAL} Installed pre-commit hook"
      else
        success=false
      fi
    fi
  else
    # No existing hook, just install
    if [ -f "$TEMPLATE_DIR/hooks/pre-commit" ]; then
      cp "$TEMPLATE_DIR/hooks/pre-commit" .git/hooks/pre-commit 2>/dev/null && \
      chmod +x .git/hooks/pre-commit 2>/dev/null && \
      echo -e "  ${SUCCESS}✓${NORMAL} Installed pre-commit hook"
    else
      success=false
    fi
  fi
  
  # Install commit-msg hook
  if [ -f .git/hooks/commit-msg ]; then
    if has_gitleaks .git/hooks/commit-msg; then
      echo -e "  ${SUCCESS}✓${NORMAL} Native commit-msg hook already has gitleaks"
    else
      cp .git/hooks/commit-msg .git/hooks/commit-msg.backup.$(date +%s) 2>/dev/null
      if [ -f "$TEMPLATE_DIR/hooks/commit-msg" ]; then
        cp "$TEMPLATE_DIR/hooks/commit-msg" .git/hooks/commit-msg 2>/dev/null && \
        chmod +x .git/hooks/commit-msg 2>/dev/null && \
        echo -e "  ${SUCCESS}✓${NORMAL} Installed commit-msg hook"
      fi
    fi
  else
    if [ -f "$TEMPLATE_DIR/hooks/commit-msg" ]; then
      cp "$TEMPLATE_DIR/hooks/commit-msg" .git/hooks/commit-msg 2>/dev/null && \
      chmod +x .git/hooks/commit-msg 2>/dev/null && \
      echo -e "  ${SUCCESS}✓${NORMAL} Installed commit-msg hook"
    fi
  fi
  
  # Test the installation
  if [ -x .git/hooks/pre-commit ]; then
    echo -e "  ${SUCCESS}✓${NORMAL} Hooks are executable and ready"
  else
    echo -e "  ${ERROR}✗${NORMAL} Warning: Hooks may not be executable"
    success=false
  fi
  
  if [ "$success" != true ]; then
    return 1
  fi
  
  return 0
}

function update_repo {
  local d="$1"
  
  # Skip if not a directory or is a symbolic link
  if [ ! -d "$d" ] || [ -L "$d" ]; then
    return 0
  fi
  
  # Try to enter directory, return if fails
  cd "$d" > /dev/null 2>&1 || return 0
  
  if [ -d ".git" ]; then
    printf "%b\n" "${HIGHLIGHT}Installing gitleaks hooks in $(pwd)${NORMAL}"
    
    # CRITICAL: Check if core.hooksPath is configured but directory doesn't exist
    HOOKS_PATH=$(git config core.hooksPath 2>/dev/null || echo "")
    if [ -n "$HOOKS_PATH" ] && [ ! -d "$HOOKS_PATH" ]; then
      echo -e "  ${ERROR}🚨 CRITICAL${NORMAL}: Git is configured to use hooks from '$HOOKS_PATH' but directory doesn't exist!"
      echo -e "  ${WARNING}⚠${NORMAL}  This means NO hooks are running - security bypass!"
      echo -e "  ${HIGHLIGHT}→${NORMAL} Fixing: Unsetting core.hooksPath and installing native hooks"
      git config --unset core.hooksPath
      install_native_hooks
      return 0
    fi
    
    # Detect if this repo uses Husky
    if [ -d ".husky" ]; then
      echo -e "  ${HIGHLIGHT}→${NORMAL} Detected Husky repository"
      
      # Check if pre-commit exists
      if [ -f ".husky/pre-commit" ]; then
        inject_gitleaks_husky ".husky/pre-commit"
      else
        # Check if husky.sh exists to confirm it's a valid Husky setup
        if [ -f ".husky/_/husky.sh" ] || [ -f ".husky/husky.sh" ]; then
          create_husky_precommit ".husky/pre-commit"
        else
          echo -e "  ${WARNING}⚠${NORMAL}  Husky directory exists but appears incomplete"
          echo -e "  ${HIGHLIGHT}→${NORMAL} Installing native Git hooks as fallback"
          install_native_hooks
        fi
      fi
    else
      # Check if core.hooksPath points to .husky but .husky doesn't exist
      if [ "$HOOKS_PATH" = ".husky/_" ] || [ "$HOOKS_PATH" = ".husky" ]; then
        echo -e "  ${WARNING}⚠${NORMAL}  Repo was using Husky but .husky/ is missing"
        echo -e "  ${HIGHLIGHT}→${NORMAL} Unsetting core.hooksPath and using native hooks"
        git config --unset core.hooksPath
      fi
      
      # Standard git hooks installation
      echo -e "  ${HIGHLIGHT}→${NORMAL} Using native Git hooks"
      install_native_hooks
    fi
  else
    # Not a git repo, scan subdirectories (but with protection)
    scan_dirs * 2>/dev/null || true
  fi
  
  cd .. > /dev/null 2>&1 || true
}

function scan_dirs {
  for x in "$@"; do
    # Skip hidden directories and problematic directories
    if [[ "$x" == .* ]] || [[ "$x" == "__MACOSX" ]] || [[ "$x" == "node_modules" ]]; then
      continue
    fi
    update_repo "$x" || true  # Continue even if update_repo fails
  done
}

function update_directory {
  if [ "$1" != "" ]; then 
    cd "$1" > /dev/null 2>&1 || {
      echo -e "${ERROR}✗${NORMAL} Cannot access directory: $1"
      return 1
    }
  fi
  printf "%b\n" "${HIGHLIGHT}Scanning ${PWD} for git repositories...${NORMAL}\n"
  scan_dirs * 2>/dev/null || true
}

# Main execution
echo -e "${HIGHLIGHT}========================================${NORMAL}"
echo -e "${HIGHLIGHT}Gitleaks Hook Installer${NORMAL}"
echo -e "${HIGHLIGHT}========================================${NORMAL}\n"

if [ "$1" == "" ]; then
  update_directory
else
  for dir in "$@"; do
    update_directory "$dir"
  done
fi

echo -e "\n${SUCCESS}========================================${NORMAL}"
echo -e "${SUCCESS}Update Complete!${NORMAL}"
echo -e "${SUCCESS}========================================${NORMAL}\n"

echo -e "${HIGHLIGHT}Summary:${NORMAL}"
echo "  • Gitleaks pre-commit hooks have been installed in all git repositories"
echo "  • Both Husky and native Git hooks are supported"
echo "  • Future commits will be scanned for blockchain private keys and secrets"
echo ""
echo -e "${HIGHLIGHT}Test the hooks:${NORMAL}"
echo "  cd /path/to/any/repo"
echo "  echo 'const key = \"abc\"' > test.js"
echo "  git add test.js"
echo "  git commit -m 'test' # Add a real secret to test blocking"
echo ""
