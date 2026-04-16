#!/usr/bin/env bash
# find.sh - Interactive Terraform file explorer

set -euo pipefail

# -------------------------------
# Colors
# -------------------------------
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
NC="\033[0m"

# -------------------------------
# FUNCTIONS
# -------------------------------

# List all tf and tfvars files (just filenames)
list_all_tf_tfvars_files() {
  echo -e "${CYAN}🔹 Listing all Terraform files (*.tf & *.tfvars)${NC}"
  echo
  mapfile -t files < <(find . -type f \( -name "*.tf" -o -name "*.tfvars" \) | sort)
  if [[ ${#files[@]} -eq 0 ]]; then
    echo -e "${RED}❌ No Terraform files found.${NC}"
    return
  fi

  for f in "${files[@]}"; do
    echo -e "${YELLOW}$f${NC}"
  done
  echo
}

# Preview a single file
preview_a_file() {
  read -rp "Enter file path to preview: " file
  if [[ ! -f "$file" ]]; then
    echo -e "${RED}❌ File not found: $file${NC}"
    return
  fi
  echo -e "${GREEN}----- Start of $file -----${NC}"
  cat "$file"
  echo -e "${GREEN}----- End of $file -----${NC}"
}

# Preview all tf and tfvars files
preview_all_tf_tfvars_files() {
  mapfile -t files < <(find . -type f \( -name "*.tf" -o -name "*.tfvars" \) | sort)
  if [[ ${#files[@]} -eq 0 ]]; then
    echo -e "${RED}❌ No Terraform files found.${NC}"
    return
  fi

  for f in "${files[@]}"; do
    echo -e "${YELLOW}==================== $f ====================${NC}"
    cat "$f"
    echo
  done
}

# Preview all tf and tfvars files in a supplied directory
preview_dir_tf_tfvars_files() {
  read -rp "Enter directory path: " dir
  if [[ ! -d "$dir" ]]; then
    echo -e "${RED}❌ Directory not found: $dir${NC}"
    return
  fi

  mapfile -t files < <(find "$dir" -type f \( -name "*.tf" -o -name "*.tfvars" \) | sort)
  if [[ ${#files[@]} -eq 0 ]]; then
    echo -e "${RED}❌ No Terraform files found in $dir${NC}"
    return
  fi

  for f in "${files[@]}"; do
    echo -e "${YELLOW}==================== $f ====================${NC}"
    cat "$f"
    echo
  done
}

# -------------------------------
# MENU
# -------------------------------

show_menu() {
  echo "----------------------------------------"
  echo "Terraform File Explorer - $(pwd)"
  echo "1) List all tf & tfvars files"
  echo "2) Preview a single file"
  echo "3) Preview all tf & tfvars files"
  echo "4) Preview all tf & tfvars files in a directory"
  echo "0) Exit"
  echo "----------------------------------------"
}

interactive_mode() {
  while true; do
    show_menu
    read -rp "Choose an option: " choice
    case "$choice" in
      1) list_all_tf_tfvars_files ;;
      2) preview_a_file ;;
      3) preview_all_tf_tfvars_files ;;
      4) preview_dir_tf_tfvars_files ;;
      0) echo "Exiting."; exit 0 ;;
      *) echo -e "${RED}Invalid choice${NC}" ;;
    esac
    echo
  done
}

# -------------------------------
# MAIN
# -------------------------------
interactive_mode
