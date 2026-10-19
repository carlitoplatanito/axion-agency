#!/usr/bin/env bash
#
# convert.sh — Convert agency agent .md files into tool-specific formats.
#
# Reads all agent files from the standard category directories and outputs
# converted files to integrations/<tool>/. Run this to regenerate all
# integration files after adding or modifying agents.
#
# Usage:
#   ./scripts/convert.sh [--tool <name>] [--out <dir>] [--parallel] [--jobs N] [--help]
#
# Tools:
#   antigravity  — Antigravity skill files (~/.gemini/antigravity/skills/)
#   gemini-cli   — Gemini CLI extension (skills/ + gemini-extension.json)
#   opencode     — OpenCode agent files (.opencode/agents/*.md)
#   cursor       — Cursor rule files (.cursor/rules/*.mdc)
#   aider        — Single CONVENTIONS.md for Aider
#   windsurf     — Single .windsurfrules for Windsurf
#   openclaw     — OpenClaw workspaces (integrations/openclaw/<agent>/SOUL.md)
#   qwen         — Qwen Code SubAgent files (~/.qwen/agents/*.md)
#   kimi         — Kimi Code CLI agent files (~/.config/kimi/agents/)
#   all          — All tools (default)
#
# Output is written to integrations/<tool>/ relative to the repo root.
# This script never touches user config dirs — see install.sh for that.
#
#   --parallel       When tool is 'all', run independent tools in parallel (output order may vary).
#   --jobs N         Max parallel jobs when using --parallel (default: nproc or 4).

set -euo pipefail

