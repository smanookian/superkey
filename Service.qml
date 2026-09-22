import QtQuick
import Quickshell
import Quickshell.Hyprland

// Superkey lesson engine (headless). Milestone 1: prove that a third-party
// service can observe Hyprland from inside omarchy-shell. Exposes the last
// few raw events and the focused workspace so Coach.qml can display them.
Item {
  id: root

  property var shell: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property int focusedWorkspace: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  readonly property string activeWindow: Hyprland.activeToplevel ? Hyprland.activeToplevel.title : ""
  property var recentEvents: []
  property int eventCount: 0

  function dispatch(request) {
    Hyprland.dispatch(request)
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var line = event.name + " " + event.data
      var next = root.recentEvents.slice(-7)
      next.push(line)
      root.recentEvents = next
      root.eventCount += 1
    }
  }
}
