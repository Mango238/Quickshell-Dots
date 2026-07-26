# QML Code Review Report — ~/.config/quickshell

**Fecha**: 2026-07-22
**Skill**: `qt-development-skills:qt-qml-review` (plugin `TheQtCompanyRnD/agent-skills`)
**Scope**: codebase completo — `~/.config/quickshell` (58 archivos `.qml`)
**Archivos revisados**: 58
**Hallazgos**: 479 de lint mecánico (273 en código propio, 206 en `Commons/FuzzySort.qml` — librería vendorizada, no propia) + 9 de análisis profundo confirmados + 9 investigation targets
**qmllint**: ejecutado pero sin señal útil — no tiene configurado el path de tipos de Quickshell (`Process`, `PanelWindow`, etc.), solo devuelve warnings de tipos base no resueltos. Descartado.

---

## Hallazgo más importante: bug real, no solo estilo

### [D-001] Identificador `root` inexistente rompe altura/anclaje en 5 componentes

- **Archivos**: `Widgets/Bar/Battery.qml:88,91`, `Widgets/Bar/Pipewire.qml:54,57`, `Widgets/Bar/LeftSide.qml:17`, `Widgets/Bar/RightSide.qml:16`, `Widgets/Bar/MidSide.qml:26,136`
- **Categoría**: Bindings & Properties / Layout & Anchoring (confirmado independientemente por 3 de los 6 agentes)
- **Confianza**: 88-92/100
- **Hallazgo**: Estos archivos usan `root.height`, `anchorWindow: root`, etc., pero `root` no existe en su propio scope. Los ids de QML son por-documento — no cruzan de `Modules/Bar.qml` (que sí declara `id: root` en su `PanelWindow`) hacia componentes instanciados por separado. El id real de `Battery.qml`/`Pipewire.qml` es `main`; `LeftSide.qml` no tiene id; `RightSide.qml` usa `miRect`; `MidSide.qml` usa `main`. Un agente encontró un comentario en `MidSide.qml` donde el autor creía que esta referencia sí resolvía ("unificado a root.height para evitar hardcodear") — sugiere que es un bug no detectado, no una decisión deliberada.
- **Efecto probable**: en `Battery.qml`/`Pipewire.qml` esto rompe el anclaje del `HoverPopup` (referencia indefinida → `NaN`/`undefined`); en `LeftSide`/`RightSide`/`MidSide` afecta el alto de las secciones de la barra.
- **Mitigación**: pasar la altura/ventana explícitamente vía `required property` (ya usado correctamente en otros componentes como `PanelPopup.qml`) en vez de depender de que un id externo cruce el límite del componente. Verificar primero visualmente si esto ya se manifiesta como un problema visible (popup mal anclado, sección de barra colapsada) o si algo más lo está compensando.

**Este es el hallazgo con mayor prioridad de verificación** — encontrado por 3 agentes distintos de forma independiente, con confianza alta.

---

## Otros hallazgos confirmados (confianza ≥80)

### [D-002] Ningún archivo con delegates usa `pragma ComponentBehavior: Bound`

- **Archivos**: `Widgets/Bar/PowerMenu.qml`, `NotificationList.qml`, `WallpaperGrid.qml`, `Widgets/Equalizer/EqControlsCard.qml`, `WifiNetworkList.qml`, `BluetoothDeviceList.qml`, `Modules/NotificationToast.qml`
- **Confianza**: 80-90/100
- **Hallazgo**: 14 archivos con `delegate:`/`Repeater` acceden a ids del scope externo (`root.cardColor`, `eq.eqBands`, `toastWindow.*`) sin la pragma, que en Qt6 hace que esas referencias se resuelvan dinámicamente en runtime en vez de estáticamente en compilación. Más lento, y frágil si algún día se extrae el delegate a un componente separado.
- **Mitigación**: agregar `pragma ComponentBehavior: Bound` como primera línea de cada archivo y declarar `required property` para lo que el delegate necesita del scope externo. Limpieza mecánica de bajo riesgo.

### [D-003] Portada de Spotify sin manejo de error de red

- **Archivo**: `Widgets/Bar/SpotifyAll.qml:85-91`
- **Confianza**: 85/100
- **Hallazgo**: la carátula se bindea directo a una URL remota (`trackData.image`) sin `onStatusChanged`/fallback si la carga falla — a diferencia de `SpotifyInfo.qml`, que sí cachea localmente por esta misma razón documentada en su propio código.
- **Mitigación**: reusar el patrón de descarga-a-caché ya existente en `SpotifyInfo.qml`, o agregar fallback a `No_cover.jpg` en `Image.Error`.

### [D-004] Búsqueda de ícono costosa evaluada en cada binding

- **Archivo**: `Widgets/Bar/MidSide.qml:176-178`
- **Confianza**: 82/100
- **Hallazgo**: `ThemeIcons.iconForAppId(...)` corre una cascada de hasta 6 estrategias (incluye fuzzy search) directamente en el binding de `source`, re-evaluada en cada cambio de ventana activa.
- **Mitigación**: cachear por `appId` (memoización en `ThemeIcons` o `readonly property` local).

