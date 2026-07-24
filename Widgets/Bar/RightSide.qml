import QtQuick
import qs.Commons
Rectangle {
    id: miRect

    // Altura de la barra pasada explícita desde Modules/Bar.qml (antes
    // llegaba por resolución dinámica del id `root`, ver LeftSide.qml).
    required property real barHeight

    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.rightMargin: 20
    
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Qt.alpha(Colors.palette[5], 0.4) }
        GradientStop { position: 1.0; color: Qt.alpha(Colors.palette[3], 0.4) }
    }

    height: miRect.barHeight
    width: row.width + 20

    Component { id: componenteAdios; Spotify {} }
    Component { id: powerOff; PowerOff {} }
    Component { id: spoti; Spoti { } }
    Component { id: barClock; BarClock {} }
    Component { id: notifBell; NotificationBell {} }
    Row {
        id: row

        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10

        EqActivate {
            height: 20
            anchors.verticalCenter: parent.verticalCenter
        }
        Repeater {
            id: miRepeater
            model: [spoti ,componenteAdios, barClock, notifBell, powerOff]
            
            delegate: BarPill {}
        }
    }
}
