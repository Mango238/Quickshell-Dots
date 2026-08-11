pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Services

// Editor markdown de la nota abierta (ObsidianEditor.path). Se edita el texto
// crudo: un TextEdit con textFormat MarkdownText reescribe el archivo al
// guardar (reformatea listas, links y front-matter), así que el render vive en
// un Text de solo lectura detrás del toggle 󰈈.
Item {
    id: root

    property bool preview: false

    readonly property color cardColor: Qt.alpha(Colors.palette[3], 0.5)
    readonly property color textColor: "#e6e6e6"

    // Las fórmulas se renderizan del color del texto del preview.
    Component.onCompleted: MathRender.color = root.textColor

    function _title() {
        const p = ObsidianEditor.path
        const i = p.lastIndexOf("/")
        return (i === -1 ? p : p.slice(i + 1)).replace(/\.md$/, "")
    }

    // ── Cabecera ───────────────────────────────────────────────────────
    Rectangle {
        id: backBtn
        anchors { top: parent.top; left: parent.left }
        width: 30
        height: 30
        radius: 10
        color: backHover.containsMouse ? Qt.alpha(Colors.accent, 0.25) : root.cardColor
        Text {
            anchors.centerIn: parent
            text: ""
            font.pixelSize: 15
            color: root.textColor
        }
        MouseArea {
            id: backHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ObsidianEditor.close()
        }
    }

    Text {
        id: title
        anchors { left: backBtn.right; leftMargin: 10; right: actions.left; rightMargin: 10
                  verticalCenter: backBtn.verticalCenter }
        text: root._title()
        color: root.textColor
        font.pixelSize: 17
        font.bold: true
        elide: Text.ElideMiddle
    }

    Row {
        id: actions
        anchors { right: parent.right; verticalCenter: backBtn.verticalCenter }
        spacing: 6

        Rectangle {
            id: previewBtn
            width: 30
            height: 30
            radius: 10
            color: root.preview ? Colors.accent
                 : previewHover.containsMouse ? Qt.alpha(Colors.accent, 0.25)
                 : root.cardColor
            Text {
                anchors.centerIn: parent
                text: "󰈈"
                font.pixelSize: 15
                color: root.preview ? Colors.accentText : root.textColor
            }
            MouseArea {
                id: previewHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.preview = !root.preview
            }
        }

        Rectangle {
            id: obsidianBtn
            width: 30
            height: 30
            radius: 10
            color: obsidianHover.containsMouse ? Qt.alpha(Colors.accent, 0.25) : root.cardColor
            Text {
                anchors.centerIn: parent
                text: "󰏋"
                font.pixelSize: 15
                color: root.textColor
            }
            MouseArea {
                id: obsidianHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(
                    ["xdg-open", "obsidian://open?path=" + encodeURIComponent(ObsidianEditor.path)])
            }
        }
    }

    // ── Estado de guardado ─────────────────────────────────────────────
    Text {
        id: status
        anchors { top: backBtn.bottom; topMargin: 8; left: parent.left; right: parent.right }
        text: ObsidianEditor.error !== "" ? ObsidianEditor.error
            : ObsidianEditor.dirty ? "sin guardar · Ctrl+S"
            : "guardado"
        color: ObsidianEditor.error !== "" ? Colors.danger : root.textColor
        opacity: ObsidianEditor.error !== "" ? 1.0 : 0.5
        font.pixelSize: 11
        elide: Text.ElideRight
    }

    // ── Cuerpo ─────────────────────────────────────────────────────────
    Flickable {
        id: editFlick
        anchors { top: status.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: !root.preview
        clip: true
        contentWidth: width
        contentHeight: editor.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        TextEdit {
            id: editor
            width: editFlick.width
            color: root.textColor
            font.family: Config.font
            font.pixelSize: 14
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            selectionColor: Qt.alpha(Colors.accent, 0.5)

            onTextChanged: ObsidianEditor.text = text

            // Mantiene el cursor a la vista al escribir más allá del pliegue.
            onCursorRectangleChanged: {
                const r = cursorRectangle
                if (r.y < editFlick.contentY)
                    editFlick.contentY = r.y
                else if (r.y + r.height > editFlick.contentY + editFlick.height)
                    editFlick.contentY = r.y + r.height - editFlick.height
            }

            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
                    event.accepted = true
                    ObsidianEditor.save()
                }
            }
            // Primer Escape sale del editor; el segundo cierra el sidebar.
            Keys.onEscapePressed: (event) => {
                event.accepted = true
                ObsidianEditor.close()
            }

            Component.onCompleted: {
                editor.text = ObsidianEditor.text   // ya había cargado
                Qt.callLater(() => editor.forceActiveFocus())
            }
        }

        // La carga del archivo es asíncrona: puede terminar después de que
        // esta vista se creó.
        Connections {
            target: ObsidianEditor
            function onTextLoaded(t) { editor.text = t }
        }
    }

    Flickable {
        id: previewFlick
        anchors.fill: editFlick
        visible: root.preview
        clip: true
        contentWidth: width
        contentHeight: rendered.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        MarkdownView {
            id: rendered
            width: previewFlick.width
            // Solo se parsea con el preview a la vista: reparsear la nota
            // entera en cada tecla mientras se edita no le sirve a nadie.
            source: root.preview ? ObsidianEditor.text : ""
            color: root.textColor
            font.family: Config.font
            font.pixelSize: 14
        }
    }

}
