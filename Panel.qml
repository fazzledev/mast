import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Bar toggles for the site block in ~/.dotfiles/system/site-block.
//
// Reading the state needs no privileges; flipping it goes through pkexec.
// Blocking is let straight through by a polkit rule the installer adds.
// Unblocking first opens a full-screen overlay where you type out a passage
// of around 190 words -- roughly five minutes, long enough for most urges to
// peak and pass -- then asks once more, plainly, whether you still want it
// unblocked, and only on a yes raises the shell's polkit dialog. A block you
// can lift with one stray click is not much of a block.
//
// Passages come from two pools mixed together: the hand-written ones in
// paragraphs.txt, and excerpts that fetch-passages.rb pulls from books,
// blogs and news articles and keeps in a cache, each shown with its source
// and a link. The script refreshes that cache once a week; this widget just
// runs it every few hours and it returns at once until the week is up.
//
// Every unblock is temporary: the helper arms a systemd timer that blocks the
// site again, and each row counts down to it.
//
// Blocking only stops new requests, so whenever a site turns blocked -- from
// the switch or from that timer -- close-open.sh closes its web app windows
// and reloads browser windows showing it. Otherwise a video that is already
// playing plays on.
//
// The site list comes from the helper's status output. Only the ones named in
// this widget's `sites` setting get a row -- the rest sit under a collapsed
// "More sites", where one click adds a site to the setting, and an unblocked
// row carries a remove button that takes it back out -- plus any that are blocked or
// counting down, so taking a site out of the setting never hides a block you
// would then forget about, nor lifts one.
Panel {
  id: root
  moduleName: "fazzledev.site-block"
  ipcTarget: "fazzledev.site-block"

  readonly property string helper: "/usr/local/bin/site-block"

  // [{ name, label, blocked }]. Empty until the first status read; the widget
  // stays hidden until then, and for good if the helper is not installed.
  property var sites: []
  readonly property bool installed: sites.length > 0
  // Names from the `sites` setting (see manifest.json).
  readonly property var enabledNames: {
    var v = setting("sites", ["youtube", "twitter"])
    return Array.isArray(v) ? v : String(v).split(/[,\s]+/)
  }
  // Adds and removes whose settings write has not landed yet ({ name: bool }),
  // so a row comes and goes on the click rather than a moment later.
  property var listOverrides: ({})
  readonly property var listedNames: {
    var names = enabledNames.filter(function(n) { return n && listOverrides[n] !== false })
    for (var n in listOverrides) if (listOverrides[n] === true && names.indexOf(n) === -1) names.push(n)
    return names
  }
  readonly property var shownSites: sites.filter(function(s) {
    return s.blocked || s.relockAt > 0 || listedNames.indexOf(s.name) !== -1
  })
  readonly property var hiddenSites: sites.filter(function(s) { return shownSites.indexOf(s) === -1 })
  property bool moreExpanded: false

  // One cursor runs down the site rows, the "More sites" row, then -- when it
  // is open -- the hidden sites.
  readonly property int moreIndex: hiddenSites.length > 0 ? shownSites.length : -1
  readonly property int cursorCount: shownSites.length + (hiddenSites.length > 0 ? 1 + (moreExpanded ? hiddenSites.length : 0) : 0)
  readonly property int blockedCount: shownSites.filter(function(s) { return s.blocked }).length
  readonly property bool allBlocked: installed && blockedCount === shownSites.length
  property string pendingSite: ""
  property bool pendingBlock: false
  property string lastError: ""
  property int cursorIndex: 0
  property bool cursorActive: false

  // The site being unblocked in the overlay (null when it is closed), and the
  // paragraph drawn for it.
  property var confirmingSite: null
  // Index into `passages` of the one on screen; the prev and next buttons
  // step from it.
  property int confirmIndex: -1
  property string confirmPhrase: ""
  property string confirmSource: ""
  property string confirmUrl: ""
  // Typing done; the overlay is on its yes/no question.
  property bool confirmAsking: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Brand glyphs for the sites the helper knows; anything added there later
  // falls back to the shield until it gets one here. The font has no X logo,
  // so X keeps the bird.
  // TikTok has no mark in the font either, so it gets a music note.
  readonly property var siteGlyphs: ({
    youtube: "󰗃", twitter: "󰕄", instagram: "󰋾", facebook: "󰈌",
    tiktok: "󰝚", reddit: "󰑍", twitch: "󰕃", netflix: "󰝆", hackernews: "\uf1d4"
  })
  function siteGlyph(name) { return siteGlyphs[name] || "󰕥" }
  // Unblocked sites show in their brand colour -- Twitter blue for the bird,
  // since that is the mark on screen. Unknown sites fall back to urgent.
  readonly property var siteColors: ({
    youtube: "#ff0000", twitter: "#1da1f2", instagram: "#e1306c", facebook: "#1877f2",
    tiktok: "#ff0050", reddit: "#ff4500", twitch: "#9146ff", netflix: "#e50914", hackernews: "#ff6600"
  })
  function siteColor(name) { return siteColors[name] || root.urgent }

  // The theme's terminal green from colors.toml, which the shell's Color does
  // not expose. Everything blocked shows in it; anything unblocked stands out
  // in urgent as a reminder that it is still off.
  property color green: "#4caf50"
  readonly property string barGlyph: allBlocked ? "󰕥" : "󰦞"
  readonly property color barIconColor: allBlocked ? green : urgent

  // [{ text, source, url }]. Blank-line separated paragraphs from
  // paragraphs.txt, whitespace collapsed so line wrapping in the file never
  // has to be typed, with no source...
  property var paragraphs: []
  // ...and the fetched excerpts, which have one.
  property var fetchedPassages: []
  readonly property var passages: paragraphs.concat(fetchedPassages)
  readonly property string passageCache: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/fazzledev-site-block/passages.json"

  visible: installed
  implicitWidth: installed ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  function normalise(text) {
    return String(text || "").replace(/\s+/g, " ")
  }

  function escapeHtml(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  // A random index, never the passage on screen when there is a choice.
  function randomPassageIndex() {
    if (passages.length === 0) return -1
    var next = Math.floor(Math.random() * passages.length)
    if (passages.length > 1 && passages[next].text === confirmPhrase) return randomPassageIndex()
    return next
  }

  // Switching passage starts the typing over, so hunting for an easier one
  // costs whatever was already typed.
  function showPassage(index) {
    var passage = passages[index]
    if (!passage) return
    confirmIndex = index
    confirmPhrase = passage.text
    confirmSource = passage.source
    confirmUrl = passage.url
    phraseField.text = ""
    phraseField.lastText = ""
    phraseField.lastGood = 0
    phraseField.progressLog = []
    phraseField.startedAt = 0
    phraseField.wpm = 0
    phraseField.forceActiveFocus()
  }

  function stepPassage(delta) {
    if (passages.length < 2) return
    showPassage((confirmIndex + delta + passages.length) % passages.length)
  }

  function shufflePassage() {
    if (passages.length > 1) showPassage(randomPassageIndex())
  }

  // Seconds since the epoch, ticking while anything is counting down.
  property real now: Date.now() / 1000

  function relockText(site) {
    var left = Math.max(0, site.relockAt - now)
    if (left < 60) return "Blocks again in under a minute"
    return "Blocks again in " + Math.ceil(left / 60) + " min"
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function setBlocked(site, on) {
    if (!site || toggleProc.running) return
    lastError = ""
    pendingSite = site.name
    pendingBlock = on
    toggleProc.command = ["pkexec", root.helper, on ? "on" : "off", site.name]
    toggleProc.running = true
  }

  function activate(index) {
    if (index < shownSites.length) flip(index)
    else if (index === moreIndex) moreExpanded = !moreExpanded
    else showSite(hiddenSites[index - moreIndex - 1])
  }

  // Save the `sites` setting in-process, the way the clock widget saves its
  // format. Not `omarchy bar set`: its IPC hop splits arguments on commas, which
  // breaks any JSON array longer than one element. updateEntryInline replaces
  // the whole bar entry, so every other setting is carried over. The shell
  // writes shell.json through its symlink, so the change lands in dotfiles.
  function saveSites(names) {
    if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") {
      lastError = "Could not save the site list: this bar does not allow widget settings writes."
      return
    }
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.sites = names
    bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Add a site to, or take one out of, the `sites` setting.
  function setListed(site, listed) {
    if (!site) return
    // Worked out here rather than read back from listedNames, which may not
    // have re-evaluated yet.
    var names = listedNames.filter(function(n) { return n !== site.name })
    if (listed) names.push(site.name)
    var next = Object.assign({}, listOverrides)
    next[site.name] = listed
    listOverrides = next
    saveSites(names)
    if (hiddenSites.length === 0) moreExpanded = false
    cursorIndex = Math.max(0, Math.min(cursorIndex, cursorCount - 1))
  }

  function showSite(site) { setListed(site, true) }

  // Only an unblocked site: a blocked one stays on screen regardless, and
  // removing it must never be a way round a block.
  function removable(site) { return !!site && !site.blocked }

  // A site counting down to its relock would stay on screen until the relock
  // fired and then be blocked for good, so its relock is dropped first. That
  // is root work outside the polkit rule, so it asks for auth -- the same
  // price as the unblock that started the countdown.
  function removeSite(site) {
    if (!removable(site) || forgetProc.running) return
    if (!(site.relockAt > 0)) {
      setListed(site, false)
      return
    }
    lastError = ""
    forgetProc.site = site
    forgetProc.command = ["pkexec", root.helper, "forget", site.name]
    forgetProc.running = true
  }

  function flip(index) {
    var site = shownSites[index]
    if (!site || toggleProc.running) return
    if (!site.blocked) {
      setBlocked(site, true)
      return
    }
    var index = randomPassageIndex()
    if (index < 0) {
      lastError = "No passages to type -- paragraphs.txt is missing or empty, and nothing has been fetched."
      return
    }
    showPassage(index)
    confirmAsking = false
    confirmingSite = site
    close()
  }

  function cancelConfirm() {
    confirmingSite = null
    confirmAsking = false
  }

  function askConfirm() {
    confirmAsking = true
    // No is the default: Enter straight after the last keystroke keeps the
    // block.
    askKeys.yesSelected = false
    Qt.callLater(function() { askKeys.forceActiveFocus() })
  }

  function finishConfirm() {
    var site = confirmingSite
    confirmingSite = null
    confirmAsking = false
    setBlocked(site, false)
  }

  function applyStatus(raw) {
    var next = []
    String(raw || "").split("\n").forEach(function(line) {
      var f = line.split("\t")
      if (f.length >= 3 && (f[2] === "0" || f[2] === "1")) {
        next.push({ name: f[0], label: f[1], blocked: f[2] === "1", relockAt: parseInt(f[3] || "0", 10) || 0 })
      }
    })
    // Sites that were open last time we looked and are blocked now. Nothing
    // fires on the first read, when there is no "last time" to compare with.
    var closing = []
    next.forEach(function(site) {
      var before = sites.filter(function(s) { return s.name === site.name })[0]
      if (before && !before.blocked && site.blocked) closing.push(site.name)
    })
    if (closing.length > 0) {
      Quickshell.execDetached(["bash", String(Qt.resolvedUrl("close-open.sh")).replace(/^file:\/\//, "")].concat(closing))
    }
    sites = next
    if (cursorIndex >= shownSites.length) cursorIndex = Math.max(0, shownSites.length - 1)
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    moreExpanded = false
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var m = String(text() || "").match(/^\s*green\s*=\s*"(#[0-9a-fA-F]{6,8})"/m)
      if (m) root.green = m[1]
    }
  }

  FileView {
    path: String(Qt.resolvedUrl("paragraphs.txt")).replace(/^file:\/\//, "")
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.paragraphs = String(text() || "").split(/\n\s*\n/)
      .map(function(p) { return root.normalise(p).trim() })
      .filter(function(p) { return p !== "" })
      .map(function(p) { return { text: p, source: "", url: "" } })
    onLoadFailed: root.paragraphs = []
  }

  FileView {
    id: passageFile
    path: root.passageCache
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var list = []
      try { list = JSON.parse(text() || "[]") } catch (e) {}
      root.fetchedPassages = (Array.isArray(list) ? list : []).filter(function(p) {
        return p && typeof p.text === "string" && p.text.trim() !== ""
      }).map(function(p) {
        return { text: root.normalise(p.text).trim(), source: String(p.source || ""), url: String(p.url || "") }
      })
    }
    onLoadFailed: root.fetchedPassages = []
  }

  // Every few hours, so a missed week (asleep, offline) is caught up soon.
  Timer {
    interval: 6 * 3600 * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!fetchProc.running) fetchProc.running = true
  }

  Process {
    id: fetchProc
    command: ["ruby", String(Qt.resolvedUrl("fetch-passages.rb")).replace(/^file:\/\//, "")]
    // The watch misses the cache being created for the first time.
    onExited: passageFile.reload()
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.blockedCount < root.shownSites.length
    onTriggered: {
      root.now = Date.now() / 1000
      // Pick up the relock as soon as it is due rather than on the next poll.
      if (root.sites.some(function(s) { return !s.blocked && s.relockAt > 0 && s.relockAt <= root.now })) root.refresh()
    }
  }

  Timer {
    interval: 15000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    // Through sh so a missing helper is a quiet non-zero exit rather than a
    // failed-to-start warning in the journal every poll.
    command: ["sh", "-c", "[ -x \"$1\" ] || exit 127; exec \"$1\" status", "sh", root.helper]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStatus(text) }
    onExited: function(exitCode) { if (exitCode !== 0) root.sites = [] }
  }

  Process {
    id: toggleProc
    stderr: StdioCollector { id: toggleStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.pendingSite = ""
      // 126 is pkexec's "dismissed the dialog" -- not worth an error line.
      if (exitCode !== 0 && exitCode !== 126) {
        root.lastError = String(toggleStderr.text || "").trim() || ("Failed (exit " + exitCode + ")")
      }
      root.refresh()
    }
  }

  Process {
    id: forgetProc
    property var site: null
    stderr: StdioCollector { id: forgetStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.setListed(forgetProc.site, false)
      else if (exitCode !== 126) root.lastError = String(forgetStderr.text || "").trim() || ("Failed (exit " + exitCode + ")")
      forgetProc.site = null
      root.refresh()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barGlyph
    foreground: root.barIconColor
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.cursorIndex = Math.max(0, Math.min(root.cursorCount - 1, root.cursorIndex + dy))
      }
      onActivateRequested: if (root.cursorActive) root.activate(root.cursorIndex)
      onDeleteRequested: if (root.cursorActive && root.cursorIndex < root.shownSites.length) root.removeSite(root.shownSites[root.cursorIndex])
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Site Block"
          meta: root.blockedCount + " of " + root.shownSites.length + " blocked"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: root.barGlyph
              color: root.barIconColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.shownSites

            SiteRow {
              required property var modelData
              required property int index
              width: parent.width
              site: modelData
              rowIndex: index
            }
          }

          MoreRow {
            visible: root.hiddenSites.length > 0
            width: parent.width
          }

          Repeater {
            model: root.moreExpanded ? root.hiddenSites : []

            HiddenSiteRow {
              required property var modelData
              required property int index
              width: parent.width
              site: modelData
              rowIndex: root.moreIndex + 1 + index
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.lastError !== ""
          width: parent.width
          text: root.lastError
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  // ------------------------------------------------------ unblock overlay
  PanelWindow {
    id: overlay
    visible: root.confirmingSite !== null
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "fazzledev-site-block"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
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
      onClicked: root.confirmAsking ? askKeys.forceActiveFocus() : phraseField.forceActiveFocus()
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
      readonly property string siteName: root.confirmingSite ? root.confirmingSite.name : ""

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
            text: root.siteGlyph(card.siteName)
            color: root.siteColor(card.siteName)
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: "Unblock " + (root.confirmingSite ? root.confirmingSite.label : "") + "?"
              color: card.text
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: root.confirmAsking
                ? "You typed it all out. One last question."
                : "Type this out first. Take your time -- the urge will pass while you do."
              color: card.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        // What is typed so far in full colour, the rest faint. Styled text is
        // not selectable, so the paragraph cannot be copied into the field.
        Text {
          visible: !root.confirmAsking
          width: parent.width
          textFormat: Text.StyledText
          text: {
            var done = phraseField.progress
            return "<font color='" + card.text + "'>" + root.escapeHtml(root.confirmPhrase.slice(0, done)) + "</font>"
              + "<font color='" + card.faint + "'>" + root.escapeHtml(root.confirmPhrase.slice(done)) + "</font>"
          }
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          lineHeight: 1.35
          wrapMode: Text.WordWrap
        }

        // Where the passage is from, and buttons to swap it for another.
        Item {
          visible: !root.confirmAsking
          width: parent.width
          height: Math.max(sourceColumn.implicitHeight, passageControls.implicitHeight)

          // The link opens behind this overlay, to read once you are done here.
          Column {
            id: sourceColumn
            visible: root.confirmSource !== ""
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - passageControls.width - Style.space(16)
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "-- " + root.confirmSource
              color: card.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.italic: true
              wrapMode: Text.WordWrap
            }

            Text {
              visible: root.confirmUrl !== ""
              textFormat: Text.PlainText
              width: parent.width
              text: root.confirmUrl
              color: sourceLink.containsMouse ? card.text : card.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.underline: true
              elide: Text.ElideMiddle

              MouseArea {
                id: sourceLink
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  Qt.openUrlExternally(root.confirmUrl)
                  phraseField.forceActiveFocus()
                }
              }
            }
          }

          Row {
            id: passageControls
            visible: root.passages.length > 1
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰒮"
              tooltipText: "Previous passage (Alt+Left)"
              foreground: card.text
              fontFamily: root.fontFamily
              onClicked: root.stepPassage(-1)
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: (root.confirmIndex + 1) + " / " + root.passages.length
              color: card.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰒭"
              tooltipText: "Next passage (Alt+Right)"
              foreground: card.text
              fontFamily: root.fontFamily
              onClicked: root.stepPassage(1)
            }

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰒝"
              tooltipText: "Random passage (Alt+S)"
              foreground: card.text
              fontFamily: root.fontFamily
              onClicked: root.shufflePassage()
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
          }

          // Ticks so the figure falls off when typing stops, not only when a
          // key moves it.
          Timer {
            interval: 500
            repeat: true
            running: overlay.visible && !root.confirmAsking && phraseField.startedAt > 0
            onTriggered: phraseField.updateWpm()
          }
          readonly property string typed: root.normalise(text)
          readonly property bool onTrack: root.confirmPhrase.indexOf(typed) === 0
          readonly property int progress: onTrack ? typed.length : lastGood

          visible: !root.confirmAsking
          width: parent.width
          height: Math.max(Style.space(120), implicitHeight)
          wrapMode: TextArea.Wrap
          placeholderText: "Start typing…"
          color: onTrack ? card.text : root.urgent
          placeholderTextColor: card.faint
          selectionColor: Style.selectionFillFor(card.text, Color.accent)
          font.family: root.fontFamily
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
            var now = root.normalise(text)
            if (root.confirmPhrase.indexOf(now) === 0) lastGood = now.length
            if (text !== "") logProgress()
            if (now.trim() === root.confirmPhrase) root.askConfirm()
          }
          Keys.onPressed: function(event) {
            if (event.matches(StandardKey.Paste)) {
              event.accepted = true
            } else if (event.modifiers & Qt.AltModifier) {
              if (event.key === Qt.Key_Left) root.stepPassage(-1)
              else if (event.key === Qt.Key_Right) root.stepPassage(1)
              else if (event.key === Qt.Key_S) root.shufflePassage()
              else return
              event.accepted = true
            }
          }
          Keys.onReturnPressed: function(event) { event.accepted = true }
          Keys.onEnterPressed: function(event) { event.accepted = true }
          Keys.onEscapePressed: function(event) {
            event.accepted = true
            root.cancelConfirm()
          }
        }

        Item {
          visible: !root.confirmAsking
          width: parent.width
          height: progressText.implicitHeight

          Text {
            id: progressText
            textFormat: Text.PlainText
            anchors.left: parent.left
            readonly property int wordsDone: phraseField.progress === 0 ? 0 : root.confirmPhrase.slice(0, phraseField.progress).trim().split(" ").length
            readonly property int wordsTotal: root.confirmPhrase.split(" ").length
            text: phraseField.onTrack
              ? wordsDone + " of " + wordsTotal + " words" + (phraseField.startedAt > 0 ? "  ·  " + phraseField.wpm + " wpm" : "")
              : "Typo -- fix it to keep going"
            color: phraseField.onTrack ? card.faint : root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            text: "Esc to keep it blocked"
            color: card.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // The yes/no step. Keys live on this item so the buttons stay plain.
        Item {
          id: askKeys
          visible: root.confirmAsking
          width: parent.width
          height: askColumn.implicitHeight
          focus: root.confirmAsking

          property bool yesSelected: false

          Keys.onPressed: function(event) {
            switch (event.key) {
            case Qt.Key_Left:
            case Qt.Key_Right:
            case Qt.Key_Tab:
            case Qt.Key_Backtab:
              askKeys.yesSelected = !askKeys.yesSelected
              break
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
              if (askKeys.yesSelected) root.finishConfirm()
              else root.cancelConfirm()
              break
            case Qt.Key_Y:
              root.finishConfirm()
              break
            case Qt.Key_N:
            case Qt.Key_Escape:
              root.cancelConfirm()
              break
            default:
              return
            }
            event.accepted = true
          }

          Column {
            id: askColumn
            width: parent.width
            spacing: Style.space(18)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "Do you still want to unblock " + (root.confirmingSite ? root.confirmingSite.label : "") + "? It blocks itself again after a while."
              color: card.text
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              wrapMode: Text.WordWrap
            }

            Row {
              spacing: Style.space(10)

              Button {
                text: "No, keep it blocked"
                bordered: true
                hasCursor: !askKeys.yesSelected
                foreground: card.text
                fontFamily: root.fontFamily
                onHovered: function(on) { if (on) askKeys.yesSelected = false }
                onClicked: root.cancelConfirm()
              }

              Button {
                text: "Yes, unblock"
                bordered: true
                hasCursor: askKeys.yesSelected
                foreground: card.text
                fontFamily: root.fontFamily
                onHovered: function(on) { if (on) askKeys.yesSelected = true }
                onClicked: root.finishConfirm()
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "Y / N  ·  Esc keeps it blocked"
              color: card.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }

  // Expands and collapses the list of sites not in the setting.
  component MoreRow: CursorSurface {
    id: moreRow
    hasCursor: root.cursorActive && root.cursorIndex === root.moreIndex
    foreground: root.foreground
    implicitHeight: moreContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.cursorIndex = root.moreIndex
      }
      onClicked: root.moreExpanded = !root.moreExpanded
    }

    Row {
      id: moreContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      spacing: Style.space(10)

      Text {
        id: chevron
        anchors.verticalCenter: parent.verticalCenter
        width: Style.font.heading * 1.4
        horizontalAlignment: Text.AlignHCenter
        text: root.moreExpanded ? "󰅀" : "󰅂"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "More sites (" + root.hiddenSites.length + ")"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }

  // A site not in the setting: its mark, its name, and a click to show it.
  component HiddenSiteRow: CursorSurface {
    id: hiddenRow
    property var site: null
    property int rowIndex: 0

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    foreground: root.foreground
    implicitHeight: hiddenContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.cursorIndex = hiddenRow.rowIndex
      }
      onClicked: root.showSite(hiddenRow.site)
    }

    Row {
      id: hiddenContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      spacing: Style.space(10)

      Text {
        id: hiddenIcon
        anchors.verticalCenter: parent.verticalCenter
        width: Style.font.heading * 1.4
        horizontalAlignment: Text.AlignHCenter
        text: root.siteGlyph(hiddenRow.site ? hiddenRow.site.name : "")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - hiddenIcon.width - addLabel.width - parent.spacing * 2
        textFormat: Text.PlainText
        text: hiddenRow.site ? hiddenRow.site.label : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: addLabel
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Add"
        color: hiddenRow.hasCursor ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // Icon, name, state, switch. Not the kit's Toggle, which has no icon slot.
  component SiteRow: CursorSurface {
    id: siteRow
    property var site: null
    property int rowIndex: 0
    readonly property bool pending: site !== null && root.pendingSite === site.name
    readonly property bool blocked: site !== null && site.blocked

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    foreground: root.foreground
    implicitHeight: siteContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.cursorIndex = siteRow.rowIndex
      }
      onClicked: root.flip(siteRow.rowIndex)
    }

    Row {
      id: siteContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      spacing: Style.space(10)

      Text {
        id: siteIcon
        anchors.verticalCenter: parent.verticalCenter
        width: Style.font.heading * 1.4
        horizontalAlignment: Text.AlignHCenter
        text: root.siteGlyph(siteRow.site ? siteRow.site.name : "")
        // Blocked recedes; unblocked stands out in the site's own colour.
        color: siteRow.blocked ? root.dim : root.siteColor(siteRow.site ? siteRow.site.name : "")
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - siteIcon.width - siteSwitch.width - parent.spacing * 2
          - (removeButton.visible ? removeButton.width + parent.spacing : 0)
        spacing: Style.spacing.xs

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: siteRow.site ? siteRow.site.label : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: siteRow.pending ? (root.pendingBlock ? "Blocking…" : "Waiting for authentication…") : (siteRow.blocked ? "Blocked" : (siteRow.site && siteRow.site.relockAt > 0 ? root.relockText(siteRow.site) : "Not blocked"))
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      // Shown under the cursor only, so the resting panel stays a column of
      // switches. Delete does the same from the keyboard.
      PanelActionButton {
        id: removeButton
        anchors.verticalCenter: parent.verticalCenter
        visible: siteRow.hasCursor && root.removable(siteRow.site)
        iconText: "󰅖"
        tooltipText: "Remove from list"
        foreground: root.foreground
        hoverColor: root.urgent
        fontFamily: root.fontFamily
        onClicked: root.removeSite(siteRow.site)
      }

      // The row owns the click, so the switch is presentation only.
      ToggleSwitch {
        id: siteSwitch
        anchors.verticalCenter: parent.verticalCenter
        checked: siteRow.blocked
        busy: siteRow.pending
        interactive: false
        foreground: root.allBlocked ? root.green : root.foreground
        accent: root.allBlocked ? root.green : Color.accent
      }
    }
  }
}
