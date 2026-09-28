# Multi-Monitor Workspaces

An [Omarchy](https://omarchy.org) plugin that gives **each monitor its own workspaces 1–9 (and 0)**.

Stock Hyprland has one global set of numbered workspaces. The first time you press `SUPER+1`, workspace 1 is created on whichever monitor has focus, and every later `SUPER+1` jumps there. So the numbers end up scattered across screens (1 and 3 on one, 2 on the other). With this plugin enabled:

- `SUPER` + a number key goes to that workspace **on the monitor you're on**.
- `SUPER+SHIFT` + a number key moves the focused window there, and `SUPER+SHIFT+ALT` + a number key moves it without following.
- `SUPER` + scroll wheel cycles through the current monitor's workspaces only.
- Each screen's bar shows **only that screen's** workspaces, numbered 1–9/0, and marks the one that screen is showing.
- If [hyprtasking](https://github.com/raybbian/hyprtasking) is installed, its overview grid shows each monitor its own workspaces.

Disabling the plugin puts every one of these back to stock Omarchy.

## Install

```bash
omarchy plugin add https://github.com/davidboulay/omarchy-multi-monitor-workspaces.git --enable
```

Or add it without `--enable` and turn it on from the menu (next section).

Requires Omarchy 4 (Hyprland with the Lua config). Tested on Omarchy 4.0.4 with Hyprland 0.56.2. No extra packages are needed.

## Turn on and off

**Omarchy menu → Setup → Plugins → Enable Plugin / Disable Plugin → Multi-Monitor Workspaces.**

- **Enabling** replaces the stock *Workspaces* bar widget with this plugin's widget, in the same position. The plugin's service then puts a small loader file into Omarchy's Hyprland toggles folder (`~/.local/state/omarchy/toggles/hypr/`, the same folder Omarchy's own *Window Gaps* toggle uses) and reloads Hyprland.
- **Disabling** puts the stock widget back. The Hyprland side notices within about two seconds and reloads to stock.

It never edits your own config files (`~/.config/hypr/*`, your bindings, your monitor setup).

## Remove

```bash
~/.config/omarchy/plugins/io.github.davidboulay.multi-monitor-workspaces/bin/multi-monitor-workspaces remove-loader
omarchy plugin remove io.github.davidboulay.multi-monitor-workspaces
```

The first command deletes the loader file and reloads Hyprland. You can skip it: once the plugin folder is gone the loader does nothing, and deleting it by hand later is always safe. Plugin state lives in `~/.local/state/omarchy/multi-monitor-workspaces/`, which you can delete as well.

## How it works

Each monitor gets a **slot**, ranked by position from left to right (then top to bottom); mirrored outputs are skipped. Slot *S* owns the real Hyprland workspace ids *S*×10+1 … *S*×10+10:

| Slot | Monitor | Real ids | Shown as |
|---|---|---|---|
| 0 | leftmost | 1–10 | 1–9, 0 |
| 1 | next to the right | 11–20 | 1–9, 0 |
| 2 | … | 21–30 | 1–9, 0 |

A single monitor is always slot 0, so it behaves exactly like stock.

- **Rules.** Every id is bound to its monitor with a Hyprland workspace rule, so a new workspace always opens on the right screen.
- **Hotplug.** When monitors are added, removed or rearranged, the plugin waits 1.5 s for your monitor setup to apply. If the slot map changed, it reloads Hyprland so the rules follow.
- **Renumbering.** A workspace that ends up on a monitor that doesn't own its id is renumbered into that monitor's range (`hl.dsp.workspace.change_id`), keeping its number when that's free. This happens when a monitor is unplugged (Hyprland moves its workspaces to the remaining screen) or when you move a workspace across with `SUPER+SHIFT+ALT+arrow`. Windows are never moved; only the number changes.

> **Unplugging folds, replugging doesn't restore.** When you unplug a monitor, its workspaces move to the remaining screen and take free numbers there. They stay there when you plug the monitor back in.

## Update checks

The plugin checks the system when the shell starts (so after every `omarchy update`) and once a day. It sends **one notification per new problem**:

| Check | Why |
|---|---|
| Omarchy changed `default/hypr/bindings/tiling.lua` | Those are the stock workspace keys this plugin replaces |
| Omarchy changed the stock *Workspaces* bar widget | This plugin's widget is derived from it |
| The Hyprland side failed to load, or is inactive while the plugin is enabled | Otherwise the bar and the keys would disagree |
| Hyprland config errors mention this plugin | |
| The stock *Workspaces* widget is also in the bar | It would show global numbers beside the per-monitor ones |
| The installed hyprtasking build lacks the overview-grid fix | See below |

Run the checks yourself at any time:

```bash
~/.config/omarchy/plugins/io.github.davidboulay.multi-monitor-workspaces/bin/multi-monitor-workspaces status
```

A "changed" warning doesn't mean anything is broken, only that the plugin was tested against the previous version (see `compat.json`).

## hyprtasking (optional)

If you use the hyprtasking overview, builds before [raybbian/hyprtasking#138](https://github.com/raybbian/hyprtasking/pull/138) can place the second monitor's workspaces one tile off after the monitor layout changes, and every tile still *looks* right. The plugin warns when your build doesn't have the fix. Everything else works without hyprtasking.

## Dependencies

None beyond Omarchy 4: `hyprctl`, `jq` and `omarchy-notification-send` all ship with it. hyprtasking is optional.

## License

MIT, see [LICENSE](LICENSE). The bar widget is derived from Omarchy's built-in `omarchy.workspaces` widget, which is also MIT licensed.
