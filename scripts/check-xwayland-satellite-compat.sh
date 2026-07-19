#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-"$(cd -- "$SCRIPT_DIR/.." && pwd)"}"
TAHOE_CACHE_DIR="${TAHOE_CACHE_DIR:-"${XDG_CACHE_HOME:-"$HOME/.cache"}/tahoe-niri"}"
TAHOE_STATE_DIR="${TAHOE_STATE_DIR:-"${XDG_STATE_HOME:-"$HOME/.local/state"}/tahoe-niri"}"
NIRI_CONFIG_TARGET="${NIRI_CONFIG_TARGET:-"$HOME/.config/niri/tahoe/config.kdl"}"
XWAYLAND_SATELLITE_REPO_URL="${XWAYLAND_SATELLITE_REPO_URL:-https://github.com/Supreeeme/xwayland-satellite.git}"
XWAYLAND_SATELLITE_REF="${XWAYLAND_SATELLITE_REF:-v0.8.1}"
XWAYLAND_SATELLITE_PATCH="${XWAYLAND_SATELLITE_PATCH:-"$REPO_DIR/patches/xwayland-satellite-minimize.patch"}"
XWAYLAND_SATELLITE_UPSTREAM_DIR="${XWAYLAND_SATELLITE_UPSTREAM_DIR:-"$TAHOE_CACHE_DIR/xwayland-satellite/upstream"}"
XWAYLAND_SATELLITE_BIN="${XWAYLAND_SATELLITE_BIN:-"$HOME/.local/lib/niri/xwayland-satellite-minimize"}"
XWAYLAND_SATELLITE_GLAMOR_WRAPPER="${XWAYLAND_SATELLITE_GLAMOR_WRAPPER:-"$XWAYLAND_SATELLITE_BIN-glamor"}"
XWAYLAND_SATELLITE_BUILD_STAMP="${XWAYLAND_SATELLITE_BUILD_STAMP:-"$TAHOE_STATE_DIR/xwayland-satellite-minimize.stamp"}"

STRICT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --status)
      ;;
    --strict)
      STRICT=true
      ;;
    -h|--help)
      cat <<'EOF'
Usage: check-xwayland-satellite-compat.sh [--status] [--strict]

Checks Tahoe's patched xwayland-satellite compatibility path and prints
STATUS|id|state|title|detail|impact|action lines for the Tahoe health page.

States used by this check:
  ok       path, regression anchors, and behavior-tested build are current
  missing  required path is absent
  stale    installed build/config/runtime does not match the expected ref/patch
  broken   installed path exists but fails validation

--strict exits non-zero for static missing/stale/broken failures. Runtime
process mismatch is reported as stale but does not fail strict mode because a
newly deployed satellite is not used until niri/X11 clients restart.
EOF
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

strict_failed=false

field() {
  printf '%s' "$*" | sed 's/[|]/ /g; s/[\r\n]/ /g'
}

