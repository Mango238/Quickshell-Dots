pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Services
import qs.Widgets.Bar
import qs.Widgets.General
import qs.Commons
/**
 * WallpaperGrid.qml — Selector de wallpapers en grilla.
 *
 * Todo el estado real vive en WallpaperService (singleton); este componente
 * es solo la vista. Pensado para caer como `content` de un PanelPopup:
 *
 *   PanelPopup {
 *       alignItem: wallpaperIcon
 *       show: BarPopupState.isOpen("wallpaper")
 *       panelColor: Colors.palette[4]
 *       panelHeight: 380
 *
 *       WallpaperGrid {
 *           anchors.fill: parent
 *           anchors.margins: 12
 *       }
 *   }
 */
Item {
    id: root

    // Defaults ligados a la paleta derivada del wallpaper (Colors.palette):
    // [3] fondo secundario (distinto del panelColor [4] del popup contenedor,
    // para que las cards se distingan del fondo), [7] texto/borde principal,
    // [8] borde fino/acento interactivo (selección, hover). dangerColor no
    // tiene slot de paleta garantizado (la paleta depende del wallpaper) y
    // queda fijo como color semántico de error.
    property color textColor: Colors.palette[7]
    property color subTextColor: Qt.alpha(Colors.palette[7], 0.6)
    property color accentColor: Colors.palette[8]
    property color dangerColor: "#F38BA8"
    property color cardColor: Colors.palette[3]
    property real cardRadius: 10

    /// Tamaño de cada celda (ancho x alto) en la grilla.
    property real cellWidth: 140
    property real cellHeight: 90
    property real cellSpacing: 10

    // Al abrirse el popup: cursor de teclado sobre el wallpaper actual y foco
    // al grid. El foco real de teclado a nivel Wayland lo da el
    // HyprlandFocusGrab del PanelPopup contenedor (grabKeyboardFocus: true en
    // Bar.qml); el forceActiveFocus diferido es el mismo patrón documentado en
    // DirectorySearchBar (la ventana necesita unos frames tras mostrarse).
    readonly property bool popupOpen: PopupState.isOpen("wallpaper")

    function _initCursor() {
        var idx = WallpaperService.visibleWallpapers.indexOf(WallpaperService.currentWallpaper)
        grid.currentIndex = idx >= 0 ? idx : 0
        grid.positionViewAtIndex(grid.currentIndex, GridView.Contain)
        Qt.callLater(() => grid.forceActiveFocus())
    }

    onPopupOpenChanged: if (popupOpen) _initCursor()
    // Con el contenido del popup en un Loader perezoso (Bar.qml), este
    // componente nace con popupOpen ya en true y onPopupOpenChanged no
    // dispara: inicializar también al crearse.
    Component.onCompleted: if (popupOpen) _initCursor()

    Column {
        anchors.fill: parent
        spacing: 10

        // ── Header ───────────────────────────────────────────────────────
        RowLayout {
            id: header
            width: parent.width
            spacing: 8

            Text {
                id: title
                text: "Wallpapers"
                color: root.textColor
                font.pixelSize: 15
                font.bold: true
            }
            
            DirectorySearchBar {
                id: dirSearch
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                startDir: Quickshell.env("HOME")
                accentColor: root.accentColor
                cardColor: root.cardColor
                // Legibilidad garantizada: conserva el color de texto si ya
                // contrasta con el fondo; si no, elige desde Colors.palette.
                textColor: Colors.ensureReadable(root.textColor, root.cardColor)
                onAccepted: (path) => {
                    WallpaperService.wallpaperDir = path
                    WallpaperService.scan()
                    grid.forceActiveFocus()
                }
                onCancelled: grid.forceActiveFocus()
                z: 3
            }

            Text {
                id: scan
                visible: WallpaperService.scanning
                text: "Buscando…"
                color: root.subTextColor
                font.pixelSize: 11
            }

            Text {
                id: analyzeLabel
                visible: WallpaperService.analyzing
                text: "Analizando " + WallpaperService.analyzeDone + "/" + WallpaperService.analyzeTotal + "…"
                color: root.subTextColor
                font.pixelSize: 11
            }

            Text {
                id: countLabel
                text: (WallpaperService.colorFilter !== ""
                        ? WallpaperService.visibleWallpapers.length + "/"
                        : "")
                    + WallpaperService.wallpapers.length + " wallpapers"
                color: root.subTextColor
                font.pixelSize: 11
            }

            // Botón de refrescar
            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
                color: refreshArea.pressed ? Qt.darker(root.accentColor, 1.2) : root.cardColor

                Text {
                    anchors.centerIn: parent
                    text: "⟳"
                    color: root.textColor
                    font.pixelSize: 15
                }

                MouseArea {
                    id: refreshArea
                    anchors.fill: parent
                    onClicked: {
                        WallpaperService.invalidateColorCache()
                        WallpaperService.scan()
                        WallpaperService.refreshCurrent()
                    }
                }
            }

            // Botón de wallpaper aleatorio
            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
                color: randomArea.pressed ? Qt.darker(root.accentColor, 1.2) : root.cardColor

                Text {
                    anchors.centerIn: parent
                    text: "🔀"
                    color: root.textColor
                    font.pixelSize: 13
                }

                MouseArea {
                    id: randomArea
                    anchors.fill: parent
                    onClicked: {
                        // Aleatorio dentro del filtro de color activo (o todos)
                        var list = WallpaperService.visibleWallpapers
                        if (list.length === 0) return
                        var pick = list[Math.floor(Math.random() * list.length)]
                        WallpaperService.apply(pick)
                    }
                }
            }

            // Selector compacto de transición de awww (cicla grow/wipe/wave/outer/random)
            Rectangle {
                id: transitionPill
                readonly property var cycle: ["grow", "wipe", "wave", "outer", "random"]

                Layout.preferredWidth: transitionLabel.implicitWidth + 20
                Layout.preferredHeight: 28
                radius: 14
                color: transitionArea.pressed ? Qt.darker(root.accentColor, 1.2) : root.cardColor

                Text {
                    id: transitionLabel
                    anchors.centerIn: parent
                    text: WallpaperService.transitionType
                    color: root.textColor
                    font.pixelSize: 11
                }

                MouseArea {
                    id: transitionArea
                    anchors.fill: parent
                    onClicked: {
                        var idx = transitionPill.cycle.indexOf(WallpaperService.transitionType)
                        var next = transitionPill.cycle[(idx + 1) % transitionPill.cycle.length]
                        WallpaperService.transitionType = next
                    }
                }
            }

            // Selector compacto de orden de la grilla (cicla nombre/tono/luz)
            Rectangle {
                id: sortPill
                readonly property var cycle: ["nombre", "tono", "luz"]

                Layout.preferredWidth: sortLabel.implicitWidth + 20
                Layout.preferredHeight: 28
                radius: 14
                color: sortArea.pressed ? Qt.darker(root.accentColor, 1.2) : root.cardColor

                Text {
                    id: sortLabel
                    anchors.centerIn: parent
                    text: "⇅ " + WallpaperService.sortMode
                    color: root.textColor
                    font.pixelSize: 11
                }

                MouseArea {
                    id: sortArea
                    anchors.fill: parent
                    onClicked: {
                        var idx = sortPill.cycle.indexOf(WallpaperService.sortMode)
                        var next = sortPill.cycle[(idx + 1) % sortPill.cycle.length]
                        WallpaperService.sortMode = next
                    }
                }
            }
        }

        Rectangle {
            id: divider
            width: parent.width
            height: 1
            color: Qt.darker(root.cardColor, 1.3)

            z: -1
        }

        // ── Filtro por color ──────────────────────────────────────────────
        Row {
            id: filterRow
            spacing: 6
            visible: WallpaperService.wallpapers.length > 0

            z: -1

            // Chip "todos" (limpia el filtro)
            Rectangle {
                width: allLabel.implicitWidth + 16
                height: 18
                radius: 9
                color: root.cardColor
                border.width: WallpaperService.colorFilter === "" ? 2 : 0
                border.color: root.accentColor

                Text {
                    id: allLabel
                    anchors.centerIn: parent
                    text: "todos"
                    color: root.textColor
                    font.pixelSize: 10
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: WallpaperService.colorFilter = ""
                }
            }

            // Un círculo por bucket con al menos un wallpaper; click filtra,
            // segundo click en el activo vuelve a "todos".
            Repeater {
                model: WallpaperService.colorBuckets.filter(
                    b => (WallpaperService.bucketCounts[b.id] || 0) > 0)
                delegate: Rectangle {
                    required property var modelData
                    width: 18
                    height: 18
                    radius: 9
                    color: modelData.swatch
                    border.width: WallpaperService.colorFilter === modelData.id ? 2 : 0
                    border.color: root.accentColor

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: WallpaperService.colorFilter =
                            (WallpaperService.colorFilter === modelData.id) ? "" : modelData.id
                    }
                }
            }
        }

        // ── Aviso de error de aplicación ────────────────────────────────────
        Text {
            id: errorBanner
            width: parent.width
            visible: text.length > 0
            wrapMode: Text.WordWrap
            color: root.dangerColor
            font.pixelSize: 11

            Connections {
                target: WallpaperService
                function onApplyFailed(message) {
                    errorBanner.text = message
                    errorHideTimer.restart()
                }
            }

            Timer {
                id: errorHideTimer
                interval: 4000
                onTriggered: errorBanner.text = ""
            }
        }

        // ── Estado vacío ──────────────────────────────────────────────────
        Text {
            visible: !WallpaperService.scanning && WallpaperService.wallpapers.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: "No se encontraron imágenes en " + WallpaperService.wallpaperDir
            color: root.subTextColor
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
        }

        // ── Grilla ────────────────────────────────────────────────────────
        GridView {
            z: -1
            id: grid
            readonly property int columns: Math.max(1, Math.floor(parent.width / (root.cellWidth + root.cellSpacing)))
            width: columns * cellWidth
            anchors.horizontalCenter: parent.horizontalCenter
            // Robusto ante cambios de altura del header (ej. el nuevo contador
            // "N wallpapers"): en vez de un "24" mágico, resta explícitamente
            // la altura de cada hermano visible que precede a la grilla más
            // el spacing del Column entre ellos. Los positioners de QtQuick
            // (Column) no reservan espacio para hijos con visible:false, así
            // que errorBanner solo cuenta cuando está mostrando un mensaje.
            height: parent.height
                - header.height - parent.spacing
                - divider.height - parent.spacing
                - (filterRow.visible ? filterRow.height + parent.spacing : 0)
                - (errorBanner.visible ? errorBanner.height + parent.spacing : 0)
            clip: true

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            cellWidth: root.cellWidth + root.cellSpacing
            cellHeight: root.cellHeight + root.cellSpacing
            // Lista plana de JS (WallpaperService.wallpapers), no un
            // ObjectModel: evitamos el identificador "modelData" a propósito
            // (puede chocar con un modelData real declarado más arriba en el
            // árbol, p. ej. el de un Variants{ model: Quickshell.screens }) y
            // en su lugar indexamos explícitamente por "index".
            model: WallpaperService.visibleWallpapers.length

            // Navegación por teclado: las flechas en las 4 direcciones son
            // nativas de GridView cuando tiene activeFocus (respetan columnas
            // y auto-scrollean); aquí solo Enter/Escape/Tab.
            Keys.onPressed: (event) => {
                switch (event.key) {
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    if (grid.currentIndex >= 0 && grid.currentIndex < WallpaperService.visibleWallpapers.length)
                        WallpaperService.apply(WallpaperService.visibleWallpapers[grid.currentIndex])
                    event.accepted = true
                    break
                case Qt.Key_Escape:
                    PopupState.active = ""
                    event.accepted = true
                    break
                case Qt.Key_Tab:
                    dirSearch.forceFocus()
                    event.accepted = true
                    break
                }
            }

            delegate: WallpaperThumbnail {
                required property int index
                path: WallpaperService.visibleWallpapers[index]
                width: root.cellWidth
                height: root.cellHeight

                cardColor: root.cardColor
                cardRadius: root.cardRadius
                accentColor: root.accentColor
                textColor: root.textColor

                selected: path === WallpaperService.currentWallpaper
                applying: WallpaperService.applying && path === WallpaperService.pendingPath
                // Un solo cursor, sin pelea hover/teclado: el hover mueve el
                // cursor, y el cursor solo se pinta con foco en el grid (el
                // uso puro-ratón no muestra un resaltado fantasma).
                highlighted: GridView.isCurrentItem && grid.activeFocus
                onHoveredChanged: if (hovered) grid.currentIndex = index

                onClicked: WallpaperService.apply(path)
            }
        }
    }
}
