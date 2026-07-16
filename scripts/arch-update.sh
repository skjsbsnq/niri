#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[arch-update] %s\n' "$*"
}

die() {
  printf '[arch-update] ERROR: %s\n' "$*" >&2
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-"$(cd -- "$SCRIPT_DIR/.." && pwd)"}"
NIRI_DIR="${NIRI_DIR:-"$REPO_DIR/niri"}"
QUICKSHELL_DIR="${QUICKSHELL_DIR:-"$REPO_DIR/quickshell"}"
TAHOE_SHELL_DIR="${TAHOE_SHELL_DIR:-"$REPO_DIR/tahoe-shell"}"
NIRI_CONFIG_SRC="${NIRI_CONFIG_SRC:-"$REPO_DIR/config/niri/tahoe-phase0.kdl"}"

INSTALL_PREFIX="${INSTALL_PREFIX:-"$HOME/.local"}"
TAHOE_CACHE_DIR="${TAHOE_CACHE_DIR:-"${XDG_CACHE_HOME:-"$HOME/.cache"}/tahoe-niri"}"
TAHOE_STATE_DIR="${TAHOE_STATE_DIR:-"${XDG_STATE_HOME:-"$HOME/.local/state"}/tahoe-niri"}"
NIRI_BIN_DIR="${NIRI_BIN_DIR:-"$INSTALL_PREFIX/bin"}"
NIRI_BIN_NAME="${NIRI_BIN_NAME:-niri}"
QUICKSHELL_BUILD_DIR="${QUICKSHELL_BUILD_DIR:-"$QUICKSHELL_DIR/build-tahoe"}"
QUICKSHELL_BUILD_STAMP="${QUICKSHELL_BUILD_STAMP:-"$QUICKSHELL_BUILD_DIR/.tahoe-installed-commit"}"
QUICKSHELL_BIN_DIR="${QUICKSHELL_BIN_DIR:-"$INSTALL_PREFIX/bin"}"
QUICKSHELL_BIN_NAME="${QUICKSHELL_BIN_NAME:-quickshell}"
TAHOE_CONFIG_DIR="${TAHOE_CONFIG_DIR:-"$HOME/.config/quickshell/tahoe"}"
NIRI_CONFIG_DIR="${NIRI_CONFIG_DIR:-"$HOME/.config/niri/tahoe"}"
NIRI_CONFIG_TARGET="${NIRI_CONFIG_TARGET:-"$NIRI_CONFIG_DIR/config.kdl"}"
NIRI_CONFIG_DEPLOY_BASELINE="${NIRI_CONFIG_DEPLOY_BASELINE:-"$TAHOE_STATE_DIR/niri-config-deployed-baseline.kdl"}"
TAHOE_SESSION_LAUNCHER_SRC="${TAHOE_SESSION_LAUNCHER_SRC:-"$REPO_DIR/scripts/tahoe-niri-session.sh"}"
TAHOE_SESSION_BIN="${TAHOE_SESSION_BIN:-"$NIRI_BIN_DIR/tahoe-niri-session"}"
TAHOE_SYSTEM_SESSION_BIN="${TAHOE_SYSTEM_SESSION_BIN:-/usr/local/bin/tahoe-niri-session}"
TAHOE_SESSION_DESKTOP_DIR="${TAHOE_SESSION_DESKTOP_DIR:-"$HOME/.local/share/wayland-sessions"}"
TAHOE_SESSION_DESKTOP_TARGET="${TAHOE_SESSION_DESKTOP_TARGET:-"$TAHOE_SESSION_DESKTOP_DIR/tahoe-niri.desktop"}"
TAHOE_SYSTEM_SESSION_DESKTOP_DIR="${TAHOE_SYSTEM_SESSION_DESKTOP_DIR:-/usr/share/wayland-sessions}"
TAHOE_SYSTEM_SESSION_DESKTOP_TARGET="${TAHOE_SYSTEM_SESSION_DESKTOP_TARGET:-"$TAHOE_SYSTEM_SESSION_DESKTOP_DIR/tahoe-niri.desktop"}"
TAHOE_XSESSION_DESKTOP_DIR="${TAHOE_XSESSION_DESKTOP_DIR:-/usr/share/xsessions}"
TAHOE_XSESSION_DESKTOP_TARGET="${TAHOE_XSESSION_DESKTOP_TARGET:-"$TAHOE_XSESSION_DESKTOP_DIR/tahoe-niri.desktop"}"
DEPLOY_TAHOE_SESSION_ENTRY="${DEPLOY_TAHOE_SESSION_ENTRY:-true}"
DEPLOY_TAHOE_SYSTEM_SESSION_ENTRY="${DEPLOY_TAHOE_SYSTEM_SESSION_ENTRY:-true}"
DEPLOY_TAHOE_XSESSION_ENTRY="${DEPLOY_TAHOE_XSESSION_ENTRY:-false}"
CLEANUP_TAHOE_XSESSION_ENTRY="${CLEANUP_TAHOE_XSESSION_ENTRY:-true}"
FORCE_NIRI_CONFIG_DEPLOY="${FORCE_NIRI_CONFIG_DEPLOY:-false}"
ALLOW_ROOT_ARCH_UPDATE="${ALLOW_ROOT_ARCH_UPDATE:-false}"
BUILD_NIRI_FORK="${BUILD_NIRI_FORK:-false}"
FORCE_NIRI_BUILD="${FORCE_NIRI_BUILD:-false}"
BUILD_QUICKSHELL_FORK="${BUILD_QUICKSHELL_FORK:-false}"
FORCE_QUICKSHELL_BUILD="${FORCE_QUICKSHELL_BUILD:-false}"
INSTALL_QUICKSHELL_BUILD_DEPS="${INSTALL_QUICKSHELL_BUILD_DEPS:-true}"
BUILD_XWAYLAND_SATELLITE="${BUILD_XWAYLAND_SATELLITE:-auto}"
FORCE_XWAYLAND_SATELLITE_BUILD="${FORCE_XWAYLAND_SATELLITE_BUILD:-false}"
INSTALL_XWAYLAND_SATELLITE_BUILD_DEPS="${INSTALL_XWAYLAND_SATELLITE_BUILD_DEPS:-true}"
XWAYLAND_SATELLITE_REPO_URL="${XWAYLAND_SATELLITE_REPO_URL:-https://github.com/Supreeeme/xwayland-satellite.git}"
XWAYLAND_SATELLITE_REF="${XWAYLAND_SATELLITE_REF:-v0.8.1}"
XWAYLAND_SATELLITE_PATCH="${XWAYLAND_SATELLITE_PATCH:-"$REPO_DIR/patches/xwayland-satellite-minimize.patch"}"
XWAYLAND_SATELLITE_UPSTREAM_DIR="${XWAYLAND_SATELLITE_UPSTREAM_DIR:-"$TAHOE_CACHE_DIR/xwayland-satellite/upstream"}"
XWAYLAND_SATELLITE_WORK_DIR="${XWAYLAND_SATELLITE_WORK_DIR:-"$TAHOE_CACHE_DIR/xwayland-satellite/work"}"
XWAYLAND_SATELLITE_TARGET_DIR="${XWAYLAND_SATELLITE_TARGET_DIR:-"$TAHOE_CACHE_DIR/xwayland-satellite/target"}"
XWAYLAND_SATELLITE_BIN="${XWAYLAND_SATELLITE_BIN:-"$HOME/.local/lib/niri/xwayland-satellite-minimize"}"
XWAYLAND_SATELLITE_GLAMOR_WRAPPER="${XWAYLAND_SATELLITE_GLAMOR_WRAPPER:-"$XWAYLAND_SATELLITE_BIN-glamor"}"
XWAYLAND_SATELLITE_BUILD_STAMP="${XWAYLAND_SATELLITE_BUILD_STAMP:-"$TAHOE_STATE_DIR/xwayland-satellite-minimize.stamp"}"
XWAYLAND_SATELLITE_COMPAT_CHECK_SCRIPT="${XWAYLAND_SATELLITE_COMPAT_CHECK_SCRIPT:-"$REPO_DIR/scripts/check-xwayland-satellite-compat.sh"}"
TAHOE_XWAYLAND_COMPAT_CHECK_TARGET="${TAHOE_XWAYLAND_COMPAT_CHECK_TARGET:-"$TAHOE_CONFIG_DIR/scripts/check-xwayland-satellite-compat.sh"}"
RUN_TAHOE_GLASS_GUARDRAILS="${RUN_TAHOE_GLASS_GUARDRAILS:-true}"
TAHOE_GLASS_GUARDRAILS_SCRIPT="${TAHOE_GLASS_GUARDRAILS_SCRIPT:-"$REPO_DIR/scripts/check-tahoe-glass-guardrails.sh"}"
# Tahoe shell deploy parity (T01). State files live under TAHOE_STATE_DIR only.
TAHOE_SHELL_DEPLOY_ROOT_COMMIT_FILE="${TAHOE_SHELL_DEPLOY_ROOT_COMMIT_FILE:-"$TAHOE_STATE_DIR/tahoe-shell-deployed-root-commit"}"
TAHOE_SHELL_DEPLOY_MANIFEST_HASH_FILE="${TAHOE_SHELL_DEPLOY_MANIFEST_HASH_FILE:-"$TAHOE_STATE_DIR/tahoe-shell-deployed-manifest.sha256"}"
TAHOE_SHELL_DEPLOY_MANIFEST_FILE="${TAHOE_SHELL_DEPLOY_MANIFEST_FILE:-"$TAHOE_STATE_DIR/tahoe-shell-deployed-manifest.txt"}"
# Exact cache excludes shared by sync and manifest. Do not widen without review.
TAHOE_SHELL_RSYNC_EXCLUDES=(
  "--exclude=__pycache__/"
  "--exclude=*.pyc"
  "--exclude=.pytest_cache/"
)

