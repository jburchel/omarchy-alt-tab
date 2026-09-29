#!/bin/bash
# End-to-end tests against the live Hyprland session and Omarchy shell.
#
# Spawns throwaway foot windows (class alttab-test-*) on a spare workspace,
# replays exactly what hypr/omarchy-alt-tab.lua dispatches (its real snapshot code,
# the submap, the shell events) and checks the switcher's state and the
# window that ends up focused. Physical key handling (Alt release) cannot be
# injected; tests/bindings.test.lua covers how those binds are registered.
#
# Your focus, cursor, settings and submap are restored afterwards, and the
# test windows are closed. Needs: hyprctl, jq, foot, omarchy-shell.
#
# Usage: tests/e2e.sh [screenshot-dir]

set -u
PLUGIN_DIR=$(cd "$(dirname "$0")/.." && pwd)
SHOTS=${1:-}
SNAP=$(sed -n '/local function snapshot()/,/^  end$/p' "$PLUGIN_DIR/hypr/omarchy-alt-tab.lua")

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [[ -n ${2:-} ]] && printf '       %s\n' "$2"; }
eq() { if [[ $2 == "$3" ]]; then ok "$1"; else bad "$1" "got: $2 | want: $3"; fi; }
section() { printf '\n%s\n' "$1"; }

state() { omarchy-shell omarchy-alt-tab state; }
st() { state | jq -r "$1"; }
ipc() {
  for _ in 1 2 3; do omarchy-shell omarchy-alt-tab "$@" >/dev/null 2>&1 && break; sleep 0.3; done
  sleep 0.15
}
send() { hyprctl dispatch "hl.dsp.event(\"omarchy-alt-tab:$1\")" >/dev/null; sleep 0.12; }
open() {
  hyprctl eval "$SNAP
hl.dispatch(hl.dsp.event('omarchy-alt-tab:open;${1:-next};' .. snapshot()))
hl.dispatch(hl.dsp.submap('omarchy-alt-tab'))" >/dev/null
  sleep 0.3
}
# What the global Alt-release bind does.
release() {
  hyprctl eval "if hl.get_current_submap() == 'omarchy-alt-tab' then
hl.dispatch(hl.dsp.event('omarchy-alt-tab:commit'))
hl.dispatch(hl.dsp.submap('reset'))
end" >/dev/null
  sleep 0.6
}
cancel() { send cancel; hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null; sleep 0.2; }
active() { hyprctl activewindow -j | jq -r '.address // ""'; }
focus() { hyprctl dispatch "hl.dsp.focus({ window = \"address:$1\" })" >/dev/null; sleep 0.35; }
mru() { hyprctl clients -j | jq -r 'map(select(.mapped)) | sort_by(.focusHistoryID) | .[].address'; }
addr_of() { hyprctl clients -j | jq -r --arg c "$1" '.[] | select(.class == $c) | .address'; }
layer_up() { hyprctl layers -j | jq '[.. | objects | select(.namespace? == "omarchy-alt-tab")] | length > 0'; }
shot() { [[ -n $SHOTS ]] && grim -o "$(hyprctl monitors -j | jq -r '.[] | select(.focused).name')" "$SHOTS/$1.png"; }
sorted() { jq -c 'sort'; }

command -v foot >/dev/null || { echo "foot is required"; exit 2; }
# The shell reloads a plugin whenever a file in its folder changes, and its IPC
# target is briefly gone while it does; wait for three answers in a row.
streak=0
for _ in $(seq 40); do
  if state >/dev/null 2>&1; then streak=$((streak + 1)); (( streak >= 3 )) && break; else streak=0; fi
  sleep 0.25
done
(( streak >= 3 )) || { echo "Omarchy Alt-Tab service is not running in omarchy-shell"; exit 2; }
[[ -n $SHOTS ]] && mkdir -p "$SHOTS"

# --- setup / teardown --------------------------------------------------------
ORIG=$(active)
CURSOR=$(hyprctl cursorpos)
SETTINGS=$(omarchy-shell omarchy-alt-tab status)
used=$(hyprctl workspaces -j | jq -r '.[].id')
TW=""
for n in $(seq 11 40); do grep -qx "$n" <<<"$used" || { TW=$n; break; }; done
EMPTY=$((TW + 1))

