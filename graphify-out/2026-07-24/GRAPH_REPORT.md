# Graph Report - quickshell  (2026-07-24)

## Corpus Check
- 7 files · ~12,883 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 138 nodes · 200 edges · 25 communities (15 shown, 10 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 3 edges (avg confidence: 0.83)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `6faa1b81`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Bar & Widgets UI
- Equalizer Apply/Switch Logic
- PipeWire Sink Selection
- System Stats Bar Widgets
- Network & Bluetooth Widgets
- Theming & Shell Root
- Equalizer Recovery/Restart
- EQ Script Dependency Checks
- Equalizer Backend & Controls
- EQ Route Stabilization
- PipeWire Source Selection
- Audio Visualization (Cava)
- Lock Screen Listener
- DankCircularImage
- FuzzySort
- Theme Icons Singleton
- ClockWidget
- EqBootstrap
- WallpaperThumbnail
- AlbumArt
- DirectorySearchBar
- MediaButton
- 🐚 Quickshell Dots
- Dónde está tu config hoy, y qué le falta para caelestia/DMS

## God Nodes (most connected - your core abstractions)
1. `apply_eq()` - 18 edges
2. `switch_eq_target()` - 14 edges
3. `Investigation targets (verificación humana, ordenados por confianza)` - 11 edges
4. `PopupState` - 11 edges
5. `recover_eq()` - 10 edges
6. `sink_exists()` - 8 edges
7. `disable_eq()` - 8 edges
8. `🐚 Quickshell Dots` - 8 edges
9. `eq_filter_chain.sh script` - 7 edges
10. `RightSide` - 7 edges

## Surprising Connections (you probably didn't know these)
- `BleActivate` --calls--> `PopupState`  [EXTRACTED]
  Widgets/Bar/BleActivate.qml → Services/PopupState.qml
- `Shell Root` --references--> `PopupState`  [EXTRACTED]
  shell.qml → Services/PopupState.qml
- `SpotifyInfo` --calls--> `OrderColors Singleton`  [EXTRACTED]
  Services/SpotifyInfo.qml → Commons/OrderColors.qml
- `Bar Module` --references--> `PopupState`  [EXTRACTED]
  Modules/Bar.qml → Services/PopupState.qml
- `Equalizer` --references--> `PopupState`  [EXTRACTED]
  Modules/Equalizer.qml → Services/PopupState.qml

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Dynamic Theming System** — services_wallpaperservice, commons_colors, commons_ordercolors, services_themesync [EXTRACTED 0.95]
- **Notification Pipeline** — services_notificationservice, modules_bar, widgets_bar_notificationlist [EXTRACTED 0.90]
- **Media & Audio Visualization** — services_spotifyinfo, services_cavaservice, modules_bar [EXTRACTED 0.85]
- **Equalizer System** — widgets_equalizer_eqcontrolscard, widgets_equalizer_eqlightningcanvas, widgets_equalizer_equalizerbackend, eq_parametric_eq [EXTRACTED 1.00]
- **General UI Components** — widgets_general_panel, widgets_general_panelpopup, widgets_general_hoverpopup, widgets_general_mediabutton [EXTRACTED 0.90]
- **Bar Layout Components** — widgets_bar_leftside, widgets_bar_midside, widgets_bar_rightside [EXTRACTED 1.00]
- **Popup Trigger Pattern** — widgets_bar_archwallpaperbutton, widgets_bar_bleactivate, widgets_bar_eqactivate, widgets_bar_notificationbell, widgets_bar_poweroff, widgets_bar_red, widgets_bar_spotify [INFERRED 0.90]

## Communities (25 total, 10 thin omitted)

### Community 0 - "Bar & Widgets UI"
Cohesion: 0.14
Nodes (18): Bar Module, Equalizer, NotificationToast, NotificationService, PopupState, SpotifyInfo, ArchWallpaperButton, BarClock (+10 more)

### Community 1 - "Equalizer Apply/Switch Logic"
Cohesion: 0.33
Nodes (9): capture_eq_sink_state(), first_real_sink(), node_id_by_name(), normalize_eq_sink(), pick_best_sink(), sink_exists(), switch_eq_target(), wait_for_eq_nodes() (+1 more)

### Community 2 - "PipeWire Sink Selection"
Cohesion: 0.23
Nodes (6): check_deps(), first_real_source(), need_cmd(), pick_best_source(), source_exists(), wait_for_source()

### Community 3 - "System Stats Bar Widgets"
Cohesion: 0.24
Nodes (10): CpuService, BarPill, Battery, BleActivate, Cpu, LeftSide, Pipewire, HoverPopup (+2 more)

### Community 4 - "Network & Bluetooth Widgets"
Cohesion: 0.29
Nodes (8): NetworkStats, WifiService, BluetoothActionButton, BluetoothDeviceList, BluetoothDeviceRow, Red, WifiNetworkList, WifiNetworkRow

### Community 5 - "Theming & Shell Root"
Cohesion: 0.38
Nodes (7): Colors Singleton, OrderColors Singleton, Lock Screen Root, ThemeSync, WallpaperService, Shell Root, WallpaperGrid

### Community 6 - "Equalizer Recovery/Restart"
Cohesion: 0.43
Nodes (8): disable_eq(), read_state(), recover_eq(), set_default_sink_compat(), set_default_source_compat(), eq_filter_chain.sh script, status_eq(), write_state()

### Community 7 - "EQ Script Dependency Checks"
Cohesion: 0.10
Nodes (20): [D-001] Identificador `root` inexistente rompe altura/anclaje en 5 componentes, [D-002] Ningún archivo con delegates usa `pragma ComponentBehavior: Bound`, [D-003] Portada de Spotify sin manejo de error de red, [D-004] Búsqueda de ícono costosa evaluada en cada binding, Hallazgo más importante: bug real, no solo estilo, [I-001] `Binding.restoreMode` no seteado en sliders de Spotify (Qt6 cambió el default), [I-002] `CpuService` sin manejo de `onExited`/stderr, [I-003] `ListView` de notificaciones sin `reuseItems`, con altura variable + Repeater anidado (+12 more)

### Community 8 - "Equalizer Backend & Controls"
Cohesion: 0.83
Nodes (4): Parametric EQ State, EqControlsCard, EqLightningCanvas, EqualizerBackend

### Community 9 - "EQ Route Stabilization"
Cohesion: 0.67
Nodes (4): finalize_eq_route(), move_sink_inputs_to(), relink_eq_output_to_base_sink(), stabilize_eq_route()

### Community 10 - "PipeWire Source Selection"
Cohesion: 0.40
Nodes (5): apply_eq(), is_virtual_eq_sink(), restart_audio_stack(), write_eq_file(), write_pipewire_conf()

### Community 11 - "Audio Visualization (Cava)"
Cohesion: 0.67
Nodes (3): Ref, CavaService, AudioVisualization

### Community 23 - "🐚 Quickshell Dots"
Cohesion: 0.22
Nodes (8): ✨ Características, ⚙️ Configuración, 📦 Dependencias, 🧠 Desarrollo, 🗂️ Estructura, 🐚 Quickshell Dots, 🚀 Setup, 🎨 Theming

### Community 24 - "Dónde está tu config hoy, y qué le falta para caelestia/DMS"
Cohesion: 0.29
Nodes (6): 1. Panorama, 2. Lo que ya está a la altura, 3. Las brechas reales, 4. Hoja de ruta, Dónde está tu config hoy, y qué le falta para caelestia/DMS, No priorizado (a propósito)

## Knowledge Gaps
- **52 isolated node(s):** `lock-listener.sh script`, `1. Panorama`, `2. Lo que ya está a la altura`, `3. Las brechas reales`, `No priorizado (a propósito)` (+47 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **10 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `PopupState` connect `Bar & Widgets UI` to `System Stats Bar Widgets`, `Network & Bluetooth Widgets`, `Theming & Shell Root`?**
  _High betweenness centrality (0.057) - this node is a cross-community bridge._
- **Why does `Red` connect `Network & Bluetooth Widgets` to `Bar & Widgets UI`, `System Stats Bar Widgets`?**
  _High betweenness centrality (0.035) - this node is a cross-community bridge._
- **Why does `LeftSide` connect `System Stats Bar Widgets` to `Network & Bluetooth Widgets`?**
  _High betweenness centrality (0.030) - this node is a cross-community bridge._
- **What connects `lock-listener.sh script`, `1. Panorama`, `2. Lo que ya está a la altura` to the rest of the system?**
  _52 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Bar & Widgets UI` be split into smaller, more focused modules?**
  _Cohesion score 0.13725490196078433 - nodes in this community are weakly interconnected._
- **Should `EQ Script Dependency Checks` be split into smaller, more focused modules?**
  _Cohesion score 0.09523809523809523 - nodes in this community are weakly interconnected._