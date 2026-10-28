## 2026-10-28 - Sanitize File Paths Passed to Awk in Shell Scripts
**Vulnerability:** Passing raw file paths directly as positional arguments to `awk` (`awk ... "$file"`).
**Learning:** `awk` interprets positional arguments containing `=` as variable assignments (e.g. `var=val`) and leading `-` as options rather than file paths, causing file processing failures or unexpected behavior if file paths contain `=` or `-`.
**Prevention:** Use input redirection (`< "$file"`) when reading a single file or prepend `./` to relative paths (`./"$file"`) when passing file lists to `awk`.

## 2025-05-18 - Parameterize Shell Arguments in Parallel Subshells
**Vulnerability:** Unsafe string interpolation (`{}`) inside `xargs -I {} sh -c '... {} ...'` in parallel execution scripts (`convert.sh` and `install.sh`).
**Learning:** Interpolating xargs placeholders directly into inline shell scripts allows string expansion and possible code execution if input values contain quotes, spaces, or special shell characters.
**Prevention:** Pass placeholders as explicit positional arguments to subshells (`sh -c '... "$2" ...' _ "$VAR" {}`) so that user inputs are treated strictly as data parameters rather than executable script body text.
