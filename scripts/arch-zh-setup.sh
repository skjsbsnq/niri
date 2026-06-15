#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[arch-zh-setup] %s\n' "$*"
}

die() {
  printf '[arch-zh-setup] ERROR: %s\n' "$*" >&2
  exit 1
}

ZH_LOCALE="${ZH_LOCALE:-zh_CN.UTF-8}"
FALLBACK_LOCALE="${FALLBACK_LOCALE:-en_US.UTF-8}"
SET_SYSTEM_LOCALE="${SET_SYSTEM_LOCALE:-true}"
INSTALL_INPUT_METHOD="${INSTALL_INPUT_METHOD:-true}"
CONFIGURE_FONTCONFIG="${CONFIGURE_FONTCONFIG:-true}"
CONFIGURE_INPUT_METHOD_ENV="${CONFIGURE_INPUT_METHOD_ENV:-true}"
CONFIGURE_FCITX_PROFILE="${CONFIGURE_FCITX_PROFILE:-true}"
OVERWRITE_FCITX_PROFILE="${OVERWRITE_FCITX_PROFILE:-false}"
ENABLE_FCITX_SERVICE="${ENABLE_FCITX_SERVICE:-true}"
ALLOW_ROOT_ZH_SETUP="${ALLOW_ROOT_ZH_SETUP:-false}"

FONTCONFIG_TARGET="${FONTCONFIG_TARGET:-"$HOME/.config/fontconfig/conf.d/64-arch-zh-cjk.conf"}"
USER_ENV_TARGET="${USER_ENV_TARGET:-"$HOME/.config/environment.d/90-arch-zh-input-method.conf"}"
FCITX_PROFILE_TARGET="${FCITX_PROFILE_TARGET:-"$HOME/.config/fcitx5/profile"}"

FONT_PACKAGES=(
  noto-fonts
  noto-fonts-cjk
  noto-fonts-emoji
  ttf-liberation
  wqy-microhei
  wqy-zenhei
)

INPUT_METHOD_PACKAGES=(
  fcitx5
  fcitx5-chinese-addons
  fcitx5-configtool
  fcitx5-gtk
  fcitx5-qt
)

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

locale_regex() {
  printf '%s' "${1//./\\.}"
}

enable_locale() {
  local locale_name="$1"
  local regex

  [[ -n "$locale_name" ]] || return
  regex="$(locale_regex "$locale_name")"

  if sudo grep -Eq "^[#[:space:]]*${regex}[[:space:]]+UTF-8" /etc/locale.gen; then
    log "enabling locale in /etc/locale.gen: $locale_name"
    sudo sed -i -E "s|^[#[:space:]]*(${regex}[[:space:]]+UTF-8.*)$|\1|" /etc/locale.gen
  else
    log "adding locale to /etc/locale.gen: $locale_name"
    printf '%s UTF-8\n' "$locale_name" | sudo tee -a /etc/locale.gen >/dev/null
  fi
}

configure_locales() {
  [[ -f /etc/locale.gen ]] || die "/etc/locale.gen does not exist"

  enable_locale "$ZH_LOCALE"
  if [[ -n "$FALLBACK_LOCALE" && "$FALLBACK_LOCALE" != "$ZH_LOCALE" ]]; then
    enable_locale "$FALLBACK_LOCALE"
  fi

  log "running locale-gen"
  sudo locale-gen

  if [[ "$SET_SYSTEM_LOCALE" != true ]]; then
    log "skipping system LANG because SET_SYSTEM_LOCALE=$SET_SYSTEM_LOCALE"
    return
  fi

  if command -v localectl >/dev/null 2>&1 && localectl status >/dev/null 2>&1; then
    log "setting system LANG=$ZH_LOCALE"
    sudo localectl set-locale "LANG=$ZH_LOCALE"
  else
    log "localectl is unavailable; writing /etc/locale.conf"
    write_locale_conf
  fi
}

write_locale_conf() {
  local tmp

  require_cmd mktemp
  tmp="$(mktemp)"

  if [[ -f /etc/locale.conf ]]; then
    cp /etc/locale.conf "$tmp"
  fi

  if grep -Eq '^LANG=' "$tmp"; then
    sed -i -E "s|^LANG=.*$|LANG=$ZH_LOCALE|" "$tmp"
  else
    printf 'LANG=%s\n' "$ZH_LOCALE" >> "$tmp"
  fi

  sudo install -m644 "$tmp" /etc/locale.conf
  rm -f "$tmp"
}

install_packages() {
  local packages=("${FONT_PACKAGES[@]}")

  require_cmd pacman
  require_cmd sudo

  if [[ "$INSTALL_INPUT_METHOD" == true ]]; then
    packages+=("${INPUT_METHOD_PACKAGES[@]}")
  fi

  log "installing Arch packages"
  sudo pacman -Syu --needed "${packages[@]}"
}

