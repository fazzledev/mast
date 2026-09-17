import QtQuick
import qs.Commons
import qs.Ui

// One column of the settings tab: section headings and setting rows, which
// scroll if the screen is short.
Flickable {
  id: settingsColumnFlick
  // The widget this belongs to: every one of these reads its state. Not
  // called `root`, which an id of that name would shadow at the call site.
  required property var widget
  property var rows: []

  contentHeight: settingsColumnBody.implicitHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  // Scrolls the cursor's row into view, if it is in this column.
  function reveal() {
    var index = rows.indexOf(widget.settingsItems[widget.settingsCursor])
    if (index < 0) return
    var row = settingsColumnRepeater.itemAt(index)
    if (!row) return
    var y = row.mapToItem(settingsColumnBody, 0, 0).y
    if (y < contentY) contentY = y
    else if (y + row.height > contentY + height) contentY = y + row.height - height
  }

  Column {
    id: settingsColumnBody
    width: settingsColumnFlick.width
    spacing: Style.space(6)

    Repeater {
      id: settingsColumnRepeater
      model: settingsColumnFlick.rows

      Loader {
        id: settingLoader
        required property var modelData
        width: settingsColumnBody.width
        sourceComponent: modelData.section ? sectionHeading : settingRow

        Component {
          id: sectionHeading
          PanelSectionHeader {
            width: settingsColumnBody.width
            topPadding: Style.space(6)
            bottomPadding: Style.space(2)
            text: settingLoader.modelData.section.toUpperCase()
            foreground: Color.menu.text
            fontFamily: widget.fontFamily
          }
        }

        Component {
          id: settingRow
          SettingRow {
            widget: settingsColumnFlick.widget
            width: settingsColumnBody.width
            item: settingLoader.modelData
            cursorIndex: settingsColumnFlick.widget.settingsItems.indexOf(settingLoader.modelData)
          }
        }
      }
    }
  }
}
