import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "community.cn-input"
  property bool refreshPending: false

  // BarWidget is the single owner of backend status for this widget instance.
  // Panel.qml only consumes this state and asks the host to refresh it.
  property var status: ({
    ready: false,
    mode: "unknown",
    startupLanguage: "en",
    message: "Checking Chinese input setup…"
  })

  readonly property string controlPath: root.localPath(Qt.resolvedUrl("scripts/cn-inputctl"))
  readonly property string label: status.mode === "cn" ? "cn"
    : status.mode === "en" ? "en" : status.mode === "rime" ? "Rime" : "--"
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.substring(7)
    try { return decodeURIComponent(value) } catch (error) { return value }
  }

  function applyStatus(value) {
    // A query started before the panel opened can finish after focus moved.
    if (root.opened) return
    if (value && typeof value === "object") root.status = value
  }

  function refreshStatus() {
    if (root.opened) return
    if (statusProc.running) {
      root.refreshPending = true
      return
    }
    root.refreshPending = false
    statusProc.running = true
  }

  function toggleLanguage() {
    if (root.status.canSwitch !== true) {
      root.open()
      return
    }
    if (!toggleProc.running) toggleProc.running = true
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("controlPath" in target) target.controlPath = root.controlPath
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onOpenedChanged: if (!opened) refreshDelay.restart()
  Component.onCompleted: refreshStatus()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Process {
    id: statusProc
    command: [root.controlPath, "status"]
    onExited: if (root.refreshPending) refreshDelay.restart()

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.applyStatus(JSON.parse(text || "{}"))
        } catch (error) {
          root.applyStatus({
            ready: false,
            mode: "unknown",
            startupLanguage: "en",
            message: "Could not read Fcitx5 status"
          })
        }
      }
    }
  }

  // Events reduce latency; polling still covers Rime submode changes and
  // frontends that do not emit CurrentIM. No keystroke inference is used.
  Process {
    id: monitor
    running: true
    command: ["dbus-monitor", "--session", "--profile",
      "type='signal',interface='org.fcitx.Fcitx.InputContext1',member='CurrentIM'",
      "type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='org.fcitx.Fcitx5'"]
    stdout: SplitParser {
      onRead: function(line) {
        if (line.indexOf("CurrentIM") !== -1 || line.indexOf("NameOwnerChanged") !== -1)
          refreshDelay.restart()
      }
    }
    onExited: monitorRetry.restart()
  }

  Timer {
    id: monitorRetry
    interval: 5000
    onTriggered: monitor.running = true
  }

  Timer {
    id: refreshDelay
    interval: 60
    onTriggered: root.refreshStatus()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && ["activewindow", "activewindowv2", "focusedmon", "focusedmonv2"].indexOf(event.name) !== -1)
        refreshDelay.restart()
    }
  }

  Process {
    id: toggleProc
    command: [root.controlPath, "toggle"]
    onExited: function(exitCode) {
      // Multiple monitor instances may exist; ask all of them to reconcile
      // from the backend rather than guessing the next state locally.
      root.broadcast("refreshStatus")
      if (exitCode !== 0) root.open()
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.refreshStatus()
  }

  IpcHandler {
    target: "community.cn-input"

    function refresh(): void { root.refreshStatus() }
    function current(): string { return JSON.stringify(root.status) }
    function toggle(): void { root.toggleLanguage() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    fontSize: Style.font.caption
    horizontalMargin: 6
    useActiveColor: false
    tooltipText: root.status.mode !== "unknown" && root.status.mode !== undefined
      ? (root.status.mode === "cn" ? "Chinese input" : root.status.mode === "en" ? "English input" : "Input mode unavailable")
        + "\nLeft click or Ctrl+Space to switch"
        + "\nRight click for startup settings"
      : String(root.status.message || "Setup required")
        + "\nClick to open guided setup"

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.togglePanel()
      else if (buttonCode === Qt.LeftButton) root.toggleLanguage()
    }
  }
}
