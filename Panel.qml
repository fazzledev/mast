import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The screens this is made of, each with the rows it is built from.
import "views/panel"
import "views/settings"
import "views/unblock"

// Mast: bar toggles for the site block that system/ installs. Named
// for Ulysses, who had himself tied to the mast before the Sirens could sing.
//
// Reading the state needs no privileges; flipping it goes through pkexec.
// Blocking is let straight through by a polkit rule the installer adds.
// Unblocking first opens a full-screen overlay where you type out a passage
// of around 190 words -- roughly five minutes, long enough for most urges to
// peak and pass -- then asks once more, plainly, whether you still want it
// unblocked, and only on a yes raises the shell's polkit dialog. A block you
// can lift with one stray click is not much of a block.
//
// Passages come from three pools mixed together: the ten hand-written ones in
// config/paragraphs.txt, and, in config/passages.json, 300 excerpts from
// public domain books and 43 from articles in The Conversation, shared under
// CC BY-ND 4.0. Each is shown with its source, a link, and its licence where
// it has one; any pool can be turned off. The ones that win battles come up
// more often, and any passage can be hidden for good.
//
// Before the yes/no, the question page shows the passage again with how the
// typing went, and asks why you want the site. Each attempt -- the passages
// shown, how far each got, the answer, and how it ended -- goes to a SQLite
// record through bin/mast-db, which also serves the week's numbers shown
// here and lets you look back at your reasons from a terminal. The Ruby side
// is laid out like a Rails app, without the gems: see lib/mast.rb.
//
// Most of this can be tuned from a settings screen (the gear in the panel
// header, or S): passage switching, the live wpm, how many words the why
// needs, a wait before yes, how long an unblock lasts, which passage pools
// are used, and the display extras. They are ordinary widget settings,
// declared in manifest.json and saved to shell.json. The same screen has a
// History tab: the week's numbers, recent attempts with their reasons, and
// how each passage has fared.
//
// Every unblock is temporary: the helper arms a systemd timer that blocks the
// site again, and each row counts down to it.
//
// Blocking only stops new requests, so whenever a site turns blocked -- from
// the switch or from that timer -- bin/close-open closes its web app windows
// and reloads browser windows showing it. Otherwise a video that is already
// playing plays on.
//
// The site list comes from the helper's status output. Only the ones named in
// this widget's `sites` setting get a row -- the rest sit under a collapsed
// "More sites", where one click adds a site to the setting, and an unblocked
// row carries a remove button that takes it back out -- plus any that are blocked or
// counting down, so taking a site out of the setting never hides a block you
// would then forget about, nor lifts one.
//
// This file is the widget: the state, the settings, the bar icon and the
// panel, and the IPC targets -- including fazzledev.mast.test, which drives
// the whole thing without a keyboard for test/shell. The screens are in
// views/, a folder each for the panel's rows, the settings, the history and
// the unblock overlay; Recorder.qml is everything that reaches the record.
Panel {
  id: root
  moduleName: "fazzledev.mast"
  ipcTarget: "fazzledev.mast"

  readonly property string helper: "/usr/local/bin/mast"

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
  property string confirmId: ""
  property string confirmPhrase: ""
  property string confirmSource: ""
  property string confirmUrl: ""
  // A licence the passage is shared under, for the ones that need crediting.
  property string confirmLicense: ""
  property string confirmLicenseUrl: ""
  // Typing done; the overlay is on its yes/no question.
  property bool confirmAsking: false
  // The attempt being recorded, the number of the passage view within it,
  // and the typing figures once a passage is finished:
  // { seconds, words, wpm, peakWpm, typos }.
  property string attemptId: ""
  property int viewSeq: -1
  property var typedSummary: null
  // The attempt waiting on the password prompt, and its answer to why.
  property string authAttempt: ""
  property string authReason: ""
  // Set when yes is chosen before the why is answered.
  property bool reasonMissing: false
  // setPassageHidden writes to these before the record comes back, so no alias
  // of them is read-only.
  property alias stats: db.stats

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
  // A boat under sail while everything is blocked; one going down while
  // anything is not.
  readonly property string barGlyph: allBlocked ? "󰻈" : "󱫯"
  readonly property color barIconColor: allBlocked ? (cfg("greenWhenBlocked") ? green : Qt.darker(barForeground, 1.55)) : urgent

  // The passages to type, watched on disk, and which of them are in play.
  Passages {
    id: pool
    sources: ({ paragraphs: root.cfg("sourceParagraphs"), books: root.cfg("sourceBooks"), news: root.cfg("sourceNews") })
    scores: root.stats.passages || ({})
  }

  readonly property alias allPassages: pool.all
  readonly property alias passages: pool.available
  function passageKind(passage) { return pool.kind(passage) }

  visible: installed
  implicitWidth: installed ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  function normalise(text) {
    return String(text || "").replace(/\s+/g, " ")
  }

  function escapeHtml(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  // Never the passage on screen, when there is a choice.
  function randomPassageIndex() { return pool.randomIndex(confirmPhrase) }

  // Never shows the passage again. Its record stays, and the History tab can
  // bring it back.
  function setPassageHidden(passage, hidden) {
    if (!passage || !passage.id) return
    record({ type: "hide", passage_id: passage.id, text: passage.text, source: passage.source, url: passage.url, hidden: hidden })
    // Straight away, rather than when the stats next come back.
    var next = Object.assign({}, stats)
    next.passages = Object.assign({}, stats.passages || {})
    next.passages[passage.id] = Object.assign({ won: 0, lost: 0 }, next.passages[passage.id] || {}, { hidden: hidden })
    stats = next
  }

  function hideCurrentPassage() {
    if (!cfg("allowSwitching")) return
    var current = { id: confirmId, text: confirmPhrase, source: confirmSource, url: confirmUrl }
    setPassageHidden(current, true)
    showPassage(randomPassageIndex())
  }

  // Switching passage starts the typing over, so hunting for an easier one
  // costs whatever was already typed.
  function showPassage(index) {
    var passage = passages[index]
    if (!passage) return
    if (attemptId !== "" && viewSeq >= 0) {
      record({ type: "leave", attempt: attemptId, seq: viewSeq, chars: overlay.typed })
    }
    confirmIndex = index
    confirmId = passage.id
    confirmPhrase = passage.text
    confirmSource = passage.source
    confirmUrl = passage.url
    confirmLicense = passage.license || ""
    confirmLicenseUrl = passage.licenseUrl || ""
    overlay.resetTyping()
    if (attemptId !== "") {
      viewSeq += 1
      record({ type: "passage", attempt: attemptId, seq: viewSeq, passage_id: passage.id, text: passage.text, source: passage.source, url: passage.url })
    }
  }

  function stepPassage(delta) {
    if (!cfg("allowSwitching") || passages.length < 2) return
    showPassage((confirmIndex + delta + passages.length) % passages.length)
  }

  function shufflePassage() {
    if (cfg("allowSwitching") && passages.length > 1) showPassage(randomPassageIndex())
  }

  // Test mode (see the `fazzledev.mast.test` IPC target below) runs in the
  // test environment, which keeps its attempts in a database of their own.
property bool testMode: false

// What test mode reaches into; see TestHarness.qml.
readonly property alias overlayView: overlay
readonly property alias settingsView: settingsWindow
readonly property alias siteRows: siteRepeater

  // The record: every event goes through here, and the numbers come back.
  Recorder {
    id: db
    testMode: root.testMode
    keepHistoryFresh: root.settingsOpen
  }

  function record(event) { db.record(event) }
  function refreshStats() { db.refreshStats() }
  function refreshHistory() { db.refreshHistory() }

  function siteStats(name) {
    return (stats.sites && stats.sites[name]) || { attempts: 0, stayed: 0, unblocked: 0, unblocked_seconds: 0 }
  }

  function formatDuration(seconds) {
    seconds = Math.round(seconds)
    if (seconds < 60) return seconds + "s"
    if (seconds < 3600) return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")
    return Math.floor(seconds / 3600) + "h " + Math.floor(seconds % 3600 / 60) + "m"
  }

  // Every attempt that did not end in an unblock is a battle won.
  function battlesText() {
    var all = stats.week || {}
    return all.stayed + " of " + all.attempts + " unblock " + (all.attempts === 1 ? "battle" : "battles") + " won"
  }

  // The week so far, as a reminder on both overlay pages.
  function weekText(site) {
    if (!site || !cfg("showWeekStats")) return ""
    var here = siteStats(site.name)
    var all = stats.week || {}
    var parts = []
    if (here.unblocked > 0) {
      parts.push("You unblocked " + site.label + " " + (here.unblocked === 1 ? "once" : here.unblocked + " times")
        + " in the last week, for " + Math.round(here.unblocked_seconds / 60) + " min.")
    }
    if (all.attempts > 0) parts.push(battlesText() + " this week.")
    return parts.join(" ")
  }

  function reasonGiven() {
    var need = cfg("reasonWords")
    return need <= 0 || overlay.reasonText.trim().split(/\s+/).filter(function(w) { return w !== "" }).length >= need
  }

  // The wait before yes: when it ends, and a clock that ticks until then.
  property real yesAt: 0
  property real askClock: 0
  readonly property int coolOffLeft: Math.ceil(Math.max(0, yesAt - askClock) / 1000)

  Timer {
    interval: 250
    repeat: true
    running: root.confirmAsking && root.coolOffLeft > 0
    onTriggered: root.askClock = Date.now()
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
    toggleProc.command = on
      ? ["pkexec", root.helper, "on", site.name]
      : ["pkexec", root.helper, "off", site.name, String(cfg("relockMinutes"))]
    toggleProc.running = true
  }

  function activate(index) {
    if (index < shownSites.length) flip(index)
    else if (index === moreIndex) moreExpanded = !moreExpanded
    else showSite(hiddenSites[index - moreIndex - 1])
  }

  // Save settings in-process, the way the clock widget saves its format. Not
  // `omarchy bar set`: its IPC hop splits arguments on commas, which breaks any
  // JSON array longer than one element. updateEntryInline replaces the whole
  // bar entry, so every other setting -- including changes still on their way
  // -- is carried over, and shell.json is written wherever it lives,
  // symlinked into dotfiles or not.
  function saveSettings(patch) {
    if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") {
      lastError = "Could not save settings: this bar does not allow widget settings writes."
      return
    }
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    for (var pending in settingOverrides) entry[pending] = settingOverrides[pending]
    for (var changed in patch) entry[changed] = patch[changed]
    bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function saveSites(names) { saveSettings({ sites: names }) }

  // ------------------------------------------------------------ settings
  // Defaults match manifest.json. Changes show at once through the overrides
  // and reach shell.json a moment later.
  readonly property var settingDefaults: ({
    allowSwitching: true, showWpm: true, reasonWords: 3, coolOffSeconds: 0, relockMinutes: 15,
    sourceParagraphs: true, sourceBooks: true, sourceNews: true,
    greenWhenBlocked: true, showWeekStats: true
  })
  property var settingOverrides: ({})
  // Test mode's settings, never saved; `stop` drops them.
  property var testOverrides: ({})

  function cfg(key) {
    if (testOverrides[key] !== undefined) return testOverrides[key]
    if (settingOverrides[key] !== undefined) return settingOverrides[key]
    return setting(key, settingDefaults[key])
  }

  function setCfg(key, value) {
    var next = Object.assign({}, settingOverrides)
    next[key] = value
    settingOverrides = next
    var patch = {}
    patch[key] = value
    saveSettings(patch)
  }

  // The settings popover's rows. `section` rows are headings; the rest take
  // the cursor, in order.
  readonly property var settingsRows: [
    { section: "Typing challenge" },
    { key: "allowSwitching", type: "bool", label: "Switch passages", description: "Previous, next and shuffle on the unblock screen" },
    { key: "showWpm", type: "bool", label: "Live typing speed", description: "Words per minute while you type" },
    { key: "reasonWords", type: "int", min: 0, max: 20, step: 1, unit: " words", label: "Why needs", description: "Words the why answer needs before yes works; 0 makes it optional" },
    { key: "coolOffSeconds", type: "int", min: 0, max: 300, step: 15, unit: "s", label: "Wait before yes", description: "After the passage is typed" },
    { section: "Relock" },
    { key: "relockMinutes", type: "int", min: 1, max: 60, step: 1, unit: " min", label: "Unblock lasts", description: "Then the site blocks itself again. The helper caps it at 60." },
    { section: "Passages" },
    { key: "sourceParagraphs", type: "bool", kind: "paragraphs", label: "Your paragraphs", description: "config/paragraphs.txt" },
    { key: "sourceBooks", type: "bool", kind: "books", label: "Books", description: "Seneca, Marcus Aurelius, Epictetus, William James, Bennett, Thoreau and more, all public domain" },
    { key: "sourceNews", type: "bool", kind: "news", label: "News", description: "Researchers writing in The Conversation, shared under CC BY-ND 4.0" },
    { section: "Display" },
    { key: "greenWhenBlocked", type: "bool", label: "Green when all blocked", description: "Bar icon and switches" },
    { key: "showWeekStats", type: "bool", label: "Week stats", description: "Unblock battles won, in the panel and the unblock screen" }
  ]
  readonly property var settingsItems: settingsRows.filter(function(r) { return !r.section })

  // The two columns of the settings tab: up to Passages, and from there.
  readonly property int settingsSplit: {
    for (var i = 0; i < settingsRows.length; i++) if (settingsRows[i].section === "Passages") return i
    return settingsRows.length
  }

  property bool settingsOpen: false
  property string settingsTab: "settings"  // or "history"
  property int settingsCursor: 0
  property bool settingsCursorActive: false

  property alias historyData: db.historyData

  function openSettings(tab) {
    close()
    settingsTab = tab || "settings"
    settingsCursorActive = false
    settingsCursor = 0
    settingsOpen = true
    refreshHistory()
  }

  function switchSettingsTab() {
    settingsTab = settingsTab === "settings" ? "history" : "settings"
    if (settingsTab === "history") refreshHistory()
  }

  readonly property var outcomeLabels: ({
    walked_away: "Walked away", kept_blocked: "Kept blocked", auth_dismissed: "Closed the password prompt",
    failed: "Unblock failed", unblocked: "Unblocked", interrupted: "Interrupted", in_progress: "In progress"
  })
  function outcomeWon(outcome) { return ["walked_away", "kept_blocked", "auth_dismissed", "failed", "interrupted"].indexOf(outcome) !== -1 }
  function outcomeColor(outcome) { return outcome === "unblocked" ? urgent : outcomeWon(outcome) ? green : dim }

  function averageWpm() {
    var typed = historyData.attempts.filter(function(a) { return a.wpm > 0 })
    if (typed.length === 0) return 0
    return Math.round(typed.reduce(function(sum, a) { return sum + a.wpm }, 0) / typed.length)
  }

  function settingDescription(item) {
    if (!item.kind) return item.description
    var count = pool.count(item.kind)
    return item.description + "  ·  " + count + (count === 1 ? " passage" : " passages")
  }

  function adjustSetting(item, direction) {
    if (!item || item.type !== "int") return
    setCfg(item.key, Math.max(item.min, Math.min(item.max, cfg(item.key) + direction * item.step)))
  }

  function activateSetting(item) {
    if (!item) return
    if (item.type === "bool") setCfg(item.key, !cfg(item.key))
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
    beginAttempt(site)
    close()
  }

  // Opens the overlay on a new attempt to unblock `site`.
  function beginAttempt(site) {
    var index = randomPassageIndex()
    if (index < 0) {
      lastError = "No passages to type -- config/paragraphs.txt is missing or empty, and nothing has been fetched."
      return false
    }
    attemptId = Date.now().toString(36) + Math.random().toString(36).slice(2, 8)
    viewSeq = -1
    typedSummary = null
    record({ type: "start", attempt: attemptId, site: site.name, label: site.label })
    showPassage(index)
    confirmAsking = false
    confirmingSite = site
    refreshStats()
    return true
  }

  // Esc while typing is walking away; no on the question keeps the block,
  // with whatever was written as the reason.
  function cancelConfirm() {
    if (attemptId !== "") {
      if (confirmAsking) {
        record({ type: "end", attempt: attemptId, outcome: "kept_blocked", reason: overlay.reasonText })
      } else {
        record({ type: "leave", attempt: attemptId, seq: viewSeq, chars: overlay.typed })
        record({ type: "end", attempt: attemptId, outcome: "walked_away" })
      }
    }
    attemptId = ""
    confirmingSite = null
    confirmAsking = false
  }

  function askConfirm() {
    typedSummary = overlay.summarizeTyping()
    record({ type: "typed", attempt: attemptId, seq: viewSeq, chars: overlay.typed,
             typing_ms: Math.round(typedSummary.seconds * 1000), wpm: typedSummary.wpm,
             peak_wpm: typedSummary.peakWpm, typos: typedSummary.typos })
    reasonMissing = false
    askClock = Date.now()
    yesAt = askClock + cfg("coolOffSeconds") * 1000
    confirmAsking = true
    overlay.beginAsking()
  }

  // A reason of a few words is the price of yes, and so is the wait -- from
  // the button, Y or Enter alike.
  function finishConfirm() {
    if (Date.now() < yesAt) {
      askClock = Date.now()
      return
    }
    if (!reasonGiven()) {
      reasonMissing = true
      overlay.focusReason()
      return
    }
    var site = confirmingSite
    authAttempt = attemptId
    authReason = overlay.reasonText.trim()
    attemptId = ""
    confirmingSite = null
    confirmAsking = false
    if (testMode) {
      // Nothing is unblocked and no password prompt appears; the record
      // shows what a successful unblock would have written.
      record({ type: "end", attempt: authAttempt, reason: authReason, outcome: "unblocked" })
      authAttempt = ""
      return
    }
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
      if (!before) return
      if (!before.blocked && site.blocked) {
        closing.push(site.name)
        record({ type: "blocked_again", site: site.name })
      } else if (before.blocked && !site.blocked && site.relockAt > 0) {
        record({ type: "relock", site: site.name, relock_at: site.relockAt })
      }
    })
    if (closing.length > 0) {
      Quickshell.execDetached(["bash", String(Qt.resolvedUrl("bin/close-open")).replace(/^file:\/\//, "")].concat(closing))
    }
    sites = next
    if (cursorIndex >= shownSites.length) cursorIndex = Math.max(0, shownSites.length - 1)
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    moreExpanded = false
    refresh()
    refreshStats()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // Test mode, for checking the widget end to end without a real unblock,
  // over an IPC target of its own. See TestHarness.qml and test/shell.
  TestHarness {
    widget: root
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
      if (root.authAttempt !== "") {
        root.record({ type: "end", attempt: root.authAttempt, reason: root.authReason,
                      outcome: exitCode === 0 ? "unblocked" : exitCode === 126 ? "auth_dismissed" : "failed" })
        root.authAttempt = ""
      }
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
      onTextKey: function(key) { if (key === "s" || key === "S") root.openSettings("settings") }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          id: siteBlockHero
          width: parent.width
          title: "Mast"
          // Inside the hero's own components `root` is the hero, so they
          // reach this panel through the hero's id.
          readonly property var panelRoot: root
          trailingControl: Component {
            Row {
              spacing: Style.space(2)

              PanelActionButton {
                iconText: "\u{F02DA}"
                tooltipText: "History"
                foreground: siteBlockHero.foreground
                fontFamily: siteBlockHero.fontFamily
                onClicked: siteBlockHero.panelRoot.openSettings("history")
              }

              PanelActionButton {
                iconText: "\u{F0493}"
                tooltipText: "Settings (S)"
                foreground: siteBlockHero.foreground
                fontFamily: siteBlockHero.fontFamily
                onClicked: siteBlockHero.panelRoot.openSettings("settings")
              }
            }
          }
          meta: root.blockedCount + " of " + root.shownSites.length + " sites blocked"
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

        Text {
          visible: text !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.cfg("showWeekStats") && root.stats.week && root.stats.week.attempts > 0
            ? root.battlesText() + " this week" : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            id: siteRepeater
            model: root.shownSites

            SiteRow {

              widget: root
              required property var modelData
              required property int index
              width: parent.width
              site: modelData
              rowIndex: index
            }
          }

          MoreRow {

            widget: root
            visible: root.hiddenSites.length > 0
            width: parent.width
          }

          Repeater {
            model: root.moreExpanded ? root.hiddenSites : []

            HiddenSiteRow {

              widget: root
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

  // ------------------------------------------------------ settings and history
  // `omarchy-shell fazzledev.mast.settings open` (or `history`), for a
  // keybinding.
  IpcHandler {
    target: "fazzledev.mast.settings"
    function open(): void { root.openSettings("settings") }
    function history(): void { root.openSettings("history") }
    function close(): void { root.settingsOpen = false }
    function toggle(): void { if (root.settingsOpen) root.settingsOpen = false; else root.openSettings("settings") }
  }

  SettingsWindow {
    id: settingsWindow
    widget: root
  }

  // ------------------------------------------------------ unblock overlay
  UnblockOverlay {
    id: overlay
    widget: root
  }
}
