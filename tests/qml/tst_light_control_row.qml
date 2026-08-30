import QtQuick
import QtTest
import "../.." as Plugin

Item {
  id: testSurface
  width: 420
  height: 220

  Component {
    id: rowComponent
    Plugin.LightControlRow {
      width: 360
      rowIndex: 0
      rowCount: 2
      rowSpacing: 9
      light: ({id: "SERIAL-1", name: "Links", reachable: true, on: 0})
      displayName: "Links"
      statusText: "Off"
    }
  }

  TestCase {
    id: testCase
    name: "LightControlRow"
    when: windowShown

    SignalSpy { id: moveSpy; signalName: "moveRequested" }
    SignalSpy { id: renameSpy; signalName: "renameRequested" }
    SignalSpy { id: toggleSpy; signalName: "toggleRequested" }

    function createRow() {
      var row = createTemporaryObject(rowComponent, testSurface, {x: 20, y: 20})
      verify(row !== null)
      moveSpy.target = row
      renameSpy.target = row
      toggleSpy.target = row
      moveSpy.clear()
      renameSpy.clear()
      toggleSpy.clear()
      waitForRendering(row)
      return row
    }

    function test_drag_moves_first_row_down_without_toggling_light() {
      var row = createRow()
      var handle = findChild(row, "dragHandle")
      verify(handle !== null)

      mouseDrag(handle, handle.width / 2, handle.height / 2,
        0, row.height + row.rowSpacing + 8, Qt.LeftButton)

      tryCompare(moveSpy, "count", 1)
      compare(moveSpy.signalArguments[0][0], 0)
      compare(moveSpy.signalArguments[0][1], 1)
      compare(toggleSpy.count, 0)
    }

    function test_pencil_opens_inline_name_editor_without_toggling_light() {
      var row = createRow()
      var renameButton = findChild(row, "renameButton")
      var nameEditor = findChild(row, "nameEditor")
      verify(renameButton !== null)
      verify(nameEditor !== null)
      compare(row.editingName, false)

      mouseClick(renameButton, renameButton.width / 2, renameButton.height / 2, Qt.LeftButton)

      tryCompare(row, "editingName", true)
      compare(nameEditor.visible, true)
      compare(nameEditor.text, "Links")
      compare(toggleSpy.count, 0)
    }

    function test_enabled_light_uses_green_switch_track() {
      var row = createTemporaryObject(rowComponent, testSurface, {
        x: 20,
        y: 20,
        light: ({id: "SERIAL-1", name: "Links", reachable: true, on: 1})
      })
      verify(row !== null)
      waitForRendering(row)

      var track = findChild(row, "toggleTrack")
      verify(track !== null)
      compare(track.color.toString().toLowerCase(), "#4ade80")
    }
  }
}