# --- Colour helpers ---
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
  GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[0;31m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; BOLD=''; RESET=''
fi

info()    { printf "${GREEN}[OK]${RESET}  %s\n" "$*"; }
warn()    { printf "${YELLOW}[!!]${RESET}  %s\n" "$*"; }
error()   { printf "${RED}[ERR]${RESET} %s\n" "$*" >&2; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

# Progress bar: [=======>    ] 3/8 (tqdm-style)
progress_bar() {
  local current="$1" total="$2" width="${3:-20}" i filled empty
  (( total > 0 )) || return
  filled=$(( width * current / total ))
  empty=$(( width - filled ))
  printf "\r  ["
  for (( i=0; i<filled; i++ )); do printf "="; done
  if (( filled < width )); then printf ">"; (( empty-- )); fi
  for (( i=0; i<empty; i++ )); do printf " "; done
  printf "] %s/%s" "$current" "$total"
  [[ -t 1 ]] || printf "\n"
}

# --- Paths & Common Helpers ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$REPO_ROOT/integrations"
TODAY="$(date +%Y-%m-%d)"

# Source shared helper functions
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

AGENT_DIRS=(
  academic design engineering finance game-development marketing paid-media product project-management
  sales spatial-computing specialized strategy support testing
)

# --- Usage ---
usage() {
  sed -n '3,26p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# --- Frontmatter helpers ---

# Convert a human-readable agent name to a lowercase kebab-case slug.
# "Frontend Developer" → "frontend-developer"
# Performance optimized: single tr + sed pipeline instead of 5 chained subshells.
slugify() {
  local s
  s="$(tr '[:upper:]' '[:lower:]' <<< "$1")"
  sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g' <<< "$s"
}

# Parse all agent frontmatter fields and body in a single pass using awk.
# Output is null-delimited to preserve special characters and multiline body strings.
parse_agent_file() {
  local file="$1"
  NAME="" DESC="" COLOR="" TOOLS="" EMOJI="" VIBE="" BODY="" SLUG=""

  local first_line
  read -r first_line < "$file" || true
  [[ "$first_line" == "---" ]] || return 1

  local res=0
  {
    IFS= read -r -d '' NAME && \
    IFS= read -r -d '' DESC && \
    IFS= read -r -d '' COLOR && \
    IFS= read -r -d '' TOOLS && \
    IFS= read -r -d '' EMOJI && \
    IFS= read -r -d '' VIBE && \
    IFS= read -r -d '' BODY
  } < <(awk '
    BEGIN { fm = 0; body = ""; body_started = 0 }
    /^---$/ { fm++; next }
    fm == 1 {
      if ($0 ~ /^name:[[:space:]]*/) { name = $0; sub(/^name:[[:space:]]*/, "", name) }
      else if ($0 ~ /^description:[[:space:]]*/) { desc = $0; sub(/^description:[[:space:]]*/, "", desc) }
      else if ($0 ~ /^color:[[:space:]]*/) { color = $0; sub(/^color:[[:space:]]*/, "", color) }
      else if ($0 ~ /^tools:[[:space:]]*/) { tools = $0; sub(/^tools:[[:space:]]*/, "", tools) }
      else if ($0 ~ /^emoji:[[:space:]]*/) { emoji = $0; sub(/^emoji:[[:space:]]*/, "", emoji) }
      else if ($0 ~ /^vibe:[[:space:]]*/) { vibe = $0; sub(/^vibe:[[:space:]]*/, "", vibe) }
    }
    fm >= 2 {
      if (body_started) body = body "\n" $0; else { body = $0; body_started = 1 }
    }
    END {
      if (name != "") {
        printf "%s\0%s\0%s\0%s\0%s\0%s\0%s\0", name, desc, color, tools, emoji, vibe, body
      }
    }
  ' "$file") || res=$?

  [[ -n "$NAME" ]] || return 1
  SLUG="$(slugify "$NAME")"
}

# --- Per-tool converters ---

convert_antigravity() {
  local outdir="$OUT_DIR/antigravity/agency-$SLUG"
  mkdir -p "$outdir"

  cat > "$outdir/SKILL.md" <<HEREDOC
---
name: agency-${SLUG}
description: ${DESC}
risk: low
source: community
date_added: '${TODAY}'
---
${BODY}
HEREDOC
}

convert_gemini_cli() {
  local outdir="$OUT_DIR/gemini-cli/skills/$SLUG"
  mkdir -p "$outdir"

  cat > "$outdir/SKILL.md" <<HEREDOC
---
name: ${SLUG}
description: ${DESC}
---
${BODY}
HEREDOC
}

# Map known color names and normalize to OpenCode-safe #RRGGBB values.
resolve_opencode_color() {
  local c="$1"
  c="${c#"${c%%[![:space:]]*}"}"
  c="${c%"${c##*[![:space:]]}"}"

  local mapped
  case "$c" in
    cyan|CYAN)                    mapped="#00FFFF" ;;
    blue|BLUE)                    mapped="#3498DB" ;;
    green|GREEN)                  mapped="#2ECC71" ;;
    red|RED)                      mapped="#E74C3C" ;;
    purple|PURPLE)                mapped="#9B59B6" ;;
    orange|ORANGE)                mapped="#F39C12" ;;
    teal|TEAL)                    mapped="#008080" ;;
    indigo|INDIGO)                mapped="#6366F1" ;;
    pink|PINK)                    mapped="#E84393" ;;
    gold|GOLD)                    mapped="#EAB308" ;;
    amber|AMBER)                  mapped="#F59E0B" ;;
    neon-green|NEON-GREEN)        mapped="#10B981" ;;
    neon-cyan|NEON-CYAN)          mapped="#06B6D4" ;;
    metallic-blue|METALLIC-BLUE)  mapped="#3B82F6" ;;
    yellow|YELLOW)                mapped="#EAB308" ;;
    violet|VIOLET)                mapped="#8B5CF6" ;;
    rose|ROSE)                    mapped="#F43F5E" ;;
    lime|LIME)                    mapped="#84CC16" ;;
    gray|GRAY)                    mapped="#6B7280" ;;
    fuchsia|FUCHSIA)              mapped="#D946EF" ;;
    *)                            mapped="$c" ;;
  esac

  if [[ "$mapped" =~ ^#[0-9a-fA-F]{6}$ ]]; then
    local hex="${mapped#\#}"
    printf '#%s\n' "$(tr '[:lower:]' '[:upper:]' <<< "$hex")"
    return
  fi

  if [[ "$mapped" =~ ^[0-9a-fA-F]{6}$ ]]; then
    printf '#%s\n' "$(tr '[:lower:]' '[:upper:]' <<< "$mapped")"
    return
  fi

  printf '#6B7280\n'
}

convert_opencode() {
  local color; color="$(resolve_opencode_color "$COLOR")"
  local outfile="$OUT_DIR/opencode/agents/${SLUG}.md"
  mkdir -p "$OUT_DIR/opencode/agents"

  cat > "$outfile" <<HEREDOC
---
name: ${NAME}
description: ${DESC}
mode: subagent
color: '${color}'
---
${BODY}
HEREDOC
}

convert_cursor() {
  local outfile="$OUT_DIR/cursor/rules/${SLUG}.mdc"
  mkdir -p "$OUT_DIR/cursor/rules"

  cat > "$outfile" <<HEREDOC
---
description: ${DESC}
globs: ""
alwaysApply: false
---
${BODY}
HEREDOC
}

convert_openclaw() {
  local outdir="$OUT_DIR/openclaw/$SLUG"
  mkdir -p "$outdir"
  local soul_file="$outdir/SOUL.md"
  local agents_file="$outdir/AGENTS.md"

  # Single-pass awk splitting for SOUL.md vs AGENTS.md (avoids thousands of line-by-line bash subshells).
  awk -v soul_file="$soul_file" -v agents_file="$agents_file" '
    BEGIN { target = "agents" }
    /^##[[:space:]]/ {
      h = tolower($0)
      if (h ~ /identity/ || h ~ /learning.*memory/ || h ~ /communication/ || h ~ /style/ || h ~ /critical.rule/ || h ~ /rules.you.must.follow/) {
        target = "soul"
      } else {
        target = "agents"
      }
    }
    {
      if (target == "soul") {
        print $0 > soul_file
      } else {
        print $0 > agents_file
      }
    }
  ' <<< "$BODY"

  touch "$soul_file" "$agents_file"

  if [[ -n "$EMOJI" && -n "$VIBE" ]]; then
    cat > "$outdir/IDENTITY.md" <<HEREDOC
# ${EMOJI} ${NAME}
${VIBE}
HEREDOC
  else
    cat > "$outdir/IDENTITY.md" <<HEREDOC
# ${NAME}
${DESC}
HEREDOC
  fi
}

