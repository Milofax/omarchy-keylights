pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "KeyLightsLogic.js" as Logic

Panel {
  id: root
  moduleName: "io.github.milofax.keylights"
  ipcTarget: "io.github.milofax.keylights"
  manageIpc: false

  readonly property string tool: decodeURIComponent(String(Qt.resolvedUrl("bin/keylights")).replace(/^file:\/\//, ""))
  readonly property string trayTool: decodeURIComponent(String(Qt.resolvedUrl("bin/keylights-tray")).replace(/^file:\/\//, ""))
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var lights: []
  property bool setupAvailable: false
  property bool setupSupported: false
  property string errorText: ""
  property string noticeText: ""
  property var commandQueue: []
  property var activeCommand: null
  property bool actionExitReceived: false
  property bool actionOutputReceived: false
  property bool actionErrorReceived: false
  property int actionExitCode: 0
  property string actionOutputText: ""
  property string actionErrorText: ""
  property bool statusInFlight: false
  property bool statusExitReceived: false
  property bool statusOutputReceived: false
  property bool statusErrorReceived: false
  property int statusExitCode: 0
  property string statusOutputText: ""
  property string statusErrorText: ""
  property bool refreshPending: false
  property bool trayMode: true
  property int trayWantedConfirmations: 0
  property bool trayStopRequested: false
  property bool trayTerminal: false
  property int trayRetryCount: 0
  readonly property int trayRetryLimit: 3
  property string trayErrorText: ""

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
  readonly property bool trayWanted: Logic.trayWanted(lights)
  readonly property bool trayUnavailable: trayMode && trayErrorText !== ""
  readonly property bool missing: errorText !== "" || trayUnavailable || setupAvailable || (lights.length > 0 && !allReachable)
  readonly property var brightnessState: Logic.brightnessSummary(lights)
  readonly property int brightnessPercent: Number(brightnessState.value)
  readonly property bool brightnessMixed: brightnessState.mixed === true
  readonly property var temperatureState: Logic.temperatureSummary(lights)
  readonly property int temperatureKelvin: Number(temperatureState.value)
  readonly property bool temperatureMixed: temperatureState.mixed === true
  readonly property bool settingsMixed: brightnessMixed || temperatureMixed
  readonly property string stateSummary: {
    if (lights.length === 0 && errorText !== "") return "Discovery error"
    if (trayUnavailable) return "Tray unavailable"
    if (lights.length === 0 && setupAvailable) return "Ready to set up"
    if (!anyReachable) return "Not reachable"
    var status = onCount === 0 ? "Off" : (onCount === reachableCount ? "On" : onCount + " of " + reachableCount + " on")
    return settingsMixed ? status + " · Mixed settings" : status + " · " + brightnessPercent + "% · " + temperatureKelvin + " K"
  }

  visible: !trayMode || trayUnavailable
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (Logic.operationBusy(statusInFlight, actionProcess.running, setupProcess.running,
                            commandQueue.length, activeCommand)) {
      refreshPending = true
      return
    }
    refreshPending = false
    statusInFlight = true
    statusExitReceived = false
    statusOutputReceived = false
    statusErrorReceived = false
    statusExitCode = 0
    statusOutputText = ""
    statusErrorText = ""
    statusProcess.running = true
  }

  function applyStatus(output) {
    try {
      var parsed = JSON.parse(String(output || "").trim())
      setupAvailable = parsed.setupAvailable === true
      setupSupported = parsed.setupSupported === true
      if (parsed.error) {
        errorText = String(parsed.error)
        return
      }

      var nextLights = Logic.reconcileLights(lights, parsed.lights instanceof Array ? parsed.lights : [])
      var reachable = 0
      for (var i = 0; i < nextLights.length; i++) if (nextLights[i].reachable === true) reachable++
      lights = nextLights
      noticeText = ""
      errorText = nextLights.length > 0 && reachable < nextLights.length
        ? "One or more lights are not reachable."
        : ""
    } catch (error) {
      errorText = "Could not read the Key Light status."
    }
  }

  function optimisticLight(light, action, value) {
    var next = {
      id: light.id,
      discoveryId: light.discoveryId,
      name: light.name,
      product: light.product,
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

  function targetsFor(target) {
    var targets = []
    for (var i = 0; i < lights.length; i++) {
      var light = lights[i]
      if (light.reachable !== true || (target !== "all" && target !== light.id)) continue
      targets.push({
        id: String(light.id),
        discoveryId: String(light.discoveryId || light.id),
        name: String(light.name || "Key Light"),
        address: String(light.address),
        port: Number(light.port)
      })
    }
    return targets
  }

  function startNextCommand() {
    if (actionProcess.running || activeCommand !== null || commandQueue.length === 0) return
    var dequeued = Logic.dequeueCommand(commandQueue)
    var next = dequeued.command
    commandQueue = dequeued.remaining
    activeCommand = next
    actionExitReceived = false
    actionOutputReceived = false
    actionErrorReceived = false
    actionExitCode = 0
    actionOutputText = ""
    actionErrorText = ""
    actionProcess.command = [
      tool,
      "control",
      next.action,
      next.value === undefined || next.value === null ? "-" : String(Math.round(next.value)),
      JSON.stringify(next.targets)
    ]
    actionProcess.running = true
  }

  function applyOptimisticTargets(targets, action, value) {
    var targetIds = {}
    for (var i = 0; i < targets.length; i++) targetIds[String(targets[i].id)] = true
    var next = []
    for (var j = 0; j < lights.length; j++) {
      var light = lights[j]
      next.push(targetIds[String(light.id)] ? optimisticLight(light, action, value) : light)
    }
    lights = next
  }

  function reapplyQueuedOptimism() {
    for (var i = 0; i < commandQueue.length; i++) {
      var command = commandQueue[i]
      applyOptimisticTargets(command.targets, command.action, command.value)
    }
  }

  function runCommand(target, action, value) {
    var targets = targetsFor(target)
    if (targets.length === 0) {
      errorText = "No reachable Key Light is available."
      return
    }

    applyOptimistic(target, action, value)
    errorText = ""
    commandQueue = Logic.enqueueCommand(commandQueue, {targets: targets, action: action, value: value})
    startNextCommand()
  }

  function applyControlResult(output) {
    try {
      var parsed = JSON.parse(String(output || "").trim())
      var results = parsed.results instanceof Array ? parsed.results : []
      var byId = {}
      for (var i = 0; i < results.length; i++) byId[String(results[i].id)] = results[i]

      var next = []
      for (var j = 0; j < lights.length; j++) {
        var light = lights[j]
        var result = byId[String(light.id)]
        if (!result) {
          next.push(light)
          continue
        }
        next.push({
          id: light.id,
          discoveryId: result.discoveryId || light.discoveryId,
          name: light.name,
          product: light.product,
          host: light.host,
          address: result.address || light.address,
          port: Number(result.port || light.port),
          reachable: result.ok === true,
          on: result.on !== undefined ? Number(result.on) : Number(light.on || 0),
          brightness: result.brightness !== undefined ? Number(result.brightness) : Number(light.brightness || 20),
          temperature: result.temperature !== undefined ? Number(result.temperature) : Number(light.temperature || 213)
        })
      }
      commandQueue = Logic.refreshQueuedTargets(commandQueue, results)
      lights = next
      reapplyQueuedOptimism()
    } catch (error) {
      errorText = "Could not read the Key Light response."
    }
  }

  function finishActionIfReady() {
    if (!Logic.operationReady(activeCommand, actionExitReceived, actionOutputReceived) || !actionErrorReceived) return

    if (actionOutputText.trim() !== "") applyControlResult(actionOutputText)
    else errorText = firstErrorLine(actionErrorText, "The Key Light command returned no status.")
    if (actionExitCode !== 0 && (actionOutputText.trim() !== "" || actionErrorText.trim() === ""))
      errorText = Logic.actionError(actionExitCode)

    activeCommand = null
    if (commandQueue.length > 0) {
      Qt.callLater(startNextCommand)
    } else {
      refreshPending = true
      Qt.callLater(refresh)
    }
  }

  function handleActionOutput(output) {
    actionOutputText = String(output || "")
    actionOutputReceived = true
    finishActionIfReady()
  }

  function handleActionError(output) {
    actionErrorText = String(output || "")
    actionErrorReceived = true
    finishActionIfReady()
  }

  function handleActionExit(exitCode) {
    actionExitCode = exitCode
    actionExitReceived = true
    finishActionIfReady()
  }

  function lightLabel(light) {
    var name = String(light && light.name ? light.name : "Key Light")
    return name.replace(/^Elgato\s+/, "")
  }

  function lightStatus(light) {
    if (!light || light.reachable !== true) return "Not reachable"
    var status = Number(light.on) === 1 ? "On" : "Off"
    var kelvin = Math.round((1000000 / Math.max(143, Number(light.temperature || 213))) / 100) * 100
    return status + " · " + Math.round(Number(light.brightness || 20)) + "% · " + kelvin + " K"
  }

  function startSetup() {
    if (Logic.operationBusy(statusInFlight, actionProcess.running, setupProcess.running,
                            commandQueue.length, activeCommand)) {
      noticeText = "Wait for the current Key Light operation to finish."
      return
    }
    if (!setupSupported) {
      errorText = "Setup requires NetworkManager, Zenity, and a browser."
      return
    }
    setupProcess.running = true
    noticeText = ""
    close()
  }

  function adjustBrightness(delta) {
    if (!anyReachable || delta === 0) return
    var next = Math.max(1, Math.min(100, brightnessPercent + (delta > 0 ? 5 : -5)))
    runCommand("all", "brightness", next)
  }

  function firstErrorLine(output, fallback) {
    var lines = String(output || "").trim().split(/\r?\n/)
    return lines.length > 0 && lines[0] !== "" ? lines[0] : fallback
  }

  function finishStatusIfReady() {
    if (!Logic.operationReady(statusInFlight, statusExitReceived, statusOutputReceived) || !statusErrorReceived) return

    if (statusOutputText.trim() !== "") applyStatus(statusOutputText)
    else errorText = statusExitCode === 0
      ? "Could not read the Key Light status."
      : firstErrorLine(statusErrorText, "Could not discover Key Lights.")
    statusInFlight = false
    if (statusExitCode !== 0 && errorText === "") errorText = "Could not discover Key Lights."
    if (refreshPending && !actionProcess.running && activeCommand === null) Qt.callLater(refresh)
  }

  function handleStatusOutput(output) {
    statusOutputText = String(output || "")
    statusOutputReceived = true
    finishStatusIfReady()
  }

  function handleStatusError(output) {
    statusErrorText = String(output || "")
    statusErrorReceived = true
    finishStatusIfReady()
  }

  function handleStatusExit(exitCode) {
    statusExitCode = exitCode
    statusExitReceived = true
    finishStatusIfReady()
  }

  function recordTrayPreference() {
    var next = Logic.advanceTrayMode(trayMode, trayWanted, trayWantedConfirmations)
    trayWantedConfirmations = Number(next.confirmations)
    trayMode = next.trayMode === true
  }

  function syncTrayProcess() {
    if (trayMode) {
      if (!trayTerminal && !trayStopRequested && !trayProcess.running && !trayRetry.running)
        trayProcess.running = true
    } else {
      trayRetry.stop()
      trayHealthy.stop()
      trayTerminal = false
      trayRetryCount = 0
      trayErrorText = ""
      if (trayProcess.running) {
        trayStopRequested = true
        trayProcess.running = false
      }
    }
  }

  function scheduleTrayRetry(message, terminalMessage) {
    trayRetryCount++
    if (trayRetryCount >= trayRetryLimit) {
      trayTerminal = true
      trayErrorText = terminalMessage !== ""
        ? terminalMessage
        : "System tray support stopped repeatedly. Check the Omarchy shell log."
      return
    }
    trayErrorText = message
    trayRetry.restart()
  }

  function handleTrayExit(exitCode) {
    var action = Logic.trayExitAction(exitCode, trayStopRequested, trayMode)
    trayStopRequested = false
    if (action === "ignore") {
      if (trayMode) Qt.callLater(syncTrayProcess)
      return
    }
    if (action === "missing-dependency") {
      trayTerminal = true
      trayErrorText = "System tray support requires python-dbus and python-gobject."
      return
    }
    if (action === "session-bus") {
      scheduleTrayRetry(
        "The session D-Bus is unavailable; tray support will retry.",
        "The session D-Bus remained unavailable; tray support stopped retrying."
      )
      return
    }
    scheduleTrayRetry("", "")
  }

  Component.onCompleted: {
    refresh()
    syncTrayProcess()
  }
  Component.onDestruction: {
    trayRetry.stop()
    trayHealthy.stop()
    trayStopRequested = true
    trayProcess.running = false
  }
  onOpenedChanged: if (opened) refresh()
  onLightsChanged: recordTrayPreference()
  onTrayModeChanged: Qt.callLater(syncTrayProcess)

  Timer {
    interval: root.opened ? 5000 : 15000
    running: Logic.shouldPoll(root.opened, root.lights)
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProcess
    running: false
    command: [root.tool, "json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleStatusOutput(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleStatusError(text)
    }
    onExited: function(exitCode) { root.handleStatusExit(exitCode) }
  }

  Timer {
    id: trayRetry
    interval: Math.min(60000, 10000 * Math.max(1, root.trayRetryCount))
    repeat: false
    onTriggered: root.syncTrayProcess()
  }

  Timer {
    id: trayHealthy
    interval: 60000
    repeat: false
    onTriggered: root.trayRetryCount = 0
  }

  Process {
    id: trayProcess
    running: false
    command: [root.trayTool]
    onRunningChanged: {
      if (running) {
        root.trayErrorText = ""
        trayHealthy.restart()
      } else {
        trayHealthy.stop()
      }
    }
    onExited: function(exitCode) { root.handleTrayExit(exitCode) }
  }

  Process {
    id: actionProcess
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleActionOutput(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleActionError(text)
    }
    onExited: function(exitCode) { root.handleActionExit(exitCode) }
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
    function brightnessUp(): string { root.adjustBrightness(1); return "ok" }
    function brightnessDown(): string { root.adjustBrightness(-1); return "ok" }
    function state(): string {
      return JSON.stringify({
        visible: root.visible,
        reachable: root.anyReachable,
        on: root.anyOn,
        lights: root.lights,
        setupAvailable: root.setupAvailable,
        error: root.errorText !== "" ? root.errorText : root.trayErrorText
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
        crossed: Logic.connectionLost(root.lights)
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
      root.adjustBrightness(delta)
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
              crossed: Logic.connectionLost(root.lights)
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
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  width: parent.width
                  elide: Text.ElideRight
                }

                Text {
                  text: root.lightStatus(modelData)
                  textFormat: Text.PlainText
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
                text: brightnessSlider.dragging
                  ? Math.round(brightnessSlider.liveValue) + "%"
                  : (root.brightnessMixed ? "Mixed" : root.brightnessPercent + "%")
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
                text: "COLOR TEMPERATURE"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
              }
              Text {
                id: temperatureValue
                text: temperatureSlider.dragging
                  ? Math.round(temperatureSlider.liveValue / 100) * 100 + " K"
                  : (root.temperatureMixed ? "Mixed" : root.temperatureKelvin + " K")
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
              onReleased: function(value) {
                root.runCommand("all", "temperature", Math.round(value / 100) * 100)
              }
            }
          }

          Text {
            visible: root.errorText !== ""
            text: root.errorText
            textFormat: Text.PlainText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.trayErrorText !== ""
            text: root.trayErrorText
            textFormat: Text.PlainText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.noticeText !== ""
            text: root.noticeText
            textFormat: Text.PlainText
            color: root.dim
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
              enabled: root.setupSupported && !setupProcess.running
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
      visible: parent.missing && !parent.crossed
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
