# 🐚 Quickshell Dots

[![Quickshell](https://img.shields.io/badge/Quickshell-0.3.0-8839ef?style=flat-square)](https://quickshell.org)
[![Hyprland](https://img.shields.io/badge/Hyprland-WM-89b4fa?style=flat-square)](https://hyprland.org)
[![Arch Linux](https://img.shields.io/badge/Arch_Linux-BTW-1793d1?style=flat-square&logo=arch-linux&logoColor=white)](https://archlinux.org)
[![QML](https://img.shields.io/badge/QML-100%25-41cd52?style=flat-square)](#)

Configuración personal de [Quickshell](https://quickshell.org) para **Hyprland** en **Arch Linux**: barra, ecualizador paramétrico, pantalla de bloqueo y sincronización de tema, todo en QML.

## ✨ Características

- 📶 **Barra** con red (WiFi/ethernet vía `Quickshell.Networking`), bluetooth, batería, volumen (pipewire), reproductor Spotify/MPRIS, CPU (binario Rust nativo) y menú de energía.
- 🔔 **Notificaciones** con historial persistente, DND y toasts con acciones.
- 🖼️ **Selector de wallpapers** con filtro por color, orden por tono/luz y atajo global (`WIN+Q`).
- 🎚️ **Ecualizador paramétrico** sobre PipeWire (filter-chain generado desde `eq/parametric-eq.txt`).
- 🎨 **ThemeSync**: la paleta derivada del wallpaper activo se propaga a kitty, Hyprland y starship.
- 🔒 **Lock screen** propio (`Lock.qml`), reemplaza hyprlock, disparado por `loginctl`.

## 📦 Dependencias

- `quickshell` (paquete oficial en Arch, `pacman -S quickshell`)
- Hyprland
- `pipewire` + `wireplumber`
- `spotifyd` (control vía MPRIS)
- `cava`
- Rust/cargo (solo para compilar el widget de CPU, ver [Setup](#setup))

## 🗂️ Estructura

| Carpeta | Contenido |
|---|---|
| `shell.qml` | Entrypoint. Carga la barra, el reloj, el ecualizador y las notificaciones. |
| `Modules/` | Componentes de alto nivel montados en `shell.qml` (`Bar`, `ClockWidget`, `Equalizer`, `NotificationToast`). |
| `Widgets/Bar/` | Widgets de la barra: red, bluetooth, batería, pipewire, spotify, cpu, power menu, selector de wallpapers. |
| `Widgets/Equalizer/` | UI del ecualizador paramétrico (canvas + controles). |
| `Widgets/General/` | Componentes reutilizables (popups, panel, botones de media, búsqueda). |
| `Widgets/Bar/Rust/cpu/` | Binario Rust (`sysinfo`) que alimenta el widget de CPU. |
| `Services/` | Singletons de estado: `NetworkStats`, `WifiService`, `NotificationService`, `SpotifyInfo`, `ThemeSync`, `PopupState`, `CavaService`, `CpuService`, `WallpaperService`, `EqBootstrap`. |
| `Commons/` | Utilidades compartidas (`Colors`, `FuzzySort`, íconos de tema, imagen circular). |
| `eq/parametric-eq.txt` | Definición de bandas del ecualizador, consumida por `scripts/eq_filter_chain.sh`. |
| `scripts/eq_filter_chain.sh` | Genera el filter-chain de PipeWire a partir de `eq/parametric-eq.txt`. |
| `scripts/lock-listener.sh` | Escucha la señal `Lock` de logind y lanza `Lock.qml` (single-instance vía `flock`). |
| `Lock.qml` | Pantalla de bloqueo standalone (reemplaza hyprlock), lanzada con `qs -p`. |
| `Shaders/` | Shaders QSB usados por la UI. |
| `graphify-out/` | Grafo de conocimiento del proyecto (regenerable, ver `CLAUDE.md`). No se versiona el caché. |

## 🚀 Setup

```bash
# autostart en hyprland.conf
exec-once = qs
exec-once = ~/.config/quickshell/scripts/lock-listener.sh

# bind para bloquear
bind = $mainMod, L, exec, loginctl lock-session

# bind para el selector de wallpapers
bind = $mainMod, Q, global, quickshell:wallpaperToggle
```

El widget de CPU requiere compilar el binario Rust una vez:

```bash
cd Widgets/Bar/Rust/cpu && cargo build --release
```

## 🎨 Theming

`ThemeSync` propaga la paleta de `Colors` (derivada del wallpaper activo) a kitty, Hyprland y starship en cada cambio de wallpaper.

## 🧠 Desarrollo

El repo mantiene un grafo de conocimiento en `graphify-out/` (god nodes, comunidades, relaciones cross-file) para navegar y consultar la config sin grep crudo — ver `CLAUDE.md` para el flujo de trabajo (`graphify query/path/explain`, `graphify update .` tras cada cambio).
