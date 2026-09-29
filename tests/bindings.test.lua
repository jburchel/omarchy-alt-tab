-- Run: lua tests/bindings.test.lua   (from the plugin directory)
-- Loads hypr/omarchy-alt-tab.lua against a stub `hl` and checks the binds it makes
-- and what they dispatch.

local function new_hl()
  local state = { binds = {}, unbinds = {}, dispatched = {}, submap = "", defining = nil }
  local hl = { dsp = {} }
  function hl.dsp.event(data) return { kind = "event", data = data } end
  function hl.dsp.submap(name) return { kind = "submap", name = name } end
  function hl.unbind(keys) state.unbinds[#state.unbinds + 1] = keys end
  function hl.bind(keys, fn, opts)
    state.binds[#state.binds + 1] = { keys = keys, fn = fn, opts = opts or {}, submap = state.defining or "" }
  end
  function hl.define_submap(name, fn)
    state.defining = name
    fn()
    state.defining = nil
  end
  function hl.dispatch(d)
    state.dispatched[#state.dispatched + 1] = d
    if d.kind == "submap" then state.submap = d.name == "reset" and "" or d.name end
  end
  function hl.get_current_submap() return state.submap end
  function hl.get_windows()
    return {
      { address = "0xb", mapped = true, focus_history_id = 1, pinned = false, workspace = { id = 2 }, monitor = { name = "DP-2" } },
      { address = "0xa", mapped = true, focus_history_id = 0, pinned = true, workspace = { id = 1 }, monitor = { name = "DP-1" } },
      { address = "0xc", mapped = false, focus_history_id = 2, workspace = { id = 1 }, monitor = { name = "DP-1" } },
      { address = "0xd", mapped = true, focus_history_id = 3, workspace = { id = -98 }, monitor = { name = "DP-1" } },
    }
  end
  function hl.get_active_workspace() return { id = 1 } end
  function hl.get_active_monitor() return { name = "DP-1" } end
  function hl.get_active_window() return { address = "0xa" } end
  return hl, state
end

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    print("FAIL: " .. msg)
  end
end

local function find(state, keys, submap, release)
  for _, b in ipairs(state.binds) do
    if b.keys == keys and b.submap == (submap or "") and (not not b.opts.release) == (release or false) then
      return b
    end
  end
end

local function events(state)
  local out = {}
  for _, d in ipairs(state.dispatched) do
    if d.kind == "event" then out[#out + 1] = d.data end
  end
  return out
end

local chunk = assert(loadfile("hypr/omarchy-alt-tab.lua"))

-- Default (ALT) -----------------------------------------------------------
do
  local hl, state = new_hl()
  _G.hl = hl
  chunk()()

  check(state.unbinds[1] == "ALT + TAB" and state.unbinds[2] == "ALT + SHIFT + TAB", "unbinds Omarchy's ALT+TAB pair")

  local open = find(state, "ALT + TAB")
  check(open ~= nil, "global ALT + TAB bind")
  check(find(state, "ALT + SHIFT + TAB") ~= nil, "global ALT + SHIFT + TAB bind")
  for _, k in ipairs({ "ALT + TAB", "ALT + SHIFT + TAB", "ALT + right", "ALT + left", "ALT + down", "ALT + up",
                       "ALT + grave", "ALT + RETURN", "ALT + ESCAPE", "ESCAPE", "RETURN" }) do
    check(find(state, k, "omarchy-alt-tab") ~= nil, "submap bind " .. k)
  end

  -- Release binds: global, release, transparent, for every modifier combo.
  local release_count = 0
  for _, b in ipairs(state.binds) do
    if b.opts.release then
      release_count = release_count + 1
      check(b.submap == "", "release bind " .. b.keys .. " is global")
      check(b.opts.transparent == true, "release bind " .. b.keys .. " is transparent")
    end
  end
  check(release_count == 16, "16 release binds (4 keys x 4 modifier combos), got " .. release_count)
  check(find(state, "Alt_L", "", true) and find(state, "ALT + Alt_L", "", true)
    and find(state, "ALT + SHIFT + Alt_L", "", true) and find(state, "SHIFT + Meta_L", "", true), "Alt_L / Meta_L variants")

  -- Opening: event payload in MRU order, unmapped window dropped, submap entered.
  open.fn()
  local ev = events(state)
  check(ev[1] == "omarchy-alt-tab:open;next;ws=1;mon=DP-1;act=0xa;w=0xa@1@DP-1@p,0xb@2@DP-2@,0xd@-98@DP-1@",
    "open payload, got " .. tostring(ev[1]))
  check(state.submap == "omarchy-alt-tab", "entered submap")

  -- Releasing Alt inside the switcher commits and resets; a second release is a no-op.
  local release = find(state, "ALT + Alt_L", "", true)
  release.fn()
  ev = events(state)
  check(ev[#ev] == "omarchy-alt-tab:commit", "release commits")
  check(state.submap == "", "release resets submap")
  local count = #state.dispatched
  find(state, "Alt_L", "", true).fn()
  check(#state.dispatched == count, "release outside the switcher does nothing")

  -- Escape cancels.
  open.fn()
  find(state, "ESCAPE", "omarchy-alt-tab").fn()
  ev = events(state)
  check(ev[#ev] == "omarchy-alt-tab:cancel" and state.submap == "", "escape cancels and resets")

  -- Reverse opening.
  find(state, "ALT + SHIFT + TAB").fn()
  ev = events(state)
  check(ev[#ev]:find("^omarchy%-alt%-tab:open;prev;") ~= nil, "shift opens in reverse")
end

-- SUPER modifier ------------------------------------------------------------
do
  local hl, state = new_hl()
  _G.hl = hl
  chunk()({ modifier = "super" })
  check(find(state, "SUPER + TAB") ~= nil, "SUPER + TAB bind")
  check(find(state, "SUPER + Super_L", "", true) ~= nil and find(state, "Super_R", "", true) ~= nil, "Super release binds")
  check(find(state, "Alt_L", "", true) == nil, "no Alt release binds with SUPER")
end

-- CTRL modifier -------------------------------------------------------------
do
  local hl, state = new_hl()
  _G.hl = hl
  chunk()({ modifier = "CTRL" })
  check(find(state, "CTRL + Control_L", "", true) ~= nil, "Control release binds")
end

-- The bindings.lua loader is a no-op when the plugin is gone.
check(loadfile("/nonexistent/omarchy-alt-tab.lua") == nil, "loadfile of a missing plugin returns nil")

if failures > 0 then
  print(failures .. " failure(s)")
  os.exit(1)
end
print("ok")
