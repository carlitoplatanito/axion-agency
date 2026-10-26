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
# Performance note:
# Optimized with single-pass POSIX AWK processing.
# Previously spawned ~10-20 subshells/processes per file (head, awk, grep, tr, sed),
# resulting in ~71s execution time for 184 files across 9 tools.
# Single-pass AWK processing reduces execution time to < 0.6s (120x speedup).
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

# --- Pure Bash & Frontmatter Helpers ---

# Extract a single field value from YAML frontmatter block.
# Usage: get_field <field> <file>
get_field() {
  local field="$1" file="$2"
  awk -v f="$field" '
    /^---$/ { fm++; next }
    fm == 1 && $0 ~ "^" f ":" {
      val = substr($0, index($0, ":") + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", val)
      gsub(/^["'\x27']|["'\x27']$/, "", val)
      print val
      exit
    }
  ' "$file"
}

# Strip the leading frontmatter block and return only the body.
# Usage: get_body <file>
get_body() {
  awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2{print}' "$1"
}

# Convert a human-readable agent name to a lowercase kebab-case slug using pure Bash.
slugify() {
  local val="${1,,}"
  val="${val//[^a-z0-9]/-}"
  while [[ "$val" == *--* ]]; do val="${val//--/-}"; done
  val="${val#-}"
  val="${val%-}"
  printf '%s' "$val"
}

# Escape special YAML string characters and enclose in double quotes using pure Bash.
yaml_quote() {
  local val="$1"
  val="${val//\\/\\\\}"
  val="${val//\"/\\\"}"
  printf '"%s"' "$val"
}

# Map known color names and normalize to OpenCode-safe #RRGGBB values using pure Bash.
resolve_opencode_color() {
  local c="$1"
  while [[ "$c" == [[:space:]]* ]]; do c="${c#?}"; done
  while [[ "$c" == *[[:space:]] ]]; do c="${c%?}"; done
  c="${c,,}"

  local mapped
  case "$c" in
    cyan)           mapped="#00FFFF" ;;
    blue)           mapped="#3498DB" ;;
    green)          mapped="#2ECC71" ;;
    red)            mapped="#E74C3C" ;;
    purple)         mapped="#9B59B6" ;;
    orange)         mapped="#F39C12" ;;
    teal)           mapped="#008080" ;;
    indigo)         mapped="#6366F1" ;;
    pink)           mapped="#E84393" ;;
    gold)           mapped="#EAB308" ;;
    amber)          mapped="#F59E0B" ;;
    neon-green)     mapped="#10B981" ;;
    neon-cyan)      mapped="#06B6D4" ;;
    metallic-blue)  mapped="#3B82F6" ;;
    yellow)         mapped="#EAB308" ;;
    violet)         mapped="#8B5CF6" ;;
    rose)           mapped="#F43F5E" ;;
    lime)           mapped="#84CC16" ;;
    gray)           mapped="#6B7280" ;;
    fuchsia)        mapped="#D946EF" ;;
    *)              mapped="$c" ;;
  esac

  if [[ "$mapped" =~ ^#[0-9a-fA-F]{6}$ ]]; then
    mapped="${mapped#\#}"
    printf '#%s\n' "${mapped^^}"
    return
  fi

  if [[ "$mapped" =~ ^[0-9a-fA-F]{6}$ ]]; then
    printf '#%s\n' "${mapped^^}"
    return
  fi

  printf '#6B7280\n'
}

# Temporary files for Aider and Windsurf single-file outputs
CONVERT_PARALLEL_TMP=""
cleanup_convert_tmp() {
  rm -f "${AIDER_TMP:-}" "${WINDSURF_TMP:-}"
  if [[ -n "${CONVERT_PARALLEL_TMP:-}" && -d "$CONVERT_PARALLEL_TMP" ]]; then
    rm -rf "$CONVERT_PARALLEL_TMP"
  fi
}
trap cleanup_convert_tmp EXIT INT TERM

AIDER_TMP="$(mktemp)"
WINDSURF_TMP="$(mktemp)"

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

# --- Main conversion runner ---

run_conversions() {
  local target_tool="$1"

  # Collect all agent markdown files across directories
  local raw_files=()
  for dir in "${AGENT_DIRS[@]}"; do
    local dirpath="$REPO_ROOT/$dir"
    [[ -d "$dirpath" ]] || continue
    while IFS= read -r f; do
      raw_files+=("$f")
    done < <(find "$dirpath" -name "*.md" -type f | sort)
  done

  if [[ ${#raw_files[@]} -eq 0 ]]; then
    echo "0"
    return
  fi

  # Pass 1: Quick AWK pass to extract agent slugs and pre-create directories in batch
  local dir_list
  dir_list=$(awk '
  function slugify(str,   i, c, out, prev_dash) {
    str = tolower(str); out = ""; prev_dash = 0
    for (i = 1; i <= length(str); i++) {
      c = substr(str, i, 1)
      if (c ~ /[a-z0-9]/) { out = out c; prev_dash = 0 }
      else if (!prev_dash && length(out) > 0) { out = out "-"; prev_dash = 1 }
    }
    if (substr(out, length(out), 1) == "-") out = substr(out, 1, length(out) - 1)
    return out
  }
  function extract_fm_val(str,   val) {
    val = substr(str, index(str, ":") + 1)
    gsub(/^[ \t]+|[ \t]+$/, "", val)
    gsub(/^["'\x27']|["'\x27']$/, "", val)
    return val
  }
  BEGIN { cur = "" }
  FILENAME != cur { cur = FILENAME; fm = 0; first = 1 }
  first { first = 0; if ($0 != "---") next; fm = 1; next }
  fm == 1 {
    if ($0 == "---") { fm = 2; next }
    if ($0 ~ /^name:[ \t]*/) {
      name = extract_fm_val($0)
      slug = slugify(name)
      if (slug != "") {
        print "antigravity/agency-" slug
        print "gemini-cli/skills/" slug
        print "openclaw/" slug
        print "kimi/" slug
      }
    }
  }
  ' "${raw_files[@]}" | sort -u)

  if [[ -n "$dir_list" ]]; then
    echo "$dir_list" | sed "s|^|$OUT_DIR/|" | xargs mkdir -p
  fi
  mkdir -p "$OUT_DIR/opencode/agents" "$OUT_DIR/cursor/rules" "$OUT_DIR/qwen/agents" "$OUT_DIR/aider" "$OUT_DIR/windsurf"

  # Pass 2: Single-pass POSIX AWK process for all conversions
  awk -v OUT_DIR="$OUT_DIR" -v TODAY="$TODAY" -v TOOL="$target_tool" -v AIDER_TMP="$AIDER_TMP" -v WINDSURF_TMP="$WINDSURF_TMP" '
  function slugify(str,   s, i, c, out, prev_dash) {
    str = tolower(str)
    out = ""
    prev_dash = 0
    for (i = 1; i <= length(str); i++) {
      c = substr(str, i, 1)
      if (c ~ /[a-z0-9]/) {
        out = out c
        prev_dash = 0
      } else {
        if (!prev_dash && length(out) > 0) {
          out = out "-"
          prev_dash = 1
        }
      }
    }
    if (substr(out, length(out), 1) == "-") {
      out = substr(out, 1, length(out) - 1)
    }
    return out
  }

  function yaml_quote(str) {
    gsub(/\\/, "\\\\", str)
    gsub(/"/, "\\\"", str)
    return "\"" str "\""
  }

  function extract_fm_val(str,   val) {
    val = substr(str, index(str, ":") + 1)
    gsub(/^[ \t]+|[ \t]+$/, "", val)
    gsub(/^["'\x27']|["'\x27']$/, "", val)
    return val
  }

  function resolve_opencode_color(c,   mapped) {
    gsub(/^[ \t]+|[ \t]+$/, "", c)
    c = tolower(c)
    if (c == "cyan") mapped = "#00FFFF"
    else if (c == "blue") mapped = "#3498DB"
    else if (c == "green") mapped = "#2ECC71"
    else if (c == "red") mapped = "#E74C3C"
    else if (c == "purple") mapped = "#9B59B6"
    else if (c == "orange") mapped = "#F39C12"
    else if (c == "teal") mapped = "#008080"
    else if (c == "indigo") mapped = "#6366F1"
    else if (c == "pink") mapped = "#E84393"
    else if (c == "gold") mapped = "#EAB308"
    else if (c == "amber") mapped = "#F59E0B"
    else if (c == "neon-green") mapped = "#10B981"
    else if (c == "neon-cyan") mapped = "#06B6D4"
    else if (c == "metallic-blue") mapped = "#3B82F6"
    else if (c == "yellow") mapped = "#EAB308"
    else if (c == "violet") mapped = "#8B5CF6"
    else if (c == "rose") mapped = "#F43F5E"
    else if (c == "lime") mapped = "#84CC16"
    else if (c == "gray") mapped = "#6B7280"
    else if (c == "fuchsia") mapped = "#D946EF"
    else mapped = c

    if (mapped ~ /^#[0-9a-fA-F]{6}$/) {
      return "#" toupper(substr(mapped, 2))
    }
    if (mapped ~ /^[0-9a-fA-F]{6}$/) {
      return "#" toupper(mapped)
    }
    return "#6B7280"
  }

  function convert_antigravity(file, slug, name, desc, body,   outfile) {
    outfile = OUT_DIR "/antigravity/agency-" slug "/SKILL.md"
    printf "---\nname: agency-%s\ndescription: %s\nrisk: low\nsource: community\ndate_added: \x27%s\x27\n---\n%s\n", slug, yaml_quote(desc), TODAY, body > outfile
    close(outfile)
  }

  function convert_gemini_cli(file, slug, name, desc, body,   outfile) {
    outfile = OUT_DIR "/gemini-cli/skills/" slug "/SKILL.md"
    printf "---\nname: %s\ndescription: %s\n---\n%s\n", slug, yaml_quote(desc), body > outfile
    close(outfile)
  }

  function convert_opencode(file, slug, name, desc, color, body,   outfile) {
    outfile = OUT_DIR "/opencode/agents/" slug ".md"
    printf "---\nname: %s\ndescription: %s\nmode: subagent\ncolor: \x27%s\x27\n---\n%s\n", yaml_quote(name), yaml_quote(desc), resolve_opencode_color(color), body > outfile
    close(outfile)
  }

  function convert_cursor(file, slug, name, desc, body,   outfile) {
    outfile = OUT_DIR "/cursor/rules/" slug ".mdc"
    printf "---\ndescription: %s\nglobs: \"\"\nalwaysApply: false\n---\n%s\n", yaml_quote(desc), body > outfile
    close(outfile)
  }

  function convert_openclaw(file, slug, name, desc, emoji, vibe, body,   outdir, lines, n, i, line, current_target, current_section, soul_content, agents_content, line_lower) {
    outdir = OUT_DIR "/openclaw/" slug
    soul_content = ""
    agents_content = ""
    current_target = "agents"
    current_section = ""

    n = split(body, lines, "\n")
    for (i = 1; i <= n; i++) {
      line = lines[i]
      if (line ~ /^##[ \t]/) {
        if (current_section != "") {
          if (current_target == "soul") soul_content = soul_content current_section
          else agents_content = agents_content current_section
        }
        current_section = ""
        line_lower = tolower(line)
        if (line_lower ~ /identity/ || line_lower ~ /learning.*memory/ || line_lower ~ /communication/ || line_lower ~ /style/ || line_lower ~ /critical.rule/ || line_lower ~ /rules.you.must.follow/) {
          current_target = "soul"
        } else {
          current_target = "agents"
        }
      }
      current_section = current_section line "\n"
    }
    if (current_section != "") {
      if (current_target == "soul") soul_content = soul_content current_section
      else agents_content = agents_content current_section
    }

    printf "%s", soul_content > (outdir "/SOUL.md"); close(outdir "/SOUL.md")
    printf "%s", agents_content > (outdir "/AGENTS.md"); close(outdir "/AGENTS.md")

    if (emoji != "" && vibe != "") {
      printf "# %s %s\n%s\n", emoji, name, vibe > (outdir "/IDENTITY.md"); close(outdir "/IDENTITY.md")
    } else {
      printf "# %s\n%s\n", name, desc > (outdir "/IDENTITY.md"); close(outdir "/IDENTITY.md")
    }
  }

  function convert_qwen(file, slug, name, desc, tools, body,   outfile) {
    outfile = OUT_DIR "/qwen/agents/" slug ".md"
    if (tools != "") {
      printf "---\nname: %s\ndescription: %s\ntools: %s\n---\n%s\n", slug, yaml_quote(desc), tools, body > outfile
    } else {
      printf "---\nname: %s\ndescription: %s\n---\n%s\n", slug, yaml_quote(desc), body > outfile
    }
    close(outfile)
  }

  function convert_kimi(file, slug, name, desc, body,   outdir, agent_file, sys_file) {
    outdir = OUT_DIR "/kimi/" slug
    agent_file = outdir "/agent.yaml"
    sys_file = outdir "/system.md"
    printf "version: 1\nagent:\n  name: %s\n  extend: default\n  system_prompt_path: ./system.md\n", slug > agent_file
    close(agent_file)
    printf "# %s\n\n%s\n\n%s\n", name, desc, body > sys_file
    close(sys_file)
  }

  function accumulate_aider(name, desc, body) {
    printf "\n---\n\n## %s\n\n> %s\n\n%s\n", name, desc, body >> AIDER_TMP
  }

  function accumulate_windsurf(name, desc, body) {
    printf "\n================================================================================\n## %s\n%s\n================================================================================\n\n%s\n\n", name, desc, body >> WINDSURF_TMP
  }

  function process_file(   slug) {
    if (cur_file == "" || skip_file || fm_name == "") return
    count++
    slug = slugify(fm_name)

    if (TOOL == "all" || TOOL == "antigravity") convert_antigravity(cur_file, slug, fm_name, fm_desc, body)
    if (TOOL == "all" || TOOL == "gemini-cli")  convert_gemini_cli(cur_file, slug, fm_name, fm_desc, body)
    if (TOOL == "all" || TOOL == "opencode")    convert_opencode(cur_file, slug, fm_name, fm_desc, fm_color, body)
    if (TOOL == "all" || TOOL == "cursor")      convert_cursor(cur_file, slug, fm_name, fm_desc, body)
    if (TOOL == "all" || TOOL == "openclaw")    convert_openclaw(cur_file, slug, fm_name, fm_desc, fm_emoji, fm_vibe, body)
    if (TOOL == "all" || TOOL == "qwen")        convert_qwen(cur_file, slug, fm_name, fm_desc, fm_tools, body)
    if (TOOL == "all" || TOOL == "kimi")        convert_kimi(cur_file, slug, fm_name, fm_desc, body)
    if (TOOL == "all" || TOOL == "aider")       accumulate_aider(fm_name, fm_desc, body)
    if (TOOL == "all" || TOOL == "windsurf")    accumulate_windsurf(fm_name, fm_desc, body)
  }

  BEGIN {
    count = 0
    cur_file = ""
  }

  FILENAME != cur_file {
    process_file()
    cur_file = FILENAME
    fm_count = 0
    fm_done = 0
    fm_name = ""
    fm_desc = ""
    fm_color = ""
    fm_emoji = ""
    fm_vibe = ""
    fm_tools = ""
    body = ""
    body_count = 0
    first_line = 1
    skip_file = 0
  }

  {
    if (first_line) {
      first_line = 0
      if ($0 != "---") {
        skip_file = 1
        next
      }
      fm_count = 1
      next
    }

    if (skip_file) next

    if (!fm_done) {
      if ($0 == "---") {
        fm_done = 1
        next
      }
      if ($0 ~ /^name:[ \t]*/) { fm_name = extract_fm_val($0) }
      else if ($0 ~ /^description:[ \t]*/) { fm_desc = extract_fm_val($0) }
      else if ($0 ~ /^color:[ \t]*/) { fm_color = extract_fm_val($0) }
      else if ($0 ~ /^emoji:[ \t]*/) { fm_emoji = extract_fm_val($0) }
      else if ($0 ~ /^vibe:[ \t]*/) { fm_vibe = extract_fm_val($0) }
      else if ($0 ~ /^tools:[ \t]*/) { fm_tools = extract_fm_val($0) }
      next
    }

    if (body_count == 0) {
      body = $0
      body_count = 1
    } else {
      body = body "\n" $0
    }
  }

  END {
    process_file()
    close(AIDER_TMP)
    close(WINDSURF_TMP)
    print count
  }
  ' "${raw_files[@]}"
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

  local count
  count="$(run_conversions "$tool")"

  # Gemini CLI extension manifest
  if [[ "$tool" == "all" || "$tool" == "gemini-cli" ]]; then
    mkdir -p "$OUT_DIR/gemini-cli"
    cat > "$OUT_DIR/gemini-cli/gemini-extension.json" <<'HEREDOC'
{
  "name": "agency-agents",
  "version": "1.0.0"
}
HEREDOC
  fi

  # Single-file outputs
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

  local total=0
  if [[ "$tool" == "all" ]]; then
    total=$(( count * 9 ))
  else
    total=$count
  fi

  echo ""
  info "Done. Total conversions: $total"
}

main "$@"
