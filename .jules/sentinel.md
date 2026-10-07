## 2025-05-18 - Parameterize Shell Arguments in Parallel Subshells
**Vulnerability:** Unsafe string interpolation (`{}`) inside `xargs -I {} sh -c '... {} ...'` in parallel execution scripts (`convert.sh` and `install.sh`).
**Learning:** Interpolating xargs placeholders directly into inline shell scripts allows string expansion and possible code execution if input values contain quotes, spaces, or special shell characters.
**Prevention:** Pass placeholders as explicit positional arguments to subshells (`sh -c '... "$2" ...' _ "$VAR" {}`) so that user inputs are treated strictly as data parameters rather than executable script body text.
