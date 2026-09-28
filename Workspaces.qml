import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Multi-Monitor Workspaces bar widget. Derived from Omarchy's
// omarchy.workspaces (MIT), which shows the global ids 1-10 on every screen.
// Paired with hypr/multi-monitor-workspaces.lua: each monitor owns the real ids
// slot*10+1 .. slot*10+10, slots ranked left to right (then top to bottom),
// mirrors skipped -- the same ordering as the Lua side, so both agree on which
// screen owns what. Each bar shows only the workspaces on ITS screen,
// labelled 1-9/0. A workspace from another slot that landed here (briefly,
// before the Hyprland half renumbers it) shows its real id.
BarWidget {
  id: root
  moduleName: "io.github.davidboulay.multi-monitor-workspaces"

  readonly property int span: 10

  readonly property var monitor: {
    var win = QsWindow.window
    return win && win.screen ? Hyprland.monitorFor(win.screen) : null
  }

  function isMirror(m) {
    var ipc = m ? m.lastIpcObject : null
    return !!ipc && ((ipc.mirrorOf !== undefined && ipc.mirrorOf !== "none") || ipc.disabled === true)
  }

  readonly property int slot: {
    if (!root.monitor) return 0
    var list = []
    var values = Hyprland.monitors.values
    for (var i = 0; i < values.length; i++) {
      if (!root.isMirror(values[i])) list.push(values[i])
    }
    list.sort(function(a, b) {
      if (a.x !== b.x) return a.x - b.x
      if (a.y !== b.y) return a.y - b.y
      return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
    })
    for (var j = 0; j < list.length; j++) {
      if (list[j].name === root.monitor.name) return j
    }
    return 0
  }

  readonly property int base: root.slot * root.span

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function onThisScreen(ws) {
    return !!ws && !!ws.monitor && !!root.monitor && ws.monitor.name === root.monitor.name
  }

  function workspaceIds() {
    var ids = []
    for (var n = 1; n <= 5; n++) ids.push(root.base + n)

    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && root.onThisScreen(values[i]) && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function label(id) {
    if (id > root.base && id <= root.base + root.span) {
      var digit = id - root.base
      return digit === root.span ? "0" : String(digit)
    }
    return String(id)
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        // This screen's visible workspace, not the globally focused one, so
        // each bar marks where its own monitor is.
        readonly property bool focused: root.monitor !== null && root.monitor.activeWorkspace !== null && root.monitor.activeWorkspace.id === modelData

        bar: root.bar
        text: focused ? "󱓻" : root.label(modelData)
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }
}
