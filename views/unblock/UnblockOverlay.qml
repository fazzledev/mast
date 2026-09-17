import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The unblock screen: the passage to type, then the two questions. It owns
// the typing -- the field, the progress, the speed and the typos -- and the
// widget (Panel.qml), which it is given as `widget`, owns the attempt: which
// site, which passage, and what is recorded.
PanelWindow {
  id: overlay
  // The widget running the attempt. Not called `root`: at the call site a
  // property of that name shadows the id it is being given.
  required property var widget

  // What the widget needs of the typing: how far it is right, how fast,
  // and how often it went wrong.
  readonly property alias typed: phraseField.lastGood
  readonly property alias wpm: phraseField.wpm
  readonly property alias typos: phraseField.typos
  property alias reasonText: reasonField.text

  // Starts the passage over, whether it is the first or a swap.
  function resetTyping() {
    phraseField.text = ""
    phraseField.lastText = ""
    phraseField.lastGood = 0
    phraseField.progressLog = []
    phraseField.startedAt = 0
    phraseField.wpm = 0
    phraseField.peakWpm = 0
    phraseField.typos = 0
    phraseField.wasOnTrack = true
    phraseField.forceActiveFocus()
  }

  // How the typing went, for the question page and the record.
  function summarizeTyping() {
    var ms = Math.max(1000, Date.now() - phraseField.startedAt)
    var wpm = Math.round(phraseField.lastGood / 5 / (ms / 60000))
    return {
      seconds: ms / 1000,
      words: widget.confirmPhrase.split(" ").length,
      wpm: wpm,
      peakWpm: Math.max(phraseField.peakWpm, wpm),
      typos: phraseField.typos,
  }
  }

  // The question page, with no as the default: Enter straight away keeps
  // the block.
  function beginAsking() {
    reasonField.text = ""
    askKeys.yesSelected = false
    Qt.callLater(function() { reasonField.forceActiveFocus() })
  }

  function focusReason() { reasonField.forceActiveFocus() }

  // Test mode's typist types here, through the same path a keystroke takes.
  function typeCharacter() {
    phraseField.text = phraseField.text + widget.confirmPhrase.charAt(phraseField.typed.length)
  }
  visible: widget.confirmingSite !== null
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "fazzledev-mast"
  WlrLayershell.layer: WlrLayer.Overlay
  // Test mode must never take the keyboard from whatever you are doing.
  WlrLayershell.keyboardFocus: widget.testMode ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore

  // showPassage has already cleared the field; focus only lands once the
  // window is mapped.
  onVisibleChanged: if (visible) Qt.callLater(function() { phraseField.forceActiveFocus() })

  Rectangle {
    anchors.fill: parent
    color: Color.menu.scrim
  }

  // Swallow clicks on the scrim. Walking away should be a decision -- Esc --
  // not a stray click beside the card.
  MouseArea {
    anchors.fill: parent
    onClicked: widget.confirmAsking ? askKeys.forceActiveFocus() : phraseField.forceActiveFocus()
  }

  BorderSurface {
    id: card
    anchors.centerIn: parent
    width: Math.min(Style.space(760), overlay.width - Style.gapsOut * 4)
    height: cardBody.implicitHeight + contentTopInset + contentBottomInset
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
    padding: Style.spacing.panelPadding * 1.5

    readonly property color text: Color.menu.text
    readonly property color faint: Qt.darker(Color.menu.text, 1.6)
    readonly property string siteName: widget.confirmingSite ? widget.confirmingSite.name : ""

    Column {
      id: cardBody
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      spacing: Style.space(16)

      Row {
        spacing: Style.space(14)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: widget.siteGlyph(card.siteName)
          color: widget.siteColor(card.siteName)
          font.family: widget.fontFamily
          font.pixelSize: Style.font.display
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            text: (widget.testMode ? "TEST MODE -- " : "") + "Unblock " + (widget.confirmingSite ? widget.confirmingSite.label : "") + "?"
            color: card.text
            font.family: widget.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            text: widget.confirmAsking
              ? "You typed it all out. Two questions before you decide."
              : "Type this out first. Take your time -- the urge will pass while you do."
            color: card.faint
            font.family: widget.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      Text {
        readonly property string week: widget.weekText(widget.confirmingSite)
        visible: week !== ""
        width: parent.width
        textFormat: Text.PlainText
        text: week
        color: card.text
        font.family: widget.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      // What is typed so far in full colour, the rest faint. Styled text is
      // not selectable, so the paragraph cannot be copied into the field.
      Text {
        visible: !widget.confirmAsking
        width: parent.width
        textFormat: Text.StyledText
        text: {
          var done = phraseField.progress
          return "<font color='" + card.text + "'>" + widget.escapeHtml(widget.confirmPhrase.slice(0, done)) + "</font>"
            + "<font color='" + card.faint + "'>" + widget.escapeHtml(widget.confirmPhrase.slice(done)) + "</font>"
        }
        font.family: widget.fontFamily
        font.pixelSize: Style.font.heading
        lineHeight: 1.35
        wrapMode: Text.WordWrap
      }

      // Where the passage is from, and buttons to swap it for another.
      Item {
        visible: !widget.confirmAsking
        width: parent.width
        height: Math.max(sourceColumn.implicitHeight, passageControls.implicitHeight)

        // The link opens behind this overlay, to read once you are done here.
        Column {
          id: sourceColumn
          visible: widget.confirmSource !== ""
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - passageControls.width - Style.space(16)
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "-- " + widget.confirmSource
            color: card.faint
            font.family: widget.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: true
            wrapMode: Text.WordWrap
          }

          Text {
            visible: widget.confirmUrl !== ""
            textFormat: Text.PlainText
            width: parent.width
            text: widget.confirmUrl
            color: sourceLink.containsMouse ? card.text : card.faint
            font.family: widget.fontFamily
            font.pixelSize: Style.font.caption
            font.underline: true
            elide: Text.ElideMiddle

            MouseArea {
              id: sourceLink
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                Qt.openUrlExternally(widget.confirmUrl)
                phraseField.forceActiveFocus()
              }
            }
          }

          // The credit a licensed excerpt owes: an unaltered excerpt, and
          // the licence it is shared under.
          Text {
            visible: widget.confirmLicense !== ""
            textFormat: Text.PlainText
            width: parent.width
            text: "Excerpt shared under " + widget.confirmLicense
            color: licenseLink.containsMouse ? card.text : card.faint
            font.family: widget.fontFamily
            font.pixelSize: Style.font.caption
            font.underline: licenseLink.containsMouse

            MouseArea {
              id: licenseLink
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                Qt.openUrlExternally(widget.confirmLicenseUrl)
                phraseField.forceActiveFocus()
              }
            }
          }
        }

        Row {
          id: passageControls
          visible: widget.cfg("allowSwitching") && widget.passages.length > 1
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          PanelActionButton {
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰒮"
            tooltipText: "Previous passage (Alt+Left)"
            foreground: card.text
            fontFamily: widget.fontFamily
            onClicked: widget.stepPassage(-1)
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: (widget.confirmIndex + 1) + " / " + widget.passages.length
            color: card.faint
            font.family: widget.fontFamily
            font.pixelSize: Style.font.caption
          }

          PanelActionButton {
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰒭"
            tooltipText: "Next passage (Alt+Right)"
            foreground: card.text
            fontFamily: widget.fontFamily
            onClicked: widget.stepPassage(1)
          }

          PanelActionButton {
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰒝"
            tooltipText: "Random passage (Alt+S)"
            foreground: card.text
            fontFamily: widget.fontFamily
            onClicked: widget.shufflePassage()
          }

          PanelActionButton {
            anchors.verticalCenter: parent.verticalCenter
            iconText: "\u{F0209}"
            tooltipText: "Never show this passage again (Alt+H)"
            foreground: card.text
            fontFamily: widget.fontFamily
            onClicked: widget.hideCurrentPassage()
          }
        }
      }

      TextArea {
        id: phraseField
        // A typo is still shown, just in red, so it can be fixed; progress
        // holds at the last point the text was right.
        property string lastText: ""
        property int lastGood: 0
        // Typing speed over the last few seconds, in the usual five
        // characters to a word, counting only text that matches. From the
        // first keystroke until the window fills, it is over the time so far.
        readonly property int wpmWindow: 10000
        property var progressLog: [] // [{ t, chars }], plus the last entry before the window
        property real startedAt: 0
        property int wpm: 0
        // Past the first few seconds, when the figure has settled.
        property int peakWpm: 0
        // Times the text went from matching to not.
        property int typos: 0
        property bool wasOnTrack: true

        function logProgress() {
          var now = Date.now()
          if (startedAt === 0) startedAt = now
          progressLog.push({ t: now, chars: lastGood })
          while (progressLog.length > 1 && progressLog[1].t < now - wpmWindow) progressLog.shift()
        }

        function updateWpm() {
          var now = Date.now()
          var from = Math.max(now - wpmWindow, startedAt)
          var base = 0
          progressLog.forEach(function(e) { if (e.t <= from) base = e.chars })
          // A floor on the time keeps the first keystrokes from reading as
          // a burst of hundreds.
          var minutes = Math.max(now - from, 2000) / 60000
          wpm = Math.max(0, Math.round((lastGood - base) / 5 / minutes))
          if (now - startedAt >= 5000) peakWpm = Math.max(peakWpm, wpm)
        }

        // Ticks so the figure falls off when typing stops, not only when a
        // key moves it.
        Timer {
          interval: 500
          repeat: true
          running: overlay.visible && !widget.confirmAsking && phraseField.startedAt > 0
          onTriggered: phraseField.updateWpm()
        }
        readonly property string typed: widget.normalise(text)
        readonly property bool onTrack: widget.confirmPhrase.indexOf(typed) === 0
        readonly property int progress: onTrack ? typed.length : lastGood

        visible: !widget.confirmAsking
        width: parent.width
        height: Math.max(Style.space(120), implicitHeight)
        wrapMode: TextArea.Wrap
        placeholderText: "Start typing…"
        color: onTrack ? card.text : widget.urgent
        placeholderTextColor: card.faint
        selectionColor: Style.selectionFillFor(card.text, Color.accent)
        font.family: widget.fontFamily
        font.pixelSize: Style.font.body
        padding: Style.space(10)
        background: BorderSurface {
          color: "transparent"
          borderSpec: Border.controlSpec(phraseField.activeFocus ? "focus" : "normal", card.text, Color.accent)
          radius: Style.cornerRadius
        }

        onTextChanged: {
          // More than a few characters arriving at once is a paste --
          // middle-click included -- so put the text back.
          if (text.length - lastText.length > 3) {
            text = lastText
            cursorPosition = text.length
            return
          }
          lastText = text
          // Worked out here rather than read from the bindings above, which
          // are not guaranteed to have caught up with this change yet.
          var now = widget.normalise(text)
          var matches = widget.confirmPhrase.indexOf(now) === 0
          if (matches) lastGood = now.length
          if (wasOnTrack && !matches) typos += 1
          wasOnTrack = matches
          if (text !== "") logProgress()
          if (now.trim() === widget.confirmPhrase) widget.askConfirm()
        }
        Keys.onPressed: function(event) {
          if (event.matches(StandardKey.Paste)) {
            event.accepted = true
          } else if (event.modifiers & Qt.AltModifier) {
            if (event.key === Qt.Key_Left) widget.stepPassage(-1)
            else if (event.key === Qt.Key_Right) widget.stepPassage(1)
            else if (event.key === Qt.Key_S) widget.shufflePassage()
            else if (event.key === Qt.Key_H) widget.hideCurrentPassage()
            else return
            event.accepted = true
          }
        }
        Keys.onReturnPressed: function(event) { event.accepted = true }
        Keys.onEnterPressed: function(event) { event.accepted = true }
        Keys.onEscapePressed: function(event) {
          event.accepted = true
          widget.cancelConfirm()
        }
      }

      Item {
        visible: !widget.confirmAsking
        width: parent.width
        height: progressText.implicitHeight

        Text {
          id: progressText
          textFormat: Text.PlainText
          anchors.left: parent.left
          readonly property int wordsDone: phraseField.progress === 0 ? 0 : widget.confirmPhrase.slice(0, phraseField.progress).trim().split(" ").length
          readonly property int wordsTotal: widget.confirmPhrase.split(" ").length
          text: phraseField.onTrack
            ? wordsDone + " of " + wordsTotal + " words" + (widget.cfg("showWpm") && phraseField.startedAt > 0 ? "  ·  " + phraseField.wpm + " wpm" : "")
            : "Typo -- fix it to keep going"
          color: phraseField.onTrack ? card.faint : widget.urgent
          font.family: widget.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          textFormat: Text.PlainText
          anchors.right: parent.right
          text: "Esc to keep it blocked"
          color: card.faint
          font.family: widget.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // The question page: the passage again with how the typing went, why
      // you want the site, then yes or no.
      Column {
        visible: widget.confirmAsking
        width: parent.width
        spacing: Style.space(16)

        Text {
          visible: widget.typedSummary !== null
          width: parent.width
          textFormat: Text.PlainText
          text: widget.typedSummary
            ? widget.typedSummary.words + " words in " + widget.formatDuration(widget.typedSummary.seconds)
              + "  ·  " + widget.typedSummary.wpm + " wpm average"
              + "  ·  " + widget.typedSummary.peakWpm + " wpm peak"
              + "  ·  " + widget.typedSummary.typos + (widget.typedSummary.typos === 1 ? " typo" : " typos")
            : ""
          color: card.faint
          font.family: widget.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: widget.confirmPhrase
            color: card.faint
            font.family: widget.fontFamily
            font.pixelSize: Style.font.body
            lineHeight: 1.25
            wrapMode: Text.WordWrap
          }

          Text {
            visible: widget.confirmSource !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: "-- " + widget.confirmSource + (widget.confirmLicense !== "" ? " (" + widget.confirmLicense + ")" : "")
            color: card.faint
            font.family: widget.fontFamily
            font.pixelSize: Style.font.caption
            font.italic: true
            wrapMode: Text.WordWrap
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Why do you want to unblock " + (widget.confirmingSite ? widget.confirmingSite.label : "") + "?"
            color: card.text
            font.family: widget.fontFamily
            font.pixelSize: Style.font.heading
            wrapMode: Text.WordWrap
          }

          TextArea {
            id: reasonField
            width: parent.width
            height: Math.max(Style.space(72), implicitHeight)
            wrapMode: TextArea.Wrap
            placeholderText: "What are you going there for?"
            color: card.text
            placeholderTextColor: card.faint
            selectionColor: Style.selectionFillFor(card.text, Color.accent)
            font.family: widget.fontFamily
            font.pixelSize: Style.font.body
            padding: Style.space(10)
            background: BorderSurface {
              color: "transparent"
              borderSpec: Border.controlSpec(reasonField.activeFocus ? "focus" : "normal",
                                             widget.reasonMissing ? widget.urgent : card.text, Color.accent)
              radius: Style.cornerRadius
            }

            onTextChanged: if (widget.reasonGiven()) widget.reasonMissing = false
            // Enter and Tab move on to the buttons; Shift+Enter is a new line.
            Keys.onReturnPressed: function(event) {
              if (event.modifiers & Qt.ShiftModifier) return
              event.accepted = true
              askKeys.forceActiveFocus()
            }
            Keys.onEnterPressed: function(event) {
              event.accepted = true
              askKeys.forceActiveFocus()
            }
            Keys.onTabPressed: function(event) {
              event.accepted = true
              askKeys.forceActiveFocus()
            }
            Keys.onEscapePressed: function(event) {
              event.accepted = true
              widget.cancelConfirm()
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: widget.reasonMissing
              ? "Answer this first -- at least " + widget.cfg("reasonWords") + (widget.cfg("reasonWords") === 1 ? " word" : " words") + " -- to unblock."
              : (widget.cfg("reasonWords") > 0 ? "" : "Optional. ")
                + "Saved with this attempt whatever you decide, so you can look back at your reasons later: bin/mast-db reasons"
            color: widget.reasonMissing ? widget.urgent : card.faint
            font.family: widget.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // The yes/no. Keys live on this item so the buttons stay plain.
        Item {
          id: askKeys
          width: parent.width
          height: askColumn.implicitHeight

          property bool yesSelected: false

          Keys.onPressed: function(event) {
            switch (event.key) {
            case Qt.Key_Left:
            case Qt.Key_Right:
            case Qt.Key_Tab:
              askKeys.yesSelected = !askKeys.yesSelected
              break
            case Qt.Key_Up:
            case Qt.Key_Backtab:
              reasonField.forceActiveFocus()
              break
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
              if (askKeys.yesSelected) widget.finishConfirm()
              else widget.cancelConfirm()
              break
            case Qt.Key_Y:
              widget.finishConfirm()
              break
            case Qt.Key_N:
            case Qt.Key_Escape:
              widget.cancelConfirm()
              break
            default:
              return
            }
            event.accepted = true
          }

          Column {
            id: askColumn
            width: parent.width
            spacing: Style.space(12)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "Do you still want to unblock " + (widget.confirmingSite ? widget.confirmingSite.label : "") + "? It blocks itself again after a while."
              color: card.text
              font.family: widget.fontFamily
              font.pixelSize: Style.font.heading
              wrapMode: Text.WordWrap
            }

            Row {
              spacing: Style.space(10)

              Button {
                text: "No, keep it blocked"
                bordered: true
                hasCursor: askKeys.activeFocus && !askKeys.yesSelected
                foreground: card.text
                fontFamily: widget.fontFamily
                onHovered: function(on) { if (on) askKeys.yesSelected = false }
                onClicked: widget.cancelConfirm()
              }

              Button {
                text: widget.coolOffLeft > 0 ? "Yes, unblock (" + widget.coolOffLeft + "s)" : "Yes, unblock"
                bordered: true
                hasCursor: askKeys.activeFocus && askKeys.yesSelected
                foreground: card.text
                fontFamily: widget.fontFamily
                onHovered: function(on) { if (on) askKeys.yesSelected = true }
                onClicked: widget.finishConfirm()
              }
            }

            Text {
              textFormat: Text.PlainText
              text: askKeys.activeFocus
                ? "Y / N  ·  Up to edit the reason  ·  Esc keeps it blocked"
                : "Enter to go to the buttons  ·  Esc keeps it blocked"
              color: card.faint
              font.family: widget.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
