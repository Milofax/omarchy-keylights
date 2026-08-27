function asLights(lights) {
  return lights instanceof Array ? lights : []
}

function barVisible(lights) {
  var values = asLights(lights)
  for (var i = 0; i < values.length; i++) {
    if (values[i].reachable === true && Number(values[i].on) === 1) return true
  }
  return false
}

function trayWanted(lights) {
  return !barVisible(lights)
}

function advanceTrayMode(currentMode, requestedMode, confirmations) {
  if (requestedMode !== true) return {trayMode: false, confirmations: 0}
  if (currentMode === true) return {trayMode: true, confirmations: 0}

  var nextConfirmations = Math.max(0, Number(confirmations) || 0) + 1
  return {
    trayMode: nextConfirmations >= 2,
    confirmations: nextConfirmations >= 2 ? 0 : nextConfirmations
  }
}

function trayExitAction(exitCode, stopRequested, trayMode) {
  if (stopRequested === true || trayMode !== true) return "ignore"
  if (Number(exitCode) === 3) return "missing-dependency"
  if (Number(exitCode) === 5) return "session-bus"
  return "retry"
}

function connectionLost(lights) {
  var values = asLights(lights)
  if (values.length === 0) return false
  for (var i = 0; i < values.length; i++) {
    if (values[i].reachable === true) return false
  }
  return true
}

function shouldPoll(opened, lights) {
  return opened === true || asLights(lights).length > 0
}

function brightnessSummary(lights) {
  var values = asLights(lights)
  var total = 0
  var count = 0
  var first = -1
  var mixed = false
  for (var i = 0; i < values.length; i++) {
    if (values[i].reachable !== true) continue
    var value = Math.round(Number(values[i].brightness || 20))
    total += value
    count++
    if (first < 0) first = value
    else if (value !== first) mixed = true
  }
  return {value: count > 0 ? Math.round(total / count) : 20, mixed: mixed}
}

function temperatureSummary(lights) {
  var values = asLights(lights)
  var total = 0
  var count = 0
  var first = -1
  var mixed = false
  for (var i = 0; i < values.length; i++) {
    if (values[i].reachable !== true) continue
    var value = Math.round((1000000 / Math.max(143, Number(values[i].temperature || 213))) / 100) * 100
    total += value
    count++
    if (first < 0) first = value
    else if (value !== first) mixed = true
  }
  return {value: count > 0 ? Math.round((total / count) / 100) * 100 : 4700, mixed: mixed}
}

function enqueueCommand(commands, command) {
  var queued = commands instanceof Array ? commands : []
  return queued.concat([command])
}

function dequeueCommand(commands) {
  var queued = commands instanceof Array ? commands : []
  return {
    command: queued.length > 0 ? queued[0] : null,
    remaining: queued.length > 0 ? queued.slice(1) : []
  }
}

function operationBusy(statusInFlight, actionRunning, setupRunning, queueLength, activeCommand) {
  return statusInFlight === true || actionRunning === true || setupRunning === true
    || Number(queueLength) > 0 || activeCommand !== null && activeCommand !== false
}

function operationReady(activeOperation, exitReceived, outputReceived) {
  return activeOperation !== null && activeOperation !== false
    && exitReceived === true && outputReceived === true
}

function copyObject(source) {
  var result = {}
  if (!source) return result
  for (var key in source) result[key] = source[key]
  return result
}

function sameIdentity(left, right) {
  if (!left || !right) return false
  var leftId = String(left.id || "")
  var rightId = String(right.id || "")
  var leftDiscovery = String(left.discoveryId || leftId)
  var rightDiscovery = String(right.discoveryId || rightId)
  return leftId === rightId || leftDiscovery === rightDiscovery
}

function reconcileLights(previousLights, nextLights) {
  var previous = asLights(previousLights)
  var next = asLights(nextLights)
  var result = []

  for (var i = 0; i < next.length; i++) {
    var light = copyObject(next[i])
    if (light.reachable !== true) {
      for (var j = 0; j < previous.length; j++) {
        if (!sameIdentity(previous[j], light)) continue
        light.id = previous[j].id
        if (!light.discoveryId) light.discoveryId = previous[j].discoveryId || previous[j].id
        break
      }
    }
    result.push(light)
  }
  return result
}

function refreshQueuedTargets(commands, results) {
  var queued = commands instanceof Array ? commands : []
  var values = results instanceof Array ? results : []
  var refreshed = []

  for (var i = 0; i < queued.length; i++) {
    var command = copyObject(queued[i])
    var targets = queued[i].targets instanceof Array ? queued[i].targets : []
    command.targets = []
    for (var j = 0; j < targets.length; j++) {
      var target = copyObject(targets[j])
      for (var k = 0; k < values.length; k++) {
        if (!sameIdentity(target, values[k]) || values[k].ok !== true) continue
        if (values[k].address) target.address = values[k].address
        if (values[k].port) target.port = Number(values[k].port)
        break
      }
      command.targets.push(target)
    }
    refreshed.push(command)
  }
  return refreshed
}

function actionError(exitCode) {
  if (Number(exitCode) === 0) return ""
  if (Number(exitCode) === 2) return "The Key Light command was rejected before contacting any device."
  return "One or more lights did not respond. Please try again."
}

if (typeof module !== "undefined") {
  module.exports = {
    barVisible: barVisible,
    trayWanted: trayWanted,
    advanceTrayMode: advanceTrayMode,
    trayExitAction: trayExitAction,
    connectionLost: connectionLost,
    shouldPoll: shouldPoll,
    brightnessSummary: brightnessSummary,
    temperatureSummary: temperatureSummary,
    enqueueCommand: enqueueCommand,
    dequeueCommand: dequeueCommand,
    operationBusy: operationBusy,
    operationReady: operationReady,
    reconcileLights: reconcileLights,
    refreshQueuedTargets: refreshQueuedTargets,
    actionError: actionError
  }
}
