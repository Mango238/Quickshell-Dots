import QtQuick
import QtQuick.Controls
import Quickshell.Widgets
import qs.Commons
import qs.Services
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

    /// Animado (gif o video): lo reproduce mpvpaper, no awww.
    readonly property bool animated: WallpaperService.isAnimated(root.path)
    /// Solo el gif se previsualiza animado en hover; el video se muestra por
    /// su póster (meter un decodificador de video por celda no tiene sentido).
    readonly property bool isGif: root.animated && !WallpaperService.isVideo(root.path)
    /// Lo que Qt puede dibujar: la imagen/gif, o el póster extraído del video.
    readonly property string stillPath: WallpaperService.stillFor(root.path)

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
            source: "file://" + root.stillPath
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            // Decodificamos directo a un tamaño chico — el ahorro de memoria
            // es el punto central de este componente, ver comentario arriba.
            sourceSize.width: 280
            sourceSize.height: 180

            transformOrigin: Item.Center
            scale: root.hovered ? 1.06 : 1.0
            Behavior on scale {
                NumberAnimation { duration: Config.anim.instant; easing.type: Config.easingOf(Config.anim.standard) }
            }
        }

        // Preview animado, solo para GIFs y solo mientras hay hover: la
        // source se vacía al salir para que el AnimatedImage libere los
        // frames. cache:false es obligatorio — cachear CADA frame de un gif
        // de 20MB por cada celda es exactamente el problema de memoria que
        // describe el comentario de cabecera.
        AnimatedImage {
            anchors.fill: parent
            visible: root.isGif && root.hovered
            source: visible ? "file://" + root.path : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            sourceSize.width: 280
            sourceSize.height: 180
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
                NumberAnimation { duration: Config.anim.instant; easing.type: Config.easingOf(Config.anim.standard) }
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
                NumberAnimation { duration: Config.anim.instant; easing.type: Config.easingOf(Config.anim.standard) }
            }
            Behavior on border.color {
                ColorAnimation { duration: Config.anim.instant }
            }
        }

        // Badge de animado: para distinguir los gif sin tener que hacer hover
        Rectangle {
            visible: root.animated
            width: gifLabel.implicitWidth + 10
            height: 16
            radius: 8
            color: root.accentColor
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 6

            Text {
                id: gifLabel
                anchors.centerIn: parent
                text: root.isGif ? "GIF" : "VIDEO"
                color: "#1E1E2E"
                font.pixelSize: 9
                font.bold: true
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
