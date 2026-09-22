import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Menu-summoned Glide panel. Layer-shell overlay so it does not steal a
// tile. Live changes go through scripts/omarchy-glide.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property bool closingFromHost: false

  property string deviceName: ""
  property real sensitivity: 0
  property string accelProfile: "adaptive"
  property real scrollFactor: 0.4
  property bool naturalScroll: false
  property bool disableWhileTyping: true

  property int speed: 50
  property int scrollPercent: 40
  property bool applying: false
  property var queuedSet: null

  property string focusSection: "speed"
  property int selectedIndex: 0
  property bool cursorActive: false

  readonly property string pluginId: (manifest && manifest.id) || "payton.glide"
  readonly property string bin: {
    var home = Quickshell.env("HOME") || ""
    return home + "/.config/omarchy/plugins/payton.glide/scripts/omarchy-glide"
  }
  readonly property color foreground: Color.foreground
  readonly property color background: Color.popups.background
  readonly property color accent: Color.accent
  readonly property string fontFamily: Style.font.family

  readonly property var fakeBar: QtObject {
    readonly property color foreground: root.foreground
    readonly property color background: root.background
    readonly property color urgent: Color.urgent
    readonly property string fontFamily: root.fontFamily
    readonly property string position: "top"
    readonly property bool vertical: false
    readonly property int barSize: 26
  }

  readonly property var visibleSections: ["speed", "scroll", "accel", "natural", "dwt", "reset"]

  function open(payloadJson) {
    closingFromHost = false
    opened = true
    cursorActive = false
    focusSection = "speed"
    selectedIndex = 0
    refresh()
    Qt.callLater(function() {
      if (root.opened && keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    closingFromHost = true
    opened = false
    closingFromHost = false
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function refresh() {
    if (!getProc.running) getProc.running = true
  }

  function applyState(raw) {
    var state = Model.parseState(raw)
    deviceName = state.device
    sensitivity = state.sensitivity
    accelProfile = state.accel_profile
    scrollFactor = state.scroll_factor
    naturalScroll = state.natural_scroll
    disableWhileTyping = state.disable_while_typing
    speed = state.speed
    scrollPercent = state.scroll_percent
  }

  function setValues(updates) {
    var args = [root.bin, "set", "--json"]
    for (var i = 0; i < updates.length; i += 2) {
      args.push(updates[i])
      args.push(String(updates[i + 1]))
    }
    if (setProc.running) {
      queuedSet = args
      return
    }
    queuedSet = null
    applying = true
    setProc.command = args
    setProc.running = true
  }

  function setSpeed(value) {
    var next = Math.round(Model.clamp(value, 0, 100))
    speed = next
    sensitivity = Model.speedToSensitivity(next)
    debounce.restart()
  }

  function flushSpeed() {
    debounce.stop()
    setValues(["sensitivity", sensitivity])
  }

  function setScrollPercent(value) {
    var next = Math.round(Model.clamp(value, 10, 150))
    scrollPercent = next
    scrollFactor = Model.percentToScroll(next)
    scrollDebounce.restart()
  }

  function flushScroll() {
    scrollDebounce.stop()
    setValues(["scroll-factor", scrollFactor])
  }

  function setAccel(value) {
    accelProfile = value === "flat" ? "flat" : "adaptive"
    setValues(["accel-profile", accelProfile])
  }

  function resetDefaults() {
    resetProc.running = true
  }

  function sectionCount(section) {
    if (section === "accel") return 2
    return 1
  }

  function sectionIsHorizontal(section) {
    return section === "accel"
  }

  function sectionAdjustsValue(section) {
    return section === "speed" || section === "scroll"
  }

  function moveCursor(delta) {
    var sections = visibleSections
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = sections[0]
      selectedIndex = 0
      return
    }
    if (sectionIsHorizontal(focusSection) || sectionAdjustsValue(focusSection) || sectionCount(focusSection) <= 1) {
      if (delta > 0 && sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = 0
      } else if (delta < 0 && sIdx > 0) {
        focusSection = sections[sIdx - 1]
        selectedIndex = 0
      }
      return
    }
  }

  function moveCursorH(delta) {
    if (focusSection === "speed") {
      setSpeed(speed + delta * 5)
      return
    }
    if (focusSection === "scroll") {
      setScrollPercent(scrollPercent + delta * 5)
      return
    }
    if (focusSection === "accel") {
      selectedIndex = Math.max(0, Math.min(1, selectedIndex + delta))
    }
  }

  function activateCursor() {
    if (focusSection === "accel") setAccel(selectedIndex === 1 ? "flat" : "adaptive")
    else if (focusSection === "natural") {
      naturalScroll = !naturalScroll
      setValues(["natural-scroll", naturalScroll ? "true" : "false"])
    } else if (focusSection === "dwt") {
      disableWhileTyping = !disableWhileTyping
      setValues(["disable-while-typing", disableWhileTyping ? "true" : "false"])
    } else if (focusSection === "reset") resetDefaults()
  }

  Process {
    id: getProc
    command: [root.bin, "get", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (debounce.running || scrollDebounce.running || setProc.running) return
        root.applyState(text)
      }
    }
  }

  Process {
    id: setProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text) root.applyState(text)
    }
    onRunningChanged: {
      if (running) return
      root.applying = false
      if (root.queuedSet) {
        var args = root.queuedSet
        root.queuedSet = null
        root.applying = true
        command = args
        running = true
      }
    }
  }

  Process {
    id: resetProc
    command: [root.bin, "reset", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text) root.applyState(text)
    }
  }

  Timer {
    id: debounce
    interval: 140
    repeat: false
    onTriggered: root.flushSpeed()
  }

  Timer {
    id: scrollDebounce
    interval: 140
    repeat: false
    onTriggered: root.flushScroll()
  }

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-glide"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.42)
      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(400), parent.width - Style.space(32))
      height: Math.min(column.implicitHeight + card.contentTopInset + card.contentBottomInset, parent.height - Style.space(32))
      anchors.centerIn: parent
      color: root.background
      radius: Style.cornerRadius
      padding: Style.spacing.popupPadding
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
      }

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        onMoveRequested: function(dx, dy) {
          if (!root.cursorActive) { root.cursorActive = true; return }
          if (dy !== 0) root.moveCursor(dy)
          else if (dx !== 0) root.moveCursorH(dx)
        }
        onActivateRequested: if (root.cursorActive) root.activateCursor()
        onCloseRequested: root.dismiss()

        Column {
          id: column
          width: parent.width
          spacing: Style.space(14)

          PanelHero {
            width: parent.width
            foreground: root.foreground
            fontFamily: root.fontFamily
            title: "Glide"
            meta: root.deviceName !== "" ? root.deviceName : "No touchpad detected"
              iconComponent: Component {
                Text {
                  text: "󰟸"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Pointer speed applies only to this pad. An external mouse is unchanged."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Item {
                width: parent.width
                implicitHeight: Math.max(speedHeader.implicitHeight, speedValue.implicitHeight)

                PanelSectionHeader {
                  id: speedHeader
                  text: "SPEED"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: speedValue
                  textFormat: Text.PlainText
                  text: root.speed + (root.speed === 50 ? "  default" : "")
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              CursorSurface {
                id: speedRow
                width: parent.width
                height: speedSlider.implicitHeight + Style.spacing.controlGap
                hasCursor: root.cursorActive && root.focusSection === "speed"
                foreground: root.foreground
                outline: true

                PanelSlider {
                  id: speedSlider
                  bar: root.fakeBar
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  minimum: 0
                  maximum: 100
                  step: 1
                  integer: true
                  tickCount: 5
                  value: root.speed
                  onMoved: function(v) {
                    root.cursorActive = true
                    root.focusSection = "speed"
                    root.setSpeed(v)
                  }
                  onReleased: function(v) {
                    root.setSpeed(v)
                    root.flushSpeed()
                  }
                }

                HoverHandler {
                  onHoveredChanged: if (hovered) {
                    root.cursorActive = true
                    root.focusSection = "speed"
                    root.selectedIndex = 0
                  }
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Item {
                width: parent.width
                implicitHeight: Math.max(scrollHeader.implicitHeight, scrollValue.implicitHeight)

                PanelSectionHeader {
                  id: scrollHeader
                  text: "SCROLL"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: scrollValue
                  textFormat: Text.PlainText
                  text: root.scrollPercent + "%"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              CursorSurface {
                id: scrollRow
                width: parent.width
                height: scrollSlider.implicitHeight + Style.spacing.controlGap
                hasCursor: root.cursorActive && root.focusSection === "scroll"
                foreground: root.foreground
                outline: true

                PanelSlider {
                  id: scrollSlider
                  bar: root.fakeBar
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  minimum: 10
                  maximum: 150
                  step: 5
                  integer: true
                  value: root.scrollPercent
                  onMoved: function(v) {
                    root.cursorActive = true
                    root.focusSection = "scroll"
                    root.setScrollPercent(v)
                  }
                  onReleased: function(v) {
                    root.setScrollPercent(v)
                    root.flushScroll()
                  }
                }

                HoverHandler {
                  onHoveredChanged: if (hovered) {
                    root.cursorActive = true
                    root.focusSection = "scroll"
                    root.selectedIndex = 0
                  }
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                text: "ACCELERATION"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              ButtonGroup {
                id: accelGroup
                width: parent.width
                foreground: root.foreground
                background: root.background
                accent: root.accent
                fontFamily: root.fontFamily
                focusable: false
                cursorIndex: root.cursorActive && root.focusSection === "accel" ? root.selectedIndex : -1
                value: root.accelProfile
                options: [
                  { value: "adaptive", label: "Adaptive" },
                  { value: "flat", label: "Flat" }
                ]
                onChanged: function(v) { root.setAccel(v) }
                onHovered: function(index, on) {
                  if (!on) return
                  root.cursorActive = true
                  root.focusSection = "accel"
                  root.selectedIndex = index
                }
              }
            }

            Toggle {
              width: parent.width
              label: "Natural scrolling"
              description: "Content follows your fingers."
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              checked: root.naturalScroll
              hasCursor: root.cursorActive && root.focusSection === "natural"
              onHovered: function(on) {
                if (!on) return
                root.cursorActive = true
                root.focusSection = "natural"
                root.selectedIndex = 0
              }
              onClicked: {
                root.naturalScroll = !root.naturalScroll
                root.setValues(["natural-scroll", root.naturalScroll ? "true" : "false"])
              }
            }

            Toggle {
              width: parent.width
              label: "Ignore while typing"
              description: "Blocks the pad briefly after each key. Off feels snappier; on reduces palm clicks."
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              checked: root.disableWhileTyping
              hasCursor: root.cursorActive && root.focusSection === "dwt"
              onHovered: function(on) {
                if (!on) return
                root.cursorActive = true
                root.focusSection = "dwt"
                root.selectedIndex = 0
              }
              onClicked: {
                root.disableWhileTyping = !root.disableWhileTyping
                root.setValues(["disable-while-typing", root.disableWhileTyping ? "true" : "false"])
              }
            }

            Button {
              width: parent.width
              text: "Reset to Omarchy defaults"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              bordered: true
              hasCursor: root.cursorActive && root.focusSection === "reset"
              onHovered: function(on) {
                if (!on) return
                root.cursorActive = true
                root.focusSection = "reset"
                root.selectedIndex = 0
              }
              onClicked: root.resetDefaults()
            }
        }
      }
    }
  }
}