teardown() {
  cancel >/dev/null 2>&1
  for c in alttab-test-1 alttab-test-2 alttab-test-3; do
    a=$(addr_of $c)
    [[ -n $a ]] && hyprctl dispatch "hl.dsp.window.close({ window = \"address:$a\" })" >/dev/null
  done
  jq -r 'to_entries[] | "\(.key) \(.value)"' <<<"$SETTINGS" | while read -r k v; do
    case $v in true) v=on ;; false) v=off ;; esac
    ipc "$k" "$v"
  done
  [[ $(omarchy-shell omarchy-alt-tab status) == "$SETTINGS" ]] || echo "WARNING: settings not restored; were: $SETTINGS"
  [[ -n $ORIG ]] && hyprctl dispatch "hl.dsp.focus({ window = \"address:$ORIG\" })" >/dev/null
  IFS=', ' read -r X Y <<<"$CURSOR"
  hyprctl dispatch "hl.dsp.cursor.move({ x = $X, y = $Y })" >/dev/null
}
trap teardown EXIT

for i in 1 2 3; do
  hyprctl eval "hl.exec_cmd('foot -a alttab-test-$i sleep 300', { workspace = '$TW silent' })" >/dev/null
done
for _ in $(seq 30); do [[ $(hyprctl clients -j | jq '[.[] | select(.class | startswith("alttab-test-"))] | length') == 3 ]] && break; sleep 0.2; done
T1=$(addr_of alttab-test-1); T2=$(addr_of alttab-test-2); T3=$(addr_of alttab-test-3)
[[ -n $T1 && -n $T2 && -n $T3 ]] || { echo "could not spawn test windows"; exit 2; }
echo "test windows on workspace $TW: $T1 $T2 $T3"
ipc scope all; ipc showDelay 0; ipc includeSpecial on; ipc previews on; ipc workspaceBadges on
# Focus order T3, T2, T1 so the MRU on the test workspace is T1, T2, T3.
focus "$T3"; focus "$T2"; focus "$T1"

# --- tests ---------------------------------------------------------------------
section "Opening and switching"
M=($(mru))
open next
eq "session is active after MOD+TAB" "$(st .active)" true
eq "current window heads the list" "$(st '.windows[0]')" "${M[0]}"
eq "list is in most-recently-used order" "$(st '.windows | join(" ")')" "${M[*]}"
eq "first Tab selects the previous window" "$(st .selected)" "${M[1]}"
eq "switcher is on screen (showDelay 0)" "$(st .shown)" true
eq "overlay layer is mapped" "$(layer_up)" true
eq "switcher is on the focused monitor" "$(st .screen)" "$(hyprctl monitors -j | jq -r '.[] | select(.focused).name')"
eq "overlay does not take focus" "$(active)" "$T1"
shot 01-open-all
release
eq "release focuses the selected window" "$(active)" "${M[1]}"
eq "release ends the session" "$(st .active)" false
eq "release leaves the submap" "$(hyprctl submap)" default
eq "overlay layer is unmapped" "$(layer_up)" false

