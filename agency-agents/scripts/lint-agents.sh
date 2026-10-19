#!/usr/bin/env bash
#
# Validates agent markdown files:
#   1. YAML frontmatter must exist with name, description, color (ERROR)
#   2. Recommended sections checked but only warned (WARN)
#   3. File must have meaningful content
#
# Usage: ./scripts/lint-agents.sh [file ...]
#   If no files given, scans all agent directories.

set -euo pipefail

# Keep in sync with AGENT_DIRS in scripts/convert.sh
AGENT_DIRS=(
  academic
  design
  engineering
  finance
  game-development
  marketing
  paid-media
  product
  project-management
  sales
  spatial-computing
  specialized
  strategy
  support
  testing
)

errors=0
warnings=0

lint_file() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    echo "ERROR $file: not a file or does not exist"
    errors=$((errors + 1))
    return
  fi

  local first_line
  read -r first_line < "$file" || true
  if [[ "$first_line" != "---" ]]; then
    # Non-agent documentation file (e.g., playbooks, strategy guides)
    return
  fi

  local out
  out="$(awk -v file="$file" '
    BEGIN {
      fm = 0
      has_name = 0
      has_desc = 0
      has_color = 0
      has_identity = 0
      has_mission = 0
      has_rules = 0
      words = 0
      soul_headers = 0
      agents_headers = 0
    }
    /^---$/ {
      fm++
      next
    }
    fm == 1 {
      if ($0 ~ /^name:/) has_name = 1
      if ($0 ~ /^description:/) has_desc = 1
      if ($0 ~ /^color:/) has_color = 1
    }
    fm >= 2 {
      words += NF
      low = tolower($0)
      if (low ~ /identity/) has_identity = 1
      if (low ~ /core mission/) has_mission = 1
      if (low ~ /critical rules/) has_rules = 1

      if ($0 ~ /^##[[:space:]]/) {
        if (low ~ /identity/ || low ~ /learning.*memory/ || low ~ /communication/ || low ~ /style/ || low ~ /critical.rule/ || low ~ /rules.you.must.follow/) {
          soul_headers++
        } else {
          agents_headers++
        }
      }
    }
    END {
      if (fm < 2) {
        print "ERR:empty or malformed frontmatter"
        exit
      }
      if (!has_name) print "ERR:missing frontmatter field \x27name\x27"
      if (!has_desc) print "ERR:missing frontmatter field \x27description\x27"
      if (!has_color) print "ERR:missing frontmatter field \x27color\x27"

      if (!has_identity) print "WARN:missing recommended section \x27Identity\x27"
      if (!has_mission) print "WARN:missing recommended section \x27Core Mission\x27"
      if (!has_rules) print "WARN:missing recommended section \x27Critical Rules\x27"

      if (words < 50) print "WARN:body seems very short (< 50 words)"
      if (soul_headers == 0) print "WARN:no section headers map to SOUL.md in convert.sh"
      if (agents_headers == 0) print "WARN:no section headers map to AGENTS.md in convert.sh"
    }
  ' "$file")"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if [[ "$line" == ERR:* ]]; then
      echo "ERROR $file: ${line#ERR:}"
      errors=$((errors + 1))
    elif [[ "$line" == WARN:* ]]; then
      echo "WARN  $file: ${line#WARN:}"
      warnings=$((warnings + 1))
    fi
  done <<< "$out"
}

# Collect files to lint
files=()
if [[ $# -gt 0 ]]; then
  files=("$@")
else
  for dir in "${AGENT_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
      while IFS= read -r f; do
        files+=("$f")
      done < <(find "$dir" -name "*.md" -type f | sort)
    fi
  done
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No agent files found."
  exit 1
fi

echo "Linting ${#files[@]} agent files..."
echo ""

for file in "${files[@]}"; do
  lint_file "$file"
done

echo ""
echo "Results: ${errors} error(s), ${warnings} warning(s) in ${#files[@]} files."

if [[ $errors -gt 0 ]]; then
  echo "FAILED: fix the errors above before merging."
  exit 1
else
  echo "PASSED"
  exit 0
fi
