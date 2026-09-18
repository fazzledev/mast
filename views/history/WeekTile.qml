import QtQuick
import qs.Commons
import qs.Ui

// One of the three figures across the top of the history tab.
BorderSurface {
  id: weekTile
  // The widget, for its fonts.
  required property var widget
  required property var tile
  readonly property string summary: tile.value + " " + tile.label
  height: tileColumn.implicitHeight + Style.space(28)
  radius: Style.cornerRadius
  color: "transparent"
  borderSpec: Border.controlSpec("normal", Color.menu.text, Color.accent)

  Column {
    id: tileColumn
    anchors.centerIn: parent
    width: parent.width - Style.space(28)
    spacing: Style.space(4)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: tile.value
      color: Color.menu.text
      font.family: widget.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: tile.label
      color: widget.dim
      font.family: widget.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
