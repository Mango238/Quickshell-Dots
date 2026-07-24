import Quickshell
import QtQuick
import qs.Commons
Scope {
    id: root

    PanelWindow {
        id: panel
        aboveWindows: false
        exclusiveZone: -2
        color: "transparent"
        implicitHeight: 295
        implicitWidth: 1200

        anchors.left: true
        anchors.top: true
        margins {
            top: 245
            left: 376
        }
        
        // SystemClock con precisión de minutos: despierta una vez por minuto
        // (antes: Timer de 1 s + repintado del texto de segundos).
        SystemClock {
            id: clock
            precision: SystemClock.Minutes
        }

        Column {
            anchors.centerIn: parent // Centrado en la pantalla
            spacing: 5 // Espacio entre elementos

            // 1. EL DÍA (Texto Grande)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                
                // Convierte la fecha al nombre del día (ej. MONDAY)
                text: Qt.formatDateTime(clock.date, "dddd").toUpperCase()
                antialiasing: true        
                color: Colors.palette[7]
                
                // AQUI es donde cambias la fuente. 
                // Asegúrate de tener la fuente instalada en tu sistema.
                font.family: "Anurati"
                font.pixelSize: 120 
                font.bold: true
                font.letterSpacing: 10 // Espaciado amplio entre letras como en la foto
                
                // Nota: Para efectos avanzados necesitas importar Qt5Compat.GraphicalEffects
            }

            // 2. LA FECHA (29 MAY 2023)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: 10

                // Formato: Dia Mes Año
                text: Qt.formatDateTime(clock.date, "d MMMM yyyy").toUpperCase()
                antialiasing: true
                color: Colors.palette[7]
                font.family: "Sans Serif" // Una fuente limpia estándar
                font.pixelSize: 24
                font.bold: true
                font.letterSpacing: 2
            }

            // 3. LA HORA (-12:59-)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                
                // Agregamos los guiones manualmente (sin segundos, decisión
                // del usuario: evita el repintado por segundo)
                text: "-" + Qt.formatDateTime(clock.date, "hh:mm") + "-"
                antialiasing: true
                color: Colors.palette[7]
                font.family: "Sans Serif"
                font.pixelSize: 24
                font.bold: true
            }
        }
    }

}
