pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Networking

/**
 * WifiService.qml — Estado WiFi para la barra y el popup de redes.
 *
 * Puro binding sobre el módulo nativo Quickshell.Networking (backend
 * NetworkManager): sin Process ni parseo de nmcli. Expone el dispositivo
 * WiFi, las redes visibles ordenadas y helpers de iconografía compartidos
 * por la píldora de red (Red.qml) y el popup (WifiNetworkList.qml).
 */
Singleton {
    id: wifiService

    /// true si el radio WiFi está encendido (escribible vía setEnabled()).
    readonly property bool enabled: Networking.wifiEnabled
    function setEnabled(on) { Networking.wifiEnabled = on }

    /// Primer dispositivo WiFi del sistema (normalmente wlan0), o null.
    /// Nota: los UntypedObjectModel no son iterables con for...of — .values.
    readonly property var device: {
        var list = Networking.devices.values
        for (var i = 0; i < list.length; i++)
            if (list[i].type === DeviceType.Wifi) return list[i]
        return null
    }

    /// Redes visibles: la conectada primero, el resto por señal descendente.
    readonly property var networks: {
        if (!wifiService.device) return []
        var list = wifiService.device.networks.values.slice()
        list.sort((a, b) => {
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            return b.signalStrength - a.signalStrength
        })
        return list
    }

    readonly property var activeNetwork: {
        var list = wifiService.networks
        for (var i = 0; i < list.length; i++)
            if (list[i].connected) return list[i]
        return null
    }

    readonly property string ssid: activeNetwork ? activeNetwork.name : ""
    readonly property bool connected: activeNetwork !== null

    /// Normaliza signalStrength a 0..1 (tolera backends que reporten 0..100).
    function signalUnit(strength) {
        return strength > 1 ? strength / 100 : strength
    }

    function signalPercent(strength) {
        return Math.round(signalUnit(strength) * 100)
    }

    /// Glifo nerd-font según intensidad de señal.
    function signalIcon(strength) {
        var s = signalUnit(strength)
        if (s >= 0.8) return "󰤨"
        if (s >= 0.6) return "󰤥"
        if (s >= 0.4) return "󰤢"
        if (s >= 0.2) return "󰤟"
        return "󰤯"
    }

    /// Icono de estado global para la píldora de la barra.
    readonly property string statusIcon: {
        if (!wifiService.enabled) return "󰤭"
        if (wifiService.activeNetwork)
            return signalIcon(wifiService.activeNetwork.signalStrength)
        return "󰤯"
    }
}