convert_qwen() {
  local outfile="$OUT_DIR/qwen/agents/${SLUG}.md"
  mkdir -p "$(dirname "$outfile")"

  if [[ -n "$TOOLS" ]]; then
    cat > "$outfile" <<HEREDOC
---
name: ${SLUG}
description: ${DESC}
tools: ${TOOLS}
---
${BODY}
HEREDOC
  else
    cat > "$outfile" <<HEREDOC
---
name: ${SLUG}
description: ${DESC}
---
${BODY}
HEREDOC
  fi
}

convert_kimi() {
  local outdir="$OUT_DIR/kimi/$SLUG"
  mkdir -p "$outdir"

  cat > "$outdir/agent.yaml" <<HEREDOC
version: 1
agent:
  name: ${SLUG}
  extend: default
  system_prompt_path: ./system.md
HEREDOC

  cat > "$outdir/system.md" <<HEREDOC
# ${NAME}

${DESC}

${BODY}
HEREDOC
}

# Aider and Windsurf are single-file formats — accumulate into temp files
# then write at the end.
AIDER_TMP="$(mktemp)"
WINDSURF_TMP="$(mktemp)"
trap 'rm -f "$AIDER_TMP" "$WINDSURF_TMP"' EXIT

# Write Aider/Windsurf headers once
cat > "$AIDER_TMP" <<'HEREDOC'
# The Agency — AI Agent Conventions
#
# This file provides Aider with the full roster of specialized AI agents from
# The Agency (https://github.com/msitarzewski/agency-agents).
#
# To activate an agent, reference it by name in your Aider session prompt, e.g.:
#   "Use the Frontend Developer agent to review this component."
#
# Generated by scripts/convert.sh — do not edit manually.

