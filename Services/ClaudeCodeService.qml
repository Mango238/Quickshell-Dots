pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Envuelve el CLI de Claude Code (`claude`) para un chat con continuidad de
// sesión. Cada turno lanza un proceso `claude -p "<prompt>" --output-format
// json`; la respuesta JSON trae `.result` (texto) y `.session_id`, que se
// guarda para encadenar los turnos siguientes con `--resume <id>`. El estado
// vive en el singleton, así el historial sobrevive al cambio de vista y al
// cierre del sidebar (no a un reload del shell: session_id no se persiste).
//
// ponytail: chat Q&A; en modo -p las tools que requieren permiso no se pueden
// aprobar, así que sirve para preguntas/razonamiento, no para que Claude edite
// archivos. Subir a --output-format stream-json + SplitParser para streaming
// token a token, o acotar --allowedTools si se quiere habilitar tools seguras.
Singleton {
    id: root

    property alias messages: messagesModel
    property string sessionId: ""
    property bool busy: false
    property string cwd: Quickshell.env("HOME")

    ListModel { id: messagesModel }

    function _fail(msg) {
        messagesModel.append({ role: "error", text: msg })
    }

    Process {
        id: proc

        stdout: StdioCollector {
            id: out
            onStreamFinished: {
                root.busy = false
                const raw = out.text.trim()
                if (raw === "") {
                    root._fail("Sin respuesta de claude (¿instalado y con sesión iniciada?).")
                    return
                }
                try {
                    const obj = JSON.parse(raw)
                    if (obj.session_id)
                        root.sessionId = obj.session_id
                    const txt = (obj.result !== undefined && obj.result !== null)
                        ? String(obj.result) : ""
                    if (obj.is_error) {
                        root._fail(txt !== "" ? txt : "claude devolvió un error.")
                        return
                    }
                    messagesModel.append({ role: "assistant", text: txt })
                } catch (e) {
                    root._fail("Respuesta no-JSON de claude.")
                }
            }
        }

        // Fallback: si el proceso no llegó a emitir stdout (p. ej. binario no
        // encontrado), streamFinished no resuelve el turno y busy sigue true.
        onExited: (exitCode, exitStatus) => {
            if (root.busy) {
                root.busy = false
                root._fail("No se pudo ejecutar claude (código " + exitCode + ").")
            }
        }
    }

    // Envía un turno del usuario. El prompt va como argumento argv propio,
    // nunca interpolado en un string de shell — sin riesgo de inyección.
    function send(text) {
        if (root.busy)
            return
        const t = text.trim()
        if (t === "")
            return
        messagesModel.append({ role: "user", text: t })
        var cmd = ["claude", "-p", t, "--output-format", "json"]
        if (root.sessionId !== "")
            cmd = cmd.concat(["--resume", root.sessionId])
        proc.command = cmd
        proc.workingDirectory = root.cwd
        root.busy = true
        proc.running = true
    }

    // Empieza una conversación nueva (olvida la sesión y el historial).
    function reset() {
        if (root.busy)
            return
        messagesModel.clear()
        root.sessionId = ""
    }
}
