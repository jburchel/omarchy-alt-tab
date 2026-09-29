-- Omalt-tab keybindings for Hyprland.
--
-- Load from ~/.config/hypr/bindings.lua (see README):
--
--   local omalt_tab = loadfile(os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.jburchel.omalt-tab/hypr/omalt-tab.lua")
--   if omalt_tab then omalt_tab()() end
--
-- How it works: MOD+TAB snapshots every window in most-recently-used order,
-- hands that to the Omalt-tab shell service and enters the "omalt-tab" submap.
-- Inside the submap TAB / SHIFT+TAB / arrows move the highlight, and letting
-- go of MOD commits. Hyprland itself resets the submap on release, so the
-- keyboard can never get stuck here even if the shell is not running.
--
-- The release binds must live in the global keymap: Hyprland matches a key
-- release against the submap that was active when that key was *pressed*,
-- and MOD goes down before the submap is entered.

return function(opts)
  opts = opts or {}
  local mod = string.upper(opts.modifier or "ALT")
  local key = opts.key or "TAB"
  local submap = "omalt-tab"

  local release_keys = ({
    -- Meta_* is what Alt reports when Shift was already held.
    ALT = { "Alt_L", "Alt_R", "Meta_L", "Meta_R" },
    SUPER = { "Super_L", "Super_R" },
    CTRL = { "Control_L", "Control_R" },
  })[mod] or { "Alt_L", "Alt_R", "Meta_L", "Meta_R" }

  local function send(message)
    hl.dispatch(hl.dsp.event("omalt-tab:" .. message))
  end

  local function snapshot()
    local windows = {}
    for _, w in ipairs(hl.get_windows()) do
      if w.mapped and w.workspace then
        windows[#windows + 1] = w
      end
    end
    table.sort(windows, function(a, b) return a.focus_history_id < b.focus_history_id end)

    local parts = {}
    for _, w in ipairs(windows) do
      parts[#parts + 1] = table.concat({
        w.address,
        tostring(w.workspace.id),
        w.monitor and w.monitor.name or "",
        w.pinned and "p" or "",
      }, "@")
    end

    local workspace = hl.get_active_workspace()
    local monitor = hl.get_active_monitor()
    local active = hl.get_active_window()
    return "ws=" .. (workspace and tostring(workspace.id) or "")
      .. ";mon=" .. (monitor and monitor.name or "")
      .. ";act=" .. (active and active.address or "")
      .. ";w=" .. table.concat(parts, ",")
  end

  local function open(direction)
    return function()
      send("open;" .. direction .. ";" .. snapshot())
      hl.dispatch(hl.dsp.submap(submap))
    end
  end

  local function relay(message)
    return function() send(message) end
  end

  local function finish(message)
    return function()
      send(message)
      hl.dispatch(hl.dsp.submap("reset"))
    end
  end

  -- Replaces Omarchy's default ALT+TAB / ALT+SHIFT+TAB (cycle windows).
  hl.unbind(mod .. " + " .. key)
  hl.unbind(mod .. " + SHIFT + " .. key)
  hl.bind(mod .. " + " .. key, open("next"), { description = "Window switcher (Omalt-tab)" })
  hl.bind(mod .. " + SHIFT + " .. key, open("prev"), { description = "Window switcher in reverse (Omalt-tab)" })

  hl.define_submap(submap, function()
    hl.bind(mod .. " + " .. key, relay("next"), { repeating = true })
    hl.bind(mod .. " + SHIFT + " .. key, relay("prev"), { repeating = true })
    hl.bind(mod .. " + right", relay("next"), { repeating = true })
    hl.bind(mod .. " + left", relay("prev"), { repeating = true })
    hl.bind(mod .. " + down", relay("down"), { repeating = true })
    hl.bind(mod .. " + up", relay("up"), { repeating = true })
    hl.bind(mod .. " + grave", relay("scope"))
    hl.bind(mod .. " + RETURN", finish("commit"))
    hl.bind(mod .. " + ESCAPE", finish("cancel"))
    hl.bind("ESCAPE", finish("cancel"))
    hl.bind("RETURN", finish("commit"))
  end)

  -- Releasing MOD commits. Global binds (see the note at the top), guarded so
  -- an ordinary Alt release does nothing. They must be transparent: once
  -- MOD+TAB fires, Hyprland shadows every bind whose key is still held, which
  -- would include these. Release binds never swallow the key,
  -- so apps still see Alt go up. Whether MOD is still in the modmask at
  -- release time varies, so bind every combination; once the first one has
  -- committed the submap is reset and the rest are no-ops.
  local commit_on_release = function()
    if hl.get_current_submap() == submap then
      send("commit")
      hl.dispatch(hl.dsp.submap("reset"))
    end
  end
  for _, release_key in ipairs(release_keys) do
    for _, mods in ipairs({ "", mod .. " + ", mod .. " + SHIFT + ", "SHIFT + " }) do
      hl.bind(mods .. release_key, commit_on_release, { release = true, transparent = true })
    end
  end
end
