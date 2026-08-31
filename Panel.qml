import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "grenco.snapman"
  ipcTarget: "grenco.snapman"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var snapshots: []
  property var filteredSnapshots: computeFiltered()
  property var bootableById: ({})
  property int selectedIndex: 0
  property string changes: "Loading snapshots..."
  property string statusMessage: ""
  property string pendingAction: ""
  property int pendingSnapshotNumber: -1
  property string listOutput: ""
  property string changesOutput: ""
  property string limineOutput: ""
  property string diskUsage: ""
  property var changesBySnapshot: ({})
  property int previewNumber: -1
  property int queuedPreviewNumber: -1
  property bool loading: false
  property string filterText: ""
  property bool editingDescription: false
  property bool cleanupMode: false
  property string cleanupTab: "retention"
  property string retentionMode: "count"
  property int retentionCountValue: 5
  property int retentionAgeValue: 30
  property string bulkMode: "age"
  property int bulkAgeValue: 30
  property int bulkCountValue: 5
  property bool ageTimerActive: false
  property int pendingBulkCount: 0
  property var pendingBulkNumbers: []
  property string updateOutput: ""
  property string updateState: "idle"
  property string installedVersion: ""
  property string availableVersion: ""
  property string localCommit: ""
  property string remoteCommit: ""
  property string verificationLabel: ""
  property bool verificationVerified: false
  property double lastUpdateCheckAt: 0

  readonly property bool hasSelection: filteredSnapshots.length > 0 && selectedIndex >= 0 && selectedIndex < filteredSnapshots.length
  readonly property var selected: hasSelection ? filteredSnapshots[selectedIndex] : null
  readonly property bool inputActive: filterField.activeFocus || descriptionField.activeFocus
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function computeFiltered() {
    var q = String(filterText || "").trim().toLowerCase()
    if (!q) return snapshots
    return snapshots.filter(function(s) {
      return String(s.number).indexOf(q) !== -1 ||
        String(s.description || "").toLowerCase().indexOf(q) !== -1 ||
        String(s.date || "").toLowerCase().indexOf(q) !== -1
    })
  }

  function relativeAge(dateStr) {
    if (!dateStr) return ""
    var p = String(dateStr).split(/[- :]/)
    if (p.length < 6) return dateStr
    var then = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]), Number(p[3]), Number(p[4]), Number(p[5]))
    var diff = Math.floor((new Date() - then) / 1000)
    if (diff < 0) diff = 0
    if (diff < 60) return "just now"
    if (diff < 3600) return Math.floor(diff / 60) + "m ago"
    if (diff < 86400) return Math.floor(diff / 3600) + "h ago"
    var days = Math.floor(diff / 86400)
    if (days < 30) return days + "d ago"
    if (days < 365) return Math.floor(days / 30) + "mo ago"
    return Math.floor(days / 365) + "y ago"
  }

  function formatSize(u) {
    if (u === null || u === undefined || u === "") return ""
    var n = Number(u)
    if (!isFinite(n) || n <= 0) return ""
    var units = ["B", "KB", "MB", "GB", "TB"]
    var i = 0
    while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
    return n.toFixed(i === 0 ? 0 : 1) + " " + units[i]
  }

  function isBootable(s) {
    return bootableById[String(Number(s.number))] === true
  }

  function isPersistent(s) {
    return !!s && !!s.userdata && String(s.userdata.important) === "yes"
  }

  function defaultHint() {
    return (diskUsage !== "" ? diskUsage + "\n" : "") +
      "J/K select  C new  D/Enter diff  X delete  B boot  R restore  P pin\n" +
      "S cleanup  F filter  G refresh  Q/Esc close"
  }

  function cleanupHint() {
    return "H/L tabs · drag or wheel the sliders · Esc back"
  }

  function open() {
    controller.show()
    refresh()
    checkForUpdates()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { controller.hide() }
  function toggle() { if (opened) close(); else open() }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function checkForUpdates(force) {
    if (updateCheckProcess.running || (!force && lastUpdateCheckAt > 0 && Date.now() - lastUpdateCheckAt < 900000)) return
    updateState = "checking"
    updateOutput = ""
    updateCheckProcess.running = true
  }

  function loadUpdateStatus(raw) {
    lastUpdateCheckAt = Date.now()
    try {
      var info = JSON.parse(raw)
      updateState = info.state || "error"
      installedVersion = info.installedVersion || ""
      availableVersion = info.availableVersion || ""
      localCommit = info.localCommit || ""
      remoteCommit = info.remoteCommit || ""
      verificationLabel = info.verificationLabel || "Unverified"
      verificationVerified = info.verificationVerified === true
    } catch (error) {
      updateState = "error"
    }
  }

  function applyUpdate() {
    updateLauncher.command = [
      "omarchy-launch-floating-terminal-with-presentation",
      "omarchy plugin update grenco.snapman --yes"
    ]
    updateLauncher.startDetached()
  }

  function openUpdateDiff() {
    if (!localCommit || !remoteCommit) return
    browserLauncher.command = [
      "omarchy-launch-browser",
      "https://github.com/Grenco/omarchy-snapman/compare/" + localCommit + "..." + remoteCommit
    ]
    browserLauncher.startDetached()
  }

  function openMarketplace() {
    browserLauncher.command = ["omarchy-launch-browser", "https://omarchyplugins.com/plugin.html?id=grenco.snapman"]
    browserLauncher.startDetached()
  }

  function refresh(clearPreviewCache) {
    if (listProcess.running) return
    if (clearPreviewCache) changesBySnapshot = ({})
    loading = true
    statusMessage = ""
    listProcess.running = true
    if (!limineProcess.running) limineProcess.running = true
    if (!diskProcess.running) diskProcess.running = true
  }

  function loadSnapshots(raw) {
    try {
      var document = JSON.parse(raw)
      var rows = document.root || []
      snapshots = rows.filter(function(row) { return Number(row.number) !== 0 }).reverse()
      selectedIndex = Math.max(0, Math.min(selectedIndex, filteredSnapshots.length - 1))
      if (hasSelection) previewSelected()
      else changes = "No stored snapshots. Press C to create one."
    } catch (error) {
      snapshots = []
      changes = "Could not read snapshots: " + error
    }
  }

  function loadLimine(raw) {
    var map = {}
    try {
      var doc = JSON.parse(raw)
      var entries = doc.snapshotEntries || []
      for (var i = 0; i < entries.length; i++) {
        var id = entries[i] && entries[i].snapperID ? Number(entries[i].snapperID.snapshotID) : -1
        if (id >= 0) map[String(id)] = true
      }
    } catch (e) {}
    bootableById = map
  }

  function loadDiskUsage(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var f = lines[i].trim().split(/\s+/)
      if (f.length >= 6 && f[f.length - 1] === "/") {
        root.diskUsage = "Disk: " + f[2] + " used, " + f[3] + " free (" + f[4] + ")"
        return
      }
    }
    root.diskUsage = ""
  }

  function moveSelection(delta) {
    if (!filteredSnapshots.length) return
    selectedIndex = Math.max(0, Math.min(filteredSnapshots.length - 1, selectedIndex + delta))
    previewSelected()
  }

  function select(index) {
    selectedIndex = index
    previewSelected()
  }

  function previewSelected() {
    if (!selected) return
    var number = Number(selected.number)
    if (changesBySnapshot[number] !== undefined) {
      changes = changesBySnapshot[number]
      return
    }
    if (changesProcess.running) {
      queuedPreviewNumber = number
      return
    }
    changes = "Checking changes against the live filesystem..."
    previewNumber = number
    changesProcess.command = ["snapper", "-c", "root", "status", String(number) + "..0"]
    changesProcess.running = true
  }

  function clearInputFocus() {
    filterField.focus = false
    descriptionField.focus = false
  }

  function exitInputMode() {
    if (editingDescription) { cancelCreate(); return }
    filterText = ""
    filterField.text = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function startCreate() {
    editingDescription = true
    statusMessage = ""
    Qt.callLater(function() {
      descriptionField.text = ""
      descriptionField.forceActiveFocus()
    })
  }

  function cancelCreate() {
    editingDescription = false
    descriptionField.text = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function finishCreate() {
    var desc = String(descriptionField.text || "").trim()
    editingDescription = false
    runAction(["snapper", "-c", "root", "create", "--description", desc || "Manual snapshot"], "Created snapshot.")
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function requestDelete() {
    if (!selected) return
    clearInputFocus()
    pendingAction = "delete"
    pendingSnapshotNumber = Number(selected.number)
    statusMessage = ""
  }

  function requestRestore() {
    if (!selected) return
    clearInputFocus()
    pendingAction = "restore"
    pendingSnapshotNumber = Number(selected.number)
  }

  function requestBootNext() {
    if (!selected) return
    bootLauncher.command = [
      "omarchy-launch-floating-terminal-with-presentation",
      "sudo limine-snapper-restore --kernels " + String(selected.number)
    ]
    bootLauncher.startDetached()
    statusMessage = "Prepared snapshot #" + selected.number + " to boot — pick it in the Limine menu at the next restart."
  }

  function confirmAction() {
    if (pendingAction === "") return
    if (pendingAction === "delete" && pendingSnapshotNumber >= 0)
      runAction(["snapper", "-c", "root", "delete", String(pendingSnapshotNumber)], "Deleted snapshot #" + pendingSnapshotNumber + ".")
    else if (pendingAction === "restore" && pendingSnapshotNumber >= 0)
      runAction(["snapper", "-c", "root", "undochange", String(pendingSnapshotNumber) + "..0"], "Restored changes from snapshot #" + pendingSnapshotNumber + ".")
    else if (pendingAction === "bulk")
      runAction(["snapper", "-c", "root", "delete"].concat(pendingBulkNumbers.map(function(n) { return String(n) })), "Deleted " + pendingBulkCount + " snapshot" + (pendingBulkCount === 1 ? "" : "s") + ".")
    pendingAction = ""
    pendingSnapshotNumber = -1
    pendingBulkNumbers = []
    pendingBulkCount = 0
  }

  function cancelPendingAction() {
    pendingAction = ""
    pendingSnapshotNumber = -1
    pendingBulkNumbers = []
    pendingBulkCount = 0
    statusMessage = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function runAction(command, successMessage) {
    if (actionProcess.running) return
    statusMessage = "Working..."
    actionProcess.command = command
    actionProcess.successMessage = successMessage
    actionProcess.errorOutput = ""
    actionProcess.running = true
  }

  function togglePersistent() {
    if (!selected || persistProcess.running) return
    var number = Number(selected.number)
    var pin = !isPersistent(selected)
    statusMessage = "Working..."
    persistProcess.successMessage = (pin ? "Pinned" : "Unpinned") + " snapshot #" + number + " against retention cleanup."
    persistProcess.command = ["snapper", "-c", "root", "modify", "--userdata", pin ? "important=yes" : "important=", String(number)]
    persistProcess.running = true
  }

  function openFullDiff() {
    if (!selected) return
    diffLauncher.command = [
      "omarchy-launch-floating-terminal-with-presentation",
      "snapper -c root diff " + String(selected.number) + "..0 | less -R"
    ]
    diffLauncher.startDetached()
  }

  function ageDays(dateStr) {
    var p = String(dateStr || "").split(/[- :]/)
    if (p.length < 6) return Infinity
    var then = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]), Number(p[3]), Number(p[4]), Number(p[5]))
    var diff = (new Date() - then) / 86400000
    return diff < 0 ? 0 : diff
  }

  function bulkTargets(mode, value) {
    var sorted = snapshots.slice().sort(function(a, b) { return Number(b.number) - Number(a.number) })
    if (mode === "age") return sorted.filter(function(s) { return ageDays(s.date) > value })
    return sorted.slice(value)
  }

  function bulkTargetCount(mode, value) {
    return bulkTargets(mode, value).length
  }

  function openCleanup() {
    cleanupMode = true
    statusMessage = ""
    loadCleanupSettings()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function closeCleanup() {
    cleanupMode = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function switchCleanupTab(dx) {
    if (cleanupTab === "retention" && dx > 0) cleanupTab = "bulk"
    else if (cleanupTab === "bulk" && dx < 0) cleanupTab = "retention"
  }

  function loadCleanupSettings() {
    if (!retentionReadProcess.running) retentionReadProcess.running = true
    if (!numberLimitProcess.running) numberLimitProcess.running = true
    if (!timerStateProcess.running) timerStateProcess.running = true
  }

  function parseRetentionConf(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (line.indexOf("RETENTION_MODE=") === 0) root.retentionMode = line.slice(15).trim() || "count"
      else if (line.indexOf("RETENTION_VALUE=") === 0) {
        var v = parseInt(line.slice(16).trim(), 10)
        if (isFinite(v)) {
          if (root.retentionMode === "count") root.retentionCountValue = Math.max(1, Math.min(20, v))
          else root.retentionAgeValue = Math.max(1, Math.min(365, v))
        }
      }
    }
  }

  function retentionPreview() {
    var mode = root.retentionMode
    var value = mode === "count" ? root.retentionCountValue : root.retentionAgeValue
    var n = bulkTargetCount(mode, value)
    if (mode === "count")
      return "Keeps the newest " + root.retentionCountValue + " of " + snapshots.length + " · " +
        (n > 0 ? "removes " + n + " now" : "nothing to remove") + "."
    return "Keeps snapshots from the last " + root.retentionAgeValue + " days · " +
      (n > 0 ? "removes " + n + " now" : "nothing to remove") + "."
  }

  function bulkPreview() {
    var n = bulkTargetCount(root.bulkMode, root.bulkMode === "age" ? root.bulkAgeValue : root.bulkCountValue)
    if (root.bulkMode === "age")
      return "Deletes snapshots older than " + root.bulkAgeValue + " days · " + n + " of " + snapshots.length + "."
    return "Deletes all but the newest " + root.bulkCountValue + " · " + n + " of " + snapshots.length + "."
  }

  function applyRetention() {
    var value = root.retentionMode === "count" ? root.retentionCountValue : root.retentionAgeValue
    var limit = root.retentionMode === "count" ? value : 999
    var sudoCmd = "sudo sed -i 's/^NUMBER_LIMIT=.*/NUMBER_LIMIT=\"" + limit + "\"/; s/^NUMBER_LIMIT_IMPORTANT=.*/NUMBER_LIMIT_IMPORTANT=\"999\"/' /etc/snapper/configs/root && sudo snapper -c root cleanup number"
    retentionLauncher.command = ["omarchy-launch-floating-terminal-with-presentation", sudoCmd]
    retentionLauncher.startDetached()

    var content = "RETENTION_MODE=" + root.retentionMode + "\nRETENTION_VALUE=" + value + "\n"
    var pluginDir = "\"$HOME/.config/omarchy/plugins/grenco.snapman\""
    if (root.retentionMode === "age") {
      supportProcess.command = ["sh", "-c",
        "printf '" + content + "' > \"$HOME/.config/omarchy/snapman.conf\" && " +
        "bash " + pluginDir + "/scripts/install-support.sh && " +
        "systemctl --user enable --now snapman-retention.timer >/dev/null 2>&1 && " +
        "\"$HOME/.local/bin/snapman-retention\""]
    } else {
      supportProcess.command = ["sh", "-c",
        "printf '" + content + "' > \"$HOME/.config/omarchy/snapman.conf\" && " +
        "systemctl --user disable --now snapman-retention.timer >/dev/null 2>&1; true"]
    }
    supportProcess.running = true

    statusMessage = "Retention applied — trimming snapshots in the terminal."
    postApplyTimer.restart()
  }

  function requestBulkDelete() {
    var targets = bulkTargets(root.bulkMode, root.bulkMode === "age" ? root.bulkAgeValue : root.bulkCountValue)
    if (!targets.length) { statusMessage = "Nothing matches — no snapshots to delete."; return }
    pendingAction = "bulk"
    pendingBulkNumbers = targets.map(function(s) { return Number(s.number) })
    pendingBulkCount = targets.length
    statusMessage = ""
  }

  onFilterTextChanged: Qt.callLater(function() {
    selectedIndex = Math.max(0, Math.min(selectedIndex, filteredSnapshots.length - 1))
    if (hasSelection) previewSelected()
  })

  Process {
    id: listProcess
    command: ["snapper", "-c", "root", "--jsonout", "--no-headers", "list", "--disable-used-space"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.listOutput = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.statusMessage = String(text).trim() }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode === 0) root.loadSnapshots(root.listOutput)
      else root.changes = root.statusMessage || "Snapper could not load snapshots."
    }
  }

  Process {
    id: limineProcess
    command: ["sh", "-c", "cat /boot/$(cat /etc/machine-id 2>/dev/null)/limine_history/snapshots.json 2>/dev/null"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.limineOutput = text }
    stderr: StdioCollector { waitForEnd: true }
    onExited: root.loadLimine(root.limineOutput)
  }

  Process {
    id: diskProcess
    command: ["df", "-h", "/"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.loadDiskUsage(text) }
    stderr: StdioCollector { waitForEnd: true }
  }

  Process {
    id: changesProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.changesOutput = text }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var result = exitCode === 0
        ? (String(root.changesOutput).trim() || "No filesystem changes from this snapshot.")
        : "Could not compare this snapshot to the live filesystem."
      root.changesBySnapshot[root.previewNumber] = result
      if (root.selected && Number(root.selected.number) === root.previewNumber) root.changes = result
      root.previewNumber = -1
      if (root.queuedPreviewNumber !== -1) {
        root.queuedPreviewNumber = -1
        root.previewSelected()
      }
    }
  }

  Process {
    id: actionProcess
    property string successMessage: ""
    property string errorOutput: ""
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: actionProcess.errorOutput = String(text).trim() }
    onExited: function(exitCode) {
      root.statusMessage = exitCode === 0
        ? successMessage + " Limine entries will update automatically."
        : (errorOutput || "Snapper action failed.")
      root.refresh(true)
    }
  }

  Process {
    id: persistProcess
    property string successMessage: ""
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.statusMessage = String(text).trim() || root.statusMessage }
    onExited: function(code) {
      root.statusMessage = code === 0 ? successMessage : (root.statusMessage || "Could not update snapshot flags.")
      root.refresh(true)
    }
  }

  Process { id: diffLauncher }
  Process { id: bootLauncher }

  Process {
    id: updateCheckProcess
    command: ["sh", "-c", "bash \"$HOME/.config/omarchy/plugins/grenco.snapman/scripts/snapman-update-status\""]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateOutput = text }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.loadUpdateStatus(root.updateOutput)
      else {
        root.lastUpdateCheckAt = Date.now()
        root.updateState = "error"
      }
    }
  }

  Process { id: updateLauncher }
  Process { id: browserLauncher }

  Process {
    id: retentionReadProcess
    command: ["sh", "-c", "cat \"$HOME/.config/omarchy/snapman.conf\" 2>/dev/null || true"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseRetentionConf(text) }
    stderr: StdioCollector { waitForEnd: true }
  }

  Process {
    id: numberLimitProcess
    command: ["sh", "-c", "sed -n 's/^NUMBER_LIMIT=\"\\([0-9]*\\)\".*/\\1/p' /etc/snapper/configs/root 2>/dev/null"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: function(text) {
      var v = parseInt(String(text).trim(), 10)
      if (isFinite(v) && v > 0 && v <= 999) root.retentionCountValue = v
    } }
    stderr: StdioCollector { waitForEnd: true }
  }

  Process {
    id: timerStateProcess
    command: ["systemctl", "--user", "is-enabled", "snapman-retention.timer"]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) { root.ageTimerActive = code === 0 }
  }

  Process {
    id: supportProcess
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.statusMessage = String(text).trim() || root.statusMessage }
    onExited: function(code) {
      root.refresh(true)
    }
  }

  Process { id: retentionLauncher }

  Timer {
    id: postApplyTimer
    interval: 5000
    onTriggered: root.refresh(true)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight)

    SnapshotKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      confirmationDialog: confirmDlg
      blocked: root.inputActive
      onQuitRequested: {
        root.cancelPendingAction()
        root.close()
      }
      onMoveRequested: function(dx, dy) {
        if (root.cleanupMode) {
          if (dx !== 0) root.switchCleanupTab(dx)
          return
        }
        if (dy !== 0) root.moveSelection(dy)
      }
      onActivateRequested: {
        if (root.editingDescription) root.finishCreate()
        else root.openFullDiff()
      }
      onDeleteRequested: {
        if (root.pendingAction === "") root.requestDelete()
      }
      onCloseRequested: {
        if (root.pendingAction !== "") {
          root.cancelPendingAction()
        } else if (root.cleanupMode) {
          root.closeCleanup()
        } else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(key) {
        var lower = key.toLowerCase()
        if (root.pendingAction !== "") return
        if (root.cleanupMode) {
          if (lower === "s") root.closeCleanup()
          else if (lower === "g") root.refresh(true)
          return
        }
        if (lower === "j") root.moveSelection(1)
        else if (lower === "k") root.moveSelection(-1)
        else if (lower === "c") root.startCreate()
        else if (lower === "d") root.openFullDiff()
        else if (lower === "r") root.requestRestore()
        else if (lower === "b") root.requestBootNext()
        else if (lower === "p") root.togglePersistent()
        else if (lower === "s") root.openCleanup()
        else if (lower === "f") { filterField.forceActiveFocus(); filterField.selectAll() }
        else if (lower === "g") root.refresh(true)
      }

      Column {
        id: panelColumn
        anchors.fill: parent
        spacing: Style.space(6)

        Column {
          width: parent.width
          spacing: Style.space(1)
          Item {
            width: parent.width
            height: Style.space(20)
            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)
              Text {
                text: "SNAPSHOTS"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                font.letterSpacing: 1
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.loading ? "REFRESHING" : root.filteredSnapshots.length + " SAVED"
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 0.8
              }
            }
            Button {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "Cleanup"
              tooltipText: "Retention policy and bulk delete (S)"
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(6)
              verticalPadding: Style.space(2)
              bordered: true
              onClicked: root.openCleanup()
            }
          }
          Text {
            text: "Root filesystem  ·  ● Bootable in Limine"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: root.muted
          }
          Flow {
            width: parent.width
            spacing: Style.space(6)
            visible: root.updateState === "available"

            Text {
              height: Style.space(20)
              verticalAlignment: Text.AlignVCenter
              text: "Snapman " + (root.availableVersion ? "v" + root.availableVersion : "update") + " available  ·  " + root.verificationLabel
              color: root.verificationVerified ? Color.accent : Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Button {
              text: "Update"
              tooltipText: "Apply the update now"
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(6)
              verticalPadding: Style.space(2)
              bordered: true
              onClicked: root.applyUpdate()
            }
            Button {
              text: "Diff"
              tooltipText: "View the changes on GitHub"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(6)
              verticalPadding: Style.space(2)
              bordered: true
              onClicked: root.openUpdateDiff()
            }
            Button {
              text: "Store"
              tooltipText: "Open the plugin's marketplace page"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(6)
              verticalPadding: Style.space(2)
              bordered: true
              onClicked: root.openMarketplace()
            }
          }
        }

        TextField {
          id: filterField
          width: parent.width
          visible: !root.cleanupMode
          placeholderText: "Filter snapshots…"
          foreground: root.foreground
          font.family: root.fontFamily
          onTextChanged: root.filterText = text
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.exitInputMode()
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              Qt.callLater(function() { root.keyCatcher.forceActiveFocus() })
              event.accepted = true
            }
          }
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)
          visible: !root.editingDescription && root.pendingAction === "" && !root.cleanupMode

          Button {
            text: "New"
            tooltipText: "Create a snapshot (C)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(2)
            bordered: true
            onClicked: root.startCreate()
          }
          Button {
            text: "Diff"
            tooltipText: "Compare this snapshot with the live filesystem (D)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(2)
            bordered: true
            enabled: root.hasSelection
            onClicked: root.openFullDiff()
          }
          Button {
            text: "Boot"
            tooltipText: "Boot into this snapshot at the next restart (B)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(2)
            bordered: true
            enabled: root.hasSelection
            onClicked: root.requestBootNext()
          }
          Button {
            text: "Restore"
            tooltipText: "Restore changed files into the live system (R)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(2)
            bordered: true
            enabled: root.hasSelection
            onClicked: root.requestRestore()
          }
          Button {
            text: root.hasSelection && root.isPersistent(root.selected) ? "Unpin" : "Pin"
            tooltipText: root.hasSelection && root.isPersistent(root.selected)
              ? "Remove retention protection (P)"
              : "Protect from retention cleanup (P)"
            foreground: root.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(2)
            bordered: true
            enabled: root.hasSelection
            onClicked: root.togglePersistent()
          }
          Button {
            text: "Delete"
            tooltipText: "Delete this snapshot (X)"
            foreground: root.foreground
            accent: Color.urgent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(2)
            bordered: true
            enabled: root.hasSelection
            onClicked: root.requestDelete()
          }
          Button {
            text: "Refresh"
            tooltipText: "Reload the snapshot list (G)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(2)
            bordered: true
            onClicked: root.refresh(true)
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(6)
          visible: root.editingDescription

          TextField {
            id: descriptionField
            width: parent.width - Style.space(118)
            placeholderText: "Description (Enter to create, Esc to cancel)"
            foreground: root.foreground
            font.family: root.fontFamily
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.finishCreate()
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                root.cancelCreate()
                event.accepted = true
              }
            }
          }
          Button {
            text: "Create"
            foreground: root.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(8)
            verticalPadding: Style.space(3)
            bordered: true
            onClicked: root.finishCreate()
          }
          Button {
            text: "Cancel"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(8)
            verticalPadding: Style.space(3)
            bordered: true
            onClicked: root.cancelCreate()
          }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.darker(root.foreground, 1.9); visible: !root.cleanupMode }

        Item {
          width: parent.width
          height: Style.space(160)
          visible: !root.cleanupMode

          Text {
            anchors.centerIn: parent
            visible: root.loading
            text: "Loading snapshots..."
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          ListView {
            id: snapshotList
            anchors.fill: parent
            model: root.filteredSnapshots
            currentIndex: root.selectedIndex
            spacing: Style.space(2)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Rectangle {
              required property var modelData
              required property int index
              readonly property bool isSelected: index === root.selectedIndex
              readonly property color rowForeground: isSelected ? Qt.darker(Color.accent, 3.0) : root.foreground
              readonly property color rowMuted: isSelected ? Qt.darker(Color.accent, 2.2) : root.muted
              width: ListView.view.width
              height: Style.space(36)
              radius: 4
              color: isSelected ? Qt.lighter(Color.accent, 1.15) : "transparent"

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(6)

                Text {
                  width: Style.space(30)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "#" + modelData.number
                  color: rowForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Text {
                  width: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.isBootable(modelData) ? "●" : "○"
                  color: root.isBootable(modelData) ? Color.accent : Qt.darker(root.foreground, 1.8)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  width: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "\uF2CA"
                  visible: root.isPersistent(modelData)
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Column {
                  width: parent.width - Style.space(30) - Style.space(12) - Style.space(6) - (root.isPersistent(modelData) ? Style.space(16) + Style.space(6) : 0) - (sizeText.visible ? sizeText.width + Style.space(6) : 0) - Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  Text {
                    width: parent.width
                    text: modelData.description || "Untitled snapshot"
                    color: rowForeground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    text: (root.relativeAge(modelData.date) ? root.relativeAge(modelData.date) + " · " : "") + (modelData.date || "Unknown date")
                    color: rowMuted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Text {
                  id: sizeText
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.formatSize(modelData["used-space"])
                  visible: text !== ""
                  color: rowMuted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                anchors.fill: parent
                onClicked: root.select(index)
                onDoubleClicked: root.openFullDiff()
              }
            }
          }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.darker(root.foreground, 1.9); visible: !root.cleanupMode }

        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: !root.cleanupMode
          Text {
            text: root.selected ? "CHANGES: SNAPSHOT #" + root.selected.number + " -> LIVE" : "CHANGES"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            font.letterSpacing: 1
          }
          Text {
            width: parent.width
            height: Style.space(100)
            text: root.changes
            color: root.muted
            font.family: "monospace"
            font.pixelSize: Style.font.caption
            wrapMode: Text.WrapAnywhere
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.cleanupMode

          Item {
            width: parent.width
            height: Style.space(24)
            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)
              Button {
                text: "Retention policy"
                tooltipText: "Set count or age retention (H/L)"
                selected: root.cleanupTab === "retention"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(2)
                bordered: true
                onClicked: root.cleanupTab = "retention"
              }
              Button {
                text: "Bulk delete"
                tooltipText: "One-shot bulk delete (H/L)"
                selected: root.cleanupTab === "bulk"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(2)
                bordered: true
                onClicked: root.cleanupTab = "bulk"
              }
            }
            Button {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "← Close"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(6)
              verticalPadding: Style.space(2)
              bordered: true
              onClicked: root.closeCleanup()
            }
          }

          Rectangle { width: parent.width; height: 1; color: Qt.darker(root.foreground, 1.9) }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.cleanupTab === "retention"

            Row {
              width: parent.width
              spacing: Style.space(6)
              Button {
                text: "Keep newest N"
                selected: root.retentionMode === "count"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(2)
                bordered: true
                onClicked: root.retentionMode = "count"
              }
              Button {
                text: "Keep newer than X days"
                selected: root.retentionMode === "age"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(2)
                bordered: true
                onClicked: root.retentionMode = "age"
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)
              Text {
                width: Style.space(96)
                anchors.verticalCenter: parent.verticalCenter
                text: root.retentionMode === "count" ? "Keep newest" : "Keep newer than"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
              PanelSlider {
                bar: root.bar
                width: parent.width - Style.space(96) - Style.space(72) - Style.space(16)
                minimum: 1
                maximum: root.retentionMode === "count" ? 20 : 365
                step: 1
                integer: true
                value: root.retentionMode === "count" ? root.retentionCountValue : root.retentionAgeValue
                onMoved: function(v) {
                  var n = Math.round(v)
                  if (root.retentionMode === "count") root.retentionCountValue = n
                  else root.retentionAgeValue = n
                }
                onReleased: function(v) {
                  var n = Math.round(v)
                  if (root.retentionMode === "count") root.retentionCountValue = n
                  else root.retentionAgeValue = n
                }
              }
              Text {
                width: Style.space(72)
                anchors.verticalCenter: parent.verticalCenter
                text: root.retentionMode === "count"
                  ? root.retentionCountValue + " snapshots"
                  : root.retentionAgeValue + " days"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                elide: Text.ElideRight
              }
            }

            Text {
              width: parent.width
              text: root.retentionPreview()
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            Text {
              width: parent.width
              text: root.retentionMode === "count"
                ? "Saved to snapper's config · enforced on every omarchy update."
                : (root.ageTimerActive ? "Background timer trims old snapshots daily." : "Background timer is enabled when you apply.")
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            Button {
              text: "Save & apply"
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(2)
              bordered: true
              onClicked: root.applyRetention()
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.cleanupTab === "bulk"

            Row {
              width: parent.width
              spacing: Style.space(6)
              Button {
                text: "Older than X days"
                selected: root.bulkMode === "age"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(2)
                bordered: true
                onClicked: root.bulkMode = "age"
              }
              Button {
                text: "Keep newest N"
                selected: root.bulkMode === "count"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(2)
                bordered: true
                onClicked: root.bulkMode = "count"
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)
              Text {
                width: Style.space(96)
                anchors.verticalCenter: parent.verticalCenter
                text: root.bulkMode === "age" ? "Older than" : "Newest"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
              PanelSlider {
                bar: root.bar
                width: parent.width - Style.space(96) - Style.space(72) - Style.space(16)
                minimum: 1
                maximum: root.bulkMode === "age" ? 365 : 20
                step: 1
                integer: true
                value: root.bulkMode === "age" ? root.bulkAgeValue : root.bulkCountValue
                onMoved: function(v) {
                  var n = Math.round(v)
                  if (root.bulkMode === "age") root.bulkAgeValue = n
                  else root.bulkCountValue = n
                }
                onReleased: function(v) {
                  var n = Math.round(v)
                  if (root.bulkMode === "age") root.bulkAgeValue = n
                  else root.bulkCountValue = n
                }
              }
              Text {
                width: Style.space(72)
                anchors.verticalCenter: parent.verticalCenter
                text: root.bulkMode === "age" ? root.bulkAgeValue + " days" : root.bulkCountValue + " kept"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                elide: Text.ElideRight
              }
            }

            Text {
              width: parent.width
              text: root.bulkPreview()
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            Button {
              text: root.bulkMode === "age"
                ? "Delete older than " + root.bulkAgeValue + " days"
                : "Delete all but newest " + root.bulkCountValue
              foreground: root.foreground
              accent: Color.urgent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(2)
              bordered: true
              onClicked: root.requestBulkDelete()
            }
          }
        }

        Text {
          width: parent.width
          text: root.statusMessage || (root.cleanupMode ? root.cleanupHint() : root.defaultHint())
          color: root.statusMessage ? Color.accent : root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
      }

      ConfirmDialog {
        id: confirmDlg
        anchors.fill: parent
        opened: root.pendingAction !== ""
        message: root.pendingAction === "delete"
          ? "Delete snapshot #" + root.pendingSnapshotNumber + "? This cannot be undone."
          : root.pendingAction === "bulk"
            ? "Delete " + root.pendingBulkCount + " snapshot" + (root.pendingBulkCount === 1 ? "" : "s") + "? This cannot be undone."
            : "Restore changed files from snapshot #" + root.pendingSnapshotNumber + " into the live filesystem?"
        confirmText: root.pendingAction === "restore" ? "Restore" : "Delete"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.cancelPendingAction()
        onConfirmed: root.confirmAction()
      }
    }
  }
}
