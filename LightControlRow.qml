pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

Item {
  id: root

  property var light: ({})
  property int rowIndex: 0
  property int rowCount: 1
  property real rowSpacing: 0
  property bool preferenceBusy: false
  property bool actionBusy: false
  property color foreground: "white"
  property color accent: "#ff6b6b"
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: "sans-serif"
  property real rowHeight: 38
  property real dragHandleWidth: 22
  property real actionSize: 26
  property real bodyFontSize: 14
  property real captionFontSize: 11
  property real iconFontSize: 16
  property real controlGap: 6
  property string displayName: "Key Light"
  property string statusText: ""
  property var cancelFocusTarget: null
  property bool editingName: false
  property real dragDistance: 0

  signal moveRequested(int fromIndex, int toIndex)
  signal renameRequested(var light, int index, string name)
  signal toggleRequested(var light, bool currentlyChecked)

  implicitHeight: rowHeight
  height: implicitHeight
  z: reorderDrag.active ? 10 : 0
  opacity: reorderDrag.active ? 0.8 : 1
  transform: Translate { y: reorderDrag.active ? reorderDrag.translation.y : 0 }

  Item {
    id: dragHandle
    objectName: "dragHandle"
    width: root.dragHandleWidth
    height: parent.height
    anchors.left: parent.left

    Text {
      anchors.centerIn: parent
      text: "☰"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: root.iconFontSize
    }

    HoverHandler { id: dragHover }
    ToolTip.visible: dragHover.hovered
    ToolTip.text: "Drag to reorder"

    DragHandler {
      id: reorderDrag
      target: null
      enabled: root.rowCount > 1 && !root.preferenceBusy && !root.editingName
      grabPermissions: PointerHandler.CanTakeOverFromAnything
        | PointerHandler.ApprovesTakeOverByAnything
      xAxis.enabled: false
      yAxis.enabled: true
      onTranslationChanged: if (active) root.dragDistance = translation.y
      onActiveChanged: {
        if (active) {
          root.dragDistance = 0
          return
        }
        var rowHeight = Math.max(1, root.height + root.rowSpacing)
        var destination = Math.max(0, Math.min(root.rowCount - 1,
          root.rowIndex + Math.round(root.dragDistance / rowHeight)))
        if (destination !== root.rowIndex) root.moveRequested(root.rowIndex, destination)
        root.dragDistance = 0
      }
    }

  }

  Column {
    anchors.left: dragHandle.right
    anchors.leftMargin: 4
    anchors.right: lightActions.left
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    Text {
      visible: !root.editingName
      text: root.displayName
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.bodyFontSize
      font.bold: true
      width: parent.width
      elide: Text.ElideRight
    }

    TextField {
      id: nameEditor
      objectName: "nameEditor"
      visible: root.editingName
      width: parent.width
      height: root.actionSize
      leftPadding: 6
      rightPadding: 6
      topPadding: 0
      bottomPadding: 0
      maximumLength: 64
      color: root.foreground
      selectionColor: root.accent
      selectedTextColor: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.bodyFontSize
      selectByMouse: true
      background: Rectangle {
        color: "transparent"
        border.width: 1
        border.color: root.dim
        radius: 3
      }
      onAccepted: root.renameRequested(root.light, root.rowIndex, text)
      Keys.onEscapePressed: {
        root.editingName = false
        if (root.cancelFocusTarget) root.cancelFocusTarget.forceActiveFocus()
      }
    }

    Text {
      visible: !root.editingName
      text: root.statusText
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: root.captionFontSize
    }
  }

  Row {
    id: lightActions
    anchors.right: lightSwitch.left
    anchors.rightMargin: root.controlGap
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2

    Rectangle {
      objectName: "renameButton"
      visible: !root.editingName
      width: root.actionSize
      height: root.actionSize
      color: renameHover.hovered ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : "transparent"
      radius: 3
      enabled: !root.preferenceBusy

      Text {
        anchors.centerIn: parent
        text: "✎"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.iconFontSize
      }
      HoverHandler { id: renameHover }
      ToolTip.visible: renameHover.hovered
      ToolTip.text: "Rename light"
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          nameEditor.text = String(root.light.name || "Key Light")
          root.editingName = true
          Qt.callLater(function() {
            nameEditor.forceActiveFocus()
            nameEditor.selectAll()
          })
        }
      }
    }

    Rectangle {
      visible: root.editingName
      width: root.actionSize
      height: root.actionSize
      color: "transparent"
      enabled: !root.preferenceBusy
      Text {
        anchors.centerIn: parent
        text: "✓"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.iconFontSize
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.renameRequested(root.light, root.rowIndex, nameEditor.text)
      }
    }

    Rectangle {
      visible: root.editingName
      width: root.actionSize
      height: root.actionSize
      color: "transparent"
      enabled: !root.preferenceBusy
      Text {
        anchors.centerIn: parent
        text: "×"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.iconFontSize
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.editingName = false
      }
    }
  }

  Item {
    id: lightSwitch
    objectName: "lightSwitch"
    readonly property bool checked: root.light.reachable === true && Number(root.light.on) === 1
    readonly property real trackHeight: 18
    readonly property real trackWidth: Math.round(trackHeight * 1.9)
    readonly property real knobSize: Math.round(trackHeight * 0.72)
    readonly property real knobInset: Math.round((trackHeight - knobSize) / 2)
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: trackWidth + 8
    height: trackHeight + 8
    enabled: root.light.reachable === true
    opacity: enabled ? 1 : 0.45

    Rectangle {
      id: toggleTrack
      width: lightSwitch.trackWidth
      height: lightSwitch.trackHeight
      anchors.centerIn: parent
      radius: height / 2
      color: lightSwitch.checked ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
      border.width: 1
      border.color: root.dim

      Rectangle {
        width: lightSwitch.knobSize
        height: lightSwitch.knobSize
        radius: height / 2
        x: lightSwitch.checked
          ? toggleTrack.width - width - lightSwitch.knobInset
          : lightSwitch.knobInset
        anchors.verticalCenter: parent.verticalCenter
        color: root.foreground
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: lightSwitch.enabled && !root.actionBusy
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.toggleRequested(root.light, lightSwitch.checked)
    }
  }
}
