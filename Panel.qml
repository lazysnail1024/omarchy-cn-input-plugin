import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "community.cn-input"
  ipcTarget: "community.cn-input"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property string controlPath: ""
  property int focusIndex: 0
  property string errorText: ""

  readonly property var barIdentity: hostWidget || root
  readonly property var status: hostWidget ? hostWidget.status : ({
    ready: false,
    mode: "unknown",
    startupLanguage: "en",
    message: "Checking Chinese input setup…"
  })
  readonly property string setupPath: root.localPath(Qt.resolvedUrl("scripts/setup"))
  readonly property color foreground: root.bar ? root.bar.foreground : Color.foreground
  readonly property color dimForeground: Qt.darker(foreground, 1.5)
  readonly property color urgent: root.bar ? root.bar.urgent : Color.urgent
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property string startupLanguage: status.startupLanguage === "cn" ? "cn" : "en"
  readonly property bool commandBusy: startupProc.running

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.substring(7)
    try { return decodeURIComponent(value) } catch (error) { return value }
  }

  function refreshStatus() {
    if (root.hostWidget && root.hostWidget.refreshStatus)
      root.hostWidget.refreshStatus()
  }

  function open() {
    root.controller.show()
    root.errorText = ""
    root.focusIndex = 0
    root.refreshStatus()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setStartupLanguage(language) {
    if (root.commandBusy || (language !== "en" && language !== "cn")) return
    if (language === "cn" && root.status.ready !== true) return
    if (language === root.startupLanguage) return
    root.errorText = ""
    startupProc.command = [root.controlPath, "set-startup", language]
    startupProc.running = true
  }

  function moveFocus(delta) {
    root.focusIndex = (root.focusIndex + (delta > 0 ? 1 : -1) + 3) % 3
  }

  function activateFocused() {
    if (root.focusIndex === 0) root.setStartupLanguage("en")
    else if (root.focusIndex === 1) root.setStartupLanguage("cn")
    else root.launchSetup()
  }

  function launchSetup() {
    if (root.commandBusy || root.setupPath === "") return
    root.close()
    Quickshell.execDetached(["omarchy", "launch", "terminal", root.setupPath, "--from-ui"])
  }

  Process {
    id: startupProc

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = String(text || "").trim()
        if (value !== "") root.errorText = value
      }
    }

    onExited: function(exitCode) {
      // Backend is the source of truth: after a mutation, read it again.
      // This intentionally avoids a second optimistic copy of startup state.
      if (exitCode === 0) root.errorText = ""
      else if (root.errorText === "") root.errorText = "Could not save the startup language."
      root.refreshStatus()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(330))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.commandBusy
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveFocus(dy)
      }
      onActivateRequested: root.activateFocused()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "e" || text === "E") root.setStartupLanguage("en")
        else if (text === "c" || text === "C") root.setStartupLanguage("cn")
        else if (text === "s" || text === "S") root.launchSetup()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: parent.width
          text: "Chinese Input"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        Text {
          width: parent.width
          text: root.status.ready === true
            ? "Current input: " + (root.status.mode === "cn" ? "Chinese" : "English")
            : String(root.status.message || "Setup required")
          color: root.status.ready === true ? root.dimForeground : root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          topPadding: Style.space(4)
          text: "Start new apps in"
          color: root.dimForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Button {
          width: parent.width
          text: "English"
          iconText: root.startupLanguage === "en" ? "●" : "○"
          leftAlign: true
          selected: root.startupLanguage === "en"
          hasCursor: root.focusIndex === 0
          enabled: !root.commandBusy
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.setStartupLanguage("en")
          onHovered: function(hovered) { if (hovered) root.focusIndex = 0 }
        }

        Button {
          width: parent.width
          text: "Chinese (Rime Ice)"
          iconText: root.startupLanguage === "cn" ? "●" : "○"
          leftAlign: true
          selected: root.startupLanguage === "cn"
          hasCursor: root.focusIndex === 1
          enabled: !root.commandBusy && root.status.ready === true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.setStartupLanguage("cn")
          onHovered: function(hovered) { if (hovered) root.focusIndex = 1 }
        }

        Text {
          width: parent.width
          text: "Left click the bar label or press Ctrl+Space to switch the focused app."
          color: root.dimForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Button {
          width: parent.width
          text: root.status.ready === true ? "Repair setup" : "Install Chinese input"
          iconText: root.status.ready === true ? "↻" : "+"
          leftAlign: true
          bordered: true
          hasCursor: root.focusIndex === 2
          enabled: !root.commandBusy
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.launchSetup()
          onHovered: function(hovered) { if (hovered) root.focusIndex = 2 }
        }

        Text {
          visible: root.errorText !== ""
          width: parent.width
          text: root.errorText
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
