#!/usr/bin/env bash
# Escucha la senal `Lock` de systemd-logind y lanza el locker de Quickshell.
# Se dispara con `loginctl lock-session` (boton "Bloquear" del PowerMenu, hypridle
# before_sleep_cmd / inactividad). Autostart en hyprland.conf:
#   exec-once = ~/.config/quickshell/scripts/lock-listener.sh
#
# INSTANCIA UNICA (flock): dos clientes WlSessionLock simultaneos causaban un bucle de
# re-bloqueo (al autenticar en uno, el otro seguia reteniendo la pantalla). `flock -n`
# descarta el lanzamiento si ya hay un locker activo, en vez de encolarlo.
# El locker se autotermina al desbloquear (ver exitTimer en Lock.qml), liberando el flock.

LOCK_QML="$HOME/.config/quickshell/Lock.qml"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/qs-locker.lock"

dbus-monitor --system "type='signal',interface='org.freedesktop.login1.Session',member='Lock'" 2>/dev/null |
while read -r line; do
    case "$line" in
        *"member=Lock"*)
            flock -n "$LOCK_FILE" qs -p "$LOCK_QML" &
            ;;
    esac
done
