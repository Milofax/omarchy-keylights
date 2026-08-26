import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "milofax.keylights"
  ipcTarget: "milofax.keylights"
  manageIpc: false

  readonly property string tool: decodeURIComponent(String(Qt.resolvedUrl("bin/keylights")).replace(/^file:\/\//, ""))
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var lights: []
  property bool setupAvailable: false
  property string errorText: ""
  property var queuedCommand: []
  property bool refreshPending: false

  readonly property int reachableCount: {
    var count = 0
    for (var i = 0; i < lights.length; i++) if (lights[i].reachable === true) count++
    return count
  }
  readonly property int onCount: {
    var count = 0
    for (var i = 0; i < lights.length; i++)
      if (lights[i].reachable === true && Number(lights[i].on) === 1) count++
    return count
  }
  readonly property bool anyReachable: reachableCount > 0
  readonly property bool allReachable: lights.length > 0 && reachableCount === lights.length
  readonly property bool anyOn: onCount > 0
  readonly property bool missing: setupAvailable || (lights.length > 0 && !allReachable)
  readonly property var referenceLight: {
    for (var i = 0; i < lights.length; i++) if (lights[i].reachable === true) return lights[i]
    return null
  }
  readonly property int brightnessPercent: referenceLight ? Number(referenceLight.brightness || 20) : 20
  readonly property int temperatureKelvin: {
    var mired = referenceLight ? Number(referenceLight.temperature || 213) : 213
    return Math.round((1000000 / Math.max(143, mired)) / 100) * 100
  }
  readonly property string stateSummary: {
    if (lights.length === 0 && setupAvailable) return "Ready to set up"
    if (!anyReachable) return "Not reachable"
    var status = onCount === 0 ? "Off" : (onCount === reachableCount ? "On" : onCount + " of " + reachableCount + " on")
    return status + " · " + brightnessPercent + "% · " + temperatureKelvin + " K"
  }

  visible: lights.length > 0 || setupAvailable
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (statusProcess.running || actionProcess.running) {
      refreshPending = true
      return
    }
    refreshPending = false
    statusProcess.running = true
  }

  function applyStatus(output) {
    try {
      var parsed = JSON.parse(String(output || "").trim())
      lights = parsed.lights instanceof Array ? parsed.lights : []
      setupAvailable = parsed.setupAvailable === true
      if (!anyReachable && lights.length > 0) errorText = "The lights are not reachable."
      else if (errorText === "The lights are not reachable.") errorText = ""
    } catch (error) {
      errorText = "Could not read the Key Light status."
    }
  }

  function optimisticLight(light, action, value) {
    var next = {
      id: light.id,
      name: light.name,
      host: light.host,
      address: light.address,
      port: light.port,
      reachable: light.reachable === true,
      on: Number(light.on || 0),
      brightness: Number(light.brightness || 20),
      temperature: Number(light.temperature || 213)
    }
    if (action === "on") next.on = 1
    else if (action === "off") next.on = 0
    else if (action === "toggle") next.on = next.on === 1 ? 0 : 1
    else if (action === "brightness") next.brightness = Math.round(Number(value))
    else if (action === "temperature") next.temperature = Math.round(1000000 / Number(value))
    return next
  }

  function applyOptimistic(target, action, value) {
    var next = []
    for (var i = 0; i < lights.length; i++) {
      var light = lights[i]
      next.push(target === "all" || target === light.id ? optimisticLight(light, action, value) : light)
    }
    lights = next
  }

  function runCommand(target, action, value) {
    var command = [tool, target, action]
    if (value !== undefined && value !== null && String(value) !== "") command.push(String(Math.round(value)))
    applyOptimistic(target, action, value)
    if (actionProcess.running) {
      queuedCommand = command
      return
    }
    errorText = ""
    actionProcess.command = command
    actionProcess.running = true
  }

  function lightLabel(light) {
    var name = String(light && light.name ? light.name : "Key Light")
    return name.replace(/^Elgato\s+/, "")
  }

  function lightStatus(light) {
    if (!light || light.reachable !== true) return "Not reachable"
    return Number(light.on) === 1 ? "On" : "Off"
  }

  function startSetup() {
    if (setupProcess.running) return
    setupProcess.running = true
    close()
  }

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) refresh()

  Timer {
    interval: root.opened ? 5000 : 15000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProcess
    running: false
    command: [root.tool, "json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.errorText = "Could not discover Key Lights."
      if (root.refreshPending && !actionProcess.running) Qt.callLater(root.refresh)
    }
  }

  Process {
    id: actionProcess
    running: false
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.errorText = "One or more lights did not respond. Please try again."
      if (root.queuedCommand.length > 0) {
        var next = root.queuedCommand
        root.queuedCommand = []
        actionProcess.command = next
        actionProcess.running = true
      } else {
        root.refreshPending = true
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: setupProcess
    running: false
    command: [root.tool, "setup"]
    onExited: function(exitCode) {
      root.refreshPending = true
      Qt.callLater(root.refresh)
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function setup(): string { root.startSetup(); return "ok" }
    function lightsOn(): string { root.runCommand("all", "on"); return "ok" }
    function lightsOff(): string { root.runCommand("all", "off"); return "ok" }
    function toggleAll(): string { root.runCommand("all", "toggle"); return "ok" }
    function state(): string {
      return JSON.stringify({
        visible: root.visible,
        reachable: root.anyReachable,
        on: root.anyOn,
        lights: root.lights,
        setupAvailable: root.setupAvailable,
        error: root.errorText
      })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      LightStatusIcon {
        anchors.fill: parent
        iconSize: Style.bar.iconFont
        iconColor: root.barForeground
        lit: root.anyOn
        crossed: !root.anyOn && root.allReachable
        missing: root.missing
      }
    }
    tooltipText: "Key Lights · " + root.stateSummary
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.runCommand("all", "toggle")
      else if (buttonCode === Qt.RightButton) root.runCommand("all", "off")
      else root.toggle()
    }
    onWheelMoved: function(delta) {
      if (!root.anyReachable || delta === 0) return
      var next = Math.max(1, Math.min(100, root.brightnessPercent + (delta > 0 ? 5 : -5)))
      root.runCommand("all", "brightness", next)
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
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(480))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: if (root.anyReachable) root.runCommand("all", "toggle")
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refresh()
        else if (text === "s" || text === "S") root.startSetup()
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: contentColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: contentColumn
          width: scrollArea.availableWidth
          spacing: Style.space(9)

          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            LightStatusIcon {
              id: heroIcon
              iconSize: Style.font.heading
              iconColor: root.foreground
              lit: root.anyOn
              crossed: !root.anyOn && root.allReachable
              missing: root.missing
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(10)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Key Lights"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }

              Text {
                text: root.stateSummary.toUpperCase()
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.1
              }
            }
          }

          PanelSeparator { visible: root.lights.length > 0; foreground: root.foreground }

          Repeater {
            model: root.lights

            delegate: Item {
              required property var modelData
              width: contentColumn.width
              implicitHeight: Style.space(38)

              Column {
                anchors.left: parent.left
                anchors.right: lightSwitch.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                  text: root.lightLabel(modelData)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  width: parent.width
                  elide: Text.ElideRight
                }

                Text {
                  text: root.lightStatus(modelData)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              ToggleSwitch {
                id: lightSwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: modelData.reachable === true && Number(modelData.on) === 1
                busy: actionProcess.running
                enabled: modelData.reachable === true
                opacity: enabled ? 1 : 0.45
                foreground: root.foreground
                accent: root.urgent
                trackHeight: Style.space(18)
                cursorPad: Style.space(4)
                onToggled: root.runCommand(modelData.id, checked ? "off" : "on")
              }
            }
          }

          PanelSeparator { visible: root.lights.length > 0; foreground: root.foreground }

          Column {
            visible: root.lights.length > 0
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(brightnessHeader.implicitHeight, brightnessValue.implicitHeight)
              PanelSectionHeader {
                id: brightnessHeader
                text: "BRIGHTNESS"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
              }
              Text {
                id: brightnessValue
                text: Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent) + "%"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
              }
            }

            PanelSlider {
              id: brightnessSlider
              width: parent.width
              bar: root.bar
              minimum: 1
              maximum: 100
              step: 1
              integer: true
              value: root.brightnessPercent
              enabled: root.anyReachable
              opacity: enabled ? 1 : 0.45
              onReleased: function(value) { root.runCommand("all", "brightness", value) }
            }
          }

          Column {
            visible: root.lights.length > 0
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(temperatureHeader.implicitHeight, temperatureValue.implicitHeight)
              PanelSectionHeader {
                id: temperatureHeader
                text: "TEMPERATURE"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
              }
              Text {
                id: temperatureValue
                text: Math.round(temperatureSlider.dragging ? temperatureSlider.liveValue : root.temperatureKelvin) + " K"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
              }
            }

            PanelSlider {
              id: temperatureSlider
              width: parent.width
              bar: root.bar
              minimum: 2900
              maximum: 7000
              step: 100
              integer: true
              value: root.temperatureKelvin
              enabled: root.anyReachable
              opacity: enabled ? 1 : 0.45
              onReleased: function(value) { root.runCommand("all", "temperature", value) }
            }
          }

          Text {
            visible: root.errorText !== ""
            text: root.errorText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.foreground }

          Item {
            width: parent.width
            implicitHeight: Style.space(28)

            Text {
              text: "Set up"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            PanelActionButton {
              iconText: "󰒓"
              tooltipText: "Set up a reset Key Light"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !setupProcess.running
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.startSetup()
            }
          }
        }
      }
    }
  }

  component LightStatusIcon: Item {
    property real iconSize: Style.font.icon
    property color iconColor: Color.foreground
    property bool lit: false
    property bool crossed: false
    property bool missing: false

    width: iconSize
    height: iconSize
    implicitWidth: iconSize
    implicitHeight: iconSize

    Text {
      anchors.centerIn: parent
      text: parent.lit ? "󰌵" : "󰌶"
      color: parent.iconColor
      font.family: root.fontFamily
      font.pixelSize: parent.iconSize
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }

    Rectangle {
      visible: parent.crossed
      anchors.centerIn: parent
      width: parent.width * 1.18
      height: Math.max(2, parent.height * 0.12)
      radius: height / 2
      color: parent.iconColor
      rotation: -45
    }

    Text {
      visible: parent.missing
      text: "×"
      color: parent.iconColor
      font.family: root.fontFamily
      font.pixelSize: Math.max(7, parent.iconSize * 0.62)
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: -Math.round(parent.iconSize * 0.18)
      anchors.top: parent.top
      anchors.topMargin: -Math.round(parent.iconSize * 0.22)
    }
  }
}