emit_status() {
  printf 'STATUS|%s|%s|%s|%s|%s|%s\n' \
    "$(field "$1")" "$(field "$2")" "$(field "$3")" \
    "$(field "$4")" "$(field "$5")" "$(field "$6")"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

join_reasons() {
  local IFS='；'
  printf '%s' "$*"
}

sha256_file() {
  if have sha256sum; then
    sha256sum "$1" 2>/dev/null | sed 's/[[:space:]].*$//'
  else
    printf 'sha256sum-unavailable'
  fi
}

stamp_value() {
  local key="$1"
  [[ -r "$XWAYLAND_SATELLITE_BUILD_STAMP" ]] || return 0
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$XWAYLAND_SATELLITE_BUILD_STAMP"
}

resolve_ref() {
  local ref="$1"
  local commit=""

  [[ -d "$XWAYLAND_SATELLITE_UPSTREAM_DIR/.git" ]] || return 1

  if commit="$(git -C "$XWAYLAND_SATELLITE_UPSTREAM_DIR" rev-parse --verify -q "origin/$ref^{commit}" 2>/dev/null)"; then
    printf '%s\n' "$commit"
    return 0
  fi

  if commit="$(git -C "$XWAYLAND_SATELLITE_UPSTREAM_DIR" rev-parse --verify -q "$ref^{commit}" 2>/dev/null)"; then
    printf '%s\n' "$commit"
    return 0
  fi

  return 1
}

canonical_path() {
  if have realpath; then
    realpath -m "$1" 2>/dev/null || printf '%s\n' "$1"
  elif have readlink; then
    readlink -f "$1" 2>/dev/null || printf '%s\n' "$1"
  else
    printf '%s\n' "$1"
  fi
}

contains_all() {
  local file="$1"
  shift

  local pattern
  for pattern in "$@"; do
    grep -Fq "$pattern" "$file" || return 1
  done
  return 0
}

append_missing_patterns() {
  local file="$1"
  local -n out_ref="$2"
  shift 2

  local pattern
  for pattern in "$@"; do
    if ! grep -Fq "$pattern" "$file"; then
      out_ref+=("$pattern")
    fi
  done
}

check_regressions() {
  local patch_sha="$1"
  local state="ok"
  local detail=""
  local impact="X11 最大化、最小化和 X11/Wayland 剪贴板桥接补丁锚点存在"
  local action=""
  local missing_maximize=()
  local missing_minimize=()
  local missing_clipboard=()

  if [[ ! -f "$XWAYLAND_SATELLITE_PATCH" ]]; then
    emit_status xwayland_regression missing 'XWayland 回归检查' "缺少 patch：$XWAYLAND_SATELLITE_PATCH" '无法确认 maximize、minimize 和 clipboard bridge 补丁内容' '恢复 patches/xwayland-satellite-minimize.patch'
    strict_failed=true
    return
  fi

  append_missing_patterns "$XWAYLAND_SATELLITE_PATCH" missing_maximize \
    'set_maximized' \
    'set_net_wm_state' \
    '_NET_WM_ALLOWED_ACTIONS' \
    '_NET_WM_STATE_MAXIMIZED_HORZ' \
    '_NET_WM_STATE_MAXIMIZED_VERT' \
    'wm_action_maximize_horz' \
    'wm_action_maximize_vert' \
    'xdg_toplevel::Request::SetMaximized' \
    'xdg_toplevel::Request::UnsetMaximized' \
    'xdg_toplevel::State::Maximized' \
    'SetState::Toggle' \
    'fn maximize' \
    'fn client_maximize' \
    'fn initial_maximize'
  append_missing_patterns "$XWAYLAND_SATELLITE_PATCH" missing_minimize \
    'set_minimized' \
    'WM_CHANGE_STATE' \
    'wm_action_minimize' \
    'xdg_toplevel::Request::SetMinimized' \
    'fn minimize'
  append_missing_patterns "$XWAYLAND_SATELLITE_PATCH" missing_clipboard \
    'UTF8_STRING' \
    'text/plain;charset=utf-8' \
    'ForeignSelection' \
    'ExtDataControlManagerV1' \
    'SelectionBackend::ExtDataControl' \
    'copy_from_x11_without_x11_focus' \
    'x11_utf8_string_bridges_wayland_text_mimes' \
    'wayland_offer_waits_for_x11_source_cancellation'

  if [[ ${#missing_maximize[@]} -gt 0 || ${#missing_minimize[@]} -gt 0 || ${#missing_clipboard[@]} -gt 0 ]]; then
    state="broken"
    detail="patch sha $patch_sha；缺 maximize 锚点：$(join_reasons "${missing_maximize[@]:-无}")；缺 minimize 锚点：$(join_reasons "${missing_minimize[@]:-无}")；缺 clipboard 锚点：$(join_reasons "${missing_clipboard[@]:-无}")"
    impact="更新后可能重新丢失 X11 maximize、minimize 或剪贴板桥接能力"
    action="更新 $XWAYLAND_SATELLITE_PATCH，并重新运行 arch-update.sh"
    strict_failed=true
  else
    detail="patch sha $patch_sha；maximize、minimize 与 clipboard bridge 锚点完整"
  fi

  emit_status xwayland_regression "$state" 'XWayland 回归检查' "$detail" "$impact" "$action"
}

check_xwayland_path() {
  local patch_sha="$1"
  local expected_commit=""
  local stamp_repo=""
  local stamp_ref=""
  local stamp_commit=""
  local stamp_patch_sha=""
  local stamp_patch_applied=""
  local stamp_behavior_tests=""
  local wrapper_home_path=""
  local runtime_pids=""
  local runtime_note=""
  local runtime_stale=false
  local state="ok"
  local detail=""
  local impact="X11 应用兼容路径、maximize/minimize patch 和 clipboard bridge 构建记录可诊断"
  local action=""
  local missing=()
  local stale=()
  local broken=()

  if [[ ! -f "$XWAYLAND_SATELLITE_PATCH" ]]; then
    missing+=("patch 不存在")
  elif [[ ! -r "$XWAYLAND_SATELLITE_PATCH" ]]; then
    broken+=("patch 不可读")
  fi

  if [[ ! -e "$XWAYLAND_SATELLITE_BIN" ]]; then
    missing+=("patched binary 不存在")
  elif [[ ! -x "$XWAYLAND_SATELLITE_BIN" ]]; then
    broken+=("patched binary 不可执行")
  elif have timeout; then
    if ! timeout 3s "$XWAYLAND_SATELLITE_BIN" ":0" --test-listenfd-support >/dev/null 2>&1; then
      broken+=("patched binary --test-listenfd-support 失败")
    fi
  elif ! "$XWAYLAND_SATELLITE_BIN" ":0" --test-listenfd-support >/dev/null 2>&1; then
    broken+=("patched binary --test-listenfd-support 失败")
  fi

  if [[ ! -e "$XWAYLAND_SATELLITE_GLAMOR_WRAPPER" ]]; then
    missing+=("glamor wrapper 不存在")
  elif [[ ! -x "$XWAYLAND_SATELLITE_GLAMOR_WRAPPER" ]]; then
    broken+=("glamor wrapper 不可执行")
  else
    grep -Fq "$XWAYLAND_SATELLITE_BIN" "$XWAYLAND_SATELLITE_GLAMOR_WRAPPER" \
      || broken+=("glamor wrapper 未指向 patched binary")
    grep -Fq -- '-glamor gl' "$XWAYLAND_SATELLITE_GLAMOR_WRAPPER" \
      || broken+=("glamor wrapper 未强制 -glamor gl")
  fi

  if [[ ! -r "$XWAYLAND_SATELLITE_BUILD_STAMP" ]]; then
    stale+=("缺少 build stamp")
  else
    stamp_repo="$(stamp_value repo)"
    stamp_ref="$(stamp_value ref)"
    stamp_commit="$(stamp_value commit)"
    stamp_patch_sha="$(stamp_value patch_sha256)"
    stamp_patch_applied="$(stamp_value patch_applied)"
    stamp_behavior_tests="$(stamp_value behavior_tests)"

    [[ "$stamp_repo" == "$XWAYLAND_SATELLITE_REPO_URL" ]] \
      || stale+=("stamp repo=$stamp_repo，期望 $XWAYLAND_SATELLITE_REPO_URL")
    [[ "$stamp_ref" == "$XWAYLAND_SATELLITE_REF" ]] \
      || stale+=("stamp ref=$stamp_ref，期望 $XWAYLAND_SATELLITE_REF")
    [[ "$stamp_patch_sha" == "$patch_sha" ]] \
      || stale+=("stamp patch_sha=$stamp_patch_sha，当前 $patch_sha")
    [[ "$stamp_behavior_tests" == passed ]] \
      || stale+=("behavior tests=${stamp_behavior_tests:-未记录}，期望 passed")

    if expected_commit="$(resolve_ref "$XWAYLAND_SATELLITE_REF")"; then
      [[ "$stamp_commit" == "$expected_commit" ]] \
        || stale+=("stamp commit=${stamp_commit:-空}，期望 $expected_commit")
    elif [[ -z "$stamp_commit" ]]; then
      stale+=("stamp 缺少 commit，且本地 upstream cache 无法解析 ref")
    fi
  fi

  wrapper_home_path="${XWAYLAND_SATELLITE_GLAMOR_WRAPPER/#"$HOME"/\~}"
  if [[ ! -r "$NIRI_CONFIG_TARGET" ]]; then
    stale+=("Tahoe niri config 不可读")
  elif ! grep -Fq "$XWAYLAND_SATELLITE_GLAMOR_WRAPPER" "$NIRI_CONFIG_TARGET" \
    && ! grep -Fq "$wrapper_home_path" "$NIRI_CONFIG_TARGET"; then
    stale+=("niri config 未指向 glamor wrapper")
  fi

  # Linux truncates /proc/PID/comm to 15 bytes, so the running process is
  # normally named "xwayland-satell" even though the executable is longer.
  runtime_pids="$({
    pgrep -x xwayland-satellite 2>/dev/null || true
    pgrep -x xwayland-satell 2>/dev/null || true
  } | sort -nu | paste -sd, -)"
  if [[ -n "$runtime_pids" ]]; then
    local expected_bin
    local pid
    local exe
    local matched=false
    expected_bin="$(canonical_path "$XWAYLAND_SATELLITE_BIN")"
    IFS=, read -r -a pid_values <<< "$runtime_pids"
    for pid in "${pid_values[@]}"; do
      [[ -n "$pid" ]] || continue
      exe="$(canonical_path "/proc/$pid/exe")"
      if [[ "$exe" == "$expected_bin" ]]; then
        matched=true
      fi
    done

    if [[ "$matched" == true ]]; then
      runtime_note="运行中 pid=$runtime_pids"
    else
      runtime_note="运行中 pid=$runtime_pids，但不是 Tahoe patched binary；重启 niri 后应切换"
      runtime_stale=true
    fi
  else
    runtime_note="未检测到运行中进程；X11 app 或 niri 重启后按配置启动"
  fi

  if [[ ${#broken[@]} -gt 0 ]]; then
    state="broken"
    detail="$(join_reasons "${broken[@]}")"
    impact="X11 app 可能无法启动、无法最大化/最小化或 GLX/剪贴板降级"
    action="重新运行 FORCE_XWAYLAND_SATELLITE_BUILD=true bash scripts/arch-update.sh"
    strict_failed=true
  elif [[ ${#missing[@]} -gt 0 ]]; then
    state="missing"
    detail="$(join_reasons "${missing[@]}")"
    impact="Tahoe XWayland 兼容路径缺失，X11 app 可能无法正常显示、最大化或最小化"
    action="运行 BUILD_XWAYLAND_SATELLITE=auto bash scripts/arch-update.sh"
    strict_failed=true
  elif [[ ${#stale[@]} -gt 0 || "$runtime_stale" == true ]]; then
    state="stale"
    detail="$(join_reasons "${stale[@]}")"
    if [[ -z "$detail" ]]; then
      detail="$runtime_note"
    else
      detail="$detail；$runtime_note"
    fi
    impact="当前安装或运行状态与 Tahoe 期望 patch/ref/wrapper 不一致"
    action="运行 arch-update.sh；若刚更新过，重启 niri 或重新打开 X11 app"
    [[ ${#stale[@]} -eq 0 ]] || strict_failed=true
  else
    detail="ref $XWAYLAND_SATELLITE_REF；patch sha $patch_sha；patch_applied=${stamp_patch_applied:-unknown}；behavior_tests=${stamp_behavior_tests:-unknown}；wrapper $XWAYLAND_SATELLITE_GLAMOR_WRAPPER；$runtime_note"
  fi

  emit_status xwayland "$state" 'XWayland patched path' "$detail" "$impact" "$action"
}

main() {
  local patch_sha="missing"

  if [[ -r "$XWAYLAND_SATELLITE_PATCH" ]]; then
    patch_sha="$(sha256_file "$XWAYLAND_SATELLITE_PATCH")"
  fi

  check_xwayland_path "$patch_sha"
  check_regressions "$patch_sha"

  if [[ "$STRICT" == true && "$strict_failed" == true ]]; then
    exit 1
  fi
}

main "$@"
