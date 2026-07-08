# Branding assets

Project icons for the Better Macro Icons CurseForge page. **Not shipped in the
addon** — `assets/` is excluded from the release zip and from release-change
detection by addon-ci.

- `icon.png` — detailed 3×3 layout (1024×1024).
- `icon-compact.png` — bolder 2×2 layout that stays legible shrunk to a small
  avatar; **this is the one to upload to CurseForge**.

Both are reproducible from `make_bmi_icon.py` in the private `roshne/Tooling`
repo (pure PIL/numpy, byte-for-byte stable):

    python make_bmi_icon.py --out <repo>/assets/icon.png             # 3×3
    python make_bmi_icon.py --compact --out <repo>/assets/icon-compact.png  # 2×2
