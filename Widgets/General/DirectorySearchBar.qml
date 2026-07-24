pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * DirectorySearchBar.qml — Barra de búsqueda de directorios, anclable.
 *
 * Responsabilidades:
 *   - Mostrar un campo de texto con placeholder e ícono, estilo "pill",
 *     consistente con el resto de la UI (cardColor/cardRadius/accentColor).
 *   - A medida que el usuario escribe, listar (con debounce) los
 *     subdirectorios del path tipeado hasta el momento.
 *   - Tab completa al prefijo común de las coincidencias (o al único match
 *     si hay uno solo), permitiendo encadenar tabs para ir bajando de
 *     carpeta en carpeta, como en una shell.
 *   - Flechas arriba/abajo navegan la lista de sugerencias, Enter aplica
 *     la resaltada (o emite `accepted` con el path actual si no hay
 *     ninguna resaltada), Escape cierra la lista.
 *
 * Notas de implementación:
 *   - No usamos QtQuick.Controls ni QtQuick.Layouts, para ir en línea con
 *     el resto del shell (QtQuick puro + anchors manuales). La lista de
 *     sugerencias sí usa ListView (parte de QtQuick base, no un módulo
 *     extra) para tener scroll y highlight animado "gratis".
 *   - El listado de directorios corre `ls` pasando el path como argumento
 *     de argv (Process.command es un array), NUNCA interpolado en un
 *     string de shell — así un path con espacios, comillas o "$(...)"
 *     no puede romper ni inyectar nada.
 *   - Directorios ocultos (dotdirs): NO se listan. `ls -1 -p` (sin `-A`)
 *     ya excluye por defecto todo lo que empiece con ".". Además hay un
 *     filtro defensivo en JS (`!l.startsWith(".")`) por si el `ls` del
 *     sistema difiere en comportamiento.
 *   - Limitación conocida: `ls -p` marca como directorio a los directorios
 *     reales, pero NO a symlinks que apunten a un directorio (habría que
 *     agregar -L para eso, a costa de resolver todos los symlinks en cada
 *     escaneo). Si tenés carpetas simlinkeadas que querés que aparezcan,
 *     avisame y lo ajustamos.
 *   - La lista de sugerencias se ancla debajo (`anchors.top: bottom`) como
 *     hijo del propio componente, no como Popup/Window — si algo la tapa
 *     visualmente (ej. un GridView pegado justo debajo), subile el `z` a
 *     ese elemento o reparentá la lista a la ventana.
 *   - Tab completa el prefijo común; si ya estás en el máximo prefijo
 *     posible y quedan varias coincidencias, Tab (y Shift+Tab en reversa)
 *     cicla el resaltado entre ellas, como el tab-completion de una shell.
 *     Pasar el mouse por encima de una sugerencia también actualiza el
 *     resaltado, así teclado y mouse comparten el mismo estado visual.
 *
 * Uso típico:
 *   DirectorySearchBar {
 *       anchors.top: parent.top
 *       anchors.left: parent.left
 *       anchors.right: parent.right
 *       startDir: Quickshell.env("HOME")
 *       accentColor: root.accentColor
 *       cardColor: root.cardColor
 *       textColor: root.textColor
 *       onAccepted: (path) => WallpaperService.wallpaperDir = path
 *   }
 */
