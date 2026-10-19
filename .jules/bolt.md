## 2026-10-19 - Avoid process-spawning loops in shell scripts

**Learning:** Shell scripts iterating over hundreds of files with per-iteration subshell spawns (e.g. `head`, `grep`, `wc`, `awk`, `tr`, `sed`) incur severe process creation overhead (~10-20ms per subshell), resulting in 70s+ runtimes for conversion scripts. Combining frontmatter extraction and conversion/linting into a single `awk` process per file (or single pass over files) reduced script runtime from 70s to ~15s (and linting from 21s to 1s).
**Action:** Always prefer single-pass file processing or `awk`/pure Bash string operations over launching subshell pipelines inside loops in shell scripts.
