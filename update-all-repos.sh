#!/bin/bash

# Script to install gitleaks pre-commit hooks in existing repositories
# Supports both Husky-managed repos and native Git hooks
# Based on git-secrets update-all-repos.sh

# Usage examples:
#   ./update-all-repos.sh                    # Smart mode: scans current dir + common locations
#   ./update-all-repos.sh --all              # Scans home + system dirs (auto-sudo if needed)
#   ./update-all-repos.sh ~/Projects         # Updates all repos in ~/Projects (recursively)
#   ./update-all-repos.sh ~/Sites ~/Projects # Updates repos in multiple directories
#   sudo ./update-all-repos.sh /var          # Updates repos in system directories (requires root)
#
# Environment variables:
#   MAX_DEPTH=3 ./update-all-repos.sh ~/     # Limit recursion depth (default: unlimited)
#
# WARNING: Scanning large directories like ~ or / can take a very long time!
#          It's better to specify specific project directories.

HIGHLIGHT="\e[01;34m"
SUCCESS="\e[01;32m"
ERROR="\e[01;31m"
WARNING="\e[01;33m"
NORMAL='\e[00m'

# Configuration
MAX_DEPTH="${MAX_DEPTH:-}"  # Default: unlimited depth
DRY_RUN="${DRY_RUN:-false}"  # Set to true to only show what would be updated

# Temporary files for tracking stats across subshells
STATS_DIR=$(mktemp -d)
trap "rm -rf $STATS_DIR" EXIT

touch "$STATS_DIR/found"
touch "$STATS_DIR/updated"
touch "$STATS_DIR/failed"
touch "$STATS_DIR/skipped"

function increment_stat {
  local stat_file="$STATS_DIR/$1"
  echo "1" >> "$stat_file"
}

function get_stat {
  local stat_file="$STATS_DIR/$1"
  wc -l < "$stat_file" 2>/dev/null | tr -d ' ' || echo "0"
}

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
# Handle case when running with sudo - use the actual user's home
if [ -n "$SUDO_USER" ]; then
  TEMPLATE_DIR=$(eval echo ~$SUDO_USER)/.git-template
fi

if [ ! -d "$TEMPLATE_DIR/hooks" ]; then
    echo -e "${ERROR}Error: Git template directory not found${NORMAL}"
    echo "Expected location: $TEMPLATE_DIR/hooks"
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
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

# Try to find gitleaks
GITLEAKS_BIN=""
for gitleaks_path in /usr/local/bin/gitleaks /opt/homebrew/bin/gitleaks /usr/bin/gitleaks $(which gitleaks 2>/dev/null); do
  if [ -x "$gitleaks_path" ] 2>/dev/null; then
    GITLEAKS_BIN="$gitleaks_path"
    break
  fi
done

if [ -n "$GITLEAKS_BIN" ]; then
  echo "🔍 Scanning for secrets with gitleaks..."
  GITLEAKS_CONFIG="$HOME/.config/gitleaks/gitleaks.toml"
  if [ -f "$GITLEAKS_CONFIG" ]; then
    "$GITLEAKS_BIN" protect --staged --redact --verbose --config="$GITLEAKS_CONFIG" || exit 1
  else
    "$GITLEAKS_BIN" protect --staged --redact --verbose || exit 1
  fi
  echo "✓ No secrets detected"
else
  echo "⚠ Warning: gitleaks not found in PATH, skipping secret scan"
  echo "  Searched: /usr/local/bin, /opt/homebrew/bin, /usr/bin"
fi
GITLEAKS_INJECT
      injected=true
    fi
  done < "$hook_file"
  
  # If we didn't find the husky.sh line, append at the end
  if [ "$injected" != true ]; then
    cat >> "$temp_file" << 'GITLEAKS_INJECT'

# Gitleaks secret scanning (auto-injected by gitleaks)
# Add common gitleaks installation paths to PATH for Husky non-login shell
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

# Try to find gitleaks
GITLEAKS_BIN=""
for gitleaks_path in /usr/local/bin/gitleaks /opt/homebrew/bin/gitleaks /usr/bin/gitleaks $(which gitleaks 2>/dev/null); do
  if [ -x "$gitleaks_path" ] 2>/dev/null; then
    GITLEAKS_BIN="$gitleaks_path"
    break
  fi
done

if [ -n "$GITLEAKS_BIN" ]; then
  echo "🔍 Scanning for secrets with gitleaks..."
  GITLEAKS_CONFIG="$HOME/.config/gitleaks/gitleaks.toml"
  if [ -f "$GITLEAKS_CONFIG" ]; then
    "$GITLEAKS_BIN" protect --staged --redact --verbose --config="$GITLEAKS_CONFIG" || exit 1
  else
    "$GITLEAKS_BIN" protect --staged --redact --verbose || exit 1
  fi
  echo "✓ No secrets detected"
else
  echo "⚠ Warning: gitleaks not found in PATH, skipping secret scan"
  echo "  Searched: /usr/local/bin, /opt/homebrew/bin, /usr/bin"
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
#!/bin/sh

# Gitleaks secret scanning (auto-injected by gitleaks)
# Add common gitleaks installation paths to PATH for Husky non-login shell
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

# Try to find gitleaks
GITLEAKS_BIN=""
for gitleaks_path in /usr/local/bin/gitleaks /opt/homebrew/bin/gitleaks /usr/bin/gitleaks $(which gitleaks 2>/dev/null); do
  if [ -x "$gitleaks_path" ] 2>/dev/null; then
    GITLEAKS_BIN="$gitleaks_path"
    break
  fi
done

if [ -n "$GITLEAKS_BIN" ]; then
  echo "🔍 Scanning for secrets with gitleaks..."
  GITLEAKS_CONFIG="$HOME/.config/gitleaks/gitleaks.toml"
  if [ -f "$GITLEAKS_CONFIG" ]; then
    "$GITLEAKS_BIN" protect --staged --redact --verbose --config="$GITLEAKS_CONFIG" || exit 1
  else
    "$GITLEAKS_BIN" protect --staged --redact --verbose || exit 1
  fi
  echo "✓ No secrets detected"
else
  echo "⚠ Warning: gitleaks not found in PATH, skipping secret scan"
  echo "  Searched: /usr/local/bin, /opt/homebrew/bin, /usr/bin"
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

# Function to process a single git repository
function process_repo {
  local repodir="$1"
  
  cd "$repodir" 2>/dev/null || {
    echo -e "${WARNING}⚠${NORMAL}  Cannot access repository: $repodir (permission denied)"
    increment_stat "skipped"
    return 1
  }
  
  increment_stat "found"
  printf "%b\n" "${HIGHLIGHT}Found git repository: $(pwd)${NORMAL}"
  
  # Dry run mode - just show what would be updated
  if [ "$DRY_RUN" = "true" ]; then
    echo -e "  ${HIGHLIGHT}→${NORMAL} [DRY RUN] Would install hooks here"
    increment_stat "updated"
    return 0
  fi
  
  # Check if .git directory is writable
  if [ ! -w ".git" ]; then
    echo -e "  ${ERROR}✗${NORMAL} Cannot write to .git directory (permission denied)"
    echo -e "  ${WARNING}⚠${NORMAL}  Repository owned by: $(stat -c '%U:%G' .git 2>/dev/null || echo 'unknown')"
    echo -e "  ${WARNING}⚠${NORMAL}  Current user: $(whoami)"
    if [ "$EUID" -ne 0 ]; then
      echo -e "  ${HIGHLIGHT}→${NORMAL} Tip: Run script with sudo to update system repositories"
    fi
    increment_stat "failed"
    return 1
  fi
  
  # CRITICAL: Check if core.hooksPath is configured but directory doesn't exist
  HOOKS_PATH=$(git config core.hooksPath 2>/dev/null || echo "")
  if [ -n "$HOOKS_PATH" ] && [ ! -d "$HOOKS_PATH" ]; then
    echo -e "  ${ERROR}🚨 CRITICAL${NORMAL}: Git is configured to use hooks from '$HOOKS_PATH' but directory doesn't exist!"
    echo -e "  ${WARNING}⚠${NORMAL}  This means NO hooks are running - security bypass!"
    echo -e "  ${HIGHLIGHT}→${NORMAL} Fixing: Unsetting core.hooksPath and installing native hooks"
    git config --unset core.hooksPath
    if install_native_hooks; then
      increment_stat "updated"
      return 0
    else
      increment_stat "failed"
      return 1
    fi
  fi
  
  # Detect if this repo uses Husky
  if [ -d ".husky" ]; then
    echo -e "  ${HIGHLIGHT}→${NORMAL} Detected Husky repository"
    
    # Check if pre-commit exists
    if [ -f ".husky/pre-commit" ]; then
      if inject_gitleaks_husky ".husky/pre-commit"; then
        increment_stat "updated"
        return 0
      else
        increment_stat "failed"
        return 1
      fi
    else
      # Check if husky.sh exists to confirm it's a valid Husky setup
      if [ -f ".husky/_/husky.sh" ] || [ -f ".husky/husky.sh" ]; then
        if create_husky_precommit ".husky/pre-commit"; then
          increment_stat "updated"
          return 0
        else
          increment_stat "failed"
          return 1
        fi
      else
        echo -e "  ${WARNING}⚠${NORMAL}  Husky directory exists but appears incomplete"
        echo -e "  ${HIGHLIGHT}→${NORMAL} Installing native Git hooks as fallback"
        if install_native_hooks; then
          increment_stat "updated"
          return 0
        else
          increment_stat "failed"
          return 1
        fi
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
    if install_native_hooks; then
      increment_stat "updated"
      return 0
    else
      increment_stat "failed"
      return 1
    fi
  fi
}

function update_directory {
  local target_dir="$1"
  
  # Use current directory if none specified
  if [ -z "$target_dir" ]; then
    target_dir="$PWD"
  fi
  
  # Convert to absolute path
  if [[ "$target_dir" != /* ]]; then
    target_dir="$PWD/$target_dir"
  fi
  
  # Check if directory exists and is accessible
  if [ ! -d "$target_dir" ]; then
    echo -e "${ERROR}✗${NORMAL} Directory does not exist: $target_dir"
    return 1
  fi
  
  if [ ! -r "$target_dir" ]; then
    echo -e "${ERROR}✗${NORMAL} Cannot read directory: $target_dir (permission denied)"
    if [ "$EUID" -ne 0 ]; then
      echo -e "${HIGHLIGHT}→${NORMAL} Try running with sudo: sudo ./update-all-repos.sh $target_dir"
    fi
    return 1
  fi
  
  # Warn if trying to update system directories
  if [[ "$target_dir" == "/var"* ]] || [[ "$target_dir" == "/etc"* ]] || [[ "$target_dir" == "/sys"* ]] || [[ "$target_dir" == "/proc"* ]]; then
    echo -e "${WARNING}⚠${NORMAL}  WARNING: Scanning system directory: ${target_dir}"
    if [ "$EUID" -ne 0 ]; then
      echo -e "${ERROR}✗${NORMAL} ERROR: System directories require root privileges"
      echo -e "${HIGHLIGHT}→${NORMAL} Please run with sudo: sudo ./update-all-repos.sh \"$target_dir\""
      return 1
    fi
    echo -e "${SUCCESS}✓${NORMAL} Running with root privileges"
  fi
  
  printf "%b\n" "${HIGHLIGHT}Scanning ${target_dir} recursively for git repositories...${NORMAL}"
  
  # Build find command with optional depth limit
  local find_cmd="find \"$target_dir\""
  if [ -n "$MAX_DEPTH" ]; then
    find_cmd="$find_cmd -maxdepth $MAX_DEPTH"
    echo -e "${HIGHLIGHT}→${NORMAL} Maximum depth: $MAX_DEPTH levels"
  else
    echo -e "${WARNING}⚠${NORMAL}  WARNING: Unlimited depth - this may take a very long time for large directories!"
    echo -e "${HIGHLIGHT}→${NORMAL} Tip: Set MAX_DEPTH to limit recursion (e.g., MAX_DEPTH=3 ./update-all-repos.sh ~)"
  fi
  echo -e "${HIGHLIGHT}→${NORMAL} Press Ctrl+C to cancel if this takes too long"
  echo ""
  
  # Use find to recursively locate all .git directories
  # Exclude common large directories to speed up search
  # The -print0 and read -d '' handle filenames with spaces and special characters
  local count=0
  while IFS= read -r -d '' gitdir; do
    local repodir=$(dirname "$gitdir")
    
    # Skip submodules (git repos inside .git directories)
    if [[ "$repodir" == *"/.git/"* ]] || [[ "$repodir" == *"/.git" ]]; then
      continue
    fi
    
    count=$((count + 1))
    echo -e "${HIGHLIGHT}[$count]${NORMAL} Found: $repodir"
    
    # Process this repository in current shell (not subshell) to track stats
    (process_repo "$repodir")
    echo ""
    
  done < <(find "$target_dir" \
    ${MAX_DEPTH:+-maxdepth $MAX_DEPTH} \
    -type d \
    \( \
      -name "node_modules" -o -name ".npm" -o -name ".cache" -o -name "__pycache__" \
      -o -name ".venv" -o -name "venv" -o -name ".local" -o -name ".cargo" \
      -o -name ".rustup" -o -name ".m2" -o -name ".gradle" -o -name "target" \
      -o -name "build" -o -name "dist" -o -name "vendor" -o -name ".bundle" \
      -o -path "*/var/lib/*" -o -path "*/var/cache/*" -o -path "*/var/log/*" \
      -o -path "*/var/run/*" -o -path "*/var/lock/*" -o -path "*/var/spool/*" \
      -o -path "*/var/mail/*" -o -path "*/var/backups/*" -o -path "*/var/crash/*" \
      -o -path "*/var/snap/*" -o -path "*/var/metrics/*" \
    \) -prune -o \
    -type d -name ".git" -print0 2>/dev/null)
}

# Main execution
echo -e "${HIGHLIGHT}========================================${NORMAL}"
echo -e "${HIGHLIGHT}Gitleaks Hook Installer${NORMAL}"
echo -e "${HIGHLIGHT}========================================${NORMAL}\n"

# Check for --all flag (treat it same as passing home directory)
if [ "$1" = "--all" ]; then
  # Replace --all with home directory
  if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    # Running as root, use SUDO_USER's home
    set -- "$(eval echo ~$SUDO_USER)"
  else
    set -- "$HOME"
  fi
fi

if [ "$EUID" -eq 0 ]; then
  echo -e "${WARNING}⚠${NORMAL}  Running as root (sudo)"
  echo -e "${HIGHLIGHT}→${NORMAL} Will be able to update system-owned repositories"
  echo ""
fi

if [ "$#" -eq 0 ]; then
  # No arguments provided - use smart defaults
  echo -e "${HIGHLIGHT}No directory specified - using smart detection${NORMAL}\n"
  
  # Always scan current directory first
  update_directory "$PWD"
  echo ""
  
  # Auto-scan system directories
  AUTO_SCAN_SYSTEM=true
else
  # Check if user provided home directory or similar
  AUTO_SCAN_SYSTEM=false
  for arg in "$@"; do
    # Expand ~ to actual home path
    expanded_arg=$(eval echo "$arg")
    
    # If user specified home directory, also scan system dirs
    if [ "$expanded_arg" = "$HOME" ] || [ "$expanded_arg" = "~" ]; then
      AUTO_SCAN_SYSTEM=true
    fi
  done
  
  # Process specified directories first
  for dir in "$@"; do
    update_directory "$dir"
    echo ""
  done
fi

# Auto-scan system directories if enabled
if [ "$AUTO_SCAN_SYSTEM" = true ]; then
  echo -e "${HIGHLIGHT}Auto-detecting system project directories...${NORMAL}"
  
  # Check if common project directories exist and scan them
  SYSTEM_DIRS=("/var" "/opt" "/srv")
  
  DIRS_TO_SCAN=()
  for dir in "${SYSTEM_DIRS[@]}"; do
    if [ -d "$dir" ] && [ -r "$dir" ]; then
      DIRS_TO_SCAN+=("$dir")
    fi
  done
  
  if [ ${#DIRS_TO_SCAN[@]} -eq 0 ]; then
    echo -e "${HIGHLIGHT}→${NORMAL} No system directories found"
    echo ""
  else
    echo -e "${HIGHLIGHT}→${NORMAL} Found system directories: ${DIRS_TO_SCAN[*]}"
    echo ""
    
    for dir in "${DIRS_TO_SCAN[@]}"; do
      echo -e "${HIGHLIGHT}Scanning $dir for repositories...${NORMAL}"
      
      # Check if we're already root
      if [ "$EUID" -eq 0 ]; then
        update_directory "$dir"
      else
        # Not root, need to run this part with sudo
        echo -e "${WARNING}⚠${NORMAL}  System directory requires root privileges"
        echo -e "${HIGHLIGHT}→${NORMAL} Running with sudo for $dir..."
        echo -e "${HIGHLIGHT}→${NORMAL} You may be prompted for your password..."
        sudo -E bash "$0" "$dir"
      fi
      echo ""
    done
  fi
fi

# Get final statistics
REPOS_FOUND=$(get_stat "found")
REPOS_UPDATED=$(get_stat "updated")
REPOS_FAILED=$(get_stat "failed")
REPOS_SKIPPED=$(get_stat "skipped")

echo -e "\n${SUCCESS}========================================${NORMAL}"
echo -e "${SUCCESS}Update Complete!${NORMAL}"
echo -e "${SUCCESS}========================================${NORMAL}\n"

echo -e "${HIGHLIGHT}Summary:${NORMAL}"
echo "  • Git repositories found:      $REPOS_FOUND"
echo "  • Successfully updated:         $REPOS_UPDATED"
echo "  • Failed (permission denied):   $REPOS_FAILED"
echo "  • Skipped (inaccessible):       $REPOS_SKIPPED"
echo "  • Both Husky and native Git hooks are supported"
echo "  • Future commits will be scanned for blockchain private keys and secrets"
echo ""

# Show warning if there were permission failures
if [ "$REPOS_FAILED" -gt 0 ] || [ "$REPOS_SKIPPED" -gt 0 ]; then
  echo -e "${WARNING}⚠${NORMAL}  ${WARNING}WARNING: Some repositories could not be updated due to permission issues${NORMAL}"
  if [ "$EUID" -ne 0 ]; then
    echo -e "${HIGHLIGHT}→${NORMAL} To update system repositories (in /var, /etc, etc.), run with sudo:"
    echo -e "   ${HIGHLIGHT}sudo ./update-all-repos.sh /var${NORMAL}"
  else
    echo -e "${HIGHLIGHT}→${NORMAL} Some repositories may have additional access restrictions"
    echo -e "   Check ownership and permissions of failed repositories"
  fi
  echo ""
fi

echo -e "${HIGHLIGHT}Next time, you can use:${NORMAL}"
echo "  • ${HIGHLIGHT}./update-all-repos.sh --all${NORMAL}  (scans home + /var/systango, auto-handles sudo)"
echo "  • ${HIGHLIGHT}./update-all-repos.sh ~/Projects${NORMAL}  (specific directory)"
echo "  • ${HIGHLIGHT}MAX_DEPTH=3 ./update-all-repos.sh ~${NORMAL}  (limit depth for faster scan)"
echo ""
echo -e "${HIGHLIGHT}Test the hooks:${NORMAL}"
echo "  cd /path/to/any/repo"
echo "  echo 'const key = \"abc\"' > test.js"
echo "  git add test.js"
echo "  git commit -m 'test' # Add a real secret to test blocking"
echo ""
