#!/bin/zsh
# Captures the documentation screenshots with the demo vault, in English and German.
#
#   docs/images/capture-screenshots.sh [path/to/VaultSearch.app]
#
# Requirements: the Terminal (or the app running this script) needs Accessibility and
# Screen Recording permission (System Settings ▸ Privacy & Security). Your own settings
# and vault are not changed: vault, language and templates are passed as launch
# arguments only. The clipboard is restored at the end.
#
# Output: docs/images/<lang>/main-window.png, tag-search.png, settings-export.png,
#         settings-templates.png, about.png
set -euo pipefail

cd "${0:A:h}/../.."
ROOT=$PWD
APP=${1:-$(ls -d ~/Library/Developer/Xcode/DerivedData/VaultSearch-*/Build/Products/Debug/VaultSearch.app 2>/dev/null | head -1)}
[[ -d "$APP" ]] || { echo "VaultSearch.app not found. Build the app or pass its path."; exit 1; }
VAULT="$ROOT/docs/demo-vault"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Small helper: prints the CGWindowID of a VaultSearch window by title (or the largest one).
cat > "$TMP/wid.swift" <<'EOF'
import CoreGraphics
let wanted = CommandLine.arguments.dropFirst().first ?? ""
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]])
    .filter { ($0[kCGWindowOwnerName as String] as? String) == "VaultSearch" && ($0[kCGWindowLayer as String] as? Int) == 0 }
func area(_ w: [String: Any]) -> Double {
    let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    return (b["Width"] ?? 0) * (b["Height"] ?? 0)
}
let match = wanted.isEmpty
    ? windows.max { area($0) < area($1) }
    : windows.first { ($0[kCGWindowName as String] as? String) == wanted }
if let id = match?[kCGWindowNumber as String] { print(id) }
EOF
swiftc -o "$TMP/wid" "$TMP/wid.swift"

CLIPBOARD=$(pbpaste)
restore_clipboard() { printf '%s' "$CLIPBOARD" | pbcopy; rm -rf "$TMP"; }
trap restore_clipboard EXIT

ui() { osascript -e "tell application \"System Events\" to tell process \"VaultSearch\" to $1" >/dev/null; }
key() { osascript -e "tell application \"System Events\" to keystroke \"$1\" using {$2}" >/dev/null; }

search() {
    printf '%s' "$1" | pbcopy
    key f "command down"; sleep 0.3
    key a "command down"; key v "command down"
    sleep 1.2
    osascript -e 'tell application "System Events" to key code 36' >/dev/null   # ↩ closes suggestions, selects the top hit
    sleep 1
}

shoot() {  # shoot <file> [window title]
    local id
    id=$("$TMP/wid" "${2:-}")
    [[ -n "$id" ]] || { echo "  window '${2:-main}' not found"; return 1; }
    screencapture -x -l "$id" "$1"
    sips -Z 1800 "$1" >/dev/null
    echo "  $1"
}

capture() {  # capture <lang> <about window title>
    local lang=$1 about=$2 out="$ROOT/docs/images/$1"
    mkdir -p "$out"
    echo "[$lang]"
    osascript -e 'quit app "VaultSearch"' 2>/dev/null || true
    sleep 1
    open "$APP" --args -AppleLanguages "($lang)" -vaultPath "$VAULT" \
        -excludedFolders "()" -exportTemplates "{}" -exportFolder "VaultSearch Exports" -pdfEngine "" \
        -usePandoc "<true/>" -openAfterExport "<true/>" -highlightMatchesInExport "<true/>" -resultPreviewStyle excerpt
    sleep 4
    osascript -e 'tell application "VaultSearch" to activate' >/dev/null
    sleep 0.5
    ui "set position of window 1 to {60, 60}"
    ui "set size of window 1 to {1180, 740}"

    search "battery"
    key g "command down"; sleep 0.8          # second match in the note
    shoot "$out/main-window.png"

    search "tag:idea"
    shoot "$out/tag-search.png"

    key "," "command down"; sleep 1.2
    ui 'click button "Export" of toolbar 1 of window 1'; sleep 0.8
    shoot "$out/settings-export.png" "Export"
    ui 'set value of scroll bar 1 of scroll area 1 of group 1 of window 1 to 1.0'; sleep 0.6
    shoot "$out/settings-templates.png" "Export"
    key w "command down"; sleep 0.5

    ui "click menu item \"$about\" of menu 1 of menu bar item 2 of menu bar 1"; sleep 1.2
    shoot "$out/about.png" "$about"

    osascript -e 'quit app "VaultSearch"' >/dev/null
    sleep 1
}

capture en "About VaultSearch"
capture de "Über VaultSearch"
echo "Done."
