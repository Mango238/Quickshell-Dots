import Quickshell
import QtQuick
import qs.Commons

Rectangle {
    id: leftSide

    // Antes estos valores llegaban por resolución dinámica del id `root` de
    // Modules/Bar.qml a través de la cadena de contextos — funcionaba, pero
    // se rompe con ComponentBehavior: Bound. Ahora se pasan explícitos.
    required property var barWindow
    required property real barHeight

    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: 20

    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Qt.alpha(Colors.palette[3], 0.4) }
        GradientStop { position: 1.0; color: Qt.alpha(Colors.palette[5], 0.4) }
    }

    width: row.width + 20
    height: leftSide.barHeight
    Component { id: componenteHola; Pipewire { barWindow: leftSide.barWindow; barHeight: leftSide.barHeight } }
    Component { id: componenteAdios; Battery { barWindow: leftSide.barWindow; barHeight: leftSide.barHeight } }
    Component { id: componenteEstado; Red {} } 
    Component { id: hello; Cpu {} }
    
    Row {
        id: row

        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10
        Repeater {
            model: [componenteHola, componenteAdios, componenteEstado, hello]
            
            delegate: BarPill {}
        }
        BleActivate {}
    }

}