QUICKSHELL_BUILD_PACKAGES=(
  base-devel
  clang
  cli11
  cmake
  jemalloc
  libdrm
  libpipewire
  libxcb
  networkmanager
  ninja
  pam
  polkit
  qt6-base
  qt6-declarative
  qt6-shadertools
  qt6-svg
  qt6-wayland
  spirv-tools
  upower
  vulkan-headers
  wayland
  wayland-protocols
)

XWAYLAND_SATELLITE_BUILD_PACKAGES=(
  base-devel
  cargo
  clang
  git
  libxcb
  pkgconf
  xcb-util-cursor
  xorg-xwayland
)

before_commit=""
after_commit=""
niri_before_commit=""
niri_after_commit=""
quickshell_before_commit=""
quickshell_after_commit=""
xwayland_satellite_before_commit=""
xwayland_satellite_after_commit=""
xwayland_satellite_patch_sha=""
xwayland_satellite_patch_applied="not-rebuilt"
xwayland_satellite_wrapper_deployed=false
need_niri_build=false
need_quickshell_build=false
need_xwayland_satellite_build=false
need_shell_deploy=false
need_niri_config_deploy=false
need_session_deploy=false
scripts_changed=false
niri_built=false
quickshell_built=false
xwayland_satellite_built=false
shell_deployed=false
niri_config_deployed=false
session_launcher_deployed=false
system_session_launcher_deployed=false
session_desktop_deployed=false
system_session_desktop_deployed=false
xsession_desktop_deployed=false
xsession_desktop_removed=false
root_git=false
niri_git=false
niri_root_submodule=false
quickshell_git=false
quickshell_root_submodule=false

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

