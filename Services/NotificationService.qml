pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

/**
 * NotificationService.qml — Fuente de verdad para notificaciones.
 *
 * Envuelve un NotificationServer (Quickshell.Services.Notifications) y
 * mantiene un historial propio de snapshots JS planos (no las referencias
 * vivas a Notification) para que la lista del popup no dependa del ciclo de
 * vida de la notificación original (si el remitente la expira/dismissea
 * mientras seguimos mostrándola en el historial, no queremos que desaparezca
 * ni que quede un objeto colgante).
 *
 * IMPORTANTE — colisión de D-Bus con otro daemon de notificaciones:
 * Si ya hay un dunst/mako/swaync corriendo, ese proceso ya posee el nombre
 * bien conocido org.freedesktop.Notifications en el bus de sesión, y este
 * NotificationServer no podrá registrarse como servidor de notificaciones.
 * En ese caso `onNotification` simplemente nunca se dispara (no hay excepción
 * QML, no hay crash) — el historial queda vacío y unreadCount en 0. Este
 * archivo NO intenta detectar ni resolver esa colisión (no hay una propiedad
 * pública tipo `registered`/`active` documentada para eso): es tolerante al
 * fallo por diseño, simplemente no hace nada si no le llegan notificaciones.
 * No mata ni reemplaza al daemon existente.
 *
 * PERSISTENCIA: el historial (sin `notifRef` ni `image`, ver _save) y el
 * flag `dndEnabled` se guardan en ~/.cache/quickshell/notifications.json,
 * mismo patrón FileView setText/onLoaded que WallpaperService con
 * wallpaper-colors.json. `notifRef` es la referencia viva a la
 * Notification original: vive mientras el emisor no la cierre (permite
 * invocar acciones desde el historial); al cerrarse (`closed`), se pone en
 * null vía _clearNotifRef — el snapshot de texto queda, los botones de
 * acción desaparecen. `image` es una URL de image provider que no
 * sobrevive al proceso: nunca se persiste (appIcon sí).
 */
Singleton {
    id: root

    /// Historial de notificaciones recibidas, más reciente primero.
    /// Cada entrada es un snapshot plano: {id, appName, appIcon, image,
    /// summary, body, urgency, transient, timestamp, notifRef}.
    property var history: []

    /// Contador de no leídas (se resetea con markAllRead()).
    property int unreadCount: 0

    /// No Molestar: suprime solo el toast; historial y unreadCount se
    /// registran igual.
    property bool dndEnabled: false

    /// Emitida con el snapshot de cada notificación entrante, para que
    /// NotificationToast.qml la consuma sin acoplarse al NotificationServer.
    signal toastReceived(var notif)

    /// Acceso de solo lectura al modelo vivo del servidor, por si se necesita
    /// más adelante (ej. invocar acciones sobre una notificación trackeada).
    readonly property alias trackedNotifications: server.trackedNotifications

    NotificationServer {
        id: server

        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        actionsSupported: true
        keepOnReload: true

        onNotification: (notification) => {
            // Sin esto, el server no retiene la notificación.
            notification.tracked = true

            var isTransient = notification.transient === true

            var snap = {
                id: notification.id,
                appName: notification.appName,
                appIcon: notification.appIcon,
                image: notification.image,
                summary: notification.summary,
                body: notification.body,
                urgency: notification.urgency,
                transient: isTransient,
                timestamp: Date.now(),
                notifRef: notification
            }

            // Solo trackeamos closed para entradas que van al historial: las
            // transient no tienen entrada que limpiar.
            if (!isTransient) {
                notification.closed.connect(function() {
                    root._clearNotifRef(snap.id, snap.timestamp)
                })

                root.history = [snap].concat(root.history).slice(0, 100)
                root.unreadCount += 1
                root._scheduleSave()
            }

            // DND suprime solo el toast; historial y unreadCount ya se
            // registraron arriba independientemente del DND.
            if (!root.dndEnabled) {
                root.toastReceived(snap)
            }
        }
    }

    // El id de D-Bus se puede reciclar entre notificaciones del mismo
    // emisor; buscamos por (id, timestamp) para no pisar la entrada
    // equivocada si hay dos con el mismo id en el historial.
    function _clearNotifRef(id, timestamp) {
        var idx = -1
        for (var i = 0; i < root.history.length; i++) {
            if (root.history[i].id === id && root.history[i].timestamp === timestamp) {
                idx = i
                break
            }
        }
        if (idx === -1) return
        var h = root.history.slice()
        h[idx] = Object.assign({}, h[idx], { notifRef: null })
        root.history = h
        root._scheduleSave()
    }

    /// Marca todo como leído (ej. al abrir el popup de historial).
    function markAllRead() {
        root.unreadCount = 0
    }

    /// Vacía el historial completo.
    function clearHistory() {
        root.history = []
        root.unreadCount = 0
        root._scheduleSave()
    }

    /// Descarta una entrada puntual del historial por índice.
    function dismissAt(index) {
        if (index < 0 || index >= root.history.length) return
        root.history = root.history.slice(0, index).concat(root.history.slice(index + 1))
        root._scheduleSave()
    }

    /// Alterna No Molestar (suprime toasts entrantes, no el historial).
    function toggleDnd() {
        root.dndEnabled = !root.dndEnabled
        root._scheduleSave()
    }

    // ─── Persistencia ───────────────────────────────────────────────────────

    property string _cacheDir:
        (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
        + "/quickshell"

    // Evita que un _scheduleSave() disparado antes de que termine la carga
    // inicial pise el JSON en disco con el estado default vacío.
    property bool _loaded: false

    readonly property FileView _cacheFile: FileView {
        path: root._cacheDir + "/notifications.json"
        printErrors: false   // primer arranque: el archivo no existe aún
        onLoaded: {
            try {
                var parsed = JSON.parse(this.text())
                if (parsed && Array.isArray(parsed.history))
                    // Los snapshots persistidos no llevan notifRef/image:
                    // se normalizan a null/"" para que los bindings de la UI
                    // no reciban undefined.
                    root.history = parsed.history.slice(0, 100).map(function(n) {
                        return Object.assign({ notifRef: null, image: "" }, n)
                    })
                if (parsed && typeof parsed.dnd === "boolean")
                    root.dndEnabled = parsed.dnd
            } catch (e) {
                console.warn("NotificationService: historial corrupto, ignorando:", e)
            }
            root._loaded = true
        }
        onLoadFailed: (error) => { root._loaded = true }
        onSaveFailed: (error) => console.warn("NotificationService: no se pudo guardar el historial:", error)
    }

    readonly property Timer _saveDebounce: Timer {
        interval: 1000
        onTriggered: root._save()
    }

    function _scheduleSave() {
        if (!root._loaded) return
        root._saveDebounce.restart()
    }

    function _save() {
        var plain = root.history.map(function(n) {
            return {
                id: n.id, appName: n.appName, appIcon: n.appIcon,
                summary: n.summary, body: n.body, urgency: n.urgency,
                transient: n.transient, timestamp: n.timestamp
                // sin notifRef (objeto vivo) ni image (provider que muere con el proceso)
            }
        })
        root._cacheFile.setText(JSON.stringify({ dnd: root.dndEnabled, history: plain }))
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root._cacheDir])
}
