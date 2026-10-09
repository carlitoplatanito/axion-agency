## 2025-05-18 - Avoid `pointer-events: none` on Disabled Buttons
**Learning:** Using `pointer-events: none` on disabled UI components prevents hover tooltips and `cursor: not-allowed` feedback, harming accessibility and user clarity regarding why an element is disabled.
**Action:** Remove `pointer-events: none` from disabled button component styles and rely on `aria-disabled` or disabled attributes with `cursor: not-allowed`.
