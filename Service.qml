import QtQuick
import Quickshell
import Quickshell.Io

// Multi-Monitor Workspaces service. Runs only while the plugin is enabled.
//
// On every shell start (which includes after each `omarchy update`) and once
// a day it runs bin/multi-monitor-workspaces:
//   ensure          keeps the Hyprland loader in Omarchy's toggles folder and
//                   reloads Hyprland if the per-monitor side isn't active yet
//   check --notify  one notification per new problem: Omarchy changed the
//                   stock files this plugin replaces, the Hyprland side failed,
//                   hyprtasking lacks the grid fix, ...
//
// Turning the plugin off needs nothing from here: the Hyprland side watches
// shell.json and returns to stock by itself.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null

  readonly property string pluginDir: {
    var url = String(Qt.resolvedUrl("."))
    return decodeURIComponent(url.replace(/^file:\/\//, "")).replace(/\/$/, "")
  }
  readonly property string helper: pluginDir + "/bin/multi-monitor-workspaces"

  function runChecks() {
    if (!ensure.running && !check.running) ensure.running = true
  }

  Process {
    id: ensure
    command: ["bash", root.helper, "ensure"]
    onExited: check.running = true
  }

  Process {
    id: check
    command: ["bash", root.helper, "check", "--notify"]
    stdout: StdioCollector {
      onStreamFinished: {
        var out = text.trim()
        if (out && out !== "ok") console.log("multi-monitor-workspaces: " + out)
      }
    }
  }

  // Let the compositor and the rest of the shell settle after login.
  Timer {
    interval: 5000
    running: true
    onTriggered: root.runChecks()
  }

  Timer {
    interval: 24 * 60 * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.runChecks()
  }
}
