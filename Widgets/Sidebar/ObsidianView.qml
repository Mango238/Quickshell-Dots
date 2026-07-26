pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services

// Explorador de notas del vault de Obsidian: lista los .md, filtra con
// FuzzySort, y abre la nota elegida en Obsidian vía su esquema obsidian://.
// Sin editor propio. Los vaults se leen en runtime de ~/.config/obsidian/
// obsidian.json (no se hardcodean rutas).
Item {
    id: root

    property var vaults: []          // [{ path, open }]
    property string vaultPath: ""
    property var allNotes: []        // rutas absolutas de .md
    property string search: ""

    readonly property color cardColor: Qt.alpha(Colors.palette[3], 0.5)
    readonly property color textColor: "#e6e6e6"

    function _basename(p) {
        const i = p.lastIndexOf("/")
        return i === -1 ? p : p.slice(i + 1)
    }
    function _relDir(p) {
        var rel = p.startsWith(root.vaultPath) ? p.slice(root.vaultPath.length) : p
        if (rel.startsWith("/")) rel = rel.slice(1)
        const i = rel.lastIndexOf("/")
        return i === -1 ? "" : rel.slice(0, i)
    }

    // Resultados mostrados: sin búsqueda, las primeras 200 notas; con
    // búsqueda, FuzzySort sobre la ruta completa (permite filtrar por carpeta).
    readonly property var filtered: {
        if (root.search.trim() === "")
            return root.allNotes.slice(0, 200)
        const res = FuzzySort.go(root.search, root.allNotes, { limit: 200 })
        const out = []
        for (var i = 0; i < res.length; i++)
            out.push(res[i].target)
        return out
    }

    // ── Carga de vaults ────────────────────────────────────────────────
    Process {
        id: vaultsProc
        running: true
        command: ["cat", Config.obsidian.configPath]
        stdout: StdioCollector {
            id: vaultsOut
            onStreamFinished: {
                try {
                    const obj = JSON.parse(vaultsOut.text)
                    const vs = []
                    for (const id in obj.vaults)
                        vs.push({ path: obj.vaults[id].path, open: !!obj.vaults[id].open })
                    root.vaults = vs
                    const cur = vs.find(v => v.open) || vs[0]
                    if (cur)
                        root.vaultPath = cur.path
                } catch (e) {
                    // Sin obsidian.json legible: la lista queda vacía.
                }
            }
        }
    }

    // ── Escaneo de notas del vault activo ──────────────────────────────
    onVaultPathChanged: {
        root.search = ""
        if (root.vaultPath === "")
            return
        if (findProc.running)
            findProc.running = false
        findProc.command = ["find", root.vaultPath, "-name", "*.md", "-type", "f"]
        findProc.running = true
    }

    Process {
        id: findProc
        stdout: StdioCollector {
            id: findOut
            onStreamFinished: {
                root.allNotes = findOut.text.split("\n")
                    .filter(l => l.trim().length > 0)
                    .sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()))
            }
        }
    }

    // ── UI ─────────────────────────────────────────────────────────────
    Text {
        id: title
        anchors { top: parent.top; left: parent.left; right: parent.right }
        text: "Obsidian"
        color: root.textColor
        font.pixelSize: 20
        font.bold: true
    }

    // Selector de vault (una fila de chips; solo si hay más de uno)
    Flow {
        id: vaultRow
        anchors { top: title.bottom; topMargin: 12; left: parent.left; right: parent.right }
        spacing: 6
        visible: root.vaults.length > 1

        Repeater {
            model: root.vaults
            delegate: Rectangle {
                id: chip
                required property var modelData
                readonly property bool current: modelData.path === root.vaultPath
                height: 28
                width: chipText.implicitWidth + 20
                radius: 14
                color: current ? Colors.accent : root.cardColor

                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: root._basename(chip.modelData.path)
                    color: chip.current ? Colors.accentText : root.textColor
                    font.pixelSize: 12
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.vaultPath = chip.modelData.path
                }
            }
        }
    }

    // Buscador
    Rectangle {
        id: searchBox
        anchors { top: vaultRow.visible ? vaultRow.bottom : title.bottom; topMargin: 12
                  left: parent.left; right: parent.right }
        height: 42
        radius: 10
        color: root.cardColor
        border.width: searchInput.activeFocus ? 2 : 1
        border.color: searchInput.activeFocus ? Colors.accent : Qt.rgba(1, 1, 1, 0.12)

        Text {
            id: searchIcon
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            text: "󰍉"
            font.pixelSize: 16
            color: root.textColor
            opacity: 0.6
        }
        Text {
            text: "Buscar nota…"
            visible: searchInput.text.length === 0
            anchors { left: searchIcon.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
            color: root.textColor
            opacity: 0.4
        }
        TextInput {
            id: searchInput
            anchors { left: searchIcon.right; leftMargin: 8; right: parent.right; rightMargin: 12
                      verticalCenter: parent.verticalCenter }
            color: root.textColor
            font.pixelSize: 14
            clip: true
            selectByMouse: true
            onTextChanged: root.search = text
            Keys.onEscapePressed: (event) => {
                if (text.length > 0) { text = ""; event.accepted = true }
                else event.accepted = false   // deja que el sidebar cierre
            }
        }
        Component.onCompleted: Qt.callLater(() => searchInput.forceActiveFocus())
    }

    Text {
        id: countLabel
        anchors { top: searchBox.bottom; topMargin: 10; left: parent.left }
        text: root.filtered.length + " nota" + (root.filtered.length === 1 ? "" : "s")
        color: root.textColor
        opacity: 0.5
        font.pixelSize: 11
    }

    // Lista de notas
    ListView {
        id: notesList
        anchors { top: countLabel.bottom; topMargin: 6; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        model: root.filtered
        boundsBehavior: Flickable.StopAtBounds
        spacing: 2

        delegate: Rectangle {
            id: noteItem
            required property int index
            required property string modelData
            width: notesList.width
            height: 46
            radius: 8
            color: hover.containsMouse ? Qt.alpha(Colors.accent, 0.18) : "transparent"

            Column {
                anchors { left: parent.left; leftMargin: 12; right: openHint.left; rightMargin: 8
                          verticalCenter: parent.verticalCenter }
                spacing: 2
                Text {
                    width: parent.width
                    text: root._basename(noteItem.modelData).replace(/\.md$/, "")
                    color: root.textColor
                    font.pixelSize: 14
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: root._relDir(noteItem.modelData)
                    visible: text.length > 0
                    color: root.textColor
                    opacity: 0.45
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                }
            }
            Text {
                id: openHint
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                text: "󰏋"
                font.pixelSize: 15
                color: root.textColor
                opacity: hover.containsMouse ? 0.8 : 0.0
            }
            MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(
                    ["xdg-open", "obsidian://open?path=" + encodeURIComponent(noteItem.modelData)])
            }
        }
    }
}
