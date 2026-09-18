import QtQuick
import qs.Commons
import qs.Ui

// One row of the settings screen: label and description, and a switch,
// a stepper, or a run glyph on the right.
CursorSurface {
  id: settingRowItem
  // The widget this belongs to: every one of these reads its state. Not
  // called `root`, which an id of that name would shadow at the call site.
  required property var widget
  property var item: ({})
  property int cursorIndex: 0
  // A copy row has no value of its own; it hands over a command.
  readonly property var value: item.key && item.type !== "copy" ? widget.cfg(item.key) : null
  property bool copied: false

  hasCursor: widget.settingsCursorActive && widget.settingsCursor === cursorIndex
  foreground: widget.foreground
  implicitHeight: settingContent.implicitHeight + Style.spacing.rowPaddingX

  function copy() {
    widget.copyCommand(item.command)
    copied = true
    copiedFor.restart()
  }

  Timer {
    id: copiedFor
    interval: 2500
    onTriggered: settingRowItem.copied = false
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: settingRowItem.item.type === "int" ? Qt.ArrowCursor : Qt.PointingHandCursor
    onEntered: {
      widget.settingsCursorActive = true
      widget.settingsCursor = settingRowItem.cursorIndex
    }
    onClicked: settingRowItem.item.type === "copy" ? settingRowItem.copy() : widget.activateSetting(settingRowItem.item)
  }

  Row {
    id: settingContent
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.spacing.rowPaddingX
    anchors.rightMargin: Style.spacing.rowPaddingX
    spacing: Style.space(10)

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - control.width - parent.spacing
      spacing: Style.spacing.xs

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: settingRowItem.item.label || ""
        color: widget.foreground
        font.family: widget.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: settingRowItem.copied ? "Copied. Paste it into a terminal." : widget.settingDescription(settingRowItem.item)
        color: widget.dim
        font.family: widget.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    Item {
      id: control
      anchors.verticalCenter: parent.verticalCenter
      width: settingRowItem.item.type === "bool" ? toggle.width
        : settingRowItem.item.type === "copy" ? copyButton.width
        : stepper.width
      height: Math.max(toggle.height, stepper.height)

      PanelActionButton {
        id: copyButton
        visible: settingRowItem.item.type === "copy"
        anchors.verticalCenter: parent.verticalCenter
        iconText: settingRowItem.copied ? "\u{F012C}" : "\u{F018F}"
        tooltipText: "Copy the command"
        foreground: widget.foreground
        fontFamily: widget.fontFamily
        onClicked: settingRowItem.copy()
      }

      ToggleSwitch {
        id: toggle
        visible: settingRowItem.item.type === "bool"
        anchors.verticalCenter: parent.verticalCenter
        checked: settingRowItem.value === true
        interactive: false
        foreground: widget.foreground
      }

      Row {
        id: stepper
        visible: settingRowItem.item.type === "int"
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        PanelActionButton {
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\u{F0374}"
          enabled: settingRowItem.value > settingRowItem.item.min
          foreground: widget.foreground
          fontFamily: widget.fontFamily
          onClicked: widget.adjustSetting(settingRowItem.item, -1)
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(64)
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: settingRowItem.value + (settingRowItem.item.unit || "")
          color: widget.foreground
          font.family: widget.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        PanelActionButton {
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\u{F0415}"
          enabled: settingRowItem.value < settingRowItem.item.max
          foreground: widget.foreground
          fontFamily: widget.fontFamily
          onClicked: widget.adjustSetting(settingRowItem.item, 1)
        }
      }

    }
  }
}
