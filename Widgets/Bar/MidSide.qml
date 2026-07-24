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
        color: Colors.palette[3]
        width: normalRow.width + 20
        // Antes: 30 fijo, mientras Left/RightSide ya usaban la altura de la
        // barra (≈27.5) para sus propios contenedores — leve desalineación
        // vertical. Se unifica a main.barHeight.
        height: main.barHeight
        radius: 10
        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Row {
            id: normalRow
            anchors.centerIn: parent
            spacing: 5

            Repeater {
                model: Hyprland.workspaces
                delegate: Rectangle {
                    // Oculta el Special Workspace (ID -98) de este contenedor
                    visible: modelData.id !== -98 
                    
                    width: modelData.focused ? 30 : 20
                    height: 20
                    color: Colors.palette[2]
                    radius: 5
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
                        ColorAnimation { duration: 200 }
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
                            Hyprland.dispatch(`workspace ${modelData.id}`)
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

        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

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

                    Behavior on color { ColorAnimation { duration: 200 } }
                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
            }
        }
    }
}
