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
TAHOE_SHELL_DIR="${TAHOE_SHELL_DIR:-"$REPO_DIR/tahoe-shell"}"
NIRI_CONFIG_SRC="${NIRI_CONFIG_SRC:-"$REPO_DIR/config/niri/tahoe-phase0.kdl"}"

INSTALL_PREFIX="${INSTALL_PREFIX:-"$HOME/.local"}"
NIRI_BIN_DIR="${NIRI_BIN_DIR:-"$INSTALL_PREFIX/bin"}"
NIRI_BIN_NAME="${NIRI_BIN_NAME:-niri}"
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
DEPLOY_TAHOE_XSESSION_ENTRY="${DEPLOY_TAHOE_XSESSION_ENTRY:-true}"
BUILD_NIRI_FORK="${BUILD_NIRI_FORK:-false}"
FORCE_NIRI_BUILD="${FORCE_NIRI_BUILD:-false}"

before_commit=""
after_commit=""
niri_before_commit=""
niri_after_commit=""
need_niri_build=false
need_shell_deploy=false
need_niri_config_deploy=false
need_session_deploy=false
scripts_changed=false
niri_built=false
shell_deployed=false
niri_config_deployed=false
session_launcher_deployed=false
system_session_launcher_deployed=false
session_desktop_deployed=false
system_session_desktop_deployed=false
xsession_desktop_deployed=false
root_git=false
niri_git=false
niri_root_submodule=false

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

  if [[ "$DEPLOY_TAHOE_SESSION_ENTRY" != true && "$DEPLOY_TAHOE_SYSTEM_SESSION_ENTRY" != true && "$DEPLOY_TAHOE_XSESSION_ENTRY" != true ]]; then
    log "skipping Tahoe session entry deploy; DEPLOY_TAHOE_SESSION_ENTRY=$DEPLOY_TAHOE_SESSION_ENTRY DEPLOY_TAHOE_SYSTEM_SESSION_ENTRY=$DEPLOY_TAHOE_SYSTEM_SESSION_ENTRY DEPLOY_TAHOE_XSESSION_ENTRY=$DEPLOY_TAHOE_XSESSION_ENTRY"
    return
  fi

  [[ -f "$TAHOE_SESSION_LAUNCHER_SRC" ]] || die "Tahoe session launcher source does not exist: $TAHOE_SESSION_LAUNCHER_SRC"

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

main() {
  require_cmd git
  require_cmd grep
  require_cmd install
  require_cmd find
  require_cmd sed

  if is_git_repo "$REPO_DIR"; then
    root_git=true
  fi

  if is_git_repo "$NIRI_DIR"; then
    niri_git=true
  fi

  if is_root_submodule_path "$NIRI_DIR"; then
    niri_root_submodule=true
  fi

  if [[ "$root_git" != true && "$niri_git" != true ]]; then
    die "neither REPO_DIR nor NIRI_DIR is a git repository"
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

  if [[ "$niri_git" == true && "$niri_root_submodule" == true ]]; then
    niri_after_commit="$(git -C "$NIRI_DIR" rev-parse HEAD)"
    log "niri submodule commit: $niri_after_commit"
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

  if [[ "$BUILD_NIRI_FORK" == auto ]] && niri_changed_since_pull; then
    need_niri_build=true
  fi

  if [[ "$FORCE_NIRI_BUILD" == true ]]; then
    log "FORCE_NIRI_BUILD=true"
    need_niri_build=true
  fi

  if changed_since_pull '^(tahoe-shell/|macOS-26-Tahoe-for-the-Web-main/(background|icon)/|.*\.qml$)' \
    || dirs_differ "$TAHOE_SHELL_DIR" "$TAHOE_CONFIG_DIR"; then
    need_shell_deploy=true
  fi

  if changed_since_pull '^(config/niri/|.*\.kdl$)' \
    || files_differ "$NIRI_CONFIG_SRC" "$NIRI_CONFIG_TARGET"; then
    need_niri_config_deploy=true
  fi

  if [[ "$DEPLOY_TAHOE_SESSION_ENTRY" == true || "$DEPLOY_TAHOE_SYSTEM_SESSION_ENTRY" == true || "$DEPLOY_TAHOE_XSESSION_ENTRY" == true ]]; then
    if changed_since_pull '^scripts/(arch-update|tahoe-niri-session)\.sh$' \
      || { [[ "$DEPLOY_TAHOE_SESSION_ENTRY" == true ]] && files_differ "$TAHOE_SESSION_LAUNCHER_SRC" "$TAHOE_SESSION_BIN"; } \
      || { [[ "$DEPLOY_TAHOE_SYSTEM_SESSION_ENTRY" == true || "$DEPLOY_TAHOE_XSESSION_ENTRY" == true ]] && files_differ "$TAHOE_SESSION_LAUNCHER_SRC" "$TAHOE_SYSTEM_SESSION_BIN"; } \
      || { [[ "$DEPLOY_TAHOE_SESSION_ENTRY" == true ]] && desktop_needs_update "$TAHOE_SESSION_DESKTOP_TARGET" "$TAHOE_SESSION_BIN"; } \
      || { [[ "$DEPLOY_TAHOE_SYSTEM_SESSION_ENTRY" == true ]] && desktop_needs_update "$TAHOE_SYSTEM_SESSION_DESKTOP_TARGET" "$TAHOE_SYSTEM_SESSION_BIN"; } \
      || { [[ "$DEPLOY_TAHOE_XSESSION_ENTRY" == true ]] && desktop_needs_update "$TAHOE_XSESSION_DESKTOP_TARGET" "$TAHOE_SYSTEM_SESSION_BIN"; }; then
      need_session_deploy=true
    fi
  fi

  if changed_since_pull '^scripts/'; then
    scripts_changed=true
  fi

  if [[ "$need_niri_build" == true ]]; then
    build_niri
  else
    log "niri build not needed"
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
  if [[ "$niri_git" == true && "$niri_root_submodule" == true ]]; then
    log "  niri mode: root submodule"
    log "  niri commit: $niri_after_commit"
  elif [[ "$niri_git" == true ]]; then
    log "  niri from: $niri_before_commit"
    log "  niri to:   $niri_after_commit"
  fi
  log "  niri built: $niri_built"
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
  log "  Tahoe xsession-compatible desktop target: $TAHOE_XSESSION_DESKTOP_TARGET"

  if [[ "$scripts_changed" == true ]]; then
    log "scripts changed; rerun this script if the update modified arch-update.sh behavior"
  fi

  if [[ "$niri_built" == true || "$niri_config_deployed" == true ]]; then
    log "restart niri or log out/in to use the updated compositor/config"
  fi

  if [[ "$shell_deployed" == true ]]; then
    log "restart Quickshell Tahoe shell to use the deployed QML/assets"
  fi

  if [[ "$session_launcher_deployed" == true || "$session_desktop_deployed" == true ]]; then
    log "log out/in or restart the display manager if it does not show the Tahoe Niri session immediately"
  fi
}

main "$@"
