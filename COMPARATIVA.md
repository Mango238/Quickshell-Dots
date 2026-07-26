# Dónde está tu config hoy, y qué le falta para caelestia/DMS

Comparación de `~/.config/quickshell` (63 archivos, barra + ecualizador + lock screen + theming propio) contra **caelestia-dots/shell** y **AvengeMedia/DankMaterialShell** — las dos referencias que nombraste — más un vistazo liviano a end-4/dots-hyprland y noctalia.

*2026-07-23 · Hyprland · Arch · Quickshell 0.3.0 · fuente: lectura directa de archivos + repos en GitHub*

---

## 1. Panorama

Tu config ya tiene decisiones correctas que caelestia y DMS también toman — paleta derivada del wallpaper vía `ColorQuantizer`, singletons perezosos, popups que se instancian bajo demanda. La brecha no es de talento, es de **capas que faltan por completo**, no de calidad de lo que ya existe.

| Dimensión | Tu config | caelestia | DankMaterialShell |
|---|---|---|---|
| Config de usuario | hardcodeada en QML | ✅ JSON + watch | ✅ JSON + watch |
| UI de settings | no existe | ✅ "Nexus" | ✅ Modules/Settings |
| Theming wallpaper→paleta | ✅ `ColorQuantizer` propio | matugen externo | matugen externo |
| Tokens de animación | ad hoc, sin singleton | ✅ `Anim.qml` | ✅ `Anims.qml` |
| IPC externo | ❌ 0 `IpcHandler` | CLI dedicado | ✅ `DMSShellIPC.qml`, ~27 targets |
| Multi-compositor | Hyprland (único uso real) | Hyprland only | Hypr/Niri/Mango/Labwc |
| Sistema de plugins | n/a | n/a | ✅ sí, con registry público |
| Lint en CI | ninguno | ✅ qmllint vía `qs -p .` | `make lint-qml` |
| Diferenciador propio | **ecualizador PipeWire + CPU en Rust** — ninguna de las dos tiene esto | — | — |

---

## 2. Lo que ya está a la altura

Vale nombrarlo porque el instinto al comparar contra proyectos de 7-10k estrellas es sentir que hay que reescribir todo. No es así — esto ya compite:

**Funciones de contraste WCAG en `Colors.readableOn()` / `ensureReadable()`**
Ni caelestia ni DMS resuelven legibilidad texto/fondo con un ratio WCAG real y ajuste mínimo por bisección — ambos se apoyan en roles Material 3 fijos. Tu enfoque deriva el color legible directamente de la paleta del wallpaper, que es más difícil de acertar y lo tenés funcionando.
*`Commons/Colors.qml`*

**Popups perezosos + scoping por monitor en `PopupState`**
El patrón `Loader { active: contentActive }` para no instanciar ×3 (por monitor) el contenido pesado — y `isOpenOn(name, screen)` para que un popup abierto en un monitor no aparezca duplicado en los otros — es exactamente el tipo de detalle de RAM-en-reposo que caelestia resuelve con más código (`GSFLoader`/`ServiceLoader` dedicados). El tuyo lo hace con un singleton de 30 líneas.
*`Services/PopupState.qml` · `Modules/Bar.qml`*

**`ThemeSync` propaga la paleta fuera de Quickshell con debounce**
kitty + Hyprland + starship (con templates de usuario) desde un solo write coalescido. Es el mismo problema que matugen resuelve para caelestia/DMS, salvo que ahí matugen es una dependencia externa y acá es 150 líneas de QML que ya controlás vos.
*`Services/ThemeSync.qml`*

**Ecualizador paramétrico sobre PipeWire filter-chain**
Ninguna de las dos referencias tiene esto. Es tu feature real, no un "me too" del ecosistema Material-You — vale destacarlo si en algún momento el repo se vuelve público.
*`eq/` · `scripts/eq_filter_chain.sh` · `Widgets/Equalizer/`*

---

## 3. Las brechas reales

En orden de qué tan seguido te va a doler no tenerlo.

