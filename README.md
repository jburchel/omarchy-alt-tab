# Omalt-tab

Windows / macOS-style **Alt+Tab** for Omarchy.

Hold **Alt** and tap **Tab**: a switcher shows your open windows with live previews, in most-recently-used order and with the current window first. Each Tab moves the highlight one window on. Let go of Alt and Omalt-tab jumps to the highlighted window, on its own workspace, without touching your tiling.

A quick Alt+Tab tap goes straight back to the previous window, and the switcher doesn't flash on screen.

## Keys

| Keys (while holding Alt) | Action |
| --- | --- |
| Tab / → | Next window |
| Shift+Tab / ← | Previous window |
| ↓ / ↑ | Down / up a row |
| ` (backtick) | Switch scope for this switch only: all workspaces → current workspace → current monitor |
| Enter or release Alt | Switch to the highlighted window |
| Esc | Cancel |

You can also move the mouse over a card to highlight it, and click it to switch.

## Install

```sh
omarchy plugin add https://github.com/jburchel/omalt-tab.git --enable
```

Then add the keybinding to `~/.config/hypr/bindings.lua`. It replaces Omarchy's default ALT+TAB / ALT+SHIFT+TAB (focus next/previous window):

```lua
local omalt_tab = loadfile(os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.jburchel.omalt-tab/hypr/omalt-tab.lua")
if omalt_tab then omalt_tab()() end
```

Run `hyprctl reload`, then check that `hyprctl configerrors` prints nothing. If you remove the plugin, this block just skips itself and Omarchy's defaults come back.

To use a different modifier, pass options, e.g. `omalt_tab()({ modifier = "SUPER" })`. Supported modifiers are `ALT`, `SUPER` and `CTRL`.

## Settings

Open the settings panel:

```sh
omarchy-shell omalt-tab settings
```

| Setting | Values | Default |
| --- | --- | --- |
| Windows shown | All workspaces, Current workspace, Current monitor | All workspaces |
| Show switcher | Instantly, 120 ms, 250 ms, 400 ms (a delay means quick taps switch without flashing the switcher) | 120 ms |
| Cards | Live previews, App icons | Live previews |
| Workspace badges | on / off | on |
| Scratchpad windows | on / off (include special workspaces) | on |

Settings are saved in this plugin's entry in `~/.config/omarchy/shell.json`. You can also set them from scripts:

```sh
omarchy-shell omalt-tab scope workspace      # all | workspace | monitor
omarchy-shell omalt-tab showDelay 0          # 0-1000 ms
omarchy-shell omalt-tab previews off         # on | off
omarchy-shell omalt-tab workspaceBadges off  # on | off
omarchy-shell omalt-tab includeSpecial off   # on | off
omarchy-shell omalt-tab status
```

## How it works

- **Hyprland side:** `hypr/omalt-tab.lua` binds Alt+Tab. On the first press it takes a snapshot of every window, sorted by Hyprland's `focus_history_id`, and sends it to the shell as a custom event. It then enters an `omalt-tab` submap, where Tab, arrows and backtick send more events.
- **Releasing Alt:** a release bind sends `commit` and resets the submap. Hyprland does this itself, so the keyboard can't get stuck even if the shell is down.
- **Shell side:** `Switcher.qml` is an Omarchy shell service that draws the overlay. The overlay never takes keyboard focus, so your app keeps focus until the switch happens.
- **Switching:** Omalt-tab calls `hl.dsp.focus({ window = "address:…" })`. Hyprland moves to the window's workspace and leaves the layout alone.

## Development

- Run the tests with `node tests/window-list.test.js`.
- Validate the plugin with `omarchy plugin validate .`.
- Reload after editing: the shell caches service QML, so after editing `Switcher.qml` or `SwitcherCard.qml` run `omarchy restart shell`. The settings overlay reloads on save.

## License

MIT
