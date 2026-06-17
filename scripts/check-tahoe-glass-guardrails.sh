#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[tahoe-glass-guardrails] %s\n' "$*"
}

fail() {
  printf '[tahoe-glass-guardrails] FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-"$(cd -- "$SCRIPT_DIR/.." && pwd)"}"
TAHOE_SHELL_DIR="${TAHOE_SHELL_DIR:-"$REPO_DIR/tahoe-shell"}"
NIRI_CONFIG_SRC="${NIRI_CONFIG_SRC:-"$REPO_DIR/config/niri/tahoe-phase0.kdl"}"

failures=0
panel_count=0
glass_file_count=0
region_count=0

check_no_broad_quickshell_rule() {
  if [[ ! -f "$NIRI_CONFIG_SRC" ]]; then
    fail "missing niri config: $NIRI_CONFIG_SRC"
    return
  fi

  if grep -nE 'namespace[[:space:]]*=[[:space:]]*"\^quickshell"' "$NIRI_CONFIG_SRC"; then
    fail "niri config must not contain a broad namespace=\"^quickshell\" glass/shadow rule"
  else
    log "niri config has no broad namespace=\"^quickshell\" rule"
  fi

  if grep -qE 'match[[:space:]]+namespace[[:space:]]*=[[:space:]]*"\^tahoe-' "$NIRI_CONFIG_SRC"; then
    log "niri config keeps explicit Tahoe namespace rules"
  else
    fail "niri config does not contain explicit Tahoe namespace rules"
  fi
}

check_no_tahoe_background_effect_calls() {
  local matches
  matches="$(grep -RInE '\bBackgroundEffect\b|\bblurRegion\b' \
    "$TAHOE_SHELL_DIR/components" "$TAHOE_SHELL_DIR/shell.qml" 2>/dev/null || true)"

  if [[ -n "$matches" ]]; then
    printf '%s\n' "$matches" >&2
    fail "Tahoe QML must not call BackgroundEffect or blurRegion directly; use TahoeGlass.regions"
  else
    log "Tahoe QML has no direct BackgroundEffect/blurRegion usage"
  fi
}

check_panel_namespaces() {
  local file

  while IFS= read -r -d '' file; do
    if ! grep -qE 'PanelWindow[[:space:]]*\{' "$file"; then
      continue
    fi

    panel_count=$((panel_count + 1))

    if grep -qE 'WlrLayershell[.]namespace:[[:space:]]*"quickshell"' "$file"; then
      fail "$(realpath --relative-to="$REPO_DIR" "$file") sets the default quickshell namespace"
      continue
    fi

    if ! grep -qE 'WlrLayershell[.]namespace:[[:space:]]*"tahoe-[A-Za-z0-9-]+"' "$file"; then
      fail "$(realpath --relative-to="$REPO_DIR" "$file") contains PanelWindow without a tahoe-* WlrLayershell.namespace"
    fi
  done < <(find "$TAHOE_SHELL_DIR" -name '*.qml' -print0)

  log "checked $panel_count PanelWindow namespace declarations"
}

check_region_blocks_have_material_and_radius() {
  local file
  local rel

  while IFS= read -r -d '' file; do
    if ! grep -q 'TahoeGlassRegion' "$file"; then
      continue
    fi

    rel="$(realpath --relative-to="$REPO_DIR" "$file")"
    region_count=$((region_count + $(grep -c 'TahoeGlassRegion' "$file")))

    if ! awk '
      /TahoeGlassRegion[[:space:]]*\{/ {
        inside = 1
        start = FNR
        material = 0
        radius = 0
        material_alpha = 0
        next
      }
      inside && /material[[:space:]]*:/ { material = 1 }
      inside && /radius[[:space:]]*:/ { radius = 1 }
      inside && /materialAlpha[[:space:]]*:/ { material_alpha = 1 }
      inside && /}/ {
        if (!material || !radius || !material_alpha) {
          printf "%s:%d missing%s%s%s\n", FILENAME, start, material ? "" : " material", radius ? "" : " radius", material_alpha ? "" : " materialAlpha"
          bad = 1
        }
        inside = 0
      }
      END { exit bad ? 1 : 0 }
    ' "$file"; then
      fail "$rel has TahoeGlassRegion blocks without material/radius/materialAlpha"
    fi
  done < <(find "$TAHOE_SHELL_DIR" -name '*.qml' -print0)

  log "checked $region_count TahoeGlassRegion declarations"
}

check_glass_files_declare_material_constants() {
  local file
  local rel

  while IFS= read -r -d '' file; do
    if ! grep -q 'TahoeGlass[.]regions' "$file"; then
      continue
    fi

    glass_file_count=$((glass_file_count + 1))
    rel="$(realpath --relative-to="$REPO_DIR" "$file")"

    if ! grep -q 'tahoeGlassMaterial' "$file"; then
      fail "$rel uses TahoeGlass.regions without declaring tahoeGlassMaterial on the glass item"
    fi

    if ! grep -q 'tahoeGlassRadius' "$file"; then
      fail "$rel uses TahoeGlass.regions without declaring tahoeGlassRadius on the glass item"
    fi
  done < <(find "$TAHOE_SHELL_DIR" -name '*.qml' -print0)

  log "checked $glass_file_count TahoeGlass.regions files for material/radius item properties"
}

check_phase5_popup_region_geometry_static() {
  local rel
  local file
  local popups=(
    components/ControlCenter.qml
    components/MenuPopup.qml
    components/BatteryPopup.qml
    components/NotificationCenter.qml
    components/TrayMenu.qml
  )

  for rel in "${popups[@]}"; do
    file="$TAHOE_SHELL_DIR/$rel"
    [[ -f "$file" ]] || continue

    if grep -nE '^[[:space:]]*y:[[:space:]]*root[.]open[[:space:]]*[?]|^[[:space:]]*Behavior[[:space:]]+on[[:space:]]+y[[:space:]]*\{' "$file"; then
      fail "tahoe-shell/$rel animates popup glass-region y; Phase 5 keeps popup region bounds stable"
    fi
  done

  log "checked Phase 5 popup glass-region geometry animations"
}

main() {
  check_no_broad_quickshell_rule
  check_no_tahoe_background_effect_calls
  check_panel_namespaces
  check_region_blocks_have_material_and_radius
  check_glass_files_declare_material_constants
  check_phase5_popup_region_geometry_static

  if [[ "$failures" -gt 0 ]]; then
    fail "Phase 7 guardrails found $failures issue(s)"
    exit 1
  fi

  log "Phase 7 guardrails passed"
}

main "$@"