is_git_repo() {
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

is_root_submodule_path() {
  local path="$1"
  local rel_path
  local key
  local submodule_path

  [[ "$root_git" == true && -f "$REPO_DIR/.gitmodules" ]] || return 1

  case "$path" in
    "$REPO_DIR"/*) rel_path="${path#$REPO_DIR/}" ;;
    *) return 1 ;;
  esac

  while read -r key submodule_path; do
    [[ "$submodule_path" == "$rel_path" ]] && return 0
  done < <(git -C "$REPO_DIR" config --file "$REPO_DIR/.gitmodules" --get-regexp '^submodule\..*\.path$')

  return 1
}

changed_since_pull() {
  local pattern="$1"

  if [[ "$root_git" != true ]]; then
    return 1
  fi

  if [[ -z "$before_commit" || "$before_commit" == "$after_commit" ]]; then
    return 1
  fi

  git -C "$REPO_DIR" diff --name-only "$before_commit" "$after_commit" -- \
    | grep -Eq "$pattern"
}

niri_changed_since_pull() {
  if [[ "$niri_root_submodule" == true ]]; then
    changed_since_pull '^niri$'
    return
  fi

  if [[ "$niri_git" == true ]]; then
    if [[ -z "$niri_before_commit" || "$niri_before_commit" == "$niri_after_commit" ]]; then
      return 1
    fi

    git -C "$NIRI_DIR" diff --name-only "$niri_before_commit" "$niri_after_commit" -- \
      | grep -Eq '.'
    return
  fi

  changed_since_pull '^niri/'
}

quickshell_changed_since_pull() {
  if [[ "$quickshell_root_submodule" == true ]]; then
    changed_since_pull '^quickshell$'
    return
  fi

  if [[ "$quickshell_git" == true ]]; then
    if [[ -z "$quickshell_before_commit" || "$quickshell_before_commit" == "$quickshell_after_commit" ]]; then
      return 1
    fi

    git -C "$QUICKSHELL_DIR" diff --name-only "$quickshell_before_commit" "$quickshell_after_commit" -- \
      | grep -Eq '.'
    return
  fi

  changed_since_pull '^quickshell/'
}

quickshell_build_is_current() {
  local expected_commit="$quickshell_after_commit"
  local installed_commit=""

  [[ -n "$expected_commit" ]] || return 1
  [[ -x "$QUICKSHELL_BIN_DIR/$QUICKSHELL_BIN_NAME" ]] || return 1
  [[ -f "$QUICKSHELL_BUILD_STAMP" ]] || return 1

  installed_commit="$(<"$QUICKSHELL_BUILD_STAMP")"
  [[ "$installed_commit" == "$expected_commit" ]]
}

xwayland_satellite_enabled() {
  [[ "$BUILD_XWAYLAND_SATELLITE" != false || "$FORCE_XWAYLAND_SATELLITE_BUILD" == true ]]
}

sha256_file() {
  local path="$1"

  require_cmd sha256sum
  sha256sum "$path" | sed 's/[[:space:]].*$//'
}

resolve_xwayland_satellite_ref() {
  local ref="$1"
  local commit=""

  if commit="$(git -C "$XWAYLAND_SATELLITE_UPSTREAM_DIR" rev-parse --verify -q "origin/$ref^{commit}")"; then
    printf '%s\n' "$commit"
    return
  fi

  if commit="$(git -C "$XWAYLAND_SATELLITE_UPSTREAM_DIR" rev-parse --verify -q "$ref^{commit}")"; then
    printf '%s\n' "$commit"
    return
  fi

  die "could not resolve xwayland-satellite ref: $ref"
}

prepare_xwayland_satellite_upstream() {
  local current_url=""

  [[ -f "$XWAYLAND_SATELLITE_PATCH" ]] \
    || die "xwayland-satellite patch does not exist: $XWAYLAND_SATELLITE_PATCH"

  require_cmd git
  xwayland_satellite_patch_sha="$(sha256_file "$XWAYLAND_SATELLITE_PATCH")"

  if [[ -d "$XWAYLAND_SATELLITE_UPSTREAM_DIR/.git" ]]; then
    current_url="$(git -C "$XWAYLAND_SATELLITE_UPSTREAM_DIR" remote get-url origin 2>/dev/null || true)"
    if [[ "$current_url" != "$XWAYLAND_SATELLITE_REPO_URL" ]]; then
      log "updating xwayland-satellite origin URL"
      git -C "$XWAYLAND_SATELLITE_UPSTREAM_DIR" remote set-url origin "$XWAYLAND_SATELLITE_REPO_URL"
    fi

    xwayland_satellite_before_commit="$(git -C "$XWAYLAND_SATELLITE_UPSTREAM_DIR" rev-parse HEAD 2>/dev/null || true)"
    log "fetching xwayland-satellite upstream"
    git -C "$XWAYLAND_SATELLITE_UPSTREAM_DIR" fetch --prune --tags origin
  else
    if [[ -e "$XWAYLAND_SATELLITE_UPSTREAM_DIR" ]]; then
      die "xwayland-satellite upstream path exists but is not a git repository: $XWAYLAND_SATELLITE_UPSTREAM_DIR"
    fi

    log "cloning xwayland-satellite upstream cache"
    mkdir -p "$(dirname -- "$XWAYLAND_SATELLITE_UPSTREAM_DIR")"
    git clone "$XWAYLAND_SATELLITE_REPO_URL" "$XWAYLAND_SATELLITE_UPSTREAM_DIR"
    xwayland_satellite_before_commit=""
  fi

  xwayland_satellite_after_commit="$(resolve_xwayland_satellite_ref "$XWAYLAND_SATELLITE_REF")"
  log "xwayland-satellite ref $XWAYLAND_SATELLITE_REF resolves to $xwayland_satellite_after_commit"
}

xwayland_satellite_build_is_current() {
  [[ -n "$xwayland_satellite_after_commit" ]] || return 1
  [[ -n "$xwayland_satellite_patch_sha" ]] || return 1
  [[ -x "$XWAYLAND_SATELLITE_BIN" ]] || return 1
  [[ -f "$XWAYLAND_SATELLITE_BUILD_STAMP" ]] || return 1

  grep -Fxq "repo=$XWAYLAND_SATELLITE_REPO_URL" "$XWAYLAND_SATELLITE_BUILD_STAMP" || return 1
  grep -Fxq "ref=$XWAYLAND_SATELLITE_REF" "$XWAYLAND_SATELLITE_BUILD_STAMP" || return 1
  grep -Fxq "commit=$xwayland_satellite_after_commit" "$XWAYLAND_SATELLITE_BUILD_STAMP" || return 1
  grep -Fxq "patch_sha256=$xwayland_satellite_patch_sha" "$XWAYLAND_SATELLITE_BUILD_STAMP" || return 1

  return 0
}

remove_xwayland_satellite_worktree() {
  [[ -e "$XWAYLAND_SATELLITE_WORK_DIR" ]] || return 0

  if [[ -f "$XWAYLAND_SATELLITE_WORK_DIR/.git" || -d "$XWAYLAND_SATELLITE_WORK_DIR/.git" ]]; then
    git -C "$XWAYLAND_SATELLITE_UPSTREAM_DIR" worktree remove --force "$XWAYLAND_SATELLITE_WORK_DIR" >/dev/null 2>&1 \
      || rm -rf "$XWAYLAND_SATELLITE_WORK_DIR"
  else
    rm -rf "$XWAYLAND_SATELLITE_WORK_DIR"
  fi
}

prepare_xwayland_satellite_worktree() {
  remove_xwayland_satellite_worktree
  git -C "$XWAYLAND_SATELLITE_UPSTREAM_DIR" worktree prune
  mkdir -p "$(dirname -- "$XWAYLAND_SATELLITE_WORK_DIR")"
  git -C "$XWAYLAND_SATELLITE_UPSTREAM_DIR" worktree add --detach "$XWAYLAND_SATELLITE_WORK_DIR" "$xwayland_satellite_after_commit"

  xwayland_satellite_patch_applied=false
  if git -C "$XWAYLAND_SATELLITE_WORK_DIR" apply --check "$XWAYLAND_SATELLITE_PATCH"; then
    git -C "$XWAYLAND_SATELLITE_WORK_DIR" apply "$XWAYLAND_SATELLITE_PATCH"
    xwayland_satellite_patch_applied=true
    return
  fi

  if grep -Rqs 'set_minimized' "$XWAYLAND_SATELLITE_WORK_DIR/src" \
    && grep -Rqs 'WM_CHANGE_STATE' "$XWAYLAND_SATELLITE_WORK_DIR/src"; then
    log "xwayland-satellite patch no longer applies, but upstream appears to include minimize support; building without local patch"
    return
  fi

  die "xwayland-satellite minimize patch does not apply to $xwayland_satellite_after_commit; update $XWAYLAND_SATELLITE_PATCH or run with BUILD_XWAYLAND_SATELLITE=false"
}

install_xwayland_satellite_build_deps() {
  if [[ "$INSTALL_XWAYLAND_SATELLITE_BUILD_DEPS" != true ]]; then
    log "skipping xwayland-satellite build dependency install; INSTALL_XWAYLAND_SATELLITE_BUILD_DEPS=$INSTALL_XWAYLAND_SATELLITE_BUILD_DEPS"
    return
  fi

  if ! command -v pacman >/dev/null 2>&1; then
    log "pacman not found; skipping xwayland-satellite build dependency install"
    return
  fi

  require_cmd sudo
  log "installing xwayland-satellite build dependencies"
  sudo pacman -Syu --needed "${XWAYLAND_SATELLITE_BUILD_PACKAGES[@]}"
}

write_xwayland_satellite_build_stamp() {
  mkdir -p "$(dirname -- "$XWAYLAND_SATELLITE_BUILD_STAMP")"
  {
    printf 'repo=%s\n' "$XWAYLAND_SATELLITE_REPO_URL"
    printf 'ref=%s\n' "$XWAYLAND_SATELLITE_REF"
    printf 'commit=%s\n' "$xwayland_satellite_after_commit"
    printf 'patch=%s\n' "$XWAYLAND_SATELLITE_PATCH"
    printf 'patch_sha256=%s\n' "$xwayland_satellite_patch_sha"
    printf 'patch_applied=%s\n' "$xwayland_satellite_patch_applied"
    printf 'binary=%s\n' "$XWAYLAND_SATELLITE_BIN"
    printf 'glamor_wrapper=%s\n' "$XWAYLAND_SATELLITE_GLAMOR_WRAPPER"
  } > "$XWAYLAND_SATELLITE_BUILD_STAMP"
}

deploy_xwayland_satellite_glamor_wrapper() {
  local tmp

  mkdir -p "$(dirname -- "$XWAYLAND_SATELLITE_GLAMOR_WRAPPER")"
  tmp="$(mktemp "${XWAYLAND_SATELLITE_GLAMOR_WRAPPER}.tmp.XXXXXX")"

  cat > "$tmp" <<EOF
#!/usr/bin/env bash
set -euo pipefail

satellite="$XWAYLAND_SATELLITE_BIN"

if [[ ! -x "\$satellite" ]]; then
    printf 'xwayland-satellite target is missing or not executable: %s\\n' "\$satellite" >&2
    exit 127
fi

if [[ \$# -gt 0 && "\$1" == :* ]]; then
    display="\$1"
    shift
    exec "\$satellite" "\$display" -glamor gl "\$@"
fi

exec "\$satellite" -glamor gl "\$@"
EOF

  chmod 755 "$tmp"
  mv "$tmp" "$XWAYLAND_SATELLITE_GLAMOR_WRAPPER"
  xwayland_satellite_wrapper_deployed=true
}

dirs_differ() {
  local src="$1"
  local dst="$2"

  [[ -d "$src" ]] || return 1
  [[ -d "$dst" ]] || return 0

  if command -v diff >/dev/null 2>&1; then
    ! diff -qr "$src" "$dst" >/dev/null
  else
    return 0
  fi
}

files_differ() {
  local src="$1"
  local dst="$2"

  [[ -f "$src" ]] || return 1
  [[ -f "$dst" ]] || return 0

  if command -v cmp >/dev/null 2>&1; then
    ! cmp -s "$src" "$dst"
  else
    return 0
  fi
}

assert_niri_config_vrr_policy() {
  local config="$1"

  [[ -f "$config" ]] || return

  local enabled
  enabled="$(grep -Ec '^[[:space:]]*variable-refresh-rate[[:space:]]*(//.*)?$' "$config" || true)"
  if [[ "$enabled" -ne 1 ]]; then
    die "niri config must contain exactly one always-on variable-refresh-rate policy: $config"
  fi
  if grep -nE '^[[:space:]]*variable-refresh-rate[[:space:]]+on-demand=' "$config"; then
    die "niri config must use always-on variable-refresh-rate, not on-demand: $config"
  fi
}

desktop_needs_update() {
  local target="$1"
  local exec_path="$2"

  [[ -f "$target" ]] || return 0

  grep -Fxq "Name=Tahoe Niri" "$target" || return 0
  grep -Fxq "Exec=$exec_path" "$target" || return 0
  grep -Fxq "Type=Application" "$target" || return 0
  grep -Fxq "DesktopNames=niri" "$target" || return 0

  if grep -Eq '^TryExec=' "$target"; then
    return 0
  fi

  return 1
}

write_tahoe_session_desktop() {
  local target="$1"
  local exec_path="$2"

  {
    printf '[Desktop Entry]\n'
    printf 'Name=Tahoe Niri\n'
    printf 'Comment=niri session with Tahoe Quickshell\n'
    printf 'Exec=%s\n' "$exec_path"
    printf 'Type=Application\n'
    printf 'DesktopNames=niri\n'
  } > "$target"
}

sync_dir() {
  local src="$1"
  local dst="$2"

  [[ -d "$src" ]] || die "source directory does not exist: $src"
  mkdir -p "$dst"

  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$src"/ "$dst"/
  else
    find "$dst" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    cp -a "$src"/. "$dst"/
  fi
}

# Filtered sync for Tahoe shell: same exclude list as the parity manifest.
sync_tahoe_shell_tree() {
  local src="$1"
  local dst="$2"

  [[ -d "$src" ]] || die "source directory does not exist: $src"
  mkdir -p "$dst"

  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "${TAHOE_SHELL_RSYNC_EXCLUDES[@]}" "$src"/ "$dst"/
  else
    find "$dst" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    cp -a "$src"/. "$dst"/
    # Mirror rsync excludes without a broad runtime wipe.
    find "$dst" \( -type d -name '__pycache__' -o -type d -name '.pytest_cache' -o -type f -name '*.pyc' \) -prune -exec rm -rf -- {} + 2>/dev/null || true
  fi
}

# Return 0 if relative path under a tree is a cache artifact (not in desired tree).
tahoe_shell_path_is_cache() {
  local rel="${1#./}"

  case "$rel" in
    __pycache__|__pycache__/*|*/__pycache__|*/__pycache__/*) return 0 ;;
    .pytest_cache|.pytest_cache/*|*/.pytest_cache|*/.pytest_cache/*) return 0 ;;
    *.pyc) return 0 ;;
  esac
  [[ "$rel" == *.pyc ]] && return 0
  return 1
}

# Sorted "sha256  relpath" lines (two spaces; path may contain spaces).
write_tahoe_shell_tree_manifest() {
  local root="$1"
  local out="$2"
  local rel
  local digest

  [[ -d "$root" ]] || die "manifest root does not exist: $root"
  require_cmd sha256sum
  : > "$out"

  (
    cd "$root"
    find . -type f -print0 \
      | sort -z \
      | while IFS= read -r -d '' rel; do
          rel="${rel#./}"
          if tahoe_shell_path_is_cache "$rel"; then
            continue
          fi
          digest="$(sha256sum -- "./$rel" | awk '{print $1}')"
          printf '%s  %s\n' "$digest" "$rel"
        done
  ) >> "$out"
}

# Desired deployed tree = filtered tahoe-shell + declared overlay script.
write_tahoe_shell_desired_manifest() {
  local out="$1"
  local tmp
  local overlay_digest

  require_cmd sha256sum
  tmp="$(mktemp)"
  write_tahoe_shell_tree_manifest "$TAHOE_SHELL_DIR" "$tmp"

  if [[ -f "$XWAYLAND_SATELLITE_COMPAT_CHECK_SCRIPT" ]]; then
    overlay_digest="$(sha256sum -- "$XWAYLAND_SATELLITE_COMPAT_CHECK_SCRIPT" | awk '{print $1}')"
    {
      cat "$tmp"
      printf '%s  %s\n' "$overlay_digest" "scripts/check-xwayland-satellite-compat.sh"
    } | LC_ALL=C sort -t ' ' -k2 > "$out"
  else
    LC_ALL=C sort -t ' ' -k2 "$tmp" > "$out"
  fi
  rm -f "$tmp"
}

manifest_file_hash() {
  local path="$1"
  require_cmd sha256sum
  sha256sum -- "$path" | awk '{print $1}'
}

# Compare desired manifest to an installed tree. Prints mismatches to stderr.
# Returns 0 when equal (ignoring allowed cache files at destination).
verify_tahoe_shell_parity_from_manifest() {
  local desired_manifest="$1"
  local installed_root="$2"
  local rel
  local want_hash
  local got_hash
  local status=0
  local -A desired=()

  [[ -f "$desired_manifest" ]] || die "desired manifest missing: $desired_manifest"
  if [[ ! -d "$installed_root" ]]; then
    printf '[arch-update] ERROR: installed Tahoe shell root missing: %s\n' "$installed_root" >&2
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    want_hash="${line%%  *}"
    rel="${line#*  }"
    [[ -n "$rel" && -n "$want_hash" ]] || continue
    desired["$rel"]="$want_hash"
  done < "$desired_manifest"

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    want_hash="${desired[$rel]}"
    if [[ ! -f "$installed_root/$rel" ]]; then
      printf '[arch-update] ERROR: missing deployed file: %s\n' "$rel" >&2
      status=1
      continue
    fi
    got_hash="$(sha256sum -- "$installed_root/$rel" | awk '{print $1}')"
    if [[ "$got_hash" != "$want_hash" ]]; then
      printf '[arch-update] ERROR: content differs: %s (desired %s, installed %s)\n' \
        "$rel" "$want_hash" "$got_hash" >&2
      status=1
    fi
  done < <(printf '%s\n' "${!desired[@]}" | LC_ALL=C sort)

  while IFS= read -r -d '' rel; do
    rel="${rel#./}"
    if tahoe_shell_path_is_cache "$rel"; then
      continue
    fi
    if [[ -z "${desired[$rel]+x}" ]]; then
      printf '[arch-update] ERROR: extra deployed file: %s\n' "$rel" >&2
      status=1
    fi
  done < <(cd "$installed_root" && find . -type f -print0)

  return "$status"
}

record_tahoe_shell_deploy_state() {
  local manifest="$1"
  local root_commit=""
  local manifest_hash

  mkdir -p "$TAHOE_STATE_DIR"
  if is_git_repo "$REPO_DIR"; then
    root_commit="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || true)"
  fi
  if [[ -z "$root_commit" ]]; then
    root_commit="unknown"
  fi
  manifest_hash="$(manifest_file_hash "$manifest")"
  printf '%s\n' "$root_commit" > "$TAHOE_SHELL_DEPLOY_ROOT_COMMIT_FILE"
  printf '%s\n' "$manifest_hash" > "$TAHOE_SHELL_DEPLOY_MANIFEST_HASH_FILE"
  install -m644 "$manifest" "$TAHOE_SHELL_DEPLOY_MANIFEST_FILE"
  log "recorded Tahoe shell deploy state: root_commit=$root_commit manifest_hash=$manifest_hash"
}

# Read-only parity check. Does not write user config.
verify_deployed_tahoe_shell() {
  local desired
  local rc=0

  desired="$(mktemp)"
  write_tahoe_shell_desired_manifest "$desired"
  log "verifying Tahoe shell parity: source=$TAHOE_SHELL_DIR installed=$TAHOE_CONFIG_DIR"
  if verify_tahoe_shell_parity_from_manifest "$desired" "$TAHOE_CONFIG_DIR"; then
    log "Tahoe shell parity OK (manifest $(manifest_file_hash "$desired"))"
  else
    rc=1
    log "Tahoe shell parity FAILED"
  fi
  rm -f "$desired"
  return "$rc"
}

quickshell_tahoe_state_dir() {
  local state_home="${XDG_STATE_HOME:-"$HOME/.local/state"}"
  printf '%s\n' "$state_home/quickshell/by-shell/tahoe"
}

migrate_legacy_tahoe_shell_state() {
  local legacy_pins="$TAHOE_CONFIG_DIR/pinned-apps.json"
  local state_dir
  local state_pins

  state_dir="$(quickshell_tahoe_state_dir)"
  state_pins="$state_dir/pinned-apps.json"

  if [[ -f "$legacy_pins" ]]; then
    if [[ ! -f "$state_pins" || "$legacy_pins" -nt "$state_pins" ]]; then
      log "migrating Tahoe Dock pins to $state_pins"
      mkdir -p "$state_dir"
      install -m600 "$legacy_pins" "$state_pins"
    fi
  fi
}

niri_config_target_modified() {
  [[ -f "$NIRI_CONFIG_TARGET" ]] || return 1

  if [[ -f "$NIRI_CONFIG_DEPLOY_BASELINE" ]]; then
    files_differ "$NIRI_CONFIG_DEPLOY_BASELINE" "$NIRI_CONFIG_TARGET"
    return
  fi

  files_differ "$NIRI_CONFIG_SRC" "$NIRI_CONFIG_TARGET"
}

backup_niri_config_target() {
  local timestamp
  local backup

  timestamp="$(date +%Y%m%d-%H%M%S)"
  backup="$NIRI_CONFIG_TARGET.user-$timestamp.bak"
  if [[ -e "$backup" ]]; then
    backup="$NIRI_CONFIG_TARGET.user-$timestamp-$$.bak"
  fi

  cp -p "$NIRI_CONFIG_TARGET" "$backup"
  printf '%s\n' "$backup"
}

deploy_niri_config() {
  if [[ ! -f "$NIRI_CONFIG_SRC" ]]; then
    log "skipping niri config deploy; source file does not exist: $NIRI_CONFIG_SRC"
    return
  fi

  assert_niri_config_vrr_policy "$NIRI_CONFIG_SRC"

  mkdir -p "$NIRI_CONFIG_DIR"
  mkdir -p "$(dirname -- "$NIRI_CONFIG_DEPLOY_BASELINE")"

  if niri_config_target_modified; then
    local backup
    local proposed

    backup="$(backup_niri_config_target)"
    log "existing niri Tahoe config has local changes; backed up to $backup"

    if [[ "$FORCE_NIRI_CONFIG_DEPLOY" != true ]]; then
      proposed="$NIRI_CONFIG_TARGET.new"
      install -m644 "$NIRI_CONFIG_SRC" "$proposed"
      log "leaving modified niri Tahoe config in place"
      log "new Tahoe config template written to $proposed"
      log "set FORCE_NIRI_CONFIG_DEPLOY=true to overwrite after reviewing the backup"
      return
    fi

    log "FORCE_NIRI_CONFIG_DEPLOY=true; overwriting modified niri Tahoe config after backup"
  fi

  log "deploying niri Tahoe config to $NIRI_CONFIG_TARGET"
  install -m644 "$NIRI_CONFIG_SRC" "$NIRI_CONFIG_TARGET"
  install -m644 "$NIRI_CONFIG_SRC" "$NIRI_CONFIG_DEPLOY_BASELINE"
  niri_config_deployed=true
}

build_niri() {
  [[ -d "$NIRI_DIR" ]] || die "niri directory does not exist: $NIRI_DIR"
  require_cmd cargo

  log "building niri fork"
  (
    cd "$NIRI_DIR"
    cargo build --release --locked
  )

  install -Dm755 "$NIRI_DIR/target/release/niri" "$NIRI_BIN_DIR/$NIRI_BIN_NAME"
  if [[ -f "$NIRI_DIR/resources/niri-session" ]]; then
    install -Dm755 "$NIRI_DIR/resources/niri-session" "$NIRI_BIN_DIR/niri-session"
  fi
  niri_built=true
}

install_quickshell_build_deps() {
  if [[ "$INSTALL_QUICKSHELL_BUILD_DEPS" != true ]]; then
    log "skipping Quickshell build dependency install; INSTALL_QUICKSHELL_BUILD_DEPS=$INSTALL_QUICKSHELL_BUILD_DEPS"
    return
  fi

  if ! command -v pacman >/dev/null 2>&1; then
    log "pacman not found; skipping Quickshell build dependency install"
    return
  fi

  require_cmd sudo
  log "installing Quickshell build dependencies"
  sudo pacman -Syu --needed "${QUICKSHELL_BUILD_PACKAGES[@]}"
}

build_quickshell() {
  [[ -d "$QUICKSHELL_DIR" ]] || die "Quickshell directory does not exist: $QUICKSHELL_DIR"

  install_quickshell_build_deps

  require_cmd cmake
  require_cmd ninja

  log "building Quickshell fork"
  cmake -S "$QUICKSHELL_DIR" -B "$QUICKSHELL_BUILD_DIR" -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -DINSTALL_QML_PREFIX=lib/qt6/qml \
    -DDISTRIBUTOR="Tahoe fork" \
    -DCRASHREPORT_URL="https://github.com/skjsbsnq/quickshell/issues/new/choose"
  cmake --build "$QUICKSHELL_BUILD_DIR"
  cmake --install "$QUICKSHELL_BUILD_DIR"

  if [[ ! -x "$QUICKSHELL_BIN_DIR/$QUICKSHELL_BIN_NAME" ]]; then
    die "Quickshell build finished but binary is missing: $QUICKSHELL_BIN_DIR/$QUICKSHELL_BIN_NAME"
  fi

  git -C "$QUICKSHELL_DIR" rev-parse HEAD > "$QUICKSHELL_BUILD_STAMP"
  quickshell_built=true
}

build_xwayland_satellite() {
  [[ -n "$xwayland_satellite_after_commit" ]] \
    || die "xwayland-satellite source was not prepared"

  install_xwayland_satellite_build_deps

  require_cmd cargo

  prepare_xwayland_satellite_worktree

  log "building patched xwayland-satellite"
  (
    cd "$XWAYLAND_SATELLITE_WORK_DIR"
    CARGO_TARGET_DIR="$XWAYLAND_SATELLITE_TARGET_DIR" cargo build --release --locked
  )

  install -Dm755 "$XWAYLAND_SATELLITE_TARGET_DIR/release/xwayland-satellite" "$XWAYLAND_SATELLITE_BIN"

  if ! "$XWAYLAND_SATELLITE_BIN" ":0" --test-listenfd-support >/dev/null 2>&1; then
    die "patched xwayland-satellite failed --test-listenfd-support after install: $XWAYLAND_SATELLITE_BIN"
  fi

  write_xwayland_satellite_build_stamp
  xwayland_satellite_built=true
}

deploy_tahoe_shell() {
  local desired_manifest

  if [[ ! -d "$TAHOE_SHELL_DIR" ]]; then
    log "skipping Tahoe shell deploy; directory does not exist: $TAHOE_SHELL_DIR"
    return
  fi

  log "deploying Tahoe shell to $TAHOE_CONFIG_DIR"
  migrate_legacy_tahoe_shell_state

  desired_manifest="$(mktemp)"
  write_tahoe_shell_desired_manifest "$desired_manifest"
  log "pre-deploy Tahoe shell manifest hash: $(manifest_file_hash "$desired_manifest")"

  sync_tahoe_shell_tree "$TAHOE_SHELL_DIR" "$TAHOE_CONFIG_DIR"
  if [[ -x "$XWAYLAND_SATELLITE_COMPAT_CHECK_SCRIPT" ]]; then
    install -Dm755 "$XWAYLAND_SATELLITE_COMPAT_CHECK_SCRIPT" "$TAHOE_XWAYLAND_COMPAT_CHECK_TARGET"
  else
    log "xwayland-satellite compatibility check script not deployed; missing $XWAYLAND_SATELLITE_COMPAT_CHECK_SCRIPT"
  fi

  if ! verify_tahoe_shell_parity_from_manifest "$desired_manifest" "$TAHOE_CONFIG_DIR"; then
    rm -f "$desired_manifest"
    die "Tahoe shell deploy parity check failed for $TAHOE_CONFIG_DIR"
  fi
  record_tahoe_shell_deploy_state "$desired_manifest"
  rm -f "$desired_manifest"
  shell_deployed=true
}

deploy_tahoe_session_entry() {
  local tmp_desktop

  if [[ "$DEPLOY_TAHOE_SESSION_ENTRY" != true && "$DEPLOY_TAHOE_SYSTEM_SESSION_ENTRY" != true && "$DEPLOY_TAHOE_XSESSION_ENTRY" != true && "$CLEANUP_TAHOE_XSESSION_ENTRY" != true ]]; then
    log "skipping Tahoe session entry deploy; DEPLOY_TAHOE_SESSION_ENTRY=$DEPLOY_TAHOE_SESSION_ENTRY DEPLOY_TAHOE_SYSTEM_SESSION_ENTRY=$DEPLOY_TAHOE_SYSTEM_SESSION_ENTRY DEPLOY_TAHOE_XSESSION_ENTRY=$DEPLOY_TAHOE_XSESSION_ENTRY CLEANUP_TAHOE_XSESSION_ENTRY=$CLEANUP_TAHOE_XSESSION_ENTRY"
    return
  fi

  [[ -f "$TAHOE_SESSION_LAUNCHER_SRC" ]] || die "Tahoe session launcher source does not exist: $TAHOE_SESSION_LAUNCHER_SRC"

  if [[ "$CLEANUP_TAHOE_XSESSION_ENTRY" == true && "$DEPLOY_TAHOE_XSESSION_ENTRY" != true && -f "$TAHOE_XSESSION_DESKTOP_TARGET" ]]; then
    require_cmd sudo
    log "removing stale Tahoe xsession-compatible entry from $TAHOE_XSESSION_DESKTOP_TARGET"
    sudo rm -f "$TAHOE_XSESSION_DESKTOP_TARGET"
    xsession_desktop_removed=true
  fi

  if [[ "$DEPLOY_TAHOE_SESSION_ENTRY" == true ]]; then
    log "deploying Tahoe user session launcher to $TAHOE_SESSION_BIN"
    install -Dm755 "$TAHOE_SESSION_LAUNCHER_SRC" "$TAHOE_SESSION_BIN"
    session_launcher_deployed=true
  fi

  if [[ "$DEPLOY_TAHOE_SYSTEM_SESSION_ENTRY" == true || "$DEPLOY_TAHOE_XSESSION_ENTRY" == true ]]; then
    require_cmd sudo

    log "deploying Tahoe system session launcher to $TAHOE_SYSTEM_SESSION_BIN"
    sudo install -Dm755 "$TAHOE_SESSION_LAUNCHER_SRC" "$TAHOE_SYSTEM_SESSION_BIN"
    system_session_launcher_deployed=true
  fi

  if [[ "$DEPLOY_TAHOE_SESSION_ENTRY" == true ]]; then
    log "deploying Tahoe user wayland session entry to $TAHOE_SESSION_DESKTOP_TARGET"
    mkdir -p "$TAHOE_SESSION_DESKTOP_DIR"
    write_tahoe_session_desktop "$TAHOE_SESSION_DESKTOP_TARGET" "$TAHOE_SESSION_BIN"
    session_desktop_deployed=true
  fi

  if [[ "$DEPLOY_TAHOE_SYSTEM_SESSION_ENTRY" == true ]]; then
    require_cmd mktemp

    tmp_desktop="$(mktemp)"
    write_tahoe_session_desktop "$tmp_desktop" "$TAHOE_SYSTEM_SESSION_BIN"
    log "deploying Tahoe system wayland session entry to $TAHOE_SYSTEM_SESSION_DESKTOP_TARGET"
    sudo install -Dm644 "$tmp_desktop" "$TAHOE_SYSTEM_SESSION_DESKTOP_TARGET"
    rm -f "$tmp_desktop"
    system_session_desktop_deployed=true
  fi

  if [[ "$DEPLOY_TAHOE_XSESSION_ENTRY" == true ]]; then
    require_cmd mktemp

    tmp_desktop="$(mktemp)"
    write_tahoe_session_desktop "$tmp_desktop" "$TAHOE_SYSTEM_SESSION_BIN"
    log "deploying Tahoe xsession-compatible entry to $TAHOE_XSESSION_DESKTOP_TARGET"
    sudo install -Dm644 "$tmp_desktop" "$TAHOE_XSESSION_DESKTOP_TARGET"
    rm -f "$tmp_desktop"
    xsession_desktop_deployed=true
  fi
}

run_tahoe_glass_guardrails() {
  if [[ "$RUN_TAHOE_GLASS_GUARDRAILS" != true ]]; then
    log "skipping Tahoe glass guardrails; RUN_TAHOE_GLASS_GUARDRAILS=$RUN_TAHOE_GLASS_GUARDRAILS"
    return
  fi

  [[ -f "$TAHOE_GLASS_GUARDRAILS_SCRIPT" ]] \
    || die "missing Tahoe glass guardrail script: $TAHOE_GLASS_GUARDRAILS_SCRIPT"

  log "running Tahoe glass Phase 7 guardrails"
  bash "$TAHOE_GLASS_GUARDRAILS_SCRIPT"
}

run_xwayland_satellite_compat_check() {
  local output

  if ! xwayland_satellite_enabled; then
    log "skipping patched xwayland-satellite compatibility check; BUILD_XWAYLAND_SATELLITE=$BUILD_XWAYLAND_SATELLITE"
    return
  fi

  [[ -x "$XWAYLAND_SATELLITE_COMPAT_CHECK_SCRIPT" ]] \
    || die "missing xwayland-satellite compatibility check: $XWAYLAND_SATELLITE_COMPAT_CHECK_SCRIPT"

  log "checking patched xwayland-satellite compatibility"
  if ! output="$(
    REPO_DIR="$REPO_DIR" \
    TAHOE_CACHE_DIR="$TAHOE_CACHE_DIR" \
    TAHOE_STATE_DIR="$TAHOE_STATE_DIR" \
    NIRI_CONFIG_TARGET="$NIRI_CONFIG_TARGET" \
    XWAYLAND_SATELLITE_REPO_URL="$XWAYLAND_SATELLITE_REPO_URL" \
    XWAYLAND_SATELLITE_REF="$XWAYLAND_SATELLITE_REF" \
    XWAYLAND_SATELLITE_PATCH="$XWAYLAND_SATELLITE_PATCH" \
    XWAYLAND_SATELLITE_UPSTREAM_DIR="$XWAYLAND_SATELLITE_UPSTREAM_DIR" \
    XWAYLAND_SATELLITE_BIN="$XWAYLAND_SATELLITE_BIN" \
    XWAYLAND_SATELLITE_GLAMOR_WRAPPER="$XWAYLAND_SATELLITE_GLAMOR_WRAPPER" \
    XWAYLAND_SATELLITE_BUILD_STAMP="$XWAYLAND_SATELLITE_BUILD_STAMP" \
    bash "$XWAYLAND_SATELLITE_COMPAT_CHECK_SCRIPT" --status --strict 2>&1
  )"; then
    printf '%s\n' "$output" | sed 's/^/[arch-update]   /'
    die "patched xwayland-satellite compatibility check failed"
  fi

  printf '%s\n' "$output" | sed 's/^/[arch-update]   /'
}

main() {
  local mode="${1:-}"

  if [[ "$mode" == "-h" || "$mode" == "--help" ]]; then
    cat <<'EOF'
Usage: arch-update.sh [options]

Update Tahoe niri/Quickshell sources and deploy managed configs.

Options:
  --verify-tahoe-shell   Read-only: verify the installed Tahoe shell tree matches
                         filtered tahoe-shell plus the xwayland compat overlay.
                         Does not write user config.
  --deploy-tahoe-shell   Deploy only the Tahoe shell tree (filtered sync +
                         overlay), verify parity, and record deploy state.
                         Does not pull/build niri or Quickshell.
  -h, --help             Show this help.
EOF
    return 0
  fi

  if [[ "$mode" == "--verify-tahoe-shell" ]]; then
    require_cmd sha256sum
    require_cmd find
    verify_deployed_tahoe_shell
    return
  fi

  if [[ "$mode" == "--deploy-tahoe-shell" ]]; then
    require_cmd sha256sum
    require_cmd find
    require_cmd install
    deploy_tahoe_shell
    return
  fi

  if [[ -n "$mode" ]]; then
    die "unknown argument: $mode (try --help)"
  fi

  require_cmd git
  require_cmd grep
  require_cmd install
  require_cmd find
  require_cmd sed

  case "$BUILD_XWAYLAND_SATELLITE" in
    auto | true | false) ;;
    *) die "BUILD_XWAYLAND_SATELLITE must be auto, true, or false; got: $BUILD_XWAYLAND_SATELLITE" ;;
  esac

  if [[ "${EUID:-$(id -u)}" -eq 0 && "$ALLOW_ROOT_ARCH_UPDATE" != true ]]; then
    die "do not run this whole script with sudo; run bash scripts/arch-update.sh as the target user. The script will call sudo only for system session files."
  fi

  if is_git_repo "$REPO_DIR"; then
    root_git=true
  fi

  if is_git_repo "$NIRI_DIR"; then
    niri_git=true
  fi

  if is_git_repo "$QUICKSHELL_DIR"; then
    quickshell_git=true
  fi

  if is_root_submodule_path "$NIRI_DIR"; then
    niri_root_submodule=true
  fi

  if is_root_submodule_path "$QUICKSHELL_DIR"; then
    quickshell_root_submodule=true
  fi

  if [[ "$root_git" != true && "$niri_git" != true && "$quickshell_git" != true ]]; then
    die "none of REPO_DIR, NIRI_DIR, or QUICKSHELL_DIR is a git repository"
  fi

  if [[ "$root_git" == true ]]; then
    before_commit="$(git -C "$REPO_DIR" rev-parse HEAD)"
    log "repo current commit: $before_commit"

    git -C "$REPO_DIR" fetch --prune
    git -C "$REPO_DIR" pull --ff-only

    after_commit="$(git -C "$REPO_DIR" rev-parse HEAD)"
    log "repo updated commit: $after_commit"

    if [[ "$before_commit" == "$after_commit" ]]; then
      log "repo has no upstream changes"
    else
      log "repo changed files:"
      git -C "$REPO_DIR" diff --name-only "$before_commit" "$after_commit" \
        | sed 's/^/[arch-update]   /'
    fi

    if [[ -f "$REPO_DIR/.gitmodules" ]]; then
      log "syncing submodules"
      git -C "$REPO_DIR" submodule sync --recursive
      git -C "$REPO_DIR" submodule update --init --recursive
    fi
  else
    before_commit="no-root-git"
    after_commit="no-root-git"
    log "REPO_DIR is not a git repository; skipping root pull: $REPO_DIR"
  fi

  if is_git_repo "$NIRI_DIR"; then
    niri_git=true
  fi

  if is_git_repo "$QUICKSHELL_DIR"; then
    quickshell_git=true
  fi

  if [[ "$niri_git" == true && "$niri_root_submodule" == true ]]; then
    niri_before_commit="$(git -C "$NIRI_DIR" rev-parse HEAD)"
    log "niri submodule current commit: $niri_before_commit"

    log "updating niri submodule to latest upstream"

    # Get the configured branch for this submodule
    local niri_branch
    niri_branch="$(git -C "$REPO_DIR" config -f "$REPO_DIR/.gitmodules" "submodule.niri.branch" || echo "main")"

    # Fetch from remote
    git -C "$NIRI_DIR" fetch --prune origin

    # Ensure we're on a branch, not detached HEAD
    if ! git -C "$NIRI_DIR" symbolic-ref -q HEAD >/dev/null 2>&1; then
      log "niri submodule is in detached HEAD state; checking out branch: $niri_branch"
      git -C "$NIRI_DIR" checkout "$niri_branch" || git -C "$NIRI_DIR" checkout -b "$niri_branch" "origin/$niri_branch"
    fi

    # Always reset to remote to ensure we get latest upstream (submodules should track upstream exactly)
    log "resetting niri submodule to origin/$niri_branch"
    git -C "$NIRI_DIR" reset --hard "origin/$niri_branch"

    niri_after_commit="$(git -C "$NIRI_DIR" rev-parse HEAD)"
    log "niri submodule updated commit: $niri_after_commit"

    if [[ "$niri_before_commit" == "$niri_after_commit" ]]; then
      log "niri submodule has no upstream changes"
    else
      log "niri submodule changed files:"
      git -C "$NIRI_DIR" diff --name-only "$niri_before_commit" "$niri_after_commit" \
        | sed 's/^/[arch-update]   niri\//'
    fi
  elif [[ "$niri_git" == true ]]; then
    niri_before_commit="$(git -C "$NIRI_DIR" rev-parse HEAD)"
    log "niri current commit: $niri_before_commit"

    git -C "$NIRI_DIR" fetch --prune
    git -C "$NIRI_DIR" pull --ff-only

    niri_after_commit="$(git -C "$NIRI_DIR" rev-parse HEAD)"
    log "niri updated commit: $niri_after_commit"

    if [[ "$niri_before_commit" == "$niri_after_commit" ]]; then
      log "niri has no upstream changes"
    else
      log "niri changed files:"
      git -C "$NIRI_DIR" diff --name-only "$niri_before_commit" "$niri_after_commit" \
        | sed 's/^/[arch-update]   niri\//'
    fi
  fi

  if [[ "$quickshell_git" == true && "$quickshell_root_submodule" == true ]]; then
    quickshell_before_commit="$(git -C "$QUICKSHELL_DIR" rev-parse HEAD)"
    log "Quickshell submodule current commit: $quickshell_before_commit"

    log "updating Quickshell submodule to latest upstream"

    # Get the configured branch for this submodule
    local quickshell_branch
    quickshell_branch="$(git -C "$REPO_DIR" config -f "$REPO_DIR/.gitmodules" "submodule.quickshell.branch" || echo "master")"

    # Fetch from remote
    git -C "$QUICKSHELL_DIR" fetch --prune origin

    # Ensure we're on a branch, not detached HEAD
    if ! git -C "$QUICKSHELL_DIR" symbolic-ref -q HEAD >/dev/null 2>&1; then
      log "Quickshell submodule is in detached HEAD state; checking out branch: $quickshell_branch"
      git -C "$QUICKSHELL_DIR" checkout "$quickshell_branch" || git -C "$QUICKSHELL_DIR" checkout -b "$quickshell_branch" "origin/$quickshell_branch"
    fi

    # Always reset to remote to ensure we get latest upstream (submodules should track upstream exactly)
    log "resetting Quickshell submodule to origin/$quickshell_branch"
    git -C "$QUICKSHELL_DIR" reset --hard "origin/$quickshell_branch"

    quickshell_after_commit="$(git -C "$QUICKSHELL_DIR" rev-parse HEAD)"
    log "Quickshell submodule updated commit: $quickshell_after_commit"

    if [[ "$quickshell_before_commit" == "$quickshell_after_commit" ]]; then
      log "Quickshell submodule has no upstream changes"
    else
      log "Quickshell submodule changed files:"
      git -C "$QUICKSHELL_DIR" diff --name-only "$quickshell_before_commit" "$quickshell_after_commit" \
        | sed 's/^/[arch-update]   quickshell\//'
    fi
  elif [[ "$quickshell_git" == true ]]; then
    quickshell_before_commit="$(git -C "$QUICKSHELL_DIR" rev-parse HEAD)"
    log "Quickshell current commit: $quickshell_before_commit"

    git -C "$QUICKSHELL_DIR" fetch --prune
    git -C "$QUICKSHELL_DIR" pull --ff-only

    quickshell_after_commit="$(git -C "$QUICKSHELL_DIR" rev-parse HEAD)"
    log "Quickshell updated commit: $quickshell_after_commit"

    if [[ "$quickshell_before_commit" == "$quickshell_after_commit" ]]; then
      log "Quickshell has no upstream changes"
    else
      log "Quickshell changed files:"
      git -C "$QUICKSHELL_DIR" diff --name-only "$quickshell_before_commit" "$quickshell_after_commit" \
        | sed 's/^/[arch-update]   quickshell\//'
    fi
  fi

  if [[ "$BUILD_NIRI_FORK" == auto ]] && niri_changed_since_pull; then
    need_niri_build=true
  fi

  if [[ "$BUILD_QUICKSHELL_FORK" == auto ]]; then
    if quickshell_changed_since_pull; then
      need_quickshell_build=true
    elif ! quickshell_build_is_current; then
      log "Quickshell installed build is missing or not from the current submodule commit"
      need_quickshell_build=true
    fi
  fi

  if xwayland_satellite_enabled; then
    prepare_xwayland_satellite_upstream
  fi

  case "$BUILD_XWAYLAND_SATELLITE" in
    auto)
      if ! xwayland_satellite_build_is_current; then
        log "patched xwayland-satellite build is missing or out of date"
        need_xwayland_satellite_build=true
      fi
      ;;
    true)
      need_xwayland_satellite_build=true
      ;;
    false)
      ;;
  esac

  if [[ "$FORCE_NIRI_BUILD" == true ]]; then
    log "FORCE_NIRI_BUILD=true"
    need_niri_build=true
  fi

  if [[ "$FORCE_QUICKSHELL_BUILD" == true ]]; then
    log "FORCE_QUICKSHELL_BUILD=true"
    need_quickshell_build=true
  fi

  if [[ "$FORCE_XWAYLAND_SATELLITE_BUILD" == true ]]; then
    log "FORCE_XWAYLAND_SATELLITE_BUILD=true"
    need_xwayland_satellite_build=true
  fi

  if changed_since_pull '^(tahoe-shell/|macOS-26-Tahoe-for-the-Web-main/(background|icon)/|.*\.qml$)' \
    || changed_since_pull '^scripts/check-xwayland-satellite-compat\.sh$' \
    || dirs_differ "$TAHOE_SHELL_DIR" "$TAHOE_CONFIG_DIR" \
    || files_differ "$XWAYLAND_SATELLITE_COMPAT_CHECK_SCRIPT" "$TAHOE_XWAYLAND_COMPAT_CHECK_TARGET"; then
    need_shell_deploy=true
  fi

  if changed_since_pull '^(config/niri/|.*\.kdl$)' \
    || files_differ "$NIRI_CONFIG_SRC" "$NIRI_CONFIG_TARGET" \
    || [[ ! -f "$NIRI_CONFIG_DEPLOY_BASELINE" ]]; then
    need_niri_config_deploy=true
  fi

  if [[ "$DEPLOY_TAHOE_SESSION_ENTRY" == true || "$DEPLOY_TAHOE_SYSTEM_SESSION_ENTRY" == true || "$DEPLOY_TAHOE_XSESSION_ENTRY" == true || "$CLEANUP_TAHOE_XSESSION_ENTRY" == true ]]; then
    if changed_since_pull '^scripts/(arch-update|tahoe-niri-session)\.sh$' \
      || { [[ "$DEPLOY_TAHOE_SESSION_ENTRY" == true ]] && files_differ "$TAHOE_SESSION_LAUNCHER_SRC" "$TAHOE_SESSION_BIN"; } \
      || { [[ "$DEPLOY_TAHOE_SYSTEM_SESSION_ENTRY" == true || "$DEPLOY_TAHOE_XSESSION_ENTRY" == true ]] && files_differ "$TAHOE_SESSION_LAUNCHER_SRC" "$TAHOE_SYSTEM_SESSION_BIN"; } \
      || { [[ "$DEPLOY_TAHOE_SESSION_ENTRY" == true ]] && desktop_needs_update "$TAHOE_SESSION_DESKTOP_TARGET" "$TAHOE_SESSION_BIN"; } \
      || { [[ "$DEPLOY_TAHOE_SYSTEM_SESSION_ENTRY" == true ]] && desktop_needs_update "$TAHOE_SYSTEM_SESSION_DESKTOP_TARGET" "$TAHOE_SYSTEM_SESSION_BIN"; } \
      || { [[ "$DEPLOY_TAHOE_XSESSION_ENTRY" == true ]] && desktop_needs_update "$TAHOE_XSESSION_DESKTOP_TARGET" "$TAHOE_SYSTEM_SESSION_BIN"; } \
      || { [[ "$CLEANUP_TAHOE_XSESSION_ENTRY" == true && "$DEPLOY_TAHOE_XSESSION_ENTRY" != true && -f "$TAHOE_XSESSION_DESKTOP_TARGET" ]]; }; then
      need_session_deploy=true
    fi
  fi

  if changed_since_pull '^scripts/'; then
    scripts_changed=true
  fi

  assert_niri_config_vrr_policy "$NIRI_CONFIG_SRC"
  run_tahoe_glass_guardrails

  if [[ "$need_niri_build" == true ]]; then
    build_niri
  else
    log "niri build not needed"
  fi

  if [[ "$need_quickshell_build" == true ]]; then
    build_quickshell
  else
    log "Quickshell build not needed"
  fi

  if [[ "$need_xwayland_satellite_build" == true ]]; then
    build_xwayland_satellite
  else
    log "patched xwayland-satellite build not needed"
  fi

  if xwayland_satellite_enabled; then
    deploy_xwayland_satellite_glamor_wrapper
  fi

  if [[ "$need_shell_deploy" == true ]]; then
    deploy_tahoe_shell
  else
    log "Tahoe shell deploy not needed"
  fi

  if [[ "$need_niri_config_deploy" == true ]]; then
    deploy_niri_config
  else
    log "niri Tahoe config deploy not needed"
  fi

  if [[ "$need_session_deploy" == true ]]; then
    deploy_tahoe_session_entry
  else
    log "Tahoe session entry deploy not needed"
  fi

  run_xwayland_satellite_compat_check

  log "summary:"
  log "  repo from: $before_commit"
  log "  repo to:   $after_commit"
  log "  build niri fork mode: $BUILD_NIRI_FORK"
  log "  build Quickshell fork mode: $BUILD_QUICKSHELL_FORK"
  log "  build xwayland-satellite mode: $BUILD_XWAYLAND_SATELLITE"
  if [[ "$niri_git" == true && "$niri_root_submodule" == true ]]; then
    log "  niri mode: root submodule"
    log "  niri commit: $niri_after_commit"
  elif [[ "$niri_git" == true ]]; then
    log "  niri from: $niri_before_commit"
    log "  niri to:   $niri_after_commit"
  fi
  if [[ "$quickshell_git" == true && "$quickshell_root_submodule" == true ]]; then
    log "  Quickshell mode: root submodule"
    log "  Quickshell commit: $quickshell_after_commit"
  elif [[ "$quickshell_git" == true ]]; then
    log "  Quickshell from: $quickshell_before_commit"
    log "  Quickshell to:   $quickshell_after_commit"
  fi
  log "  niri built: $niri_built"
  log "  Quickshell built: $quickshell_built"
  log "  Quickshell binary: $QUICKSHELL_BIN_DIR/$QUICKSHELL_BIN_NAME"
  log "  Quickshell build stamp: $QUICKSHELL_BUILD_STAMP"
  log "  patched xwayland-satellite built: $xwayland_satellite_built"
  log "  patched xwayland-satellite binary: $XWAYLAND_SATELLITE_BIN"
  log "  patched xwayland-satellite glamor wrapper: $XWAYLAND_SATELLITE_GLAMOR_WRAPPER"
  log "  patched xwayland-satellite glamor wrapper deployed: $xwayland_satellite_wrapper_deployed"
  log "  patched xwayland-satellite build stamp: $XWAYLAND_SATELLITE_BUILD_STAMP"
  if [[ -n "$xwayland_satellite_after_commit" ]]; then
    log "  xwayland-satellite ref: $XWAYLAND_SATELLITE_REF"
    log "  xwayland-satellite commit: $xwayland_satellite_after_commit"
    log "  xwayland-satellite patch applied: $xwayland_satellite_patch_applied"
  fi
  log "  Tahoe shell deployed: $shell_deployed"
  if [[ -f "$TAHOE_SHELL_DEPLOY_MANIFEST_HASH_FILE" ]]; then
    log "  Tahoe shell deploy manifest hash: $(<"$TAHOE_SHELL_DEPLOY_MANIFEST_HASH_FILE")"
  fi
  if [[ -f "$TAHOE_SHELL_DEPLOY_ROOT_COMMIT_FILE" ]]; then
    log "  Tahoe shell deploy root commit: $(<"$TAHOE_SHELL_DEPLOY_ROOT_COMMIT_FILE")"
  fi
  log "  niri Tahoe config deployed: $niri_config_deployed"
  log "  niri Tahoe config target: $NIRI_CONFIG_TARGET"
  log "  Tahoe session launcher deployed: $session_launcher_deployed"
  log "  Tahoe system session launcher deployed: $system_session_launcher_deployed"
  log "  Tahoe system session launcher target: $TAHOE_SYSTEM_SESSION_BIN"
  log "  Tahoe session desktop deployed: $session_desktop_deployed"
  log "  Tahoe session desktop target: $TAHOE_SESSION_DESKTOP_TARGET"
  log "  Tahoe system session desktop deployed: $system_session_desktop_deployed"
  log "  Tahoe system session desktop target: $TAHOE_SYSTEM_SESSION_DESKTOP_TARGET"
  log "  Tahoe xsession-compatible desktop deployed: $xsession_desktop_deployed"
  log "  Tahoe xsession-compatible desktop removed: $xsession_desktop_removed"
  log "  Tahoe xsession-compatible desktop target: $TAHOE_XSESSION_DESKTOP_TARGET"

  if [[ "$scripts_changed" == true ]]; then
    log "scripts changed; rerun this script if the update modified arch-update.sh behavior"
  fi

  if [[ "$niri_built" == true || "$niri_config_deployed" == true ]]; then
    log "restart niri or log out/in to use the updated compositor/config"
  fi

  if [[ "$xwayland_satellite_built" == true || "$xwayland_satellite_wrapper_deployed" == true ]]; then
    log "log out/in or restart niri to make new X11 windows use the patched xwayland-satellite"
  fi

  if [[ "$quickshell_built" == true || "$shell_deployed" == true ]]; then
    log "restart Quickshell Tahoe shell to use the deployed QML/assets"
  fi

  if [[ "$session_launcher_deployed" == true || "$session_desktop_deployed" == true ]]; then
    log "log out/in or restart the display manager if it does not show the Tahoe Niri session immediately"
  fi
}

main "$@"