section "Stepping"
focus "$T1"; M=($(mru)); N=${#M[@]}
open next; send next
eq "Tab moves one window on" "$(st .selected)" "${M[2]}"
send prev
eq "Shift+Tab moves one window back" "$(st .selected)" "${M[1]}"
for ((i = 0; i < N - 1; i++)); do send next; done
eq "stepping wraps around the end" "$(st .selectedIndex)" 0
send prev
eq "stepping back wraps to the last window" "$(st .selectedIndex)" "$((N - 1))"
C=$(st .columns)
send next; send down
eq "down moves one row (columns=$C)" "$(st .selectedIndex)" "$(( C % N ))"
send up
eq "up moves one row back" "$(st .selectedIndex)" 0
cancel
open prev
eq "MOD+SHIFT+TAB starts at the last window" "$(st .selected)" "${M[N - 1]}"
cancel
open next; send next; open next
eq "re-opening resets the selection" "$(st .selected)" "${M[1]}"
cancel

section "Cancel and stray events"
focus "$T1"
open next; send next; cancel
eq "Escape keeps the current window" "$(active)" "$T1"
eq "Escape ends the session" "$(st .active)" false
send next; send commit
eq "events without a session are ignored" "$(active)" "$T1"
eq "no session was started by stray events" "$(st .active)" false

section "Show delay"
ipc showDelay 400
focus "$T1"; M=($(mru))
hyprctl eval "$SNAP
hl.dispatch(hl.dsp.event('omarchy-alt-tab:open;next;' .. snapshot()))
hl.dispatch(hl.dsp.submap('omarchy-alt-tab'))
hl.dispatch(hl.dsp.event('omarchy-alt-tab:commit'))
hl.dispatch(hl.dsp.submap('reset'))" >/dev/null
sleep 0.6
eq "quick tap switches to the previous window" "$(active)" "${M[1]}"
eq "quick tap never shows the switcher" "$(st .lastSessionShown)" false
focus "$T1"
open next
eq "switcher is hidden during the delay" "$(st .shown)" false
sleep 0.5
eq "switcher appears after the delay" "$(st .shown)" true
cancel
open next; send next
eq "stepping shows the switcher before the delay" "$(st .shown)" true
cancel
ipc showDelay 0

section "Scopes"
focus "$T1"
ipc scope workspace
open next
want=$(hyprctl clients -j | jq -c --argjson ws "$TW" '[.[] | select(.mapped and (.workspace.id == $ws or .pinned)) | .address] | sort')
eq "workspace scope lists this workspace's windows" "$(st '.windows' | sorted)" "$want"
eq "workspace scope still starts on the previous window" "$(st .selected)" "$T2"
release
eq "workspace scope switches within the workspace" "$(active)" "$T2"
focus "$T1"
ipc scope monitor
open next
mon=$(hyprctl monitors -j | jq -r '.[] | select(.focused).name')
want=$(hyprctl clients -j | jq -c --arg m "$mon" '(input | map({(.id | tostring): .name}) | add) as $names
  | [.[] | select(.mapped and ($names[.monitor | tostring] == $m)) | .address] | sort' - <(hyprctl monitors -j))
eq "monitor scope lists the focused monitor's windows" "$(st '.windows' | sorted)" "$want"
cancel
ipc scope all
open next
all=$(st '.windows | length')
send scope
eq "backtick switches to the current workspace" "$(st .scope)" workspace
eq "... and filters the list" "$(st '.windows | length')" 3
send scope
eq "backtick again switches to the current monitor" "$(st .scope)" monitor
send scope
eq "backtick again returns to all workspaces" "$(st .scope)" all
eq "... with the full list back" "$(st '.windows | length')" "$all"
cancel
eq "backtick does not change the saved scope" "$(omarchy-shell omarchy-alt-tab status | jq -r .scope)" all

section "Special workspaces"
hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:alttabtest\", follow = false, window = \"address:$T3\" })" >/dev/null
sleep 0.4
focus "$T1"
ipc includeSpecial off
open next
eq "special-workspace windows are hidden when off" "$(st --arg a "$T3" '.windows | index($a) == null' 2>/dev/null || state | jq --arg a "$T3" '.windows | index($a) == null')" true
cancel
ipc includeSpecial on
open next
idx=$(state | jq --arg a "$T3" '.windows | index($a)')
if [[ $idx == null ]]; then bad "special-workspace windows are listed when on"; else ok "special-workspace windows are listed when on"; fi
cur=$(st .selectedIndex)
for ((i = cur; i != idx; i = (i + 1) % $(st '.windows | length'))); do send next; done
eq "can select the scratchpad window" "$(st .selected)" "$T3"
release
eq "switching to it opens the special workspace" "$(active)" "$T3"
hyprctl dispatch "hl.dsp.window.move({ workspace = \"$TW\", follow = false, window = \"address:$T3\" })" >/dev/null
sleep 0.4

section "Windows closing while the switcher is open"
focus "$T3"; focus "$T2"; focus "$T1"
ipc scope workspace
open next; send next
eq "selected the third window" "$(st .selected)" "$T3"
hyprctl dispatch "hl.dsp.window.close({ window = \"address:$T2\" })" >/dev/null
sleep 0.6
eq "closed window leaves the list" "$(state | jq --arg a "$T2" '.windows | index($a) == null')" true
eq "selection stays on the same window" "$(st .selected)" "$T3"
release
eq "switch still lands on the selected window" "$(active)" "$T3"
hyprctl eval "hl.exec_cmd('foot -a alttab-test-2 sleep 300', { workspace = '$TW silent' })" >/dev/null
for _ in $(seq 30); do T2=$(addr_of alttab-test-2); [[ -n $T2 ]] && break; sleep 0.2; done
ipc scope all

section "Empty workspace"
hyprctl dispatch "hl.dsp.focus({ workspace = \"$EMPTY\" })" >/dev/null
sleep 0.4
M=($(mru))
open next
eq "with nothing focused the most recent window is selected" "$(st .selected)" "${M[0]}"
release
eq "... and switching goes there" "$(active)" "${M[0]}"

section "Multiple monitors"
mons=$(hyprctl monitors -j | jq length)
if (( mons < 2 )); then
  ok "skipped (one monitor)"
else
  focus "$T1"
  here=$(hyprctl monitors -j | jq -r '.[] | select(.focused).name')
  open next
  other=$(hyprctl clients -j | jq -r --arg h "$here" '(input | map({(.id | tostring): .name}) | add) as $n
    | map(select(.mapped and $n[.monitor | tostring] != $h)) | sort_by(.focusHistoryID) | .[0].address' - <(hyprctl monitors -j))
  idx=$(state | jq --arg a "$other" '.windows | index($a)')
  n=$(st '.windows | length')
  for ((i = $(st .selectedIndex); i != idx; i = (i + 1) % n)); do send next; done
  release
  eq "switching to a window on the other monitor" "$(active)" "$other"
  eq "... moves focus to that monitor" "$(hyprctl monitors -j | jq -r '.[] | select(.focused).name')" \
    "$(hyprctl clients -j | jq -r --arg a "$other" '(input | map({(.id | tostring): .name}) | add) as $n | .[] | select(.address == $a) | $n[.monitor | tostring]' - <(hyprctl monitors -j))"
  open next
  eq "the switcher follows the focused monitor" "$(st .screen)" "$(hyprctl monitors -j | jq -r '.[] | select(.focused).name')"
  cancel
fi

section "Fullscreen"
focus "$T1"
hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "fullscreen" })' >/dev/null
sleep 0.5
open next
eq "switcher maps over a fullscreen window" "$(layer_up)" true
shot 02-over-fullscreen
release
eq "switching away from a fullscreen window" "$(active)" "$(mru | sed -n 1p)"
focus "$T1"
hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "fullscreen" })' >/dev/null
sleep 0.4

