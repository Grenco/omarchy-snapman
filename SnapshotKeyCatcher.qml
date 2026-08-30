import QtQuick

Item {
  id: root

  property bool blocked: false
  property var confirmationDialog: null

  signal moveRequested(int dx, int dy)
  signal activateRequested()
  signal returnRequested()
  signal closeRequested()
  signal quitRequested()
  signal deleteRequested()
  signal tabRequested(int direction)
  signal textKey(string text)

  focus: true
  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (blocked) return

    // Q always leaves the panel, even while a confirmation is open.
    if (event.text === "q" || event.text === "Q") {
      quitRequested(); event.accepted = true; return
    }

    // A confirmation dialog is fully modal: it owns every key while open.
    if (confirmationDialog && confirmationDialog.opened) {
      if (event.text === "h" || event.text === "H" || event.text === "l" || event.text === "L") {
        confirmationDialog.selectedIndex = confirmationDialog.selectedIndex === 0 ? 1 : 0
        event.accepted = true
        return
      }
      confirmationDialog.handleKey(event)
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Escape) {
      closeRequested(); event.accepted = true; return
    }
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      tabRequested((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Down || event.text === "j") {
      moveRequested(0, 1); event.accepted = true; return
    }
    if (event.key === Qt.Key_Up || event.text === "k") {
      moveRequested(0, -1); event.accepted = true; return
    }
    if (event.key === Qt.Key_Right || event.text === "l") {
      moveRequested(1, 0); event.accepted = true; return
    }
    if (event.key === Qt.Key_Left || event.text === "h") {
      moveRequested(-1, 0); event.accepted = true; return
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      returnRequested()
      activateRequested(); event.accepted = true; return
    }
    if (event.key === Qt.Key_Space) {
      activateRequested(); event.accepted = true; return
    }
    if (event.key === Qt.Key_Delete || event.text === "x" || event.text === "X") {
      deleteRequested(); event.accepted = true; return
    }
    if (event.text && event.text.length === 1) textKey(event.text)
  }
}
