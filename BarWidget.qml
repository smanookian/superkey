import QtQuick
import qs.Ui

// Bar entry point: a single button that toggles the coach panel.
BarWidget {
  id: root
  moduleName: "stevinator.superkey"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "SK"
    horizontalMargin: 7.5
    onPressed: function(mouseButton) {
      if (!root.bar) return
      root.bar.run("omarchy-shell shell toggle stevinator.superkey '{}'")
    }
  }
}