---

## Investigation targets (verificación humana, ordenados por confianza)

### [I-001] `Binding.restoreMode` no seteado en sliders de Spotify (Qt6 cambió el default)

- **Archivo**: `Widgets/Bar/SpotifyAll.qml:192,263`
- **Confianza**: 65-68/100
- Posible salto visible del handle al presionar (no al arrastrar) el slider de progreso/volumen. En Qt6 el default de `Binding.restoreMode` cambió de `RestoreNone` a `RestoreBindingOrValue`.

### [I-002] `CpuService` sin manejo de `onExited`/stderr

- **Archivo**: `Services/CpuService.qml:19-29`
- **Confianza**: 65/100
- Si el binario Rust falta o no compila, el widget de CPU queda congelado en silencio, sin diagnóstico.

### [I-003] `ListView` de notificaciones sin `reuseItems`, con altura variable + Repeater anidado

- **Archivo**: `Widgets/Bar/NotificationList.qml:113-217`
- **Confianza**: 70/100
- Puede causar jank de scroll con historial grande (cap actual: 100 entradas).

### [I-004] Cálculo de alto del `NotificationList` no descuenta el banner de "sin notificaciones"

- **Archivo**: `Widgets/Bar/NotificationList.qml:113-115`
- **Confianza**: 72/100
- El propio código ya documenta este mismo problema en `WallpaperGrid.qml` pero no lo aplicó acá.

### [I-005] Íconos de notificación remotos (http/https) sin manejo de error

- **Archivos**: `NotificationList.qml:44-51`, `Modules/NotificationToast.qml:82-92`
- **Confianza**: 62/100

### [I-006] Cálculo de contraste WCAG re-ejecutado por cada `Text`, no cacheado por paleta

- **Archivo**: `Commons/Colors.qml:35-67` (usado en Battery, Cpu, BarClock)
- **Confianza**: 68/100

### [I-007] `DirectorySearchBar.qml` usa `height` fijo en vez de `implicitHeight`

- **Archivo**: `Widgets/General/DirectorySearchBar.qml:102`
- **Confianza**: 68/100
- Rompe la convención de sizing implícito usada en componentes hermanos.

### [I-008] Filas de Bluetooth/Wifi recrean estado y `Connections` en cada scroll (sin `reuseItems`)

- **Archivos**: `BluetoothDeviceRow.qml:118-134`, `WifiNetworkRow.qml:20-63`
- **Confianza**: 60/100
- Bajo impacto mientras las listas sean cortas.

### [I-009] Ids muertos sin referencias

- **Archivos**: `BarClock.qml:37,46`, `Modules/Bar.qml:46`
- **Confianza**: 61/100
- Cosmético.

### [I-010] `eqFrequencies` nunca reasignado pero no `readonly`

- **Archivo**: `Widgets/Equalizer/EqualizerBackend.qml:9`
- **Confianza**: 60/100

---

## Resumen

| Categoría | Lint | Deep | Investigate | Total |
|---|---|---|---|---|
| Bindings/root indefinido | — | 1 | — | 1 |
| ComponentBehavior/Delegates | — | 1 | 2 | 3 |
| Network/Image error handling | — | 1 | 1 | 2 |
| Performance | — | 1 | 2 | 3 |
| Process lifecycle | — | — | 1 | 1 |
| Layout/sizing | — | — | 2 | 2 |
| Migración Qt5→6 (restoreMode) | — | — | 1 | 1 |
| Cosmético | — | — | 2 | 2 |
| Lint mecánico (código propio) | 273 | — | — | 273 |
| Lint mecánico (FuzzySort.qml, vendorizado) | 206 | — | — | 206 |
| **Total** | **479** | **3** | **9** | **491** |

**Recomendación de prioridad**: arrancar por [D-001] (el bug de `root`) — es el único hallazgo con posible impacto funcional visible ahora mismo, y fue validado por 3 agentes distintos de forma independiente.

---

## Notas metodológicas

- **Fase 1 (lint determinístico)**: script Python de la skill, 47+ reglas, corrido sobre los 58 archivos. Salida completa en el historial de la sesión que generó este reporte (no adjunta acá para no duplicar 479 líneas).
- **Fase 1b (qmllint)**: descartada por falta de import path de Quickshell — solo generaba ruido de tipos no resueltos (`Process`, `PanelWindow`, etc. "not found").
- **Fase 2 (6 agentes en paralelo)**: Bindings & Properties, Layout & Anchoring, Component Loading & Lifecycle, ListView & Delegates, States & Transitions, Performance & Quality — cada uno con contexto del lint de Fase 1 para no duplicar hallazgos.
- **`Commons/FuzzySort.qml`** se excluyó del análisis de estilo profundo: es un puerto manual de la librería JS `fuzzysort` (farzher/fuzzysort), de ahí el uso masivo de `var`, igualdad laxa (`==`), etc. — estilo esperado de código vendorizado, no defecto propio.
