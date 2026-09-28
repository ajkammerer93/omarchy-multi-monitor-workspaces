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
-- jumps to wherever it lives. Here every SCREEN gets a block of ids, and
-- block B owns the real ids B*10+1 .. B*10+10:
--
--   block 0   1  2 ...  9  10      shown as 1-9, 0 on that screen
--   block 1  11 12 ... 19  20
--
-- Blocks belong to the screen, not the connector: they are keyed by the
-- monitor's description (plus the connector name when two identical panels
-- describe themselves alike) and remembered in
-- ~/.local/state/omarchy/multi-monitor-workspaces/blocks, so a screen keeps
-- its numbers across unplug, replug, a different dock port, and reboots.
-- A new screen takes the lowest free block; on first run, screens are handed
-- blocks left to right, so the leftmost one gets the plain 1-9.
--
-- The ids are bound to their screen with workspace rules, registered at parse
-- from the monitors present then. That binding is what makes a new workspace
-- open on the right screen, what brings a returning screen's workspaces home
-- on reload, and what makes hyprtasking's overview grid (if installed) show
-- each monitor its own ids. Unplugging a screen PARKS its workspaces on a
-- survivor, windows and all; they keep their ids, the bar shows them as a
-- glyph, and they go home when the screen returns.
--
-- Workspaces.qml reads the same blocks file; change both together.

local VERSION = "1.1.0"
local PLUGIN_ID = "io.github.davidboulay.multi-monitor-workspaces"
local HOME = os.getenv("HOME") or ""
local SHELL_CONFIG = HOME .. "/.config/omarchy/shell.json"
local USER_HYPR = HOME .. "/.config/hypr"
local STATE_DIR = HOME .. "/.local/state/omarchy/multi-monitor-workspaces"
local BLOCKS_FILE = STATE_DIR .. "/blocks"
local SETTINGS_FILE = STATE_DIR .. "/settings"

local SPAN = 10
local SETTLE_MS = 1500 -- monitor profiles and output managers apply first
local POLL_MS = 2000

local M = { version = VERSION }

-- ── Small file helpers ──────────────────────────────────────────────────────
local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

local function write_file(path, text)
  os.execute("mkdir -p '" .. STATE_DIR .. "'")
  local f = io.open(path, "w")
  if not f then return false end
  f:write(text)
  f:close()
  return true
end

function M.write_status(line)
  write_file(STATE_DIR .. "/status", line .. "\n")
end

-- ── Enabled? ────────────────────────────────────────────────────────────────
-- A third-party plugin is enabled while its id appears in shell.json's bar
-- layout or plugins list (disabling removes the entry). Omarchy's own
-- disabledPlugins list only ever names built-ins, but it is cut out first so
-- a stray entry there can never read as enabled.
function M.enabled()
  local text = read_file(SHELL_CONFIG) or ""
  text = text:gsub('"disabledPlugins"%s*:%s*%b[]', "")
  return text:find('"' .. PLUGIN_ID .. '"', 1, true) ~= nil
end