HEREDOC

cat > "$WINDSURF_TMP" <<'HEREDOC'
# The Agency — AI Agent Rules for Windsurf
#
# Full roster of specialized AI agents from The Agency.
# To activate an agent, reference it by name in your Windsurf conversation.
#
# Generated by scripts/convert.sh — do not edit manually.

HEREDOC

accumulate_aider() {
  cat >> "$AIDER_TMP" <<HEREDOC

---

## ${NAME}

> ${DESC}

${BODY}
HEREDOC
}

accumulate_windsurf() {
  cat >> "$WINDSURF_TMP" <<HEREDOC

================================================================================
## ${NAME}
${DESC}
================================================================================

${BODY}

HEREDOC
}

# --- Main loop ---

run_conversions() {
  local tool="$1"
  local count=0

  for dir in "${AGENT_DIRS[@]}"; do
    local dirpath="$REPO_ROOT/$dir"
    [[ -d "$dirpath" ]] || continue

    local files=()
    while IFS= read -r -d '' file || [[ -n "$file" ]]; do
      files+=("$file")
    done < <(find "$dirpath" -name "*.md" -type f -print0 | sort -z)

    for file in "${files[@]}"; do
      parse_agent_file "$file" || continue

      case "$tool" in
        antigravity) convert_antigravity ;;
        gemini-cli)  convert_gemini_cli  ;;
        opencode)    convert_opencode    ;;
        cursor)      convert_cursor      ;;
        openclaw)    convert_openclaw    ;;
        qwen)        convert_qwen        ;;
        kimi)        convert_kimi        ;;
        aider)       accumulate_aider    ;;
        windsurf)    accumulate_windsurf ;;
        all)
          convert_antigravity
          convert_gemini_cli
          convert_opencode
          convert_cursor
          convert_openclaw
          convert_qwen
          convert_kimi
          accumulate_aider
          accumulate_windsurf
          ;;
      esac

      (( count += 1 ))
    done
  done

  echo "$count"
}

# --- Entry point ---

