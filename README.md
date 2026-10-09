# 🐚 Quickshell Dots

[![Quickshell](https://img.shields.io/badge/Quickshell-0.3.0-8839ef?style=flat-square)](https://quickshell.org)
[![Hyprland](https://img.shields.io/badge/Hyprland-WM-89b4fa?style=flat-square)](https://hyprland.org)
[![Arch Linux](https://img.shields.io/badge/Arch_Linux-BTW-1793d1?style=flat-square&logo=arch-linux&logoColor=white)](https://archlinux.org)
[![QML](https://img.shields.io/badge/QML-%2B_Python_%2B_Rust-41cd52?style=flat-square)](#)

Configuración personal de [Quickshell](https://quickshell.org) para **Hyprland** en **Arch Linux**: barra, sidebar de notas/IA/DMs, ecualizador paramétrico, patchbay de PipeWire, wallpapers animados, pantalla de bloqueo con huella dactilar, mouse virtual por gestos de mano y sincronización de tema. La UI es QML; los helpers puntuales están en Python (mouse virtual, Instagram, LaTeX) y en Rust (CPU).

## ✨ Características

### Barra

📶 Red (WiFi/ethernet vía `Quickshell.Networking`), bluetooth, batería, volumen (pipewire), reproductor Spotify/MPRIS con blob audio-reactivo, CPU (binario Rust nativo), workspaces de Hyprland con indicador animado y menú de energía. Selector de wallpapers con filtro por color, orden por tono/luz y atajo global (`WIN+Q`).

La barra es una píldora dibujada con `Shape`: cuando se abre un popup, le sale una **muesca** animada en el borde inferior justo encima de él. En los huecos entre secciones corre **`BarStream`**, un shader (`Shaders/stream.frag`) que hace de marquee continuo y, cuando hay música, acelera y brilla con la energía de cava. El volumen cambia de ícono y de color al silenciarse, y la batería muestra si está cargando (también en el detalle al pasar el mouse).

Acepta **wallpapers animados** (gif y video): los reproduce `mpvpaper`, que decodifica el original por hardware en vez de comerse los ~60 MB por archivo que cuesta `awww`. Como el cuantizador de color no sabe leer un video, `ffmpeg` le extrae un póster fijo y de ahí sale la paleta — así el theming funciona igual con un wallpaper animado que con una imagen.

![Bar](Assets/screenshots/bar.png)

### Sidebar

Panel lateral (`WIN+A`) con cuatro vistas: navegador de notas de **Obsidian** (búsqueda difusa sobre el vault, `obsidian://` para abrir en la app), un **editor Markdown** con preview en vivo y render de fórmulas LaTeX (`$...$`/`$$...$$` vía `latex`+`dvipng`), un **chat con Claude Code** con sesión persistente, y los **DMs de Instagram** (vía `instagrapi`, apagado por defecto — ver [Instagram](#instagram)). También incluye un panel de configuración que edita `Config/config.json` en vivo.

![Sidebar](Assets/screenshots/sidebar.png)

### Ecualizador paramétrico

Ecualizador de 10 bandas sobre PipeWire (filter-chain generado desde `eq/parametric-eq.txt`), con presets, bypass y un efecto visual de "rayo" al aplicar cambios. `ESC` lo cierra.

![Equalizer](Assets/screenshots/equalizer.png)

### Otras

- 🔔 **Notificaciones** con historial persistente, DND y toasts con acciones.
- 🔌 **Patchbay de PipeWire** en vivo: nodos, cables y niveles reales, con recableado por arrastre (`WIN+P`, `ESC` para cerrar). Los cables laten con el audio que los cruza. El lienzo se panea arrastrando el fondo (estilo Google Maps) para alcanzar los nodos que quedan fuera de vista, y los nombres largos —los dispositivos ALSA llegan a 70 caracteres— se desplazan al pasarles el mouse por encima.
- 🎨 **ThemeSync**: la paleta derivada del wallpaper activo se propaga a kitty, Hyprland y starship.
- 🔒 **Lock screen** propio (`Lock.qml`), reemplaza hyprlock, disparado por `loginctl`. Soporta desbloqueo por **huella dactilar** en paralelo al password (dos `PamContext` independientes, para que un prompt de fingerprint no bloquee el tipeo). Al volver de una suspensión el sensor se rearma solo: el resume se detecta por el salto del reloj y los fallos espurios del sensor (fprintd re-enumerándose) no gastan intentos.
- 🖐️ **Mouse virtual** por gestos de mano con la webcam (MediaPipe + uinput); detalles en su sección, más abajo.

## 📦 Dependencias

- `quickshell` (paquete oficial en Arch, `pacman -S quickshell`)
- Hyprland (con soporte de dispatch vía Lua — este config usa `hl.dsp.*`, no la sintaxis hyprlang estándar)
- `pipewire` + `wireplumber` (`pw-dump`/`pw-link`/`pw-cli`/`wpctl` los usa el patchbay y el EQ)
- `jq` (el patchbay filtra los puertos de `pw-dump` con él)
- `spotifyd` (control vía MPRIS)
- `mpvpaper` + `ffmpeg` (opcional — solo para wallpapers animados: `mpvpaper` los reproduce, `ffmpeg` extrae el póster del que sale la paleta)
- `cava` (opcional — sin él, la visualización de audio anima con valores falsos)
- Rust/cargo (solo para compilar el widget de CPU, ver [Setup](#setup))
- `claude` CLI ([Claude Code](https://claude.com/claude-code)) — para el chat de la sidebar
- `instagrapi` (opcional, `pip install instagrapi`) — solo para la vista de DMs de Instagram, que viene apagada
- `texlive` (`latex` + `dvipng`, paquetes `texlive-mathscience`/`texlive-binextra`) — para el render de fórmulas en el editor de notas
- Obsidian (opcional) — solo para "abrir en Obsidian" desde la vista de notas; el vault se lee directo del filesystem
- Una Nerd Font (por defecto `JetBrainsMono Nerd Font`, configurable) para los íconos, y la fuente decorativa `Anurati` para el `ClockWidget`
- Python 3.15 + webcam + acceso de escritura a `/dev/uinput` (opcional, solo para el mouse virtual; el venv lo arma `setup.sh`)
- PAM: un servicio `/etc/pam.d/quickshell-lock` propio (sin `pam_fprintd`) para el lock screen, más `pam_fprintd` configurado si se quiere huella dactilar

## 🗂️ Estructura

| Carpeta | Contenido |
|---|---|
| `shell.qml` | Entrypoint. Registra los atajos globales y carga `Bar`, `ClockWidget`, `Equalizer`, `Patchbay`, `NotificationToast`, `Sidebar`. |
| `Lock.qml` | Pantalla de bloqueo standalone (reemplaza hyprlock), con auth por password + huella dactilar, lanzada con `qs -p`. |
| `Modules/` | Componentes de alto nivel montados en `shell.qml` (`Bar`, `ClockWidget`, `Equalizer`, `NotificationToast`, `Patchbay`, `Sidebar`). |
| `Widgets/Bar/` | Widgets de la barra: animación de huecos (`BarStream`), red, bluetooth, batería, pipewire, spotify, cpu, workspaces, power menu, selector de wallpapers. |
| `Widgets/Equalizer/` | UI del ecualizador paramétrico (canvas + controles). |
| `Widgets/Patchbay/` | Grafo del patchbay: tarjetas de nodo, pines y cables (`Shape`/`PathCubic`). |
| `Widgets/Sidebar/` | Vistas de la sidebar: navegador Obsidian, editor Markdown (`NoteEditor`), chat de Claude Code, DMs de Instagram (`InstagramView`), configuración. |
| `Widgets/Lock/` | Componentes propios del lock screen (indicador de huella dactilar). |
| `Widgets/General/` | Componentes reutilizables (popups, panel, botones de media, búsqueda). |
| `Widgets/Bar/Rust/cpu/` | Binario Rust (`sysinfo`) que alimenta el widget de CPU. |
| `Services/` | Singletons de estado: `NetworkStats`, `WifiService`, `NotificationService`, `SpotifyInfo`, `ThemeSync`, `PopupState`, `SidebarState`, `CavaService`, `CpuService`, `WallpaperService`, `EqBootstrap`, `PatchbayService`, `ObsidianEditor`, `ClaudeCodeService`, `InstagramService` (+ `instagram.py`), `MathRender` (+ `mathrender.py`), `VirtualMouse`. |
| `Services/virtual_mouse/` | Daemon Python del mouse virtual (`main.py` + `VirtualMouse.py`), su `setup.sh`, `requirements.txt` y los checks de lógica pura (`test_virtual_mouse.py`). El venv y el modelo `.task` no se versionan. |
| `Commons/` | Utilidades compartidas (`Colors`, `Config`, `FuzzySort`, `OrderColors`, íconos de tema, imagen circular). |
| `eq/parametric-eq.txt` | Definición de bandas del ecualizador, consumida por `scripts/eq_filter_chain.sh`. |
| `scripts/eq_filter_chain.sh` | Genera el filter-chain de PipeWire a partir de `eq/parametric-eq.txt`. |
| `scripts/lock-listener.sh` | Escucha la señal `Lock` de logind y lanza `Lock.qml` (single-instance vía `flock`). |
| `Shaders/` | Fuente GLSL de `BarStream` (`stream.frag`) y, en `qsb/`, los shaders precompilados (blob audio-reactivo, barras del visualizador, stream). |
| `Assets/` | Recursos runtime (`No_cover.jpg`) y `screenshots/` para este README. |
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

# bind para la sidebar (notas / Claude Code)
bind = $mainMod, A, global, quickshell:sidebarToggle

# bind para el patchbay de PipeWire
bind = $mainMod, P, global, quickshell:patchbayToggle
```

El widget de CPU requiere compilar el binario Rust una vez:

```bash
cd Widgets/Bar/Rust/cpu && cargo build --release
```

Para la huella dactilar en el lock screen hace falta un servicio PAM propio (sin `pam_fprintd`, para que no bloquee el password), por ejemplo `/etc/pam.d/quickshell-lock` calcado de `/etc/pam.d/login` sin la línea de `pam_fprintd`.

### Control por IPC

Además de los `GlobalShortcut` de arriba, el shell expone los mismos toggles por IPC. Sirve para scripts, para otro compositor, o para cualquier cosa que no pueda usar el protocolo `hyprland-global-shortcuts`:

```bash
qs ipc show                          # lista los targets disponibles
qs ipc call popup toggle wallpaper   # también: patchbay, spotify, wifi, bluetooth, notifications, power
qs ipc call sidebar toggle
qs ipc call sidebar open obsidian    # obsidian | claude | instagram | config
```

La función es `open` y no `show` a propósito: `ipc show` ya es un subcomando del CLI de quickshell y se come el nombre de la función antes de tratarlo como argumento.

### Instagram

La vista de DMs viene apagada (`instagram.enabled: false`). Para usarla, instalá `instagrapi` y creá la sesión a mano una vez:

```bash
pip install instagrapi
python3 Services/instagram.py --login Config/instagram-session.json
```

El login interactivo es lo único que ve la contraseña; el sidebar solo lee la sesión resultante. `Config/` está en `.gitignore`, así que la sesión no se versiona. Después poné `instagram.enabled: true` en `Config/config.json` (o desde el panel de settings).

## 🖐️ Mouse virtual

Controla el puntero con la mano frente a la webcam. Un daemon Python (`Services/virtual_mouse/main.py`) lee `/dev/video0`, detecta la mano con MediaPipe `HandLandmarker` y crea un mouse virtual vía `evdev`/uinput:

| Gesto | Acción |
|---|---|
| Mover la mano | Mover el cursor |
| Pinza pulgar + índice | Click izquierdo (si te movés mientras la mantenés, arrastra) |
| Pinza pulgar + medio | Click derecho |
| Pinza pulgar + anular, subiendo o bajando la mano | Scroll |

El cursor se suaviza con un filtro One Euro, interpolado a 120 Hz entre los frames de la cámara. Los gestos usan histéresis y la sensibilidad se ajusta a la distancia de la mano a la cámara.

Se prende y se apaga con **Control por gestos** en el panel de settings de la sidebar. No se persiste a propósito: arrancar el shell con la cámara tomada sería una sorpresa. Si el daemon muere (cámara ocupada, venv roto), el toggle vuelve solo a apagado.

```bash
cd Services/virtual_mouse
./setup.sh                              # crea venv/ con python3.15 y baja hand_landmarker.task
venv/bin/python test_virtual_mouse.py   # checks de la lógica pura, sin cámara ni uinput
```

Tu usuario necesita permiso de escritura en `/dev/uinput`, por ejemplo con una regla udev o el grupo `input`.

## ⚙️ Configuración

`Config/config.json` guarda los valores de usuario: rutas, binarios (backend de wallpaper, comandos de poder), fuente, identidad (`user.displayName` / `user.avatar`), vault de Obsidian (`obsidian.configPath`), comportamiento de la sidebar (`sideBar.closeWhenClicked`: cerrarla al hacer clic fuera) y los tokens de animación. Se lee en vivo — editarlo actualiza el shell sin reiniciar — y `Commons/Config.qml` también escribe en él, así que el panel de settings de la sidebar puede persistir cambios desde la UI.

El archivo se genera solo: si no existe, el shell lo escribe al arrancar con el esquema completo y los defaults declarados en `Commons/Config.qml`, así que siempre hay algo concreto que abrir y editar. Si está incompleto, las claves que falten se rellenan sin pisar las que ya tengas. Borrarlo no rompe nada — vuelve a nacer. Está en `.gitignore` porque contiene rutas propias de la máquina.

```bash
# volver a los defaults: borrarlo y reiniciar el shell
rm Config/config.json
```

Ojo: al reescribirlo, las claves quedan ordenadas alfabéticamente y se pierden los comentarios (JSON no los soporta).

## 🎨 Theming

`ThemeSync` propaga la paleta de `Colors` (derivada del wallpaper activo) a kitty, Hyprland y starship en cada cambio de wallpaper. Las tres rutas de salida son configurables en `Config/config.json` (`themeSync.*`).

## 🧠 Desarrollo

El repo mantiene un grafo de conocimiento en `graphify-out/` (god nodes, comunidades, relaciones cross-file) para navegar y consultar la config sin grep crudo — ver `CLAUDE.md` para el flujo de trabajo (`graphify query/path/explain`, `graphify update .` tras cada cambio).
