import QtQuick
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import qs.Commons
// Contenedor principal que agrupa ambos bloques

Row {
    id: main

    // Altura de la barra pasada explícita desde Modules/Bar.qml (antes
    // llegaba por resolución dinámica del id `root`, ver LeftSide.qml).
    required property real barHeight

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    spacing: 10 // Espacio que separa el bloque normal del bloque especial

    // ---------------------------------------------------------
    // 1. CONTENEDOR DE ESPACIOS DE TRABAJO NORMALES
    // ---------------------------------------------------------
    Rectangle {
        id: workspaces
        color: Colors.palette[3]
        width: normalRow.width + 20
        height: main.barHeight
        radius: 10

        readonly property int cellWidth: 20
        readonly property int cellHeight: 20

        Behavior on width { NumberAnimation { duration: Config.anim.base; easing.type: Config.easingOf(Config.anim.standard) } }

        property Item focusedItem: null
        // Solo asoma a los lados: en alto la celda ya ocupa todo lo útil.
        readonly property int blobPad: 3
        readonly property real blobX: focusedItem ? normalRow.x + focusedItem.x - blobPad : 0
        readonly property real blobWidth: focusedItem ? focusedItem.width + 2 * blobPad : 0

        // Cada borde viaja por su cuenta: el de delante sale disparado, el de
        // atrás arranca tarde y llega más lento. Ese desfase es la estela.
        readonly property int blobLead: 240
        readonly property int blobTrail: 380
        readonly property int blobLag: 90

        // Los bordes no se bindean: los escribe la animación. Bindeados
        // saltarían al destino antes de que el handler lea de dónde salían.
        function syncBlob() {
            if (blobTravel.running || !focusedItem)
                return
            blob.leftX = blobX
            blob.rightX = blobX + blobWidth
        }

        // Recolocaciones sin cambio de foco (se abre o cierra un workspace y
        // el Row se recentra). Diferido para que, cuando el disparo venga de
        // un cambio de foco, el viaje ya esté en marcha y no lo pise.
        onBlobXChanged: Qt.callLater(syncBlob)
        onBlobWidthChanged: Qt.callLater(syncBlob)

        onFocusedItemChanged: {
            if (!focusedItem)
                return
            blobTravel.stop()
            // Primer foco tras cargar: no hay origen del que salir, se coloca
            // y ya. Sin esto el blob nace en x=0 y viaja desde el borde.
            if (blob.width <= 0) {
                syncBlob()
                return
            }
            // Destino leído del delegate, NO de blobX/blobWidth: esos son
            // bindings y todavía tienen el valor de la celda anterior cuando
            // corre este handler (medido: celda en x=110 y blobX aún en 7).
            const toLeft = normalRow.x + focusedItem.x - blobPad
            const toRight = toLeft + focusedItem.width + 2 * blobPad
            const right = toLeft > blob.leftX

            blob.goingRight = right
            leftEdge.to = toLeft
            rightEdge.to = toRight
            leftLag.duration = right ? blobLag : 0
            rightLag.duration = right ? 0 : blobLag
            leftEdge.duration = right ? blobTrail : blobLead
            rightEdge.duration = right ? blobLead : blobTrail
            leftEdge.easing.type = right ? Easing.OutQuint : Easing.OutExpo
            rightEdge.easing.type = right ? Easing.OutExpo : Easing.OutQuint
            blobTravel.start()
        }

        ParallelAnimation {
            id: blobTravel

            SequentialAnimation {
                PauseAnimation { id: leftLag }
                NumberAnimation { id: leftEdge; target: blob; property: "leftX" }
            }
            SequentialAnimation {
                PauseAnimation { id: rightLag }
                NumberAnimation { id: rightEdge; target: blob; property: "rightX" }
            }
            // La celda destino sigue creciendo cuando el blob ya se posó, así
            // que al final se cuadra con la geometría definitiva.
            onFinished: workspaces.syncBlob()
        }

        Rectangle {
            id: blob
            // Bordes izquierdo y derecho como properties propias: x/width se
            // derivan de ellos, y así la animación mueve un borde sin que el
            // otro la siga.
            property real leftX: 0
            property real rightX: 0
            property bool goingRight: true
            // 0 posado, 1 estirado al doble o más: gradúa el desvanecido de la
            // cola, que solo se nota mientras viaja.
            readonly property real stretch: workspaces.blobWidth > 0
                ? Math.min(1, Math.max(0, width / workspaces.blobWidth - 1))
                : 0
            readonly property color headColor: Qt.alpha(Colors.palette[7], 0.92)
            readonly property color tailColor: Qt.alpha(Colors.palette[7], 0.92 - 0.8 * stretch)

            visible: workspaces.focusedItem !== null
            anchors.verticalCenter: parent.verticalCenter
            x: Math.min(leftX, rightX) + 3
            width: workspaces.cellWidth + 10
            height: workspaces.cellHeight
            radius: height / 2

            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: blob.goingRight ? blob.tailColor : blob.headColor }
                GradientStop { position: 1.0; color: blob.goingRight ? blob.headColor : blob.tailColor }
            }
        }

        Row {
            id: normalRow
            anchors.centerIn: parent
            spacing: 5

            Repeater {
                model: Hyprland.workspaces
                delegate: Rectangle {
                    id: cell
                    // Oculta el Special Workspace (ID -98) de este contenedor
                    visible: modelData.id !== -98

                    width: modelData.focused ? workspaces.cellWidth + 10 : workspaces.cellWidth
                    height: workspaces.cellHeight
                    color: Colors.palette[2]
                    radius: 5

                    // Le pasa al blob la celda de la que copiar la geometría.
                    // Sin restaurar al perder el foco: al enfocar el Special
                    // Workspace ninguna celda queda marcada, y el blob se
                    // queda quieto en la última en vez de irse a la nada.
                    Binding {
                        target: workspaces
                        property: "focusedItem"
                        value: cell
                        when: modelData.focused && cell.visible
                        restoreMode: Binding.RestoreNone
                    }

                    LinearGradient {
                        anchors.fill: parent
                        source: parent
                        visible: modelData.focused
                        start: Qt.point(0, 0)          // Esquina superior izquierda
                        end: Qt.point(width, height)    // Esquina inferior derecha

                        gradient: Gradient {
                            GradientStop {
                                position: 0.0
                                // Si está enfocado: color. Si no: gris.
                                color: modelData.focused ? Colors.palette[6] : Colors.palette[2]
                                Behavior on color { ColorAnimation { duration: 500 } }
                            }

                            GradientStop {
                                position: 0.5
                                // Si está enfocado: color. Si no: gris.
                                color: modelData.focused ? Colors.palette[5] : Colors.palette[2]
                                Behavior on color { ColorAnimation { duration: 500 } }
                            }

                            GradientStop {
                                position: 1.0
                                // Si está enfocado: color. Si no: gris.
                                color: modelData.focused ? Colors.palette[4] : Colors.palette[2]
                                Behavior on color { ColorAnimation { duration: 500 } }
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 5
                        color: "transparent"
                        border.color: modelData.focused ? Colors.palette[7] : Colors.palette[2]
                        border.width: modelData.focused ? 1 : 0

                        Behavior on border.color {
                            ColorAnimation { duration: 500 }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: modelData.id
                        // Fondo real: gradiente [6]→[5]→[4] si está enfocado
                        // (se contrasta contra el punto medio [5]), [2] si no.
                        color: Colors.ensureReadable(Colors.palette[7],
                            modelData.focused ? Colors.palette[5] : Colors.palette[2])
                    }

                    Behavior on color {
                        ColorAnimation { duration: Config.anim.base }
                    }

                    Behavior on width {
                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutQuint
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            // Config Lua: `dispatch` evalúa el argumento como
                            // expresión Lua, la sintaxis vieja ("workspace N") ya no existe.
                            Hyprland.dispatch(`hl.dsp.focus({workspace = ${modelData.id}})`)
                        }
                    }
                }
            }
        }
    }

    ArchWallpaperButton {
        anchors.verticalCenter: parent.verticalCenter
        height: 25
    }

    // ---------------------------------------------------------
    // 3. CONTENEDOR DEL SPECIAL WORKSPACE
    // ---------------------------------------------------------
    Rectangle {
        // Solo se muestra el contenedor si existe el Special Workspace
        id: specialRect
        visible: specialRow.width > 0

        color: Colors.palette[3]
        // Padding horizontal de 20px (10px por lado) sobre el contenido interno
        width: specialRow.width + 20
        // Unificado con la altura de la barra, ver comentario en el contenedor normal de arriba.
        height: main.barHeight
        radius: 10

        Behavior on width { NumberAnimation { duration: Config.anim.base; easing.type: Config.easingOf(Config.anim.standard) } }
        Behavior on height { NumberAnimation { duration: 400; easing.type: Config.easingOf(Config.anim.standard) } }

        Row {
            id: specialRow
            anchors.centerIn: parent
            spacing: 5

            Repeater {
                model: Hyprland.workspaces

                delegate: Rectangle {
                    id: specialDelegate
                    // Muestra ÚNICAMENTE el Special Workspace en este contenedor
                    visible: modelData.id === -98

                    // El ancho se calcula sobre el Row interno + padding horizontal (10px por lado)
                    width: modelData.focused ? innerRow.width + 20 : innerRow.width + 10
                    height: 22
                    color: Colors.palette[2]
                    radius: 5
                    clip: true

                    Row {
                        id: innerRow
                        // Centrado completo dentro del rectángulo padre
                        anchors.centerIn: parent
                        spacing: 5

                        IconImage {
                            // Tamaño ligeramente menor para respetar el padding vertical
                            implicitSize: 16
                            visible: ToplevelManager.activeToplevel
                            width: 16
                            height: 16
                            smooth: true
                            asynchronous: true
                            source: ToplevelManager.activeToplevel
                                    ? ThemeIcons.iconForAppId(ToplevelManager.activeToplevel.appId)
                                    : ""
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            id: specialText
                            anchors.verticalCenter: parent.verticalCenter
                            text: (ToplevelManager.activeToplevel ? ToplevelManager.activeToplevel.title : "󰊠")
                            color: Colors.ensureReadable(Colors.palette[7], Colors.palette[2])
                        }
                    }

                    Behavior on color { ColorAnimation { duration: Config.anim.base } }
                    Behavior on width { NumberAnimation { duration: 400; easing.type: Config.easingOf(Config.anim.standard) } }
                    Behavior on height { NumberAnimation { duration: Config.anim.base; easing.type: Config.easingOf(Config.anim.standard) } }
                }
            }
        }
    }
}
