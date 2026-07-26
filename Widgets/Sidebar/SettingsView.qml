pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons

// Editor de Config/config.json. Escribe SIEMPRE directo al singleton Config
// (qs.Commons), que persiste cada cambio vía JsonAdapter — nunca a properties
// espejo, o se rompe la recarga en vivo. Lo que no tiene UI aquí (power.*,
// themeSync.*, players: listas de comandos y rutas) se edita con el botón
// "Abrir config.json" del pie.
Item {
    id: root

    readonly property color cardColor: Qt.alpha(Colors.palette[3], 0.5)
    readonly property color textColor: "#e6e6e6"
    readonly property int fieldHeight: 34

    // ── Filas reutilizables ────────────────────────────────────────────

    component TextRow: Item {
        id: trow
        property string label: ""
        property string value: ""
        property bool numeric: false
        signal committed(string text)

        width: parent.width
        height: trowLabel.height + 4 + root.fieldHeight

        Text {
            id: trowLabel
            anchors { top: parent.top; left: parent.left }
            text: trow.label
            color: root.textColor
            opacity: 0.55
            font.pixelSize: 11
        }
        Rectangle {
            anchors { top: trowLabel.bottom; topMargin: 4; left: parent.left; right: parent.right }
            height: root.fieldHeight
            radius: 8
            color: root.cardColor
            border.width: trowInput.activeFocus ? 2 : 1
            border.color: trowInput.activeFocus ? Colors.accent : Qt.rgba(1, 1, 1, 0.12)

            TextInput {
                id: trowInput
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                verticalAlignment: TextInput.AlignVCenter
                color: root.textColor
                font.pixelSize: 13
                clip: true
                selectByMouse: true
                validator: trow.numeric ? trowValidator : null
                onEditingFinished: trow.committed(text)
            }
            // El texto no se bindea directo: escribir en un TextInput rompe el
            // binding y el campo dejaría de reflejar cambios del archivo. Con
            // `when` el valor vuelve a mandar en cuanto el campo pierde el foco.
            Binding {
                target: trowInput
                property: "text"
                value: trow.value
                when: !trowInput.activeFocus
                restoreMode: Binding.RestoreNone
            }
        }
        IntValidator { id: trowValidator; bottom: 0 }
    }

    component ToggleRow: Item {
        id: krow
        property string label: ""
        property bool value: false
        signal toggled(bool v)

        width: parent.width
        height: root.fieldHeight

        Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            text: krow.label
            color: root.textColor
            font.pixelSize: 13
        }
        Rectangle {
            id: track
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 40
            height: 22
            radius: 11
            color: krow.value ? Colors.accent : Qt.alpha(Colors.palette[4], 0.6)
            Behavior on color { ColorAnimation { duration: Config.anim.instant } }

            Rectangle {
                width: 16
                height: 16
                radius: 8
                y: 3
                x: krow.value ? track.width - width - 3 : 3
                color: krow.value ? Colors.accentText : "#e6e6e6"
                Behavior on x {
                    NumberAnimation { duration: Config.anim.instant; easing.type: Config.easingOf(Config.anim.standard) }
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: krow.toggled(!krow.value)
            }
        }
    }

    component ChoiceRow: Item {
        id: crow
        property string label: ""
        property var options: []
        property string value: ""
        signal picked(string v)

        width: parent.width
        height: crowLabel.height + 4 + 26

        Text {
            id: crowLabel
            anchors { top: parent.top; left: parent.left }
            text: crow.label
            color: root.textColor
            opacity: 0.55
            font.pixelSize: 11
        }
        Row {
            anchors { top: crowLabel.bottom; topMargin: 4; left: parent.left }
            spacing: 6

            Repeater {
                model: crow.options
                delegate: Rectangle {
                    id: chip
                    required property string modelData
                    readonly property bool current: modelData === crow.value
                    height: 26
                    width: chipText.implicitWidth + 18
                    radius: 13
                    color: current ? Colors.accent : root.cardColor

                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: chip.modelData
                        color: chip.current ? Colors.accentText : root.textColor
                        font.pixelSize: 11
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: crow.picked(chip.modelData)
                    }
                }
            }
        }
    }

    component SectionLabel: Text {
        color: Colors.accent
        font.pixelSize: 12
        font.bold: true
        topPadding: 6
    }

    // ── UI ─────────────────────────────────────────────────────────────

    Text {
        id: title
        anchors { top: parent.top; left: parent.left }
        text: "Configuración"
        color: root.textColor
        font.pixelSize: 20
        font.bold: true
    }

    Flickable {
        id: flick
        anchors { top: title.bottom; topMargin: 12; left: parent.left; right: parent.right
                  bottom: footer.top; bottomMargin: 10 }
        clip: true
        contentHeight: col.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: flick.width
            spacing: 8

            SectionLabel { text: "General" }

            TextRow {
                label: "Fuente"
                value: Config.font
                onCommitted: t => Config.font = t
            }

            SectionLabel { text: "Usuario" }

            TextRow {
                label: "Nombre a mostrar"
                value: Config.user.displayName
                onCommitted: t => Config.user.displayName = t
            }
            TextRow {
                label: "Avatar (ruta)"
                value: Config.user.avatar
                onCommitted: t => Config.user.avatar = t
            }

            SectionLabel { text: "Wallpaper" }

            TextRow {
                label: "Directorio"
                value: Config.wallpaper.dir
                onCommitted: t => Config.wallpaper.dir = t
            }
            TextRow {
                label: "Backend"
                value: Config.wallpaper.backend
                onCommitted: t => Config.wallpaper.backend = t
            }

            SectionLabel { text: "Bloqueo" }

            ToggleRow {
                label: "Ocultar contraseña"
                value: Config.lock.hidePassword
                onToggled: v => Config.lock.hidePassword = v
            }
            TextRow {
                label: "Duración del revelado (ms)"
                numeric: true
                value: String(Config.lock.revealDuration)
                onCommitted: t => { if (t.length > 0) Config.lock.revealDuration = parseInt(t) }
            }

            SectionLabel { text: "Animaciones (ms)" }

            TextRow {
                label: "instant"
                numeric: true
                value: String(Config.anim.instant)
                onCommitted: t => { if (t.length > 0) Config.anim.instant = parseInt(t) }
            }
            TextRow {
                label: "base"
                numeric: true
                value: String(Config.anim.base)
                onCommitted: t => { if (t.length > 0) Config.anim.base = parseInt(t) }
            }
            TextRow {
                label: "panel"
                numeric: true
                value: String(Config.anim.panel)
                onCommitted: t => { if (t.length > 0) Config.anim.panel = parseInt(t) }
            }
            TextRow {
                label: "slow"
                numeric: true
                value: String(Config.anim.slow)
                onCommitted: t => { if (t.length > 0) Config.anim.slow = parseInt(t) }
            }
            TextRow {
                label: "ambient"
                numeric: true
                value: String(Config.anim.ambient)
                onCommitted: t => { if (t.length > 0) Config.anim.ambient = parseInt(t) }
            }

            SectionLabel { text: "Curvas" }

            // Lista cerrada: son los únicos nombres que Config.easingOf mapea.
            ChoiceRow {
                label: "standard"
                options: ["OutCubic", "OutBack", "OutExpo", "InCubic"]
                value: Config.anim.standard
                onPicked: v => Config.anim.standard = v
            }
            ChoiceRow {
                label: "emphasized"
                options: ["OutCubic", "OutBack", "OutExpo", "InCubic"]
                value: Config.anim.emphasized
                onPicked: v => Config.anim.emphasized = v
            }
            ChoiceRow {
                label: "decelerate"
                options: ["OutCubic", "OutBack", "OutExpo", "InCubic"]
                value: Config.anim.decelerate
                onPicked: v => Config.anim.decelerate = v
            }
            ChoiceRow {
                label: "exit"
                options: ["OutCubic", "OutBack", "OutExpo", "InCubic"]
                value: Config.anim.exit
                onPicked: v => Config.anim.exit = v
            }
        }
    }

    Row {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        spacing: 8

        readonly property real btnWidth: (width - spacing) / 2

        Rectangle {
            id: openBtn
            width: footer.btnWidth
            height: 34
            radius: 8
            color: openHover.containsMouse ? Qt.alpha(Colors.accent, 0.25) : root.cardColor

            Text {
                anchors.centerIn: parent
                text: "󰈔  Abrir config.json"
                color: root.textColor
                font.pixelSize: 12
            }
            MouseArea {
                id: openHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(
                    ["xdg-open", Quickshell.env("HOME") + "/.config/quickshell/Config/config.json"])
            }
        }

        // Doble pulsación: el primer click arma, el segundo aplica. Sin esto un
        // click perdido borra las animaciones que hayas ajustado.
        Rectangle {
            id: resetBtn
            property bool armed: false
            width: footer.btnWidth
            height: 34
            radius: 8
            color: armed ? Qt.alpha("#e05561", 0.35)
                 : resetHover.containsMouse ? Qt.alpha(Colors.accent, 0.25)
                 : root.cardColor
            Behavior on color { ColorAnimation { duration: Config.anim.instant } }

            Text {
                anchors.centerIn: parent
                text: resetBtn.armed ? "󰀦  ¿Seguro?" : "󰦛  Restablecer"
                color: root.textColor
                font.pixelSize: 12
            }
            MouseArea {
                id: resetHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (resetBtn.armed) {
                        resetBtn.armed = false
                        disarm.stop()
                        Config.resetDefaults()
                    } else {
                        resetBtn.armed = true
                        disarm.restart()
                    }
                }
            }
            Timer {
                id: disarm
                interval: 3000
                onTriggered: resetBtn.armed = false
            }
        }
    }
}
