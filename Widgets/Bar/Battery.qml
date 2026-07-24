import QtQuick
import Quickshell.Widgets
import Quickshell.Services.UPower
import qs.Widgets.General
import qs.Commons
WrapperMouseArea {
    id: main

    // Ventana y altura de la barra pasadas explícitas desde el Component de
    // LeftSide.qml (antes llegaban por resolución dinámica del id `root`).
    required property var barWindow
    required property real barHeight

    property var bat: UPower.displayDevice
    child: text
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: hoverPopup.show = true
    onExited: hoverPopup.show = false;

    // Click cicla el perfil de energía (power-saver → balanced → performance
    // → power-saver), saltando performance si el hardware no lo ofrece.
    // Escritura directa a PowerProfiles.profile — única vía de escritura en
    // todo el archivo, a propósito (ninguna instancia de prueba la dispara).
    onClicked: {
        var order = PowerProfiles.hasPerformanceProfile
            ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
            : [PowerProfile.PowerSaver, PowerProfile.Balanced]
        var idx = order.indexOf(PowerProfiles.profile)
        PowerProfiles.profile = order[(idx + 1) % order.length]
    }

    // Indicador de perfil activo junto al %. Los glifos Nerd Font
    // (power-saver/balanced/performance) no se distinguían con claridad en
    // la captura de prueba de pixel con la fuente instalada — se usa el
    // fallback documentado a letra (A/E/R, iniciales de profileLabel).
    property string profileIcon: {
        switch (PowerProfiles.profile) {
            case PowerProfile.PowerSaver:  return "A"
            case PowerProfile.Performance: return "R"
            default:                       return "E"
        }
    }

    property string profileLabel: {
        switch (PowerProfiles.profile) {
            case PowerProfile.PowerSaver:  return "Ahorro de energía"
            case PowerProfile.Performance: return "Rendimiento"
            default:                       return "Equilibrado"
        }
    }

    property var icons: [" ", " ", " ", " ", " "]

    property string icon: {
        let batP = Math.round(bat.percentage * 100)
        for (let i = 0; i < icons.length; i++) {
            let low  = (i / icons.length) * 100
            let high = ((i + 1) / icons.length * 100)
            if (batP >= low && batP < high) {
                return icons[i]
            }
        }
        return icons[icons.length - 1]
    }


    function formatSeconds(totalSeconds) {
        let hours = Math.floor((totalSeconds % 86400) / 3600);
        let minutes = Math.floor((totalSeconds % 3600) / 60);

        return hours + "h " + minutes + "m";
    }

    readonly property int detailLineCount: 4 + (bat.timeToEmpty ? 1 : 0) + (bat.timeToFull ? 1 : 0)
    readonly property int externalDeviceCount: {
        let n = 0
        const devices = UPower.devices.values ? UPower.devices.values : UPower.devices
        for (const d of devices) {
            if (!d.isLaptopBattery && d.model) n++
        }
        return n
    }

    Text {
        id: text
        text: icon + "  " + Math.round(bat.percentage * 100) + "% " + main.profileIcon
        color: Colors.ensureReadable(Colors.palette[7], Colors.palette[4])
    }

    HoverPopup {
        id: hoverPopup
        triggerItem:  main
        anchorWindow: main.barWindow
        popupWidth:   200
        popupHeight:  30 + main.detailLineCount * 19 + 15 + 19 + Math.max(main.externalDeviceCount, 1) * 19
        offsetY: main.barHeight - 2
        offsetX: 30 - popupWidth / 2


        popupContent: Rectangle {
            id: rect

            anchors.fill: parent
            color: Qt.alpha(Colors.palette[3], 0.95)
            border.color: Qt.alpha(Colors.palette[8], 0.6)
            border.width: 1
            radius: 12

            Column {
                id: detalles
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: 10
                anchors.topMargin: 5
                spacing: 15
                Column {
                    spacing: 2
                    Text {
                        text: "Detalles"
                        color: Colors.ensureReadable(Colors.palette[7], Colors.palette[3])
                        font.bold: true
                    }

                    Text {
                        text: "Bateria: " + Math.round(bat.percentage * 100)
                        color: Colors.ensureReadable(Colors.palette[7], Colors.palette[3]); font.pixelSize: 12
                    }

                    Text {
                        visible: bat.timeToEmpty
                        text: "Tiempo restante: " + formatSeconds(bat.timeToEmpty)
                        color: Colors.ensureReadable(Colors.palette[7], Colors.palette[3]); font.pixelSize: 12
                    }

                    Text {
                        visible: bat.timeToFull
                        text: "Tiempo de carga: " + formatSeconds(bat.timeToFull)
                        color: Colors.ensureReadable(Colors.palette[7], Colors.palette[3]); font.pixelSize: 12
                    }

                    Text {
                        text: "Descarga: " + bat.changeRate.toFixed(2) + " W's"
                        color: Colors.ensureReadable(Colors.palette[7], Colors.palette[3]); font.pixelSize: 12
                    }

                    Text {
                        text: "Perfil: " + main.profileLabel
                        color: Colors.ensureReadable(Colors.palette[7], Colors.palette[3]); font.pixelSize: 12
                    }
                }

                Text {
                    text: "External devices:"
                    color: Qt.alpha(Colors.ensureReadable(Colors.palette[7], Colors.palette[3]), 0.6); font.bold: true
                }

                Repeater {
                    model: UPower.devices

                    delegate: Component {
                        Text {
                            visible: !modelData.isLaptopBattery && modelData.model
                            text: modelData.model + ": " + Math.round(modelData.percentage * 100)
                            color: Colors.ensureReadable(Colors.palette[7], Colors.palette[3]); font.pixelSize: 12

                        }
                    }
                }
            }
        }
    }
}