Rectangle {
    id: root

    // ─── Configuración expuesta ─────────────────────────────────────────────

    property string placeholderText: "Buscar directorio..."
    property string startDir: Quickshell.env("HOME")
    property bool directoriesOnly: true

    property color cardColor: "#2a2a2a"
    property color accentColor: "#89b4fa"
    property color textColor: "#ffffff"
    property real cardRadius: 8

    /// Contenido actual del campo. Se puede leer/setear desde afuera.
    property alias text: textInput.text

    /// Sugerencias vigentes (nombres de directorio, con "/" al final).
    property var suggestions: []
    property int highlightedIndex: -1

    /// Se emite con el path ya expandido (~ resuelto) al presionar Enter
    /// sin ninguna sugerencia resaltada.
    signal accepted(string path)
    /// Se emite con Escape cuando no hay lista de sugerencias abierta.
    signal cancelled()

    /// Llamar desde afuera (ej. onVisibleChanged del PanelWindow que aloja
    /// este componente) para tomar el foco del TextInput apenas la ventana
    /// obtenga foco de teclado del compositor. Necesario porque el foco de
    /// teclado a nivel Wayland (WlrLayershell.keyboardFocus / focusable en
    /// el PanelWindow) es un problema aparte de este componente: sin eso,
    /// ningún evento de teclado llega acá sin importar qué tan bien esté
    /// armado el Keys.onPressed.
    function forceFocus() {
        textInput.forceActiveFocus()
    }

    // ─── Apariencia ──────────────────────────────────────────────────────────

    color: root.cardColor
    radius: root.cardRadius
    height: 44
    border.width: textInput.activeFocus ? 2 : 1
    border.color: textInput.activeFocus ? root.accentColor : Qt.rgba(1, 1, 1, 0.12)

    Behavior on border.color { ColorAnimation { duration: 120 } }

    Text {
        id: icon
        text: "🔍"
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        font.pixelSize: 15
        color: root.textColor
        opacity: 0.6
    }

    Text {
        text: root.placeholderText
        visible: textInput.text.length === 0
        anchors.left: icon.right
        anchors.leftMargin: 8
        anchors.right: clearBtn.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        color: root.textColor
        opacity: 0.4
        elide: Text.ElideRight
    }

    TextInput {
        id: textInput
        // Marca a este item como "el que quiere el foco" dentro del
        // FocusScope más cercano (contentSlot en PanelPopup.qml). Cuando
        // ese FocusScope recibe forceActiveFocus() al abrirse el popup,
        // el foco se reenvía acá automáticamente.
        focus: false
        anchors.left: icon.right
        anchors.leftMargin: 8
        anchors.right: clearBtn.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        color: root.textColor
        font.pixelSize: 14
        clip: true
        selectByMouse: true

        onTextChanged: scanDebounce.restart()

        Keys.onPressed: (event) => {
            switch (event.key) {
            case Qt.Key_Tab:
            case Qt.Key_Backtab:
                event.accepted = true
                var reverse = event.key === Qt.Key_Backtab
                    || (event.modifiers & Qt.ShiftModifier)
                root._handleTab(reverse)
                break
            case Qt.Key_Down:
                event.accepted = true
                root.highlightedIndex = Math.min(root.highlightedIndex + 1, root.suggestions.length - 1)
                break
            case Qt.Key_Up:
                event.accepted = true
                root.highlightedIndex = Math.max(root.highlightedIndex - 1, -1)
                break
            case Qt.Key_Return:
            case Qt.Key_Enter:
                event.accepted = true
                root._handleEnter()
                break
            case Qt.Key_Escape:
                event.accepted = true
                root._handleEscape()
                break
            }
        }
    }

    Text {
        id: clearBtn
        text: "✕"
        visible: textInput.text.length > 0
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        color: root.textColor
        opacity: clearArea.containsMouse ? 0.9 : 0.5

    }
    MouseArea {
        id: clearArea
        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            textInput.text = ""
            root.suggestions = []
            root.highlightedIndex = -1
            textInput.forceActiveFocus()
        }
    }


    // ─── Lista de sugerencias ────────────────────────────────────────────────

    Rectangle {
        id: suggestionBox
        anchors.top: root.bottom
        anchors.topMargin: 4
        anchors.left: root.left
        anchors.right: root.right
        color: root.cardColor
        radius: root.cardRadius
        clip: true
        z: 100

        // Alto objetivo: 0 cuando no hay nada que mostrar, si no el
        // tamaño de hasta 6 filas. El Behavior de abajo lo anima, dando
        // la sensación de que la lista "se abre" en vez de aparecer de golpe.
        height: (root.suggestions.length > 0 && textInput.activeFocus)
            ? Math.min(root.suggestions.length, 6) * 32
            : 0
        Behavior on height {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        // Opacity aparte del height: así el contenido hace fade mientras
        // el alto se acomoda, en vez de un corte seco al llegar a 0.
        opacity: (root.suggestions.length > 0 && textInput.activeFocus) ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
        visible: opacity > 0

        ListView {
            id: suggestionList
            anchors.fill: parent
            model: root.suggestions
            currentIndex: root.highlightedIndex
            clip: true
            interactive: true
            boundsBehavior: Flickable.StopAtBounds

            // Hace que el resaltado se DESLICE de una fila a otra en vez
            // de saltar, tanto con teclado (arriba/abajo, tab-cycle) como
            // con el mouse (hover actualiza highlightedIndex más abajo).
            highlightMoveDuration: 120
            highlightResizeDuration: 120
            highlight: Rectangle {
                radius: 4
                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
            }

            delegate: Item {
                id: suggestionDelegate
                required property int index
                required property string modelData
                width: suggestionList.width
                height: 32

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: suggestionDelegate.modelData
                    color: root.textColor
                    elide: Text.ElideRight
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Pasar el mouse por encima sincroniza el resaltado
                    // visual con la navegación de teclado.
                    onEntered: root.highlightedIndex = suggestionDelegate.index
                    onClicked: root._applySuggestion(suggestionDelegate.index)
                }
            }
        }
    }

    // ─── Lógica de paths ─────────────────────────────────────────────────────

    function _expandHome(p) {
        if (p === "~") return root.startDir
        if (p.indexOf("~/") === 0) return root.startDir + p.slice(1)
        return p
    }

    // Separa el texto tipeado en { dir, partial }: "dir" es la carpeta a
    // listar (siempre termina en "/"), "partial" es lo que falta escribir
    // del nombre dentro de esa carpeta.
    function _splitPath(raw) {
        var expanded = root._expandHome(raw)
        if (expanded.length === 0) {
            return { dir: root.startDir + "/", partial: "" }
        }
        var idx = expanded.lastIndexOf("/")
        if (idx === -1) {
            return { dir: root.startDir + "/", partial: expanded }
        }
        var dir = expanded.slice(0, idx + 1)
        var partial = expanded.slice(idx + 1)
        return { dir: dir, partial: partial }
    }

    function _commonPrefix(arr) {
        if (arr.length === 0) return ""
        var prefix = arr[0]
        for (var i = 1; i < arr.length; i++) {
            var s = arr[i]
            var j = 0
            while (j < prefix.length && j < s.length
                   && prefix[j].toLowerCase() === s[j].toLowerCase()) {
                j++
            }
            prefix = prefix.slice(0, j)
            if (prefix.length === 0) break
        }
        return prefix
    }

    // ─── Escaneo (con debounce) ──────────────────────────────────────────────

    property string _pendingPartial: ""

    readonly property Timer scanDebounce: Timer {
        interval: 150
        onTriggered: root._runScan()
    }

    function _runScan() {
        var parts = root._splitPath(textInput.text)
        root._pendingPartial = parts.partial
        // Sin "-A": así `ls` excluye por defecto todo lo que empiece
        // con "." (directorios/archivos ocultos), que es lo que queremos.
        scanProc.command = ["ls", "-1", "-p", parts.dir]
        // OJO: Process.running es un no-op si ya vale `true` (Quickshell
        // solo llama start() cuando la propiedad efectivamente CAMBIA), y
        // reasignar "command" mientras el proceso anterior sigue vivo
        // recién se aplica al PRÓXIMO start(), no al actual. Sin este
        // corte explícito, tipear rápido (o encadenar Tabs, que vuelven a
        // llamar _runScan() al toque) podía dejar "suggestions" calculado
        // sobre el listado de una carpeta vieja.
        if (scanProc.running) {
            scanProc.running = false
        }
        scanProc.running = true
    }

    readonly property Process scanProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n")
                    .filter(l => l.trim().length > 0)
                    // Defensivo: aunque ya no pasamos "-A", nos aseguramos
                    // acá también de no admitir ocultos (dotfiles/dotdirs).
                    .filter(l => !l.startsWith("."))
                var candidates = root.directoriesOnly
                    ? lines.filter(l => l.endsWith("/"))
                    : lines
                var partialLower = root._pendingPartial.toLowerCase()
                var matches = candidates.filter(l => l.toLowerCase().startsWith(partialLower))
                matches.sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()))
                root.suggestions = matches
                root.highlightedIndex = -1
            }
        }
        onExited: (exitCode, exitStatus) => {
            // Path inexistente, sin permisos, etc. — simplemente no hay nada
            // para sugerir; no es un error que el usuario necesite ver.
            if (exitCode !== 0) {
                root.suggestions = []
                root.highlightedIndex = -1
            }
        }
    }

    // ─── Acciones de teclado ─────────────────────────────────────────────────

    function _applySuggestion(index) {
        var parts = root._splitPath(textInput.text)
        var completed = parts.dir + root.suggestions[index]
        textInput.text = completed
        textInput.cursorPosition = completed.length
        textInput.forceActiveFocus()
        root.highlightedIndex = -1
        // Re-escaneamos enseguida (sin esperar el debounce) para que, si el
        // usuario vuelve a tocar Tab de una, ya tengamos el contenido de la
        // carpeta recién completada.
        root._runScan()
    }

    function _handleTab(reverse) {
        if (root.suggestions.length === 0) return

        if (root.suggestions.length === 1) {
            root._applySuggestion(0)
            return
        }

        var parts = root._splitPath(textInput.text)
        var common = root._commonPrefix(root.suggestions)
        if (!reverse && common.length > parts.partial.length) {
            var completed = parts.dir + common
            textInput.text = completed
            textInput.cursorPosition = completed.length
            root._runScan()
            return
        }

        // Ya estamos en el prefijo común máximo (o vinimos con Shift+Tab):
        // Tab cicla el resaltado entre las coincidencias, como el
        // tab-completion de una shell. El highlight se desliza gracias al
        // ListView (highlightMoveDuration), no salta de golpe.
        var count = root.suggestions.length
        var step = reverse ? -1 : 1
        root.highlightedIndex = ((root.highlightedIndex + step) % count + count) % count
    }

    function _handleEnter() {
        if (root.highlightedIndex >= 0 && root.highlightedIndex < root.suggestions.length) {
            root._applySuggestion(root.highlightedIndex)
            return
        }
        root.accepted(root._expandHome(textInput.text))
    }

    function _handleEscape() {
        if (root.suggestions.length > 0) {
            root.suggestions = []
            root.highlightedIndex = -1
        } else {
            root.cancelled()
        }
    }

    // BUG ORIGINAL: esto solo dispara cuando `root.visible` efectivamente
    // CAMBIA de false a true. Si este componente se instancia ya visible
    // (el caso típico: un Loader/popup lo crea con `visible` en su valor
    // por defecto, true, y nunca lo pasa por false antes), onVisibleChanged
    // JAMÁS se dispara, forceFocus() nunca se llama, y ningún evento de
    // teclado (ni una letra, ni Tab, ni Escape) llega nunca al TextInput.
    // Esto explica los tres síntomas reportados a la vez, porque los tres
    // dependen de tener foco de teclado real.

    // Pide el foco de forma diferida (no sincrónica) y queda listo para
    // reintentarse. En Wayland, WlrLayershell.keyboardFocus suele llegar
    // recién uno o más frames después de que la ventana/popup se muestra;
    // si pedimos forceActiveFocus() en el mismo tick en que el componente
    // se crea, es común que el compositor todavía no le haya entregado el
    // foco de teclado a la ventana, y el pedido no sirva de nada.
}
