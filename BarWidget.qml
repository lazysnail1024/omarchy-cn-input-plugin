import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "community.cn-input"

  // BarWidget is the single owner of backend status for this widget instance.
  // Panel.qml only consumes this state and asks the host to refresh it.
  property var status: ({
    ready: false,
    mode: "unknown",
    startupLanguage: "en",
    message: "Checking Chinese input setup…"
  })

  readonly property string controlPath: root.localPath(Qt.resolvedUrl("scripts/cn-inputctl"))
  readonly property string label: status.ready === true
    ? (status.mode === "cn" ? "cn" : "en")
    : "--"
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
    if (value && typeof value === "object") root.status = value
  }

  function refreshStatus() {
    if (!statusProc.running) statusProc.running = true
  }

  function toggleLanguage() {
    if (root.status.ready !== true) {
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
    tooltipText: root.status.ready === true
      ? (root.status.mode === "cn" ? "Chinese input" : "English input")
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
