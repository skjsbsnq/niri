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
DEFAULT_TAHOE_GLASS_ROADMAP_DOC="$TAHOE_SHELL_DIR/docs/liquid-glass-niri-glass-forceblur-roadmap-2026-06-28.md"
ARCHIVED_TAHOE_GLASS_ROADMAP_DOC="$TAHOE_SHELL_DIR/docs/old/liquid-glass-niri-glass-forceblur-roadmap-2026-06-28.md"
TAHOE_GLASS_ROADMAP_DOC="${TAHOE_GLASS_ROADMAP_DOC:-"$DEFAULT_TAHOE_GLASS_ROADMAP_DOC"}"
if [[ "$TAHOE_GLASS_ROADMAP_DOC" == "$DEFAULT_TAHOE_GLASS_ROADMAP_DOC" \
  && ! -f "$TAHOE_GLASS_ROADMAP_DOC" \
  && -f "$ARCHIVED_TAHOE_GLASS_ROADMAP_DOC" ]]; then
  TAHOE_GLASS_ROADMAP_DOC="$ARCHIVED_TAHOE_GLASS_ROADMAP_DOC"
fi
NIRI_TAHOE_GLASS_XML="$REPO_DIR/niri/resources/tahoe-glass-v1.xml"
QUICKSHELL_TAHOE_GLASS_XML="$REPO_DIR/quickshell/src/wayland/tahoe_glass/tahoe-glass-v1.xml"
NIRI_TAHOE_GLASS_PROTOCOL="$REPO_DIR/niri/src/protocols/tahoe_glass.rs"
QUICKSHELL_TAHOE_GLASS_QML="$REPO_DIR/quickshell/src/wayland/tahoe_glass/qml.cpp"

failures=0
panel_count=0
glass_file_count=0
region_count=0

check_tahoe_glass_protocol_invariants() {
  local xml
  local rel

  for xml in "$NIRI_TAHOE_GLASS_XML" "$QUICKSHELL_TAHOE_GLASS_XML"; do
    if [[ ! -f "$xml" ]]; then
      fail "missing TahoeGlass XML: $xml"
      return
    fi
  done

  if cmp -s "$NIRI_TAHOE_GLASS_XML" "$QUICKSHELL_TAHOE_GLASS_XML"; then
    log "TahoeGlass XML files are in sync"
  else
    fail "TahoeGlass XML drift between niri/resources and quickshell/src/wayland/tahoe_glass"
  fi

  for xml in "$NIRI_TAHOE_GLASS_XML" "$QUICKSHELL_TAHOE_GLASS_XML"; do
    rel="$(realpath --relative-to="$REPO_DIR" "$xml")"

    if grep -qE '<interface[[:space:]]+name="tahoe_glass_manager_v1"[[:space:]]+version="1"' "$xml"; then
      log "$rel keeps manager XML version 1"
    else
      fail "$rel must keep tahoe_glass_manager_v1 XML version 1"
    fi

    if grep -qE '<interface[[:space:]]+name="tahoe_glass_surface_v1"[[:space:]]+version="3"' "$xml"; then
      log "$rel keeps surface XML version 3"
    else
      fail "$rel must keep tahoe_glass_surface_v1 XML version 3"
    fi
  done

  if [[ ! -f "$NIRI_TAHOE_GLASS_PROTOCOL" ]]; then
    fail "missing niri TahoeGlass protocol source: $NIRI_TAHOE_GLASS_PROTOCOL"
    return
  fi

  if grep -qE '^[[:space:]]*const[[:space:]]+VERSION:[[:space:]]*u32[[:space:]]*=[[:space:]]*1;' "$NIRI_TAHOE_GLASS_PROTOCOL"; then
    log "niri TahoeGlass manager global VERSION remains 1"
  else
    fail "niri TahoeGlass manager global VERSION must remain 1"
  fi
}

check_tahoe_glass_region_limit_invariants() {
  local naked_qml_limits

  if [[ ! -f "$NIRI_TAHOE_GLASS_PROTOCOL" ]]; then
    fail "missing niri TahoeGlass protocol source: $NIRI_TAHOE_GLASS_PROTOCOL"
    return
  fi

  if grep -qE '^[[:space:]]*pub[[:space:]]+const[[:space:]]+MAX_REGIONS_PER_SURFACE:[[:space:]]*usize[[:space:]]*=[[:space:]]*32;' "$NIRI_TAHOE_GLASS_PROTOCOL"; then
    log "niri TahoeGlass MAX_REGIONS_PER_SURFACE remains 32"
  else
    fail "niri TahoeGlass MAX_REGIONS_PER_SURFACE must remain 32"
  fi

  if [[ ! -f "$QUICKSHELL_TAHOE_GLASS_QML" ]]; then
    fail "missing Quickshell TahoeGlass QML client: $QUICKSHELL_TAHOE_GLASS_QML"
    return
  fi

  if grep -qE 'MaxRegionsPerSurface[[:space:]]*=[[:space:]]*32;' "$QUICKSHELL_TAHOE_GLASS_QML"; then
    log "Quickshell TahoeGlass region limit is centralized"
  else
    fail "Quickshell TahoeGlass client must centralize its region limit as MaxRegionsPerSurface = 32"
  fi

  naked_qml_limits="$(grep -nE '\b32\b' "$QUICKSHELL_TAHOE_GLASS_QML" | grep -vE 'MaxRegionsPerSurface[[:space:]]*=[[:space:]]*32' || true)"
  if [[ -n "$naked_qml_limits" ]]; then
    printf '%s\n' "$naked_qml_limits" >&2
    fail "Quickshell TahoeGlass client must not scatter naked 32 region limits"
  else
    log "Quickshell TahoeGlass client has no scattered naked 32 region limits"
  fi
}