write_user_file() {
  local target="$1"
  local mode="${2:-644}"
  local dir
  local tmp

  require_cmd cmp
  require_cmd dirname
  require_cmd install
  require_cmd mktemp

  dir="$(dirname "$target")"
  tmp="$(mktemp)"
  cat > "$tmp"

  mkdir -p "$dir"

  if [[ -f "$target" ]] && cmp -s "$tmp" "$target"; then
    log "already up to date: $target"
  else
    install -m "$mode" "$tmp" "$target"
    log "wrote $target"
  fi

  rm -f "$tmp"
}

configure_fontconfig() {
  [[ "$CONFIGURE_FONTCONFIG" == true ]] || {
    log "skipping fontconfig because CONFIGURE_FONTCONFIG=$CONFIGURE_FONTCONFIG"
    return
  }

  write_user_file "$FONTCONFIG_TARGET" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Noto Sans CJK SC</family>
      <family>Noto Sans</family>
      <family>WenQuanYi Micro Hei</family>
      <family>WenQuanYi Zen Hei</family>
      <family>Noto Color Emoji</family>
    </prefer>
  </alias>

  <alias>
    <family>serif</family>
    <prefer>
      <family>Noto Serif CJK SC</family>
      <family>Noto Serif</family>
      <family>Noto Color Emoji</family>
    </prefer>
  </alias>

  <alias>
    <family>monospace</family>
    <prefer>
      <family>Noto Sans Mono CJK SC</family>
      <family>Noto Sans Mono</family>
      <family>WenQuanYi Micro Hei Mono</family>
      <family>Noto Color Emoji</family>
    </prefer>
  </alias>
</fontconfig>
EOF

  if command -v fc-cache >/dev/null 2>&1; then
    log "refreshing font cache"
    fc-cache -f
  else
    log "fc-cache not found; font cache will refresh later"
  fi
}

configure_input_method_env() {
  [[ "$INSTALL_INPUT_METHOD" == true ]] || return
  [[ "$CONFIGURE_INPUT_METHOD_ENV" == true ]] || {
    log "skipping input method environment because CONFIGURE_INPUT_METHOD_ENV=$CONFIGURE_INPUT_METHOD_ENV"
    return
  }

  write_user_file "$USER_ENV_TARGET" <<'EOF'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
SDL_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
EOF
}

configure_fcitx_profile() {
  [[ "$INSTALL_INPUT_METHOD" == true ]] || return
  [[ "$CONFIGURE_FCITX_PROFILE" == true ]] || {
    log "skipping fcitx5 profile because CONFIGURE_FCITX_PROFILE=$CONFIGURE_FCITX_PROFILE"
    return
  }

  if [[ -f "$FCITX_PROFILE_TARGET" && "$OVERWRITE_FCITX_PROFILE" != true ]]; then
    log "keeping existing fcitx5 profile: $FCITX_PROFILE_TARGET"
    log "set OVERWRITE_FCITX_PROFILE=true to replace it with keyboard-us + pinyin"
    return
  fi

  write_user_file "$FCITX_PROFILE_TARGET" <<'EOF'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=pinyin

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=pinyin
Layout=

[GroupOrder]
0=Default
EOF
}

enable_fcitx_service() {
  [[ "$INSTALL_INPUT_METHOD" == true ]] || return
  [[ "$ENABLE_FCITX_SERVICE" == true ]] || {
    log "skipping fcitx5 service because ENABLE_FCITX_SERVICE=$ENABLE_FCITX_SERVICE"
    return
  }

  if ! command -v systemctl >/dev/null 2>&1; then
    log "systemctl not found; start fcitx5 from your desktop session instead"
    return
  fi

  if systemctl --user list-unit-files --no-legend fcitx5.service 2>/dev/null | grep -q '^fcitx5\.service'; then
    if systemctl --user enable --now fcitx5.service; then
      log "enabled and started fcitx5.service for the current user"
    else
      log "could not start fcitx5.service now; log out/in, or add fcitx5 to session autostart"
    fi
  else
    log "fcitx5.service is not available to systemd --user; add fcitx5 to session autostart"
  fi
}

main() {
  require_cmd grep
  require_cmd sed
  require_cmd tee

  if [[ "${EUID:-$(id -u)}" -eq 0 && "$ALLOW_ROOT_ZH_SETUP" != true ]]; then
    die "run as the target desktop user, not with sudo; the script calls sudo only for system files"
  fi

  install_packages
  configure_locales
  configure_fontconfig
  configure_input_method_env
  configure_fcitx_profile
  enable_fcitx_service

  log "done"
  log "log out and log back in so locale, fontconfig, and input method environment changes apply everywhere"
}

main "$@"
