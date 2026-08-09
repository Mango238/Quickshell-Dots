pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Chat de DMs de Instagram sobre un solo hilo, el que nombra
// Config.instagram.thread. El trabajo real lo hace Services/instagram.py
// (instagrapi), que corre como daemon y habla JSON por líneas: acá se le
// escribe {"cmd":...} por stdin y se leen sus respuestas por stdout.
//
// El daemon queda vivo mientras haya hilo configurado, aunque el sidebar esté
// cerrado: levantar instagrapi cuesta un par de segundos y pagarlo en cada
// apertura del panel se nota. El polling, en cambio, vive en InstagramView:
// el Loader del sidebar destruye la vista al cerrarse, así que el timer se
// apaga solo y no se gasta una llamada a la API privada con el panel oculto.
//
// ponytail: sin notificaciones ni media. El hilo abierto se recuerda en
// Config.instagram.thread, que escribe openThread().
Singleton {
    id: root

    property alias messages: messagesModel      // { mid, role, text, reply }
    property alias threads: threadsModel        // { tid, title, preview, unread }
    property bool ready: false
    property bool busy: false
    property string threadId: ""
    property string title: "Instagram"
    property string error: ""

    readonly property bool hasThread: root.threadId !== ""

    readonly property string _py: Quickshell.env("HOME") + "/.local/share/quickshell/ig-venv/bin/python"
    readonly property string _script: Quickshell.shellPath("Services/instagram.py")

    ListModel { id: messagesModel }
    ListModel { id: threadsModel }

    Process {
        id: proc

        command: [ root._py, root._script, JSON.stringify({
            session: Config.instagram.sessionPath,
            thread: Config.instagram.thread,
            amount: Config.instagram.amount
        }) ]
        // Antes que `running`, y no es cosmético: si el proceso arranca con
        // stdinEnabled en false, Quickshell cierra el canal y write() queda
        // mudo para siempre aunque después se ponga en true.
        stdinEnabled: true
        // El interruptor. Apagado no se levanta instagrapi en cada arranque
        // del shell; el hilo ya no es el gate porque para elegirlo hace falta
        // que el daemon esté vivo.
        running: Config.instagram.enabled

        stdout: SplitParser { onRead: data => root._handle(data) }
        stderr: SplitParser { onRead: data => console.warn("instagram.py:", data) }

        // Si el proceso ni arrancó (venv ausente, script borrado) no llega
        // ninguna línea por stdout y la vista se quedaría en blanco.
        onExited: (exitCode, exitStatus) => {
            root.ready = false
            root.busy = false
            root.threadId = ""
            if (root.error === "")
                root.error = "instagram.py terminó (código " + exitCode + "). ¿Falta el venv?"
        }
    }

    function _order(obj) {
        if (root.ready)
            proc.write(JSON.stringify(obj) + "\n")
    }

    // No se consulta con un envío en vuelo: la respuesta todavía no incluiría
    // el mensaje recién mandado y la reconstrucción se comería la burbuja
    // optimista, que reaparecería un segundo después.
    function refresh() {
        if (root.hasThread && !root.busy)
            root._order({ cmd: "fetch" })
    }

    function loadThreads() {
        root._order({ cmd: "threads" })
    }

    function openThread(id) {
        if (id === root.threadId)
            return
        messagesModel.clear()       // si no, se ve el hilo viejo hasta el fetch
        root._order({ cmd: "open", id: id })
    }

    // replyToId vacío o indefinido manda el mensaje suelto.
    function send(text, replyToId) {
        const t = text.trim()
        if (!root.hasThread || root.busy || t === "")
            return
        // Burbuja optimista: el mensaje aparece al instante y el fetch que
        // dispara "sent" reconstruye la lista con el ítem real de la API. El
        // campo reply va desde ya para que no cambie de alto al reemplazarse.
        messagesModel.append({
            mid: "pending",
            role: "me",
            text: t,
            reply: replyToId ? root._textOf(replyToId) : ""
        })
        root.busy = true
        root._order({ cmd: "send", text: t, replyTo: replyToId || null })
    }

    function _textOf(mid) {
        for (var i = 0; i < messagesModel.count; i++)
            if (messagesModel.get(i).mid === mid)
                return messagesModel.get(i).text
        return ""
    }

    function _handle(line) {
        var msg
        try {
            msg = JSON.parse(line)
        } catch (e) {
            console.warn("instagram: línea no-JSON:", line)
            return
        }

        switch (msg.type) {
        case "ready":
            root.ready = true
            root.error = ""
            break
        case "opened":
            root.threadId = msg.id
            root.title = msg.title
            root.error = ""
            // Recordar la selección: el daemon la reabre en el próximo
            // arranque y la vista no cae en el selector cada vez.
            Config.instagram.thread = msg.id
            root.refresh()
            break
        case "threads":
            threadsModel.clear()
            for (var i = 0; i < msg.items.length; i++)
                threadsModel.append(msg.items[i])
            break
        case "messages":
            root._apply(msg.items)
            break
        case "sent":
            root.busy = false
            root.refresh()          // trae el mensaje real y su id
            break
        case "error":
            root.busy = false
            root.error = msg.text
            break
        }
    }

    // Reconstruir el modelo en cada poll resetearía el scroll cada veinte
    // segundos aunque no hubiera novedades, así que primero se compara el
    // último id: si es el mismo, el hilo no cambió y no se toca nada.
    function _apply(items) {
        const n = messagesModel.count
        if (n > 0 && items.length === n
                && messagesModel.get(n - 1).mid === items[items.length - 1].mid)
            return
        messagesModel.clear()
        for (var i = 0; i < items.length; i++)
            messagesModel.append(items[i])
    }
}
