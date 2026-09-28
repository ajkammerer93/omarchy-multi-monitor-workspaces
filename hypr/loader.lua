-- Multi-Monitor Workspaces loader (io.github.davidboulay.multi-monitor-workspaces).
--
-- The plugin's service keeps a copy of this file in
-- ~/.local/state/omarchy/toggles/hypr/, which Omarchy sources after the
-- user's Hyprland config on every reload. It is inert unless the plugin is
-- installed AND enabled, and it never raises: a failure is written to the
-- plugin's status file (and shown as a notification by the plugin) instead of
-- aborting the rest of the toggles folder. Deleting this file is always safe.

local home = os.getenv("HOME") or ""
local module_path = home .. "/.config/omarchy/plugins/io.github.davidboulay.multi-monitor-workspaces/hypr/multi-monitor-workspaces.lua"

local handle = io.open(module_path, "r")
if handle then
  handle:close()

  local ok, err = pcall(function()
    local mmw = dofile(module_path)
    if mmw.enabled() then
      mmw.activate()
    else
      mmw.write_status("inactive")
    end
  end)

  if not ok then
    print("multi-monitor-workspaces: " .. tostring(err))
    local state_dir = home .. "/.local/state/omarchy/multi-monitor-workspaces"
    os.execute("mkdir -p '" .. state_dir .. "'")
    local status = io.open(state_dir .. "/status", "w")
    if status then
      status:write("error ", (tostring(err):gsub("\n", " ")), "\n")
      status:close()
    end
  end
end