main() {
  local tool="all"
  local use_parallel=false
  local parallel_jobs
  parallel_jobs="$(parallel_jobs_default)"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tool)     tool="${2:?'--tool requires a value'}"; shift 2 ;;
      --out)      OUT_DIR="${2:?'--out requires a value'}"; shift 2 ;;
      --parallel) use_parallel=true; shift ;;
      --jobs)     parallel_jobs="${2:?'--jobs requires a value'}"; shift 2 ;;
      --help|-h)  usage ;;
      *)          error "Unknown option: $1"; usage ;;
    esac
  done

  local valid_tools=("antigravity" "gemini-cli" "opencode" "cursor" "aider" "windsurf" "openclaw" "qwen" "kimi" "all")
  local valid=false
  for t in "${valid_tools[@]}"; do [[ "$t" == "$tool" ]] && valid=true && break; done
  if ! $valid; then
    error "Unknown tool '$tool'. Valid: ${valid_tools[*]}"
    exit 1
  fi

  header "The Agency -- Converting agents to tool-specific formats"
  echo "  Repo:   $REPO_ROOT"
  echo "  Output: $OUT_DIR"
  echo "  Tool:   $tool"
  echo "  Date:   $TODAY"
  if $use_parallel && [[ "$tool" == "all" ]]; then
    info "Parallel mode: output buffered so each tool's output stays together."
  fi

  local tools_to_run=()
  if [[ "$tool" == "all" ]]; then
    tools_to_run=("antigravity" "gemini-cli" "opencode" "cursor" "aider" "windsurf" "openclaw" "qwen" "kimi")
  else
    tools_to_run=("$tool")
  fi

  local total=0

  local n_tools=${#tools_to_run[@]}

  if $use_parallel && [[ "$tool" == "all" ]]; then
    # Tools that write to separate dirs can run in parallel; buffer output so each tool's output stays together
    local parallel_tools=(antigravity gemini-cli opencode cursor openclaw qwen)
    local parallel_out_dir
    parallel_out_dir="$(mktemp -d)"
    info "Converting: ${#parallel_tools[@]}/${n_tools} tools in parallel (output buffered per tool)..."
    export AGENCY_CONVERT_OUT_DIR="$parallel_out_dir"
    export AGENCY_CONVERT_SCRIPT="$SCRIPT_DIR/convert.sh"
    export AGENCY_CONVERT_OUT="$OUT_DIR"
    printf '%s\n' "${parallel_tools[@]}" | xargs -P "$parallel_jobs" -I {} sh -c '"$1" --tool "$2" --out "$3" > "$4/$2" 2>&1' _ "$AGENCY_CONVERT_SCRIPT" {} "$AGENCY_CONVERT_OUT" "$AGENCY_CONVERT_OUT_DIR"
    for t in "${parallel_tools[@]}"; do
      [[ -f "$parallel_out_dir/$t" ]] && cat "$parallel_out_dir/$t"
    done
    rm -rf "$parallel_out_dir"
    local idx=7
    for t in aider windsurf; do
      progress_bar "$idx" "$n_tools"
      printf "\n"
      header "Converting: $t ($idx/$n_tools)"
      local count
      count="$(run_conversions "$t")"
      total=$(( total + count ))
      info "Converted $count agents for $t"
      (( idx += 1 ))
    done
  elif [[ "$tool" == "all" ]]; then
    header "Converting: all tools in single pass"
    local count
    count="$(run_conversions "all")"
    mkdir -p "$OUT_DIR/gemini-cli"
    cat > "$OUT_DIR/gemini-cli/gemini-extension.json" <<'HEREDOC'
{
  "name": "agency-agents",
  "version": "1.0.0"
}
HEREDOC
    info "Wrote gemini-extension.json"
    total=$(( count * n_tools ))
    info "Converted $count agents for $n_tools tools"
  else
    local i=0
    for t in "${tools_to_run[@]}"; do
      (( i += 1 ))
      progress_bar "$i" "$n_tools"
      printf "\n"
      header "Converting: $t ($i/$n_tools)"
      local count
      count="$(run_conversions "$t")"
      total=$(( total + count ))

      # Gemini CLI also needs the extension manifest (written by this process when --tool gemini-cli)
      if [[ "$t" == "gemini-cli" ]]; then
        mkdir -p "$OUT_DIR/gemini-cli"
        cat > "$OUT_DIR/gemini-cli/gemini-extension.json" <<'HEREDOC'
{
  "name": "agency-agents",
  "version": "1.0.0"
}
HEREDOC
        info "Wrote gemini-extension.json"
      fi

      info "Converted $count agents for $t"
    done
  fi

  # Write single-file outputs after accumulation
  if [[ "$tool" == "all" || "$tool" == "aider" ]]; then
    mkdir -p "$OUT_DIR/aider"
    cp "$AIDER_TMP" "$OUT_DIR/aider/CONVENTIONS.md"
    info "Wrote integrations/aider/CONVENTIONS.md"
  fi
  if [[ "$tool" == "all" || "$tool" == "windsurf" ]]; then
    mkdir -p "$OUT_DIR/windsurf"
    cp "$WINDSURF_TMP" "$OUT_DIR/windsurf/.windsurfrules"
    info "Wrote integrations/windsurf/.windsurfrules"
  fi

  echo ""
  if $use_parallel && [[ "$tool" == "all" ]]; then
    info "Done. $n_tools tools (parallel; total conversions not aggregated)."
  else
    info "Done. Total conversions: $total"
  fi
}

main "$@"