| Falta | Síntoma hoy | Cómo lo resuelven ellos |
|---|---|---|
| Tokens de animación centralizados | 27 archivos usan `Behavior`/`NumberAnimation` con duración y easing decididos caso a caso — cero de esos números están relacionados entre sí. | caelestia: `components/Anim.qml` con 4 duraciones estándar + 6 curvas "expressive" M3. DMS: `Common/Anims.qml` (`durShort/durMed/durLong` + set completo de easings M3). |
| IPC externo | `PopupState.toggle()` solo es alcanzable desde `GlobalShortcut` dentro de `shell.qml`. No podés abrir el wallpaper picker, el eq o el power menu desde un script, un keybind alternativo, o waybar-style tooling. | DMS: `DMSShellIPC.qml`, un archivo, ~27 `IpcHandler` targets, invocables como `dms ipc call launcher toggle`. |
| Números mágicos fuera de QML | `Modules/Bar.qml` tiene `panelHeight: 208 // 4 filas × 40 + 3×8 + 2×12` y offsets ajustados "a ojo" (comentario propio: *"ajustar a gusto"*) repetidos en cada `PanelPopup`. | Ambos externalizan spacing/radius/duración a un archivo de config versionado aparte del componente que lo consume. |
| `Qt5Compat.GraphicalEffects` (legacy) | 4 archivos siguen en el shim de compatibilidad Qt5 en vez de `MultiEffect`/`layer.effect` nativos de Qt6 — más lento y con ciclo de vida distinto al resto del árbol de render. | Ninguna referencia moderna usa Qt5Compat; es exactamente el tipo de API que tu propio CLAUDE.md pide verificar contra Qt6 antes de asumir. |
| Lint automatizado | Nada corre `qmllint` hoy — los errores de tipo se descubren recién al ejecutar quickshell. | caelestia genera los import paths con `qs -p .` y se los pasa a `qmllint --import disable -I <paths>` en CI. Reusable sin CI: es un script de una línea. |

---

## 4. Hoja de ruta

Ordenada por impacto sobre esfuerzo, no por lo espectacular que suena. Los primeros tres cambian cómo se siente *trabajar* en el repo; los últimos cambian cómo se ve.

1. **Crear `Commons/Anim.qml` con duraciones + easings** — *esfuerzo bajo*
   Un singleton con 3-4 duraciones nombradas y 2-3 curvas de easing. Cada `Behavior on X` nuevo referencia eso en vez de inventar un número. No toca ningún archivo existente hasta que empezás a migrarlos — se puede introducir sin romper nada.

2. **Agregar 3-4 `IpcHandler` en `shell.qml`** — *esfuerzo bajo*
   Exponer `wallpaper toggle`, `eq toggle`, `power toggle`, `notifications toggle` como targets IPC. Reutiliza `PopupState.toggle()` que ya existe — es literalmente envolver la función que ya tenés en un handler. Desbloquea keybinds alternativos y scripting sin agregar GlobalShortcuts nuevos.

3. **Sacar los números mágicos de `Bar.qml` a un `Commons/Layout.qml`** — *esfuerzo medio*
   Radius, alturas de popup, offsets — a properties nombradas (`Layout.popupRadius`, etc.). No hace falta un sistema de config con archivo externo todavía: el problema hoy es que los números están duplicados y sin nombre, no que estén en QML.

4. **Migrar los 4 archivos de `Qt5Compat.GraphicalEffects` a `MultiEffect`** — *esfuerzo medio*
   Verificar cada propiedad contra la doc Qt6 (regla de tu propio CLAUDE.md) antes de reescribir — `DropShadow`/`FastBlur` no mapean 1:1. Vale hacerlo de a un archivo, probando `qs` después de cada uno.

5. **Script local de `qmllint` usando `qs -p .`** — *esfuerzo bajo*
   El truco de caelestia: `qs -p .` genera los import paths reales de tu instalación de Quickshell, se los pasás a `qmllint`. Un script de 5 líneas en `scripts/`, sin CI todavía.

6. **JSON externo para lo que hoy son "decisiones del usuario" comentadas en QML** — *esfuerzo alto*
   Cosas como el kitty background fijo en `ThemeSync` o los defaults del eq ya están documentadas como decisiones explícitas en comentarios — moverlas a un JSON con watch (patrón `FileView` que ya usás en `Colors.qml`) las hace editables sin tocar código. Recién acá se empieza a parecer al `shell.json` de caelestia.

### No priorizado (a propósito)

- **UI de settings in-app** — "Nexus" y `Modules/Settings` existen porque caelestia y DMS son proyectos públicos con miles de usuarios que no van a editar QML. Para una config personal de un solo usuario, el paso 6 (JSON + comentarios) da el 90% del beneficio por una fracción del esfuerzo — construir una UI de settings acá sería sobre-ingeniería.
- **Sistema de plugins** — tiene sentido en DMS porque alimenta un registry público de terceros. Sin eso, es abstracción especulativa: una interfaz con un único implementador.
- **Abstracción multi-compositor (Hyprland/Niri/...)** — solo usás Hyprland. La capa de servicios por compositor de DMS existe porque su base de usuarios no. No es una brecha, es una feature que no necesitás.

---

*Fuentes: lectura directa de `~/.config/quickshell` (README.md, shell.qml, Commons/Colors.qml, Services/PopupState.qml, Services/ThemeSync.qml, Modules/Bar.qml, grep de IpcHandler/Behavior/Qt5Compat) · github.com/caelestia-dots/shell · github.com/AvengeMedia/DankMaterialShell · github.com/end-4/dots-hyprland (referencia liviana) · github.com/noctalia-dev/noctalia (divergió de Quickshell upstream, comparación estructural limitada)*
