import QtQuick
import QtQuick.Controls
import Quickshell.Widgets
import qs.Commons
/**
 * WallpaperThumbnail.qml — Una miniatura dentro de WallpaperGrid.
 *
 * Carga la imagen a tamaño reducido (sourceSize) a propósito: una carpeta
 * de wallpapers suele tener imágenes en 4K/8K, y sin sourceSize Qt decodifica
 * el archivo completo en memoria por cada miniatura — con 30-40 wallpapers
 * eso es varios GB de RAM para mostrar cuadraditos de 140x90.
 */
Item {
    id: root

    required property string path

    property bool selected: false
    property bool applying: false
    property bool hovered: false
    /// Cursor de navegación por teclado (distinto de selected, que marca el
    /// wallpaper aplicado): borde fino en textColor en vez de accent.
    property bool highlighted: false

    property color cardColor: Colors.palette[3]
    property real cardRadius: 10
    property color accentColor: Colors.palette[8]
    property color textColor: Colors.palette[7]

    // Se oculta si la imagen falla en cargar (archivo corrupto, formato no soportado, etc.)
    visible: img.status !== Image.Error

    signal clicked()

    ClippingRectangle {
        id: frame
        anchors.fill: parent
        radius: root.cardRadius
        color: root.cardColor
        clip: true
        // El clipping real lo hace `frame` (ClippingRectangle exterior, radius
        // cardRadius) — este Image va directo como hijo, sin envoltorio propio
        // que clipeara con un radio distinto (era un Rectangle radius:40 muerto).
        Image {
            id: img
            anchors.fill: parent
            source: "file://" + root.path
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            // Decodificamos directo a un tamaño chico — el ahorro de memoria
            // es el punto central de este componente, ver comentario arriba.
            sourceSize.width: 280
            sourceSize.height: 180

            transformOrigin: Item.Center
            scale: root.hovered ? 1.06 : 1.0
            Behavior on scale {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
        }

        // Placeholder mientras carga / si falla
        Rectangle {
            anchors.fill: parent
            visible: img.status !== Image.Ready
            color: Qt.darker(root.cardColor, 1.15)

            Text {
                anchors.centerIn: parent
                visible: img.status === Image.Error
                text: "⚠"
                color: root.textColor
                font.pixelSize: 20
            }
        }

        // Overlay de "aplicando…"
        Rectangle {
            anchors.fill: parent
            visible: root.applying
            color: "#000000"
            opacity: 0.5

            BusyIndicator {
                anchors.centerIn: parent
                running: root.applying
                implicitWidth: 22
                implicitHeight: 22
            }
        }

        // Scrim inferior con el nombre de archivo, visible solo en hover
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * 0.4
            opacity: root.hovered ? 1.0 : 0.0
            Behavior on opacity {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }

            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.75) }
            }

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 6
                text: root.path.split("/").pop()
                color: "#FFFFFF"
                font.pixelSize: 10
                elide: Text.ElideMiddle
            }
        }

        // Borde de selección
        Rectangle {
            anchors.fill: parent
            radius: root.cardRadius
            color: "transparent"
            border.width: root.selected ? 3 : (root.highlighted ? 2 : 0)
            border.color: root.selected ? root.accentColor : root.textColor

            Behavior on border.width {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
            Behavior on border.color {
                ColorAnimation { duration: 120 }
            }
        }

        // Check de "aplicado ahora"
        Rectangle {
            visible: root.selected && !root.applying
            width: 20
            height: 20
            radius: 10
            color: root.accentColor
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 6

            Text {
                anchors.centerIn: parent
                text: "✓"
                color: "#1E1E2E"
                font.pixelSize: 12
                font.bold: true
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: !root.applying
            hoverEnabled: true
            onClicked: root.clicked()
            onEntered: root.hovered = true
            onExited: root.hovered = false
            cursorShape: Qt.PointingHandCursor
        }
    }
}
