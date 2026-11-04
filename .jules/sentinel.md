## 2025-05-18 - Parameterize Shell Arguments in Parallel Subshells
**Vulnerability:** Unsafe string interpolation (`{}`) inside `xargs -I {} sh -c '... {} ...'` in parallel execution scripts (`convert.sh` and `install.sh`).
**Learning:** Interpolating xargs placeholders directly into inline shell scripts allows string expansion and possible code execution if input values contain quotes, spaces, or special shell characters.
**Prevention:** Pass placeholders as explicit positional arguments to subshells (`sh -c '... "$2" ...' _ "$VAR" {}`) so that user inputs are treated strictly as data parameters rather than executable script body text.

## 2026-11-04 - Recursion and Unintended Remote Dispatch in Git Push Hooks
**Vulnerability:** Unconditional execution of remote synchronization commands (e.g., `git bug push origin`) inside automated Git hooks (`.githooks/pre-push`).
**Learning:** Hardcoding remotes risks directing bug sync data to unintended targets when pushing to non-origin remotes or forks. Furthermore, executing child git push commands inside `pre-push` hooks without recursion guards can induce infinite hook loops or redundant network traffic.
**Prevention:** In `pre-push` hooks, parameterize the target remote from positional argument `$1` (`"${1:-origin}"`), inspect standard input to detect already queued ref updates (such as `refs/bugs/*`), and guard child push operations with a recursion guard environment variable (`GIT_BUG_PUSHING=1`).
