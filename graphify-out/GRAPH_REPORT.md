# Graph Report - /home/tomi_218/.config/quickshell  (2026-07-23)

## Corpus Check
- 63 files · ~46,977 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 101 nodes · 166 edges · 23 communities (13 shown, 10 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 3 edges (avg confidence: 0.83)
- Token cost: 129,166 input · 4,618 output

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

## God Nodes (most connected - your core abstractions)
1. `apply_eq()` - 18 edges
2. `switch_eq_target()` - 14 edges
3. `PopupState` - 11 edges
4. `recover_eq()` - 10 edges
5. `sink_exists()` - 8 edges
6. `disable_eq()` - 8 edges
7. `eq_filter_chain.sh script` - 7 edges
8. `RightSide` - 7 edges
9. `read_state()` - 6 edges
10. `set_default_sink_compat()` - 6 edges

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

## Communities (23 total, 10 thin omitted)

### Community 0 - "Bar & Widgets UI"
Cohesion: 0.13
Nodes (19): Bar Module, Equalizer, NotificationToast, NotificationService, PopupState, SpotifyInfo, ArchWallpaperButton, BarClock (+11 more)

### Community 1 - "Equalizer Apply/Switch Logic"
Cohesion: 0.40
Nodes (10): apply_eq(), capture_eq_sink_state(), is_virtual_eq_sink(), normalize_eq_sink(), sink_exists(), switch_eq_target(), wait_for_eq_nodes(), wait_for_sink() (+2 more)

### Community 2 - "PipeWire Sink Selection"
Cohesion: 0.25
Nodes (3): first_real_sink(), node_id_by_name(), pick_best_sink()

### Community 3 - "System Stats Bar Widgets"
Cohesion: 0.25
Nodes (9): CpuService, Battery, BleActivate, Cpu, LeftSide, Pipewire, HoverPopup, PanelBackground (+1 more)

### Community 4 - "Network & Bluetooth Widgets"
Cohesion: 0.29
Nodes (8): NetworkStats, WifiService, BluetoothActionButton, BluetoothDeviceList, BluetoothDeviceRow, Red, WifiNetworkList, WifiNetworkRow

### Community 5 - "Theming & Shell Root"
Cohesion: 0.38
Nodes (7): Colors Singleton, OrderColors Singleton, Lock Screen Root, ThemeSync, WallpaperService, Shell Root, WallpaperGrid

### Community 6 - "Equalizer Recovery/Restart"
Cohesion: 0.47
Nodes (6): disable_eq(), recover_eq(), restart_audio_stack(), set_default_sink_compat(), set_default_source_compat(), write_state()

### Community 7 - "EQ Script Dependency Checks"
Cohesion: 0.40
Nodes (5): check_deps(), need_cmd(), read_state(), eq_filter_chain.sh script, status_eq()

### Community 8 - "Equalizer Backend & Controls"
Cohesion: 0.83
Nodes (4): Parametric EQ State, EqControlsCard, EqLightningCanvas, EqualizerBackend

### Community 9 - "EQ Route Stabilization"
Cohesion: 0.67
Nodes (4): finalize_eq_route(), move_sink_inputs_to(), relink_eq_output_to_base_sink(), stabilize_eq_route()

### Community 10 - "PipeWire Source Selection"
Cohesion: 0.50
Nodes (4): first_real_source(), pick_best_source(), source_exists(), wait_for_source()

### Community 11 - "Audio Visualization (Cava)"
Cohesion: 0.67
Nodes (3): Ref, CavaService, AudioVisualization

## Knowledge Gaps
- **25 isolated node(s):** `lock-listener.sh script`, `WallpaperGrid`, `NotificationList`, `CavaService`, `CpuService` (+20 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **10 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `PopupState` connect `Bar & Widgets UI` to `System Stats Bar Widgets`, `Network & Bluetooth Widgets`, `Theming & Shell Root`?**
  _High betweenness centrality (0.108) - this node is a cross-community bridge._
- **Why does `Red` connect `Network & Bluetooth Widgets` to `Bar & Widgets UI`, `System Stats Bar Widgets`?**
  _High betweenness centrality (0.066) - this node is a cross-community bridge._
- **Why does `LeftSide` connect `System Stats Bar Widgets` to `Bar & Widgets UI`, `Network & Bluetooth Widgets`?**
  _High betweenness centrality (0.056) - this node is a cross-community bridge._
- **What connects `lock-listener.sh script`, `WallpaperGrid`, `NotificationList` to the rest of the system?**
  _25 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Bar & Widgets UI` be split into smaller, more focused modules?**
  _Cohesion score 0.13450292397660818 - nodes in this community are weakly interconnected._