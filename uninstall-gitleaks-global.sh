#!/bin/bash

# Script to uninstall global gitleaks configuration and hooks

HIGHLIGHT="\e[01;34m"
SUCCESS="\e[01;32m"
ERROR="\e[01;31m"
NORMAL='\e[00m'

echo -e "${HIGHLIGHT}Uninstalling Gitleaks global configuration...${NORMAL}\n"

# Remove config directory
CONFIG_DIR="$HOME/.config/gitleaks"
if [ -d "$CONFIG_DIR" ]; then
    rm -rf "$CONFIG_DIR"
    echo -e "${SUCCESS}✓${NORMAL} Removed $CONFIG_DIR"
else
    echo -e "${ERROR}✗${NORMAL} Config directory not found: $CONFIG_DIR"
fi

# Remove git template directory
TEMPLATE_DIR="$HOME/.git-template"
if [ -d "$TEMPLATE_DIR" ]; then
    rm -rf "$TEMPLATE_DIR"
    echo -e "${SUCCESS}✓${NORMAL} Removed $TEMPLATE_DIR"
    
    # Unset git config
    git config --global --unset init.templateDir
    echo -e "${SUCCESS}✓${NORMAL} Unset global git template directory"
else
    echo -e "${ERROR}✗${NORMAL} Template directory not found: $TEMPLATE_DIR"
fi

echo -e "\n${SUCCESS}Uninstallation complete!${NORMAL}"
echo -e "\n${HIGHLIGHT}Note:${NORMAL} Existing repositories still have the hooks installed."
echo "To remove hooks from individual repos, delete the files:"
echo "  • .git/hooks/pre-commit"
echo "  • .git/hooks/commit-msg"
