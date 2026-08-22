import QtQuick
import Quickshell.Services.Pipewire
import Quickshell.Widgets
import qs.Widgets.General
import qs.Commons
WrapperMouseArea {
    id: main

    // Altura de la barra pasada explícita desde el Component de LeftSide.qml
    // (antes llegaba por resolución dinámica del id `root`).
    required property real barHeight

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onEntered: main.showVolume = false
    onExited: main.showVolume = true

    onClicked: showPopup = !showPopup
    cursorShape: Qt.PointingHandCursor
    child: audio

    property var sink: Pipewire.defaultAudioSink
    property bool showVolume: true
    property bool showPopup: false
    readonly property real volumeValue: sink ? sink.audio.volume : 0
    readonly property bool muted: sink ? sink.audio.muted : false
    property var icons: ["", " ", "󰕾 ", " "]

    property string icon: {
        if (muted) return "󰝟 "
        let vol = Math.round(volumeValue * 100)
        for (let i = 0; i < icons.length; i++) {
            let low  = (i / icons.length) * 100
            let high = ((i + 1) / icons.length * 100)
            if (vol >= low && vol < high) {
                return icons[i]
            }
        }
        return icons[icons.length - 1]  // Si volumeValue = 100, retorna el último
    }
    PwObjectTracker {
        objects: sink ? [sink] : []
    }

    Text {
        id: audio
        // Declarative binding: the text updates whenever showVolume or sink changes
        text: {
            if (!main.sink) return "Cargando...";
            
            return main.showVolume 
                ? main.icon + "  " + Math.round(main.volumeValue * 100) + "%"
                : main.icon + "  " + Math.round(main.volumeValue * 100) + "% - " + main.sink.description
        }
        color: main.muted
            ? Colors.danger
            : Colors.ensureReadable(Colors.palette[7], Colors.palette[4]) // fondo real: BarPill
    }
    HoverPopup {
        id: hoverPopup
        triggerItem:  main
        popupWidth:   200
        popupHeight:  200
        offsetY: main.barHeight - 2
        offsetX: -popupWidth / 2
        show: showPopup


        popupContent: Rectangle {
            id: rect

            anchors.fill: parent
            color: Qt.alpha(Colors.palette[3], 0.95)
            border.color: Qt.alpha(Colors.palette[8], 0.6)
            border.width: 1
            radius: 12

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 6

                Text {
                    width: parent.width
                    text: main.sink ? main.sink.description : "Sin dispositivo de audio"
                    color: Colors.ensureReadable(Colors.palette[7], Colors.palette[3])
                    font.pixelSize: 12
                    font.bold: true
                    wrapMode: Text.WordWrap
                }

                Text {
                    width: parent.width
                    visible: main.sink !== null
                    text: "Volumen: " + Math.round(main.volumeValue * 100) + "%" + (main.muted ? " (silenciado)" : "")
                    color: Qt.alpha(Colors.ensureReadable(Colors.palette[7], Colors.palette[3]), 0.6)
                    font.pixelSize: 11
                }
            }
        }
    }
}
