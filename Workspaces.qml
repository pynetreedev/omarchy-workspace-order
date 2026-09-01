import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

// Workspace indicator you can reorder.
//
// Clicking a pill switches to it, as the stock widget does. The addition is
// reordering: right-click a pill to swap the workspace you are on with that
// one, or press the reorder-mode key and left-click does the same. Dragging one
// pill onto another swaps those two specifically, for a workspace you are not
// standing on.
//
// Reordering is a renumber, not a window move: Hyprland's change_id carries a
// workspace and everything in it to a new id.
//
// Per-monitor blocks are handled. With hyprsplit each monitor owns a block of
// `workspacesPerMonitor` ids -- the first display 1-10, the next 11-20 -- so
// this works out which block belongs to the monitor it is drawn on and labels
// that block 1-10. Without hyprsplit the block is simply 1-10 and the labels
// are the ids.
//
// Nothing here reads Quickshell's workspace model. It cannot survive a
// renumber: change_id emits neither a create nor a destroy, so Quickshell never
// learns a workspace stopped existing under an id and keeps a phantom, and
// refreshWorkspaces() updates what it holds without pruning it. Ids, window
// counts and which workspace is active all come from `hyprctl -j` instead.
//
// The mode is toggled over IPC:
//   omarchy-shell workspace-order toggle | on | off | state
// which is what a Hyprland keybinding should call.
BarWidget {
  id: root
  moduleName: "pynetreedev.workspaces"

  readonly property int workspacesPerMonitor: 10

  // The bar this widget sits in is a PanelWindow per monitor, so prefer that
  // surface's own screen. Fall back to the focused monitor if the attached
  // property isn't reachable, so the widget degrades instead of breaking.
  function barMonitorName() {
    try {
      if (root.QsWindow && root.QsWindow.window && root.QsWindow.window.screen) {
        return root.QsWindow.window.screen.name
      }
    } catch (e) {}

    return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
  }

  function barMonitor() {
    var name = root.barMonitorName()
    var monitors = Hyprland.monitors.values

    for (var i = 0; i < monitors.length; i++) {
      if (monitors[i].name === name) return monitors[i]
    }

    return Hyprland.focusedMonitor
  }

  // Derive the block from the monitor's own active workspace rather than
  // hardcoding an order, so it keeps working if monitor priority changes.
  function baseId() {
    var _ = root.revision
    var id = root.activeId()
    if (id <= 0) return 1

    var per = root.workspacesPerMonitor
    return Math.floor((id - 1) / per) * per + 1
  }

  function activeId() {
    var _ = root.revision
    var name = root.barMonitorName()

    if (root.liveActive[name] !== undefined) return root.liveActive[name]

    // Before the first probe answers, Quickshell is better than nothing.
    var monitor = root.barMonitor()
    return monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
  }

  // Existence per the last compositor read. Replaces the old lookup into
  // Quickshell's list, which could report a workspace that no longer exists.
  function exists(id) {
    var _ = root.revision
    return root.liveCounts[id] !== undefined
  }

  // Always show the first five of this monitor's block, plus any other
  // workspace in the block that currently exists.
  function workspaceIds() {
    var _ = root.revision
    var base = root.baseId()
    var per = root.workspacesPerMonitor
    var ids = [base, base + 1, base + 2, base + 3, base + 4]

    for (var key in root.liveCounts) {
      var id = parseInt(key)
      if (id >= base && id < base + per && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  // Label with the position inside the block, so both monitors read 1-10.
  function labelFor(id) {
    var _ = root.revision
    var offset = id - root.baseId() + 1
    return offset === root.workspacesPerMonitor ? "0" : String(offset)
  }

  // Absolute ids are unambiguous -- each belongs to exactly one monitor -- so a
  // plain focus dispatch lands on the right screen.
  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  // Renumbering, done here rather than shelled out to a helper, so the plugin
  // depends on nothing beyond Hyprland itself.
  //
  // Two workspaces cannot hold the same id mid-swap, so one is parked on an id
  // outside every monitor's block while the other crosses over. Hyprland does
  // not reliably carry a workspace's name across a change_id -- a parked one
  // can arrive still called by the scratch number -- so each landing is
  // followed by an explicit rename. A workspace still called by its old number
  // becomes its new number; one somebody actually named keeps that name. Both
  // names are decided before anything moves, because reading a name back
  // afterwards races the compositor's own rename and can write the stale value.
  readonly property int scratchId: 9001

  function lua(code) {
    return "hyprctl dispatch " + Util.shellQuote(code)
  }

  function renameStep(id, name) {
    return root.lua('hl.dsp.workspace.rename({ workspace = "' + id + '", name = "' + name + '" })')
  }

  function changeStep(from, to) {
    return root.lua('hl.dsp.workspace.change_id({ workspace = "' + from + '", id = ' + to + ' })')
  }

  // The name a workspace should carry once it has landed on `to`.
  function landingName(from, to) {
    var current = root.liveNames[from]
    return current === undefined || current === String(from) ? String(to) : current
  }

  function reorderWorkspace(a, b) {
    if (!root.bar || a === b) return

    var aLives = root.exists(a)
    var bLives = root.exists(b)
    if (!aLives && !bLives) return

    var steps = []

    // With one side empty there is nothing to trade with, so the occupied
    // workspace simply takes the free id.
    if (!aLives) {
      steps.push(changeStep(b, a), renameStep(a, landingName(b, a)))
    } else if (!bLives) {
      steps.push(changeStep(a, b), renameStep(b, landingName(a, b)))
    } else {
      var nameAtA = landingName(b, a)
      var nameAtB = landingName(a, b)

      var scratch = root.scratchId
      while (root.exists(scratch)) scratch++

      // Deliberately no rename while parked: that id is temporary and naming
      // it would only have to be undone a step later.
      steps.push(changeStep(a, scratch))
      steps.push(changeStep(b, a), renameStep(a, nameAtA))
      steps.push(changeStep(scratch, b), renameStep(b, nameAtB))
    }

    root.bar.run(steps.join(" ; "))
  }

  // Toggled by a Hyprland keybinding through the IPC handler below. While off,
  // every stock gesture behaves exactly as it did.
  property bool reorderMode: false

  function toggleReorderMode() {
    root.reorderMode = !root.reorderMode
    if (!root.reorderMode) root.carriedId = -1
  }

  // The bar wraps every widget slot in a MouseArea that claims the left button
  // as soon as it travels a few pixels, turning it into a widget drag -- and
  // once that starts it suppresses the click it would otherwise have routed to
  // us, so our press handler never ran at all. That handler is a sibling of the
  // Loader this widget lives in, so outranking it means raising the Loader.
  //
  // Only while the mode is on. Off, the z goes back and every stock gesture --
  // click to switch, drag the widget to another section -- behaves as it always
  // did.
  onReorderModeChanged: {
    if (root.parent) root.parent.z = root.reorderMode ? 1 : 0
    if (!root.reorderMode) root.hoverId = -1
  }

  // Drop target under the cursor mid-drag, or -1.
  property int hoverId: -1

  // Bumped whenever the workspace list is re-read. Every function below reads
  // it, which is the whole point: refreshWorkspaces() updates the id ON each
  // existing Workspace object without replacing the list, so `workspaces.values`
  // never looks changed and no binding that depends on it re-evaluates. The bar
  // goes on drawing labels it computed from the old ids. Reading a property
  // that really did change gives those bindings something to notice.
  property int revision: 0

  // Renumbering a workspace emits `changeworkspaceid`, which Quickshell does
  // not model: it keeps the ids it already had, so the bar goes on drawing the
  // old order while the windows have already moved. Nothing else forces a
  // re-read either -- a `renameworkspace` only updates that workspace's name,
  // it says nothing about ids -- so the model has to be refreshed by hand.
  //
  // Listening to the event rather than refreshing after our own action means a
  // reorder from anywhere is covered -- a keybinding, a script, another tool --
  // not only the ones this widget performed.
  Connections {
    target: Hyprland

    function onRawEvent(event) {
      switch (event.name) {
        case "changeworkspaceid":
        case "createworkspacev2":
        case "destroyworkspacev2":
        case "openwindow":
        case "closewindow":
        case "movewindowv2":
        case "workspace":
        case "workspacev2":
        case "focusedmon":
        case "focusedmonv2":
          debounce.restart()
          break
      }
    }
  }

  // Which pill sits under a point given in this widget's coordinates. Walking
  // the children beats arithmetic on cell widths: it stays right for both bar
  // orientations and for however many pills the block currently has.
  function pillAt(x, y) {
    var local = grid.mapFromItem(root, x, y)

    for (var i = 0; i < grid.children.length; i++) {
      var child = grid.children[i]

      if (child && child.visible && child.width > 0 && child.height > 0
          && local.x >= child.x && local.x < child.x + child.width
          && local.y >= child.y && local.y < child.y + child.height) {
        return child
      }
    }

    return null
  }

  function enableReorderMode() {
    root.reorderMode = true
  }

  function disableReorderMode() {
    root.reorderMode = false
    root.carriedId = -1
  }

  // A bar surface exists per monitor, so this widget is instantiated more than
  // once, but an IPC target only ever routes to one of them. broadcast() is the
  // base class's relay for exactly this -- without it the mode would switch on
  // one screen and leave the others looking untouched.
  IpcHandler {
    target: "workspace-order"

    function toggle(): void { root.broadcast("toggleReorderMode") }
    function on(): void { root.broadcast("enableReorderMode") }
    function off(): void { root.broadcast("disableReorderMode") }

    // Readable state, so the mode can be checked from a script or a hook
    // without squinting at the bar.
    function state(): string { return root.reorderMode ? "on" : "off" }
  }

  // --- carry state ------------------------------------------------------
  // Absolute id of the workspace currently picked up, or -1 for nothing --
  // a value no real workspace can take.
  property int carriedId: -1

  readonly property color carryHighlight: {
    var fg = root.bar ? root.bar.barForeground : Color.foreground
    return Qt.rgba(fg.r, fg.g, fg.b, 0.22)
  }

  // Swap the workspace you are standing on with the one you pointed at. This is
  // the whole gesture: in reorder mode a click means the same thing the number
  // key means, "put me there", and needs no more clicks than the key needs
  // presses. An earlier version made you click a source and then a target,
  // which is a step longer for no gain -- the source is always the workspace
  // you are on.
  function swapWithActive(id) {
    var current = root.activeId()
    if (current > 0 && current !== id) root.reorderWorkspace(current, id)
  }

  // Leaves reorder mode everywhere, and drops the Hyprland submap with it so
  // the keyboard half does not stay armed after a mouse action finished the job.
  function leaveMode() {
    root.broadcast("disableReorderMode")
    if (root.bar) root.bar.run("hyprctl dispatch " + Util.shellQuote('hl.dsp.submap("reset")'))
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
        id: pill
        required property int modelData

        // The delegate's own id, named plainly so the handlers below read as
        // workspace operations rather than model indexing.
        readonly property int workspaceId: modelData

        readonly property bool occupied: (root.liveCounts[modelData] || 0) > 0
        readonly property bool focused: root.activeId() === modelData

        bar: root.bar
        text: focused ? "󱓻" : root.labelFor(modelData)
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize

        // Left-click arrives via the bar's click routing; right-click arrives
        // through this button's own MouseArea, which the slot handler ignores.
        onPressed: function(button) {
          // Right-click is the same swap without needing the mode at all; the
          // bar's slot handler only claims the left button, so it never sees it.
          if (button === Qt.RightButton) root.swapWithActive(pill.workspaceId)
          else root.focusWorkspace(pill.workspaceId)
        }

        // Behind the label rather than over it. Fills for the pill being
        // carried; a bare outline on the rest while reorder mode is on, so the
        // mode is visible without shouting.
        Rectangle {
          z: -1
          anchors.fill: parent
          radius: height / 4
          readonly property bool filled: root.carriedId === pill.workspaceId
                                         || root.hoverId === pill.workspaceId
          visible: root.reorderMode || filled
          color: filled ? root.carryHighlight : "transparent"
          border.width: root.reorderMode && !filled ? 1 : 0
          border.color: root.carryHighlight
        }
      }
    }
  }

  // Authoritative workspace list, read straight from the compositor.
  //
  // Quickshell's model cannot be trusted across a renumber. A change_id emits
  // neither create nor destroy, so Quickshell never learns that a workspace
  // stopped existing under an id and keeps a phantom: observed here as five
  // occupied pills when the compositor had four workspaces and no ws 3 at all.
  // refreshWorkspaces() updates the objects it already has -- it does not prune
  // them -- and refreshToplevels() cannot fix a list that is wrong to begin
  // with. Only a fresh read can, so ids and window counts come from
  // `hyprctl -j workspaces`.
  //
  // Focus is still taken from Quickshell: workspace switches emit events it
  // does handle, and that half has always tracked correctly.
  property var liveCounts: ({})
  property var liveNames: ({})

  Process {
    id: probe
    command: ["hyprctl", "-j", "workspaces"]

    stdout: StdioCollector {
      waitForEnd: true

      onStreamFinished: {
        var counts = {}
        var names = {}

        try {
          var list = JSON.parse(String(text || "[]"))

          for (var i = 0; i < list.length; i++) {
            if (list[i].id > 0) {
              counts[list[i].id] = list[i].windows
              names[list[i].id] = String(list[i].name)
            }
          }
        } catch (e) {
          return
        }

        root.liveCounts = counts
        root.liveNames = names
        root.revision++
      }
    }
  }

  // Which workspace each monitor is actually showing. Quickshell's
  // monitor.activeWorkspace is right for switching -- that emits events it
  // handles -- but not across a renumber: the workspace you are standing on
  // changes id with no event, so the object it holds keeps the old number and
  // the selected marker stays on the pill you just left.
  property var liveActive: ({})

  Process {
    id: activeProbe
    command: ["hyprctl", "-j", "monitors"]

    stdout: StdioCollector {
      waitForEnd: true

      onStreamFinished: {
        var active = {}

        try {
          var list = JSON.parse(String(text || "[]"))

          for (var i = 0; i < list.length; i++) {
            if (list[i].name && list[i].activeWorkspace) {
              active[list[i].name] = list[i].activeWorkspace.id
            }
          }
        } catch (e) {
          return
        }

        root.liveActive = active
        root.revision++
      }
    }
  }

  // Coalesces bursts: one reorder is several id changes in a row, and a probe
  // per event would be a handful of redundant compositor queries. Kept short so
  // the selected marker still feels immediate on an ordinary switch.
  Timer {
    id: debounce
    interval: 60

    onTriggered: {
      if (!probe.running) probe.running = true
      if (!activeProbe.running) activeProbe.running = true
    }
  }

  Component.onCompleted: debounce.restart()

  // Owns the pointer while the mode is on and is inert otherwise -- a disabled
  // MouseArea passes events straight through, so the bar keeps its gestures.
  // Seeing press, move and release together is what lets one surface serve both
  // a drag and a two-click pick-up-and-drop.
  MouseArea {
    id: reorderPointer
    anchors.fill: parent
    enabled: root.reorderMode
    acceptedButtons: Qt.LeftButton
    preventStealing: true
    cursorShape: Qt.PointingHandCursor

    property var pressHit: null
    property real pressX: 0
    property real pressY: 0
    property bool dragging: false
    readonly property int dragThreshold: 6

    onPressed: function(mouse) {
      pressHit = root.pillAt(mouse.x, mouse.y)
      pressX = mouse.x
      pressY = mouse.y
      dragging = false
    }

    onPositionChanged: function(mouse) {
      if (!dragging && Math.abs(mouse.x - pressX) + Math.abs(mouse.y - pressY) >= dragThreshold) {
        dragging = true
        if (pressHit && root.exists(pressHit.workspaceId)) {
          root.carriedId = pressHit.workspaceId
        }
      }

      if (!dragging) return

      var over = root.pillAt(mouse.x, mouse.y)
      root.hoverId = over ? over.workspaceId : -1
    }

    // A drag carries source to target in one gesture. A plain click is the
    // two-step flow instead: the first picks up, the second drops, and clicking
    // the held pill again puts it back.
    onReleased: function(mouse) {
      var over = root.pillAt(mouse.x, mouse.y)

      // A drag names both ends explicitly, for moving a workspace you are not
      // standing on. A click names only the destination -- the source is
      // wherever you already are. Either way one gesture finishes the job and
      // leaves the mode.
      if (dragging) {
        if (pressHit && over && over.workspaceId !== pressHit.workspaceId) {
          root.reorderWorkspace(pressHit.workspaceId, over.workspaceId)
          root.leaveMode()
        }
      } else if (over) {
        root.swapWithActive(over.workspaceId)
        root.leaveMode()
      }

      root.carriedId = -1
      root.hoverId = -1
      dragging = false
      pressHit = null
    }

    onCanceled: {
      dragging = false
      pressHit = null
      root.hoverId = -1
    }
  }
}
