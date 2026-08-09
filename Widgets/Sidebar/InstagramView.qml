pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Services

// Hilo de DMs de Instagram. Estructura calcada de ClaudeCodeView: cabecera,
// ListView de burbujas e input abajo. Lo que cambia es de dónde salen los
// mensajes (InstagramService, que consulta cada tantos segundos), que acá el
// texto viene de un tercero, y dos gestos propios: la cabecera abre el
// selector de conversación, y un click en una burbuja la marca para citarla.
Item {
    id: root

    readonly property color cardColor: Qt.alpha(Colors.palette[3], 0.5)
    readonly property color textColor: "#e6e6e6"

    // Selector de hilo. Se abre a mano desde la cabecera, y solo se muestra
    // porque sí cuando no hay conversación abierta — un chat vacío sin
    // explicación es peor que la lista.
    property bool picking: false
    readonly property bool showPicker: root.picking
        || (InstagramService.ready && !InstagramService.hasThread)
    onShowPickerChanged: if (root.showPicker) InstagramService.loadThreads()

    // Mensaje que se está citando. Vacío = se manda suelto.
    property string replyId: ""
    property string replyText: ""

    // El sidebar destruye esta vista al cerrarse o al cambiar de pestaña, así
    // que el timer muere con ella: no se consulta la API con el panel oculto.
    Timer {
        interval: Math.max(5, Config.instagram.pollSeconds) * 1000
        repeat: true
        triggeredOnStart: true      // refresco inmediato al abrir, no a los 20 s
        running: InstagramService.hasThread && !root.showPicker
        onTriggered: InstagramService.refresh()
    }

    // ── Cabecera (abre el selector) ────────────────────────────────────
    Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 28

        Text {
            id: title
            anchors { left: parent.left; right: chevron.left; rightMargin: 6
                      verticalCenter: parent.verticalCenter }
            text: root.showPicker ? "Conversaciones" : InstagramService.title
            color: root.textColor
            font.pixelSize: 20
            font.bold: true
            elide: Text.ElideRight
        }

        Text {
            id: chevron
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: root.showPicker ? "󰅖" : "󰅀"
            color: root.textColor
            opacity: headerHover.containsMouse ? 1.0 : 0.6
            font.pixelSize: 16
        }

        MouseArea {
            id: headerHover
            anchors.fill: parent
            hoverEnabled: true
            enabled: InstagramService.ready
            cursorShape: Qt.PointingHandCursor
            // Con hilo abierto la cabecera togglea; sin hilo el selector es
            // obligatorio y cerrarlo no tendría a dónde volver.
            onClicked: if (InstagramService.hasThread) root.picking = !root.picking
        }
    }

    // ── Sin sesión / apagado ───────────────────────────────────────────
    // Un fallo de sesión sin esto se ve como un panel vacío inexplicable.
    Column {
        anchors { top: header.bottom; topMargin: 24; left: parent.left; right: parent.right }
        spacing: 10
        visible: !InstagramService.ready

        Text {
            width: parent.width
            text: !Config.instagram.enabled
                ? "Prendé instagram.enabled en Config/config.json"
                : (InstagramService.error !== "" ? InstagramService.error : "Conectando…")
            color: InstagramService.error !== "" ? Colors.danger : root.textColor
            wrapMode: Text.Wrap
            font.pixelSize: 13
        }

        Rectangle {
            width: parent.width
            height: loginCmd.implicitHeight + 20
            radius: 10
            color: root.cardColor
            visible: InstagramService.error !== ""

            TextEdit {
                id: loginCmd
                anchors { left: parent.left; right: parent.right; margins: 10
                          verticalCenter: parent.verticalCenter }
                text: "~/.local/share/quickshell/ig-venv/bin/python \\\n  ~/.config/quickshell/Services/instagram.py --login \\\n  " + Config.instagram.sessionPath
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                color: root.textColor
                font.family: Config.font
                font.pixelSize: 11
                opacity: 0.8
            }
        }
    }

    // ── Selector de conversación ───────────────────────────────────────
    ListView {
        id: picker
        anchors { top: header.bottom; topMargin: 12; left: parent.left; right: parent.right
                  bottom: parent.bottom }
        clip: true
        visible: InstagramService.ready && root.showPicker
        model: InstagramService.threads
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds

        delegate: Rectangle {
            id: row
            required property string tid
            required property string title
            required property string preview
            required property bool unread
            width: picker.width
            height: 46
            radius: 8
            color: rowHover.containsMouse ? Qt.alpha(Colors.accent, 0.18) : "transparent"

            Column {
                anchors { left: parent.left; right: dot.left; rightMargin: 8
                          leftMargin: 10; verticalCenter: parent.verticalCenter }
                spacing: 2

                Text {
                    width: parent.width
                    text: row.title
                    color: root.textColor
                    font.pixelSize: 13
                    font.bold: row.unread
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: row.preview
                    textFormat: Text.PlainText
                    color: root.textColor
                    opacity: 0.55
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                id: dot
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                width: 8
                height: 8
                radius: 4
                color: Colors.accent
                visible: row.unread
            }

            MouseArea {
                id: rowHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    InstagramService.openThread(row.tid)
                    root.picking = false
                    root.replyId = ""
                }
            }
        }
    }

    // ── Hilo ───────────────────────────────────────────────────────────
    ListView {
        id: chat
        anchors { top: header.bottom; topMargin: 12; left: parent.left; right: parent.right
                  bottom: replyChip.top; bottomMargin: 10 }
        clip: true
        visible: InstagramService.hasThread && !root.showPicker
        model: InstagramService.messages
        spacing: 8
        boundsBehavior: Flickable.StopAtBounds
        onCountChanged: Qt.callLater(() => chat.positionViewAtEnd())

        delegate: Item {
            id: msg
            required property string mid
            required property string role
            required property string text
            required property string reply
            width: chat.width
            readonly property bool isMine: role === "me"
            readonly property bool quoted: reply !== ""
            implicitHeight: bubble.height

            Rectangle {
                id: bubble
                width: Math.min(Math.max(bubbleText.implicitWidth,
                                         msg.quoted ? quoteText.implicitWidth + 8 : 0) + 24,
                                chat.width * 0.86)
                height: content.implicitHeight + 18
                radius: 12
                anchors.left: msg.isMine ? undefined : parent.left
                anchors.right: msg.isMine ? parent.right : undefined
                color: msg.isMine ? Colors.accent : root.cardColor
                // Marca de "citando esta". Blanco translúcido y no Colors.accent
                // porque las burbujas propias YA son accent y no se vería.
                border.width: root.replyId === msg.mid ? 2 : 0
                border.color: Qt.rgba(1, 1, 1, 0.55)

                Column {
                    id: content
                    anchors { left: parent.left; right: parent.right; margins: 12
                              verticalCenter: parent.verticalCenter }
                    spacing: 5

                    // Cita del mensaje al que este responde.
                    Item {
                        width: parent.width
                        height: msg.quoted ? quoteText.implicitHeight : 0
                        visible: msg.quoted

                        Rectangle {
                            id: quoteBar
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: 2
                            radius: 1
                            color: msg.isMine ? Colors.accentText : Colors.accent
                            opacity: 0.7
                        }
                        Text {
                            id: quoteText
                            anchors { left: quoteBar.right; leftMargin: 6; right: parent.right }
                            text: msg.reply
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                            color: msg.isMine ? Colors.accentText : root.textColor
                            opacity: 0.7
                            font.pixelSize: 11
                        }
                    }

                    Text {
                        id: bubbleText
                        width: parent.width
                        text: msg.text
                        // PlainText a propósito: esto lo escribe otra persona, no
                        // es markdown de confianza como la respuesta de Claude.
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: msg.isMine ? Colors.accentText : root.textColor
                        font.pixelSize: 13
                    }
                }

                // Click en la burbuja = citarla. Las burbujas no hacían nada
                // antes, así que el gesto no le pisa nada a nadie.
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: msg.mid !== "pending"
                    onClicked: {
                        root.replyId = msg.mid
                        root.replyText = msg.text
                    }
                }
            }
        }

        footer: Item {
            width: chat.width
            height: InstagramService.busy ? 30 : 0
            visible: InstagramService.busy
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "󰔟 enviando…"
                color: root.textColor
                opacity: 0.6
                font.pixelSize: 13
            }
        }
    }

    // ── Chip de cita ───────────────────────────────────────────────────
    Item {
        id: replyChip
        anchors { left: parent.left; right: parent.right; bottom: liveError.top; bottomMargin: 6 }
        height: visible ? 26 : 0
        visible: root.replyId !== "" && !root.showPicker

        Text {
            anchors { left: parent.left; right: cancelReply.left; rightMargin: 8
                      verticalCenter: parent.verticalCenter }
            text: "↳ " + root.replyText
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.textColor
            opacity: 0.7
            font.pixelSize: 12
        }
        Text {
            id: cancelReply
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: "󰅖"
            color: root.textColor
            opacity: cancelHover.containsMouse ? 1.0 : 0.6
            font.pixelSize: 14

            MouseArea {
                id: cancelHover
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.replyId = ""
            }
        }
    }

    // Fallo puntual con la sesión ya viva (rate limit, red caída): no tapa el
    // hilo, avisa arriba del input.
    Text {
        id: liveError
        anchors { left: parent.left; right: parent.right; bottom: inputBox.top; bottomMargin: 6 }
        text: InstagramService.error
        visible: InstagramService.ready && InstagramService.error !== "" && !root.showPicker
        color: Colors.danger
        wrapMode: Text.Wrap
        font.pixelSize: 11
    }

    // ── Input ──────────────────────────────────────────────────────────
    Rectangle {
        id: inputBox
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Math.max(44, input.implicitHeight + 20)
        radius: 12
        color: root.cardColor
        visible: InstagramService.hasThread && !root.showPicker
        border.width: input.activeFocus ? 2 : 1
        border.color: input.activeFocus ? Colors.accent : Qt.rgba(1, 1, 1, 0.12)
        opacity: InstagramService.busy ? 0.6 : 1.0

        TextEdit {
            id: input
            anchors { left: parent.left; right: sendBtn.left; margins: 12; verticalCenter: parent.verticalCenter }
            color: root.textColor
            font.pixelSize: 14
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            enabled: !InstagramService.busy

            Text {
                anchors.fill: parent
                text: root.replyId !== "" ? "Respondé…  (Enter envía)"
                                          : "Escribí un mensaje…  (Enter envía)"
                visible: input.text.length === 0
                color: root.textColor
                opacity: 0.4
                font.pixelSize: 14
            }

            // Enter envía; Shift+Enter inserta salto de línea.
            Keys.onPressed: (event) => {
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        && !(event.modifiers & Qt.ShiftModifier)) {
                    event.accepted = true
                    root._send()
                }
            }

            // Escape cancela la cita; si no hay ninguna deja pasar el evento
            // para que el sidebar se cierre (mismo criterio que ObsidianView).
            Keys.onEscapePressed: (event) => {
                if (root.replyId !== "") {
                    root.replyId = ""
                    event.accepted = true
                } else {
                    event.accepted = false
                }
            }

            Component.onCompleted: Qt.callLater(() => input.forceActiveFocus())
        }

        Rectangle {
            id: sendBtn
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            width: 34
            height: 34
            radius: 10
            color: (input.text.trim().length > 0 && !InstagramService.busy)
                 ? Colors.accent : Qt.alpha(Colors.palette[5], 0.4)
            Text {
                anchors.centerIn: parent
                text: " "
                font.pixelSize: 16
                color: Colors.accentText
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root._send()
            }
        }
    }

    function _send() {
        if (InstagramService.busy)
            return
        const t = input.text
        if (t.trim() === "")
            return
        InstagramService.send(t, root.replyId)
        input.text = ""
        root.replyId = ""
    }
}
