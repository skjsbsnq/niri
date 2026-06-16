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
NIRI_BIN_DIR="${NIRI_BIN_DIR:-"$INSTALL_PREFIX/bin"}"
NIRI_BIN_NAME="${NIRI_BIN_NAME:-niri}"
QUICKSHELL_BUILD_DIR="${QUICKSHELL_BUILD_DIR:-"$QUICKSHELL_DIR/build-tahoe"}"
QUICKSHELL_BUILD_STAMP="${QUICKSHELL_BUILD_STAMP:-"$QUICKSHELL_BUILD_DIR/.tahoe-installed-commit"}"
QUICKSHELL_BIN_DIR="${QUICKSHELL_BIN_DIR:-"$INSTALL_PREFIX/bin"}"
QUICKSHELL_BIN_NAME="${QUICKSHELL_BIN_NAME:-quickshell}"
TAHOE_CONFIG_DIR="${TAHOE_CONFIG_DIR:-"$HOME/.config/quickshell/tahoe"}"
NIRI_CONFIG_DIR="${NIRI_CONFIG_DIR:-"$HOME/.config/niri/tahoe"}"
NIRI_CONFIG_TARGET="${NIRI_CONFIG_TARGET:-"$NIRI_CONFIG_DIR/config.kdl"}"
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
ALLOW_ROOT_ARCH_UPDATE="${ALLOW_ROOT_ARCH_UPDATE:-false}"
BUILD_NIRI_FORK="${BUILD_NIRI_FORK:-false}"
FORCE_NIRI_BUILD="${FORCE_NIRI_BUILD:-false}"
BUILD_QUICKSHELL_FORK="${BUILD_QUICKSHELL_FORK:-false}"
FORCE_QUICKSHELL_BUILD="${FORCE_QUICKSHELL_BUILD:-false}"
INSTALL_QUICKSHELL_BUILD_DEPS="${INSTALL_QUICKSHELL_BUILD_DEPS:-true}"
RUN_TAHOE_GLASS_GUARDRAILS="${RUN_TAHOE_GLASS_GUARDRAILS:-true}"
TAHOE_GLASS_GUARDRAILS_SCRIPT="${TAHOE_GLASS_GUARDRAILS_SCRIPT:-"$REPO_DIR/scripts/check-tahoe-glass-guardrails.sh"}"

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

before_commit=""
after_commit=""
niri_before_commit=""
niri_after_commit=""
quickshell_before_commit=""
quickshell_after_commit=""
need_niri_build=false
need_quickshell_build=false
need_shell_deploy=false
need_niri_config_deploy=false
need_session_deploy=false
scripts_changed=false
niri_built=false
quickshell_built=false
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

