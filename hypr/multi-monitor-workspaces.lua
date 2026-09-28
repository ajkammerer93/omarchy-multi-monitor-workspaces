-- Multi-Monitor Workspaces -- the Hyprland half.
--
-- Loaded on every config parse by hypr/loader.lua, which the plugin's service
-- copies into ~/.local/state/omarchy/toggles/hypr/ (the folder Omarchy's own
-- Hyprland toggles live in, sourced after the user's config). It does nothing
-- unless the plugin is enabled in ~/.config/omarchy/shell.json, so disabling
-- the plugin from the menu -- or removing it -- returns Hyprland to stock.
--
-- Stock Hyprland has one global pool of numbered workspaces: SUPER+1 creates
-- workspace 1 on whichever monitor has focus the first time, and from then on
-- jumps to wherever it lives. Here each monitor gets a slot, and slot S owns
-- the real ids S*10+1 .. S*10+10:
--
--   slot 0 (leftmost monitor)   1  2 ...  9  10
--   slot 1 (next one right)    11 12 ... 19  20
--
-- SUPER / SUPER+SHIFT / SUPER+SHIFT+ALT + the number row resolve against the
-- FOCUSED monitor, so 1 means "this monitor's 1". The plugin's bar widget
-- shows each screen only its own set, labelled 1-9/0.
--
-- Slots are ranked by position, left to right (then top to bottom), and
-- mirrors are skipped. Workspaces.qml ranks the same way; change both
-- together.
--
-- The ids are bound to their monitor with workspace rules, registered at
-- parse from the monitors present then. That binding is what makes a new
-- workspace open on the right screen, and what makes hyprtasking's overview
-- grid (if installed) show each monitor its own ids. When the set or the
-- arrangement changes, the slot map is recomputed after a short settle and,
-- if it moved, the config is reloaded: that re-registers the rules and
-- rebuilds hyprtasking's grid cache, which only refreshes on monitor
-- add/remove or reload.
--
-- A workspace that ends up on a monitor that doesn't own its id -- a monitor
-- unplugged (Hyprland moves its workspaces to a survivor), a workspace moved
-- across with SUPER+SHIFT+ALT+arrow -- is renumbered into its new monitor's
-- range with hl.dsp.workspace.change_id, keeping its digit when that is free.
-- Windows never move; only the number does.

local PLUGIN_ID = "io.github.davidboulay.multi-monitor-workspaces"
local HOME = os.getenv("HOME") or ""
local SHELL_CONFIG = HOME .. "/.config/omarchy/shell.json"
local STATE_DIR = HOME .. "/.local/state/omarchy/multi-monitor-workspaces"

local SPAN = 10
local SETTLE_MS = 1500 -- monitor profiles and output managers apply first
local ENABLED_POLL_MS = 2000

local M = {}

-- ── Enabled? ────────────────────────────────────────────────────────────────
-- A third-party plugin is enabled while its id appears in shell.json's bar
-- layout or plugins list (disabling removes the entry). Omarchy's own
-- disabledPlugins list only ever names built-ins, but it is cut out first so
-- a stray entry there can never read as enabled.
function M.enabled()
  local f = io.open(SHELL_CONFIG, "r")
  if not f then
    return false
  end
  local text = f:read("*a") or ""
  f:close()
  text = text:gsub('"disabledPlugins"%s*:%s*%b[]', "")
  return text:find('"' .. PLUGIN_ID .. '"', 1, true) ~= nil
end

local function write_status(line)
  os.execute("mkdir -p '" .. STATE_DIR .. "'")
  local f = io.open(STATE_DIR .. "/status", "w")
  if f then
    f:write(line, "\n")
    f:close()
  end
end
M.write_status = write_status

-- ── Slot map ────────────────────────────────────────────────────────────────
local function ordered_monitors()
  local list = {}
  for _, m in ipairs(hl.get_monitors() or {}) do
    if not m.is_mirror then
      table.insert(list, m)
    end
  end
  table.sort(list, function(a, b)
    if a.x ~= b.x then return a.x < b.x end
    if a.y ~= b.y then return a.y < b.y end
    return a.name < b.name
  end)
  return list
end

local function slot_map()
  local slots, parts = {}, {}
  for i, m in ipairs(ordered_monitors()) do
    slots[m.name] = i - 1
    table.insert(parts, m.name .. "=" .. (i - 1))
  end
  return slots, table.concat(parts, ",")
end

local function slot_of_id(id)
  return math.floor((id - 1) / SPAN)
end

local function digit_of_id(id)
  return (id - 1) % SPAN + 1
end

local function id_for(slot, digit)
  return slot * SPAN + digit
end

-- The id a number key means on the focused monitor.
local function target(digit)
  local slots = slot_map()
  local monitor = hl.get_active_monitor()
  local slot = monitor and slots[monitor.name] or 0
  return tostring(id_for(slot or 0, digit))
end

-- ── Renumber workspaces sitting on a monitor that doesn't own their id ──────
local function normalize()
  local slots = slot_map()
  local taken = {}
  local workspaces = hl.get_workspaces() or {}

  for _, w in ipairs(workspaces) do
    taken[w.id] = true
  end

  for _, w in ipairs(workspaces) do
    local slot = w.monitor and slots[w.monitor.name]
    if not w.special and w.id > 0 and slot and slot_of_id(w.id) ~= slot then
      local new_id
      if not taken[id_for(slot, digit_of_id(w.id))] then
        new_id = id_for(slot, digit_of_id(w.id))
      else
        for digit = 1, SPAN do
          if not taken[id_for(slot, digit)] then
            new_id = id_for(slot, digit)
            break
          end
        end
      end

      if new_id then
        local ok, err = pcall(hl.dispatch,
          hl.dsp.workspace.change_id({ workspace = tostring(w.id), id = new_id }))
        if ok then
          taken[w.id] = nil
          taken[new_id] = true
        else
          print("multi-monitor-workspaces: change_id " .. w.id .. " -> " .. new_id .. " failed: " .. tostring(err))
        end
      end
    end
  end
end

-- ── Activate ────────────────────────────────────────────────────────────────
function M.activate()
  local slots, registered_signature = slot_map()

  for name, slot in pairs(slots) do
    for digit = 1, SPAN do
      hl.workspace_rule({
        workspace = tostring(id_for(slot, digit)),
        monitor = name,
        default = digit == 1,
      })
    end
  end

  -- Same keys as Omarchy's default/hypr/bindings/tiling.lua (code:10..19 are
  -- the number row 1..0), unbound first so these replace rather than stack.
  for digit = 1, SPAN do
    local key = "code:" .. tostring(digit + 9)
    local label = digit == SPAN and "0" or tostring(digit)

    hl.unbind("SUPER + " .. key)
    hl.unbind("SUPER + SHIFT + " .. key)
    hl.unbind("SUPER + SHIFT + ALT + " .. key)

    o.bind("SUPER + " .. key, "Switch to workspace " .. label .. " (this monitor)", function()
      hl.dispatch(hl.dsp.focus({ workspace = target(digit) }))
    end)
    o.bind("SUPER + SHIFT + " .. key, "Move window to workspace " .. label .. " (this monitor)", function()
      hl.dispatch(hl.dsp.window.move({ workspace = target(digit) }))
    end)
    o.bind("SUPER + SHIFT + ALT + " .. key, "Move window silently to workspace " .. label .. " (this monitor)", function()
      hl.dispatch(hl.dsp.window.move({ workspace = target(digit), follow = false }))
    end)
  end

  -- Omarchy's SUPER+scroll walks every open workspace ("e+1"), hopping
  -- monitors. Keep it on the monitor under focus.
  hl.unbind("SUPER + mouse_down")
  hl.unbind("SUPER + mouse_up")
  o.bind("SUPER + mouse_down", "Scroll active workspace forward", hl.dsp.focus({ workspace = "m+1" }))
  o.bind("SUPER + mouse_up", "Scroll active workspace backward", hl.dsp.focus({ workspace = "m-1" }))

  hl.timer(normalize, { timeout = 300, type = "oneshot" })

  local pending
  local function recheck()
    if pending then
      pending:set_enabled(false)
    end
    pending = hl.timer(function()
      pending = nil
      local _, signature = slot_map()
      if signature ~= registered_signature then
        -- Reload re-runs this file: rules re-registered, then normalize.
        hl.exec_cmd("hyprctl reload")
      else
        normalize()
      end
    end, { timeout = SETTLE_MS, type = "oneshot" })
  end

  hl.on("monitor.added", recheck)
  hl.on("monitor.removed", recheck)
  hl.on("monitor.layout_changed", recheck)
  hl.on("workspace.move_to_monitor", function()
    hl.timer(normalize, { timeout = 100, type = "oneshot" })
  end)

  -- Disabled from the menu? The shell only edits shell.json, so watch it and
  -- reload; at the next parse this module stays inactive and stock returns.
  hl.timer(function()
    if not M.enabled() then
      hl.exec_cmd("hyprctl reload")
    end
  end, { timeout = ENABLED_POLL_MS, type = "repeat" })

  write_status("active " .. registered_signature)
end

return M