-- ── Settings (projected from the bar widget's shell.json entry) ─────────────
-- The widget writes key=value lines here; a change is picked up by the poll
-- below and applied with a reload.
local function load_settings()
  local text = read_file(SETTINGS_FILE) or ""
  local s = { count = SPAN, extra_keys = true }
  local count = tonumber(text:match("count=(%d+)"))
  if count then s.count = math.max(1, math.min(SPAN, count)) end
  if text:match("extra_keys=0") then s.extra_keys = false end
  return s, text
end

-- ── Keys the user bound themselves are left alone ───────────────────────────
-- This file loads AFTER ~/.config/hypr, so anything it binds would silently
-- override the user's own choice (an overview on SUPER+TAB, say). Every key
-- is checked against the user's config first, comments stripped and spacing
-- ignored.
local user_config
local function user_binds(keys)
  if not user_config then
    local parts = {}
    local handle = io.popen("find '" .. USER_HYPR .. "' -name '*.lua' -type f 2>/dev/null")
    if handle then
      for path in handle:lines() do
        for line in (read_file(path) or ""):gmatch("[^\n]*") do
          local code = line:gsub("%-%-.*$", "")
          table.insert(parts, code)
        end
      end
      handle:close()
    end
    user_config = table.concat(parts, "\n"):lower():gsub("%s+", "")
  end
  local needle = '"' .. keys:lower():gsub("%s+", "") .. '"'
  return user_config:find(needle, 1, true) ~= nil
end

local function bind(keys, description, fn)
  if user_binds(keys) then return false end
  hl.unbind(keys)
  o.bind(keys, description, fn)
  return true
end

-- ── Screens and their blocks ────────────────────────────────────────────────
local function screens()
  local list, by_desc = {}, {}
  for _, m in ipairs(hl.get_monitors() or {}) do
    if not m.is_mirror then
      table.insert(list, m)
      local d = m.description or ""
      by_desc[d] = (by_desc[d] or 0) + 1
    end
  end
  for _, m in ipairs(list) do
    local d = m.description or ""
    if d == "" then
      m.mmw_key = m.name
    elseif by_desc[d] > 1 then
      m.mmw_key = d .. "@" .. m.name
    else
      m.mmw_key = d
    end
  end
  table.sort(list, function(a, b)
    if a.x ~= b.x then return a.x < b.x end
    if a.y ~= b.y then return a.y < b.y end
    return a.name < b.name
  end)
  return list
end

local function load_blocks()
  local by_key, by_block = {}, {}
  for line in (read_file(BLOCKS_FILE) or ""):gmatch("[^\n]+") do
    local block, key = line:match("^(%d+)\t(.+)$")
    if block then
      block = tonumber(block)
      by_key[key] = block
      by_block[block] = key
    end
  end
  return by_key, by_block
end

local function save_blocks(by_block)
  local ids = {}
  for block in pairs(by_block) do table.insert(ids, block) end
  table.sort(ids)
  local lines = {}
  for _, block in ipairs(ids) do
    table.insert(lines, block .. "\t" .. by_block[block])
  end
  write_file(BLOCKS_FILE, table.concat(lines, "\n") .. "\n")
end

-- name -> block for the screens present, assigning new blocks as needed.
local function block_map()
  local list = screens()
  local by_key, by_block = load_blocks()
  local changed = false

  for _, m in ipairs(list) do
    if by_key[m.mmw_key] == nil then
      local block = 0
      while by_block[block] ~= nil do block = block + 1 end
      by_key[m.mmw_key] = block
      by_block[block] = m.mmw_key
      changed = true
    end
  end
  if changed then save_blocks(by_block) end

  local by_name, owner_name, parts = {}, {}, {}
  for _, m in ipairs(list) do
    local block = by_key[m.mmw_key]
    by_name[m.name] = block
    owner_name[block] = m.name
    table.insert(parts, m.name .. "=" .. block)
  end
  table.sort(parts)
  return {
    list = list,
    by_name = by_name,       -- connector -> block, present screens
    owner_name = owner_name, -- block -> connector, present screens
    by_block = by_block,     -- block -> screen key, every screen ever seen
    signature = table.concat(parts, ","),
  }
end

local function block_of_id(id) return math.floor((id - 1) / SPAN) end
local function digit_of_id(id) return (id - 1) % SPAN + 1 end
local function id_for(block, digit) return block * SPAN + digit end

local function focused_block(map)
  local monitor = hl.get_active_monitor()
  return monitor and map.by_name[monitor.name] or 0, monitor
end

-- ── Keep workspaces on their own screen ─────────────────────────────────────
-- For each workspace, compare the screen it is on with the screen that owns
-- its block:
--   same screen                  fine
--   owner present elsewhere      misplaced -> move it home
--   owner known but unplugged    parked -> leave it (the bar shows it)
--   block nobody owns            renumber it into its current screen's block
local function normalize()
  local map = block_map()
  local taken, homeward = {}, {}
  local workspaces = hl.get_workspaces() or {}

  for _, w in ipairs(workspaces) do taken[w.id] = true end

  for _, w in ipairs(workspaces) do
    local here = w.monitor and map.by_name[w.monitor.name]
    if not w.special and w.id > 0 and here ~= nil then
      local owner = block_of_id(w.id)
      if owner ~= here then
        if map.owner_name[owner] then
          table.insert(homeward, { id = w.id, monitor = map.owner_name[owner] })
        elseif not map.by_block[owner] then
          local new_id
          if not taken[id_for(here, digit_of_id(w.id))] then
            new_id = id_for(here, digit_of_id(w.id))
          else
            for digit = 1, SPAN do
              if not taken[id_for(here, digit)] then
                new_id = id_for(here, digit)
                break
              end
            end
          end
          if new_id then
            local ok = pcall(hl.dispatch,
              hl.dsp.workspace.change_id({ workspace = tostring(w.id), id = new_id }))
            if ok then
              taken[w.id] = nil
              taken[new_id] = true
            end
          end
        end
      end
    end
  end

  -- workspace.move only acts on the FOCUSED workspace, so visit each one and
  -- put every screen's view (and the focus) back afterwards.
  if #homeward > 0 then
    local focused = hl.get_active_workspace()
    local showing = {}
    for _, m in ipairs(map.list) do
      local ws = hl.get_active_workspace(m.name)
      if ws and not ws.special then showing[m.name] = ws.id end
    end

    for _, item in ipairs(homeward) do
      pcall(hl.dispatch, hl.dsp.focus({ workspace = tostring(item.id) }))
      pcall(hl.dispatch, hl.dsp.workspace.move({ monitor = item.monitor }))
    end

    for _, id in pairs(showing) do
      pcall(hl.dispatch, hl.dsp.focus({ workspace = tostring(id) }))
    end
    if focused and not focused.special then
      pcall(hl.dispatch, hl.dsp.focus({ workspace = tostring(focused.id) }))
    end
  end
end

-- ── Per-screen history (for "former workspace") ─────────────────────────────
local current, previous = {}, {}
local function track()
  for _, m in ipairs(hl.get_monitors() or {}) do
    local ws = hl.get_active_workspace(m.name)
    if ws and not ws.special and ws.id ~= current[m.name] then
      previous[m.name] = current[m.name]
      current[m.name] = ws.id
    end
  end
end

-- ── Cross-screen helpers ────────────────────────────────────────────────────
local function center(m)
  local scale = m.scale or 1
  return m.x + m.width / scale / 2, m.y + m.height / scale / 2
end

local function monitor_toward(from, dir)
  local fx, fy = center(from)
  local best, best_distance
  for _, m in ipairs(screens()) do
    if m.name ~= from.name then
      local x, y = center(m)
      local dx, dy = x - fx, y - fy
      local ok = (dir == "l" and dx < 0 and math.abs(dx) >= math.abs(dy))
        or (dir == "r" and dx > 0 and math.abs(dx) >= math.abs(dy))
        or (dir == "u" and dy < 0 and math.abs(dy) > math.abs(dx))
        or (dir == "d" and dy > 0 and math.abs(dy) > math.abs(dx))
      local distance = dx * dx + dy * dy
      if ok and (not best or distance < best_distance) then
        best, best_distance = m, distance
      end
    end
  end
  return best
end

-- Every window on this workspace goes to the workspace showing on the screen
-- in that direction, and focus follows. Workspaces themselves stay put: each
-- belongs to its screen.
local function send_workspace_windows(dir)
  return function()
    local from = hl.get_active_monitor()
    local source = hl.get_active_workspace()
    if not from or not source or source.special then return end
    local to = monitor_toward(from, dir)
    if not to then return end
    local target = hl.get_active_workspace(to.name)
    if not target then return end
    for _, w in ipairs(hl.get_workspace_windows(tostring(source.id)) or {}) do
      pcall(hl.dispatch, hl.dsp.window.move({
        workspace = tostring(target.id), window = "address:" .. w.address, follow = false,
      }))
    end
    pcall(hl.dispatch, hl.dsp.focus({ workspace = tostring(target.id) }))
  end
end

-- ── Activate ────────────────────────────────────────────────────────────────
function M.activate()
  local settings, settings_text = load_settings()
  local map = block_map()
  local count = settings.count

  for name, block in pairs(map.by_name) do
    for digit = 1, SPAN do
      hl.workspace_rule({
        workspace = tostring(id_for(block, digit)),
        monitor = name,
        default = digit == 1,
      })
    end
  end

  local function target(digit)
    local block = focused_block(block_map())
    return tostring(id_for(block, digit))
  end

  -- The number row (code:10..19 = 1..0), same keys as Omarchy's
  -- default/hypr/bindings/tiling.lua. Keys past `count` are unbound rather
  -- than left global, so they can't pull focus to another screen.
  for digit = 1, SPAN do
    local key = "code:" .. tostring(digit + 9)
    local label = digit == SPAN and "0" or tostring(digit)
    if digit <= count then
      bind("SUPER + " .. key, "Switch to workspace " .. label .. " (this monitor)", function()
        hl.dispatch(hl.dsp.focus({ workspace = target(digit) }))
      end)
      bind("SUPER + SHIFT + " .. key, "Move window to workspace " .. label .. " (this monitor)", function()
        hl.dispatch(hl.dsp.window.move({ workspace = target(digit) }))
      end)
      bind("SUPER + SHIFT + ALT + " .. key, "Move window silently to workspace " .. label .. " (this monitor)", function()
        hl.dispatch(hl.dsp.window.move({ workspace = target(digit), follow = false }))
      end)
    else
      for _, mods in ipairs({ "SUPER + ", "SUPER + SHIFT + ", "SUPER + SHIFT + ALT + " }) do
        if not user_binds(mods .. key) then hl.unbind(mods .. key) end
      end
    end
  end

  -- Next / previous slot on this screen, wrapping within 1..count. Empty
  -- slots count too: Hyprland deletes a workspace when its last window
  -- closes, so cycling only live ones would usually be a cycle of one.
  local function step(delta)
    return function()
      local block = focused_block(block_map())
      local ws = hl.get_active_workspace()
      local digit = (ws and not ws.special and block_of_id(ws.id) == block) and digit_of_id(ws.id) or 1
      digit = (digit - 1 + delta) % count + 1
      hl.dispatch(hl.dsp.focus({ workspace = tostring(id_for(block, digit)) }))
    end
  end

  bind("SUPER + mouse_down", "Next workspace (this monitor)", step(1))
  bind("SUPER + mouse_up", "Previous workspace (this monitor)", step(-1))

  if settings.extra_keys then
    bind("SUPER + TAB", "Next workspace (this monitor)", step(1))
    bind("SUPER + SHIFT + TAB", "Previous workspace (this monitor)", step(-1))
    bind("SUPER + CTRL + TAB", "Former workspace (this monitor)", function()
      local monitor = hl.get_active_monitor()
      local id = monitor and previous[monitor.name]
      if id then hl.dispatch(hl.dsp.focus({ workspace = tostring(id) })) end
    end)
    for dir, arrow in pairs({ l = "LEFT", r = "RIGHT", u = "UP", d = "DOWN" }) do
      local names = { l = "left", r = "right", u = "up", d = "down" }
      bind("SUPER + SHIFT + ALT + " .. arrow,
        "Send this workspace's windows to the " .. names[dir] .. " monitor", send_workspace_windows(dir))
    end
  end

  track()
  hl.on("workspace.active", track)
  hl.timer(normalize, { timeout = 300, type = "oneshot" })

  local pending
  local function recheck()
    if pending then pending:set_enabled(false) end
    pending = hl.timer(function()
      pending = nil
      if block_map().signature ~= map.signature then
        -- Reload re-runs this file: rules re-registered (which also brings a
        -- returning screen's workspaces home), then normalize.
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

  -- The shell only edits shell.json when the plugin is disabled, and the
  -- widget only rewrites the settings file when a setting changes. Watch both
  -- and reload; at the next parse this module is inactive or re-read.
  hl.timer(function()
    local _, now = load_settings()
    if not M.enabled() or now ~= settings_text then
      hl.exec_cmd("hyprctl reload")
    end
  end, { timeout = POLL_MS, type = "repeat" })

  M.write_status("active " .. VERSION .. " " .. map.signature)
end

return M
