import QtQuick
import qs.Commons
import qs.Ui

// The settings tab: every setting, in two columns, with the cursor running
// down them both.
Row {
  id: settingsTab
  // The widget whose settings these are.
  required property var widget

  // Keeps the cursor's row on screen, wherever it has moved to.
  function reveal() {
    leftSettings.reveal()
    rightSettings.reveal()
  }

  spacing: Style.space(32)

  SettingsColumn {
    id: leftSettings
    widget: settingsTab.widget
    width: (parent.width - parent.spacing) / 2
    height: parent.height
    rows: settingsTab.widget.settingsRows.slice(0, settingsTab.widget.settingsSplit)
  }

  SettingsColumn {
    id: rightSettings
    widget: settingsTab.widget
    width: (parent.width - parent.spacing) / 2
    height: parent.height
    rows: settingsTab.widget.settingsRows.slice(settingsTab.widget.settingsSplit)
  }
}
