#!/usr/bin/env bash
# Test the Tahoe notification daemon with real org.freedesktop.Notifications
# payloads. Run inside the VM, after the Tahoe session is up.
#
# These exercises the Quickshell.NotificationServer backing
# services/Notifications.qml:
#   - basic summary/body
#   - themed app icon (resolved via image://icon/<name>)
#   - urgency levels (Normal vs Critical -> red accent, never auto-expires)
#   - action buttons (notify-send -A)
#   - a replace-id update
#
# Requirements: libnotify (notify-send). On Arch:
#   sudo pacman -S libnotify
#
# Usage:
#   bash scripts/test-notification.sh            # default demo sequence
#   bash scripts/test-notification.sh basic
#   bash scripts/test-notification.sh icon
#   bash scripts/test-notification.sh urgent
#   bash scripts/test-notification.sh actions
#   bash scripts/test-notification.sh replace
#   bash scripts/test-notification.sh spam <n>    # queue n notifications

set -euo pipefail

if ! command -v notify-send >/dev/null 2>&1; then
    echo "notify-send not found. Install libnotify (Arch: sudo pacman -S libnotify)." >&2
    exit 1
fi

send_basic() {
    notify-send "Tahoe Test" "This is a real notification from notify-send."
}

send_icon() {
    notify-send \
        --icon=dialog-information \
        --app-name="Settings" \
        "System Update" "A new version of Tahoe is available."
}

send_urgent() {
    # urgency=critical (2) -> the toast gets a red accent border and will
    # NOT auto-expire; it only leaves when the user dismisses it.
    notify-send \
        --urgency=critical \
        --app-name="Battery" \
        "Battery Low" "You have 7% battery remaining."
}

send_actions() {
    # -A identifier=label adds an action button. Our popup renders one
    # pill per action; clicking it invokes the action and dismisses the
    # notification (unless the client set resident=true).
    notify-send \
        --app-name="Messages" \
        --icon=preferences-desktop-chat \
        --action="reply=Reply" \
        --action="dismiss=Dismiss" \
        "New Message" "Alex: hey, ready for lunch?" \
        >/dev/null || true
    echo "(action invocations are returned by notify-send; the toast buttons call the daemon directly)"
}

send_replace() {
    # A non-zero --replace-id updates the existing notification in place.
    local rid="${1:-4242}"
    notify-send --replace-id="$rid" "Installing" "Downloading… 0%"
    sleep 0.8
    notify-send --replace-id="$rid" "Installing" "Downloading… 60%"
    sleep 0.8
    notify-send --replace-id="$rid" --icon=checkbox-checked "Installing" "Done"
}

send_spam() {
    local n="${1:-5}"
    local i
    for (( i = 1; i <= n; i++ )); do
        notify-send --app-name="Spam" "Notification $i/$n" "Queued at $(date +%T)"
        sleep 0.4
    done
}

case "${1:-demo}" in
    basic)   send_basic ;;
    icon)    send_icon ;;
    urgent)  send_urgent ;;
    actions) send_actions ;;
    replace) send_replace "${2:-4242}" ;;
    spam)    send_spam "${2:-5}" ;;
    demo)
        send_basic
        sleep 2
        send_icon
        sleep 2
        send_actions
        sleep 2
        send_urgent
        ;;
    *)
        echo "Usage: $0 {basic|icon|urgent|actions|replace|spam|demo} [args]" >&2
        exit 2
        ;;
esac