deploy_niri_config() {
  if [[ ! -f "$NIRI_CONFIG_SRC" ]]; then
    log "skipping niri config deploy; source file does not exist: $NIRI_CONFIG_SRC"
    return
  fi

  log "deploying niri Tahoe config to $NIRI_CONFIG_TARGET"
  mkdir -p "$NIRI_CONFIG_DIR"
  install -m644 "$NIRI_CONFIG_SRC" "$NIRI_CONFIG_TARGET"
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

deploy_tahoe_shell() {
  if [[ ! -d "$TAHOE_SHELL_DIR" ]]; then
    log "skipping Tahoe shell deploy; directory does not exist: $TAHOE_SHELL_DIR"
    return
  fi

  log "deploying Tahoe shell to $TAHOE_CONFIG_DIR"
  sync_dir "$TAHOE_SHELL_DIR" "$TAHOE_CONFIG_DIR"
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

main() {
  require_cmd git
  require_cmd grep
  require_cmd install
  require_cmd find
  require_cmd sed

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
    git -C "$NIRI_DIR" fetch --prune

    # Ensure we're on the configured branch and pull from its upstream
    local niri_branch
    niri_branch="$(git -C "$REPO_DIR" config -f "$REPO_DIR/.gitmodules" "submodule.niri.branch" || echo "main")"

    if ! git -C "$NIRI_DIR" symbolic-ref -q HEAD >/dev/null 2>&1; then
      log "niri submodule is in detached HEAD state; checking out branch: $niri_branch"
      git -C "$NIRI_DIR" checkout "$niri_branch"
    fi

    # If branches have diverged, reset to remote (submodules should track upstream exactly)
    if ! git -C "$NIRI_DIR" merge-base --is-ancestor HEAD "origin/$niri_branch" 2>/dev/null && \
       ! git -C "$NIRI_DIR" merge-base --is-ancestor "origin/$niri_branch" HEAD 2>/dev/null; then
      log "niri submodule has diverged from upstream; resetting to origin/$niri_branch"
      git -C "$NIRI_DIR" reset --hard "origin/$niri_branch"
    else
      git -C "$NIRI_DIR" pull --ff-only origin "$niri_branch"
    fi

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
    git -C "$QUICKSHELL_DIR" fetch --prune

    # Ensure we're on the configured branch and pull from its upstream
    local quickshell_branch
    quickshell_branch="$(git -C "$REPO_DIR" config -f "$REPO_DIR/.gitmodules" "submodule.quickshell.branch" || echo "master")"

    if ! git -C "$QUICKSHELL_DIR" symbolic-ref -q HEAD >/dev/null 2>&1; then
      log "Quickshell submodule is in detached HEAD state; checking out branch: $quickshell_branch"
      git -C "$QUICKSHELL_DIR" checkout "$quickshell_branch"
    fi

    # If branches have diverged, reset to remote (submodules should track upstream exactly)
    if ! git -C "$QUICKSHELL_DIR" merge-base --is-ancestor HEAD "origin/$quickshell_branch" 2>/dev/null && \
       ! git -C "$QUICKSHELL_DIR" merge-base --is-ancestor "origin/$quickshell_branch" HEAD 2>/dev/null; then
      log "Quickshell submodule has diverged from upstream; resetting to origin/$quickshell_branch"
      git -C "$QUICKSHELL_DIR" reset --hard "origin/$quickshell_branch"
    else
      git -C "$QUICKSHELL_DIR" pull --ff-only origin "$quickshell_branch"
    fi

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

  if [[ "$FORCE_NIRI_BUILD" == true ]]; then
    log "FORCE_NIRI_BUILD=true"
    need_niri_build=true
  fi

  if [[ "$FORCE_QUICKSHELL_BUILD" == true ]]; then
    log "FORCE_QUICKSHELL_BUILD=true"
    need_quickshell_build=true
  fi

  if changed_since_pull '^(tahoe-shell/|macOS-26-Tahoe-for-the-Web-main/(background|icon)/|.*\.qml$)' \
    || dirs_differ "$TAHOE_SHELL_DIR" "$TAHOE_CONFIG_DIR"; then
    need_shell_deploy=true
  fi

  if changed_since_pull '^(config/niri/|.*\.kdl$)' \
    || files_differ "$NIRI_CONFIG_SRC" "$NIRI_CONFIG_TARGET"; then
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

  log "summary:"
  log "  repo from: $before_commit"
  log "  repo to:   $after_commit"
  log "  build niri fork mode: $BUILD_NIRI_FORK"
  log "  build Quickshell fork mode: $BUILD_QUICKSHELL_FORK"
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
  log "  Tahoe shell deployed: $shell_deployed"
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

  if [[ "$quickshell_built" == true || "$shell_deployed" == true ]]; then
    log "restart Quickshell Tahoe shell to use the deployed QML/assets"
  fi

  if [[ "$session_launcher_deployed" == true || "$session_desktop_deployed" == true ]]; then
    log "log out/in or restart the display manager if it does not show the Tahoe Niri session immediately"
  fi
}

main "$@"