section "Appearance settings"
focus "$T1"
ipc previews off
open next
eq "icon mode opens" "$(layer_up)" true
shot 03-icons
cancel
ipc previews on; ipc workspaceBadges off
open next
shot 04-no-badges
cancel
ipc workspaceBadges on

section "Settings IPC"
eq "rejects an unknown scope" "$(omarchy-shell omarchy-alt-tab scope sideways)" "expected all, workspace or monitor"
eq "clamps showDelay to 1000 ms" "$(omarchy-shell omarchy-alt-tab showDelay 5000)" 1000
saved=""
for _ in $(seq 20); do
  saved=$(jq -r '.plugins[] | select(.id == "io.github.jburchel.omarchy-alt-tab") | .showDelay' ~/.config/omarchy/shell.json)
  [[ $saved == 1000 ]] && break
  sleep 0.1
done
eq "saves settings to shell.json" "$saved" 1000
ipc showDelay 0

section "Shell log"
id=$(ls -t "$XDG_RUNTIME_DIR/quickshell/by-id" | head -1)
warnings=$(quickshell log --id "$id" 2>/dev/null | grep -F "io.github.jburchel.omarchy-alt-tab/" | grep -iE "warn|error|TypeError|ReferenceError" | sort -u)
if [[ -z $warnings ]]; then ok "no QML warnings from the plugin"; else bad "QML warnings from the plugin" "$warnings"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