normalize_git_url() {
  local url="$1"
  printf '%s\n' "${url%.git}"
}

check_reference_repo() {
  local name="$1"
  local path="$2"
  local url="$3"
  local commit="$4"
  local actual_commit
  local actual_url

  if [[ ! -f "$TAHOE_GLASS_ROADMAP_DOC" ]]; then
    fail "missing TahoeGlass roadmap doc: $TAHOE_GLASS_ROADMAP_DOC"
    return
  fi

  if grep -Fq "$path" "$TAHOE_GLASS_ROADMAP_DOC" \
    && grep -Fq "$url" "$TAHOE_GLASS_ROADMAP_DOC" \
    && grep -Fq "$commit" "$TAHOE_GLASS_ROADMAP_DOC"; then
    log "$name reference path, URL, and commit are recorded in the roadmap"
  else
    fail "$name reference path, URL, and commit must be recorded in $(realpath --relative-to="$REPO_DIR" "$TAHOE_GLASS_ROADMAP_DOC")"
  fi

  if [[ ! -d "$path/.git" ]]; then
    fail "$name reference repo is missing or is not a git checkout: $path"
    return
  fi

  actual_commit="$(git -C "$path" rev-parse --short HEAD 2>/dev/null || true)"
  if [[ "$actual_commit" == "$commit" ]]; then
    log "$name reference commit matches local checkout ($commit)"
  else
    fail "$name reference commit drift: roadmap=$commit local=${actual_commit:-missing}"
  fi

  actual_url="$(git -C "$path" remote get-url origin 2>/dev/null || true)"
  if [[ "$(normalize_git_url "$actual_url")" == "$(normalize_git_url "$url")" ]]; then
    log "$name reference URL matches local checkout"
  else
    fail "$name reference URL drift: roadmap=$url local=${actual_url:-missing}"
  fi
}

check_tahoe_glass_reference_sources() {
  check_reference_repo \
    "Niri-glass" \
    "/home/wwt/.cache/tahoe-liquid-glass-refs/Niri-glass" \
    "https://github.com/zaroutt/Niri-glass" \
    "e018a31"

  check_reference_repo \
    "kwin-effects-forceblur" \
    "/home/wwt/.cache/tahoe-liquid-glass-refs/kwin-effects-forceblur" \
    "https://github.com/taj-ny/kwin-effects-forceblur" \
    "51a1d49"
}

check_niri_vrr_policy() {
  if [[ ! -f "$NIRI_CONFIG_SRC" ]]; then
    fail "missing niri config: $NIRI_CONFIG_SRC"
    return
  fi

  local enabled
  enabled="$(grep -Ec '^[[:space:]]*variable-refresh-rate[[:space:]]*(//.*)?$' "$NIRI_CONFIG_SRC" || true)"
  if [[ "$enabled" -ne 1 ]]; then
    fail "niri Tahoe config must contain exactly one always-on variable-refresh-rate policy"
  elif grep -nE '^[[:space:]]*variable-refresh-rate[[:space:]]+on-demand=' "$NIRI_CONFIG_SRC"; then
    fail "niri Tahoe config must use the always-on VRR policy, not on-demand"
  else
    log "niri config enables the always-on VRR policy"
  fi
}

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

    if grep -qE 'GlassPanel[[:space:]]*\{' "$file"; then
      if ! grep -qE '^[[:space:]]*material:[[:space:]]*GlassStyle[.]Material' "$file"; then
        fail "$rel uses GlassPanel-backed TahoeGlass.regions without declaring material on the glass panel"
      fi

      if ! grep -qE '^[[:space:]]*radius:[[:space:]]*GlassStyle[.]Radius' "$file"; then
        fail "$rel uses GlassPanel-backed TahoeGlass.regions without declaring radius on the glass panel"
      fi
    else
      if ! grep -q 'tahoeGlassMaterial' "$file"; then
        fail "$rel uses TahoeGlass.regions without declaring tahoeGlassMaterial on the glass item"
      fi

      if ! grep -q 'tahoeGlassRadius' "$file"; then
        fail "$rel uses TahoeGlass.regions without declaring tahoeGlassRadius on the glass item"
      fi
    fi
  done < <(find "$TAHOE_SHELL_DIR" -name '*.qml' -print0)

  log "checked $glass_file_count TahoeGlass.regions files for material/radius declarations"
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
  check_tahoe_glass_protocol_invariants
  check_tahoe_glass_region_limit_invariants
  check_tahoe_glass_reference_sources
  check_niri_vrr_policy
  check_no_broad_quickshell_rule
  check_no_tahoe_background_effect_calls
  check_panel_namespaces
  check_region_blocks_have_material_and_radius
  check_glass_files_declare_material_constants
  check_phase5_popup_region_geometry_static

  if [[ "$failures" -gt 0 ]]; then
    fail "Tahoe glass guardrails found $failures issue(s)"
    exit 1
  fi

  log "Tahoe glass guardrails passed"
}

main "$@"
