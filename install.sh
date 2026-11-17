#!/usr/bin/env bash
# install.sh — install roneo from its latest GitHub release.
#   curl -fsSL https://raw.githubusercontent.com/lockyc/roneo/main/install.sh | bash
# Installs /Applications/roneo.app and launches it; roneo updates itself from then on.
# RONEO_ZIP_URL and RONEO_APP_DIR override the download and the install folder.
set -euo pipefail

main() {
    zip_url=${RONEO_ZIP_URL:-https://github.com/lockyc/roneo/releases/latest/download/roneo.zip}
    app_dir=${RONEO_APP_DIR:-/Applications}
    team=G9V8U6ZU5E

    fail() { echo "roneo: $*" >&2; exit 1; }

    [ "$(uname)" = Darwin ] || fail "roneo runs on macOS only."
    major=$(sw_vers -productVersion | cut -d. -f1)
    [ "$major" -ge 27 ] || fail "roneo needs macOS 27 or later; this Mac runs $(sw_vers -productVersion)."

    # Runs a command as the user, or with sudo when $1 (a directory) isn't writable.
    in_dir() {
        local dir=$1
        shift
        if [ -w "$dir" ]; then "$@"; else sudo "$@"; fi
    }

    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT

    echo "→ downloading roneo"
    curl -fsSL "$zip_url" -o "$work/roneo.zip" || fail "couldn't download $zip_url"
    ditto -x -k "$work/roneo.zip" "$work/unzipped" || fail "the download isn't a zip."
    new="$work/unzipped/roneo.app"
    [ -d "$new" ] || fail "the download holds no roneo.app."
    [ -z "$(find "$work/unzipped" -maxdepth 1 -type l)" ] && [ ! -L "$new" ] \
        || fail "the download's roneo.app is a link."
    codesign --verify --strict --deep "$new" 2>/dev/null || fail "the download's signature doesn't verify."
    info=$(codesign -dv "$new" 2>&1) || fail "the download's signature can't be read."
    printf '%s\n' "$info" | grep -qx "TeamIdentifier=$team" \
        || fail "the download isn't signed by roneo's developer."
    spctl --assess --type execute "$new" 2>/dev/null || fail "macOS won't open the download: it isn't notarized."
    version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$new/Contents/Info.plist")

    if pgrep -U "$(id -u)" -x Roneo >/dev/null; then
        echo "→ quitting the running roneo"
        pkill -U "$(id -u)" -x Roneo || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -U "$(id -u)" -x Roneo >/dev/null || break; sleep 0.5; done
        ! pgrep -U "$(id -u)" -x Roneo >/dev/null || fail "roneo didn't quit; quit it from its menu and re-run."
    fi

    target="$app_dir/roneo.app"
    echo "→ installing roneo $version to $target"
    [ -d "$app_dir" ] || in_dir "$(dirname "$app_dir")" mkdir -p "$app_dir"
    staged="$app_dir/.roneo.app.new"
    in_dir "$app_dir" rm -rf "$staged"
    in_dir "$app_dir" ditto "$new" "$staged" || fail "couldn't copy roneo into $app_dir."
    old="$app_dir/.roneo.app.old"
    in_dir "$app_dir" rm -rf "$old"
    if [ -e "$target" ]; then
        in_dir "$app_dir" mv "$target" "$old" \
            || fail "couldn't move the old $target aside. Allow your terminal in System Settings > Privacy & Security > App Management, or drag the old app to the Trash, then re-run."
    fi
    if ! in_dir "$app_dir" mv "$staged" "$target"; then
        [ ! -e "$old" ] || in_dir "$app_dir" mv "$old" "$target" || true
        fail "couldn't move roneo into place at $target."
    fi
    in_dir "$app_dir" rm -rf "$old"

    open "$target" || fail "$target didn't launch."
    echo "✓ roneo $version is in $target and running; it updates itself from here."
}

main "$@"
