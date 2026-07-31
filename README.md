# DSO Dashboard — Documentación del Proyecto

> **Para el próximo Claude que trabaje en este archivo:** este README resume TODO lo construido hasta ahora en conversaciones anteriores, las decisiones de diseño, los bugs que se encontraron y corrigieron, y las cosas que el usuario debe saber (limitaciones de seguridad, credenciales hardcodeadas, etc). Léelo completo antes de tocar el código.

## Qué es esto

Un dashboard de **DSO (Days Sales Outstanding)** para análisis de Cuentas por Cobrar (AR Aging), construido como **un solo archivo HTML autocontenido** (`DSO_Dashboard.html`). No tiene backend, no tiene base de datos — todo corre en el navegador del usuario. Los datos viven solo en memoria mientras la pestaña está abierta; al recargar la página se pierden y hay que volver a cargar los archivos.

**Usuario final:** Genesis Zerpa (gzerpa@lemontech.com), empresa Lemontech.

## Stack técnico (todo vía CDN, sin build step)

- **Chart.js 4.4.1** — gráficos
- **PapaParse 5.4.1** — parseo de CSV
- **jsPDF 2.5.1** + **jsPDF-autotable 3.8.2** — generación de PDF
- **SheetJS (xlsx) 0.18.5** — generación de Excel
- **Google Fonts (Inter)** — tipografía
- Vanilla JS puro, sin frameworks, sin npm, sin bundler.

## Flujo de la app (3 pasos + dashboard)

1. **Carga de Datos** (`screen-upload`): sube CSV de AR Aging (NetSuite), ingresa manualmente el monto de ventas del mes + mes/año, y opcionalmente sube CSV de histórico de DSO.
2. **Mapeo de Columnas** (`screen-mapping`): el usuario mapea qué columna del CSV corresponde a cada campo requerido (cliente, fecha factura, fecha vencimiento, monto, saldo, moneda).
3. **Generar Dashboard** → `generateDashboard()` calcula todo y llama a `renderDashboard(...)`.
4. **Dashboard** (`screen-dashboard`): TODAS las secciones quedan siempre visibles y apiladas verticalmente (no se ocultan entre sí). La navegación por el sidebar hace **scroll suave** hacia la sección (`scrollToSection(id)`), no las oculta/muestra.

## Layout: SIDEBAR, no navbar

⚠️ Se probó un navbar horizontal en algún punto de la conversación, pero el usuario pidió explícitamente **volver al sidebar vertical**. No lo cambies a navbar de nuevo sin confirmar con el usuario.

- `.sidebar` fijo a la izquierda, fondo oscuro (`var(--ink)`), con el logo arriba, el nav en el medio, la fecha abajo.
- El nav del sidebar cambia de contenido según la etapa (`renderSidebarNav(stage)`):
  - `stage='setup'` → `NAV_SETUP` = [Carga de Datos, Mapeo de Columnas] — estos SÍ se ocultan/muestran exclusivamente vía `showScreen(id)` (es un wizard secuencial, tiene sentido que se tapen entre sí).
  - `stage='dashboard'` → `navDashboardItems()` — estos usan `scrollToSection(id)`, NO se ocultan.

### Orden de las secciones del dashboard (importante, el usuario lo pidió explícitamente)

**Resumen PRIMERO.** Orden actual en `navDashboardItems()` y en el HTML (deben coincidir):

1. **Resumen** (`sec-resumen`) — KPIs principales + calc-box con la fórmula
2. **Impacto Inactivos** (`sec-impacto`) — DSO con vs sin clientes inactivos
3. **Histórico DSO** (`sec-historico`) — solo aparece si se cargó el CSV histórico (`hasHistoricalData`)
4. **Concentración Total** (`sec-total`)
5. **Por Cartera** (`sec-cartera`) — Nacional (CLP) vs Internacional (USD)
6. **Top Clientes** (`sec-topclientes`)
7. **Clientes Churn** (`sec-churn`) — tabla con paginación/filtros
8. **Detalle de Facturas** (`sec-facturas`) — tabla con paginación/filtros
9. **Exportar** (`sec-exportar`) — checkboxes de gráficos + botones PDF/XLSX + envío a Slack

> Nota histórica: en algún punto "Histórico DSO" estuvo primero. El usuario pidió revertirlo — **Resumen siempre va primero.**

## Diseño visual

Paleta inspirada en un pantallazo de referencia de la app "TimeTracking" que el usuario compartió al inicio:

```css
--ink:#1c1c15        /* fondo sidebar, botones primarios, headers de tabla */
--olive:#6f9c3d       /* acento interactivo, focus, bordes DSO */
--olive-dark:#587c2f
--lime:#a9cf3d         /* acento brillante, logo, texto destacado en calc-box */
--forest:#3f5c34       /* acento AR */
--sage-bg:#eef3df      /* fondos suaves, filas alternadas */
--danger:#ef4444       /* vencido */
--warning:#f59e0b      /* churn */
--bg:#f5f4ec           /* fondo general cream */
--radius:16px
```

Tipografía: **Inter** (Google Fonts), pesos 400/500/600/700/800.

**Logo:** el usuario subió una imagen (hexágono/leaf verde). Se procesó para quitarle el fondo blanco (quedó transparente) y se **embebió en base64 directamente en el HTML** (no es un archivo externo) para que el dashboard siga siendo un solo archivo portable. Está en el `<img>` dentro de `.sidebar-brand`.

## Cálculo del DSO — MUY IMPORTANTE, aquí hubo bugs reales

### Fórmula base
```
DSO = (AR Total / Ventas del mes) × días del mes
```
`calcDSO(arBal, salesAmt, days)` — devuelve `null` si `arBal` o `salesAmt` son 0/falsy.

### Regla de redondeo (pedida explícitamente por el usuario, cambió 2 veces)

**Regla final y vigente:** el DSO **siempre redondea hacia arriba al entero siguiente**, sin importar qué tan chico sea el decimal. Ejemplo: 10.1 → 11, 10.9 → 11. Si el número ya es un entero exacto (10.0), se queda en 10.

```js
function roundUpDSO(x){return Math.ceil(x-1e-9);}
```

El `-1e-9` es un guard contra el ruido de coma flotante de JS: sin él, un valor que matemáticamente debería ser exactamente 10.0 pero que la división de floats representa como `10.000000000002` se redondearía mal hacia 11. Restar un epsilon minúsculo antes de `Math.ceil` neutraliza ese ruido sin afectar decimales reales.

`fmtDSO(v)` es el formateador de display — SIEMPRE usar esta función (o `roundUpDSO` directamente) para mostrar cualquier valor de DSO. **Nunca** concatenar un número crudo de DSO en el HTML sin pasar por `fmtDSO`/`roundUpDSO` primero.

⚠️ **Historial de cambios de esta regla** (por si el usuario pide volver a algo anterior):
1. Primero fue `Math.round()` normal (redondeo estándar, entero).
2. Luego se pidió agregar 1 decimal (`toFixed(1)`) — se implementó en TODOS los KPIs, gráficos, tooltips, exports PDF/XLSX.
3. Luego se pidió volver a enteros — se revirtió todo lo del punto 2.
4. Luego se pidió "redondeo al entero siguiente, ej 10.5→11" — inicialmente interpretado como "round half up" (`Math.floor(x+0.5+1e-9)`), que YA es el comportamiento default de `Math.round` en JS para positivos.
5. Finalmente el usuario aclaró: es SIEMPRE hacia arriba (ceiling), no solo para el .5 — ej 10.1→11. Se cambió a `Math.ceil` con el guard de epsilon. **Esta es la regla vigente.**

### Bug encontrado y corregido #1 — "Impacto Inactivos" siempre daba el mismo DSO

En el cálculo de "DSO sin inactivos" se reducía proporcionalmente **tanto el AR como las Ventas** por el mismo % (el % que representa el AR de clientes inactivos). Matemáticamente eso se cancela: `(AR×(1-p)) / (Ventas×(1-p)) = AR/Ventas` — el factor `(1-p)` se anula y el resultado es idéntico sin importar cuántos inactivos haya.

**Fix:** las Ventas del mes son un dato único de la empresa (no varían por cliente), así que se dejan **fijas**, y solo se recalcula el AR del numerador excluyendo el saldo de clientes inactivos:

```js
const dsoConInactivos = dsoTotal; // AR total / Ventas × días
const dsoSinInactivos = calcDSO(totalARBal - churnARBal, manualSales, daysInMonth); // AR activo / MISMAS Ventas × días
```

### Bug encontrado y corregido #2 — inconsistencia en el histórico de DSO

Los valores del **CSV de histórico** subido por el usuario se parseaban con `parseFloat()` crudo, SIN pasar por `roundUpDSO`. Esto rompía la aritmética al mostrar KPIs derivados: por ejemplo con valores crudos 45.1 y 45.9, el dashboard mostraba "DSO inicial: 46, DSO actual: 46, pero Variación: +1" — contradictorio, porque redondear cada número por separado y luego restar no da lo mismo que restar primero y redondear después.

**Fix:** el redondeo se aplica **una sola vez, al momento de leer el dato** (tanto para el histórico importado como para el punto actual calculado), y todo lo demás (deltas, gráficos, tooltips) opera sobre esos enteros ya consistentes:

```js
histData = rawHist.map(row => {
  const vals = Object.values(row);
  return { label: ..., dso: roundUpDSO(parseFloat(vals[1])) }; // <- redondeo al leer, no al mostrar
}).filter(r => r.label && !isNaN(r.dso));
```

**Regla general para el próximo Claude:** si agregas cualquier nueva fuente de datos de DSO (otro CSV, otro cálculo derivado), redondea SIEMPRE al momento de generar/leer el valor, nunca solo al mostrarlo — para que las operaciones aritméticas posteriores (restas, sumas, comparaciones) sean consistentes con lo que se ve en pantalla.

## ¿Cómo se detectan los clientes "inactivos" / churn?

**Esto es una heurística muy básica, no una columna de estado real:**

```js
const isChurn = cn.toLowerCase().includes('inactivo');
```

Donde `cn` es el nombre del cliente (columna mapeada en el Paso 2). Si el nombre del cliente contiene la palabra "inactivo" (sin importar mayúsculas), se marca como churn/inactivo. No hay ninguna columna de fecha de última compra ni de estado explícito involucrada. Esto depende 100% de que la convención de nombres en NetSuite del usuario incluya esa palabra.

El usuario preguntó por esto y quedó conforme, pero si en el futuro pide "detectar inactivos de otra forma" (por columna de estado, por antigüedad sin compras, etc.), este es el único lugar donde se define `isChurn` — está en `generateDashboard()`, en el `.map()` que construye el array `invoices`.

## Sección "Impacto Inactivos" (`sec-impacto`)

Feature completa agregada a pedido del usuario para medir cuánto infla el DSO la cartera de clientes inactivos (más difícil de cobrar). Muestra:
- 4 KPIs: DSO con inactivos, DSO sin inactivos, Impacto (diferencia en días), AR de inactivos ($ y %)
- Gráfico de barras comparando ambos escenarios (`chartInactiveImpact`)
- Texto explicativo autogenerado (`#impactoTexto`)

También está integrada en:
- El panel de exportación de gráficos (checkbox "Impacto Inactivos en DSO")
- El informe PDF gerencial (con su propia interpretación en `chartInsight()`)
- El XLSX (hoja "ImpactoInactivos")

## Tablas de datos (Clientes Churn y Detalle de Facturas)

Ambas usan el mismo motor genérico `createTable(id, cfg)` (buscar esa función). Cada tabla tiene:
- Buscador de texto (`#{id}Search`)
- Filtros por select (`data-table="{id}"` + `data-filter="campo"`)
- Selección de filas con checkboxes (`.row-chk`) + "seleccionar todo" (`#{id}SelectAll`)
- Paginación (`#{id}PageSize`, `#{id}Prev`, `#{id}Next`, `#{id}PageIndicator`, `#{id}Info`)
- Exportar PDF/XLSX de la selección (o de todo lo filtrado si no hay selección): `exportTableData(id, format)`

**Importante:** `createTable()` usa `freshEl()`/`freshAll()` para clonar los elementos del DOM antes de adjuntar listeners — esto es para evitar que se acumulen event listeners duplicados si `generateDashboard()` se vuelve a ejecutar en la misma sesión (el usuario puede volver a "Carga de Datos" y generar un dashboard nuevo sin recargar la página).

## Exportación de gráficos — Informe PDF "gerencial"

El usuario pidió explícitamente que el PDF de fuentes de gráficos sea:
- Tamaño **Carta (Letter)**, no A4
- Estilo "informe gerencial": portada, explicación en prosa, KPIs, tablas — no solo una tabla pelada
- Adaptativo a páginas (salta de página sola si no cabe)
- Mismo estilo visual que el dashboard (colores, tipografía)

Todo esto vive en las funciones `pdfDrawHeader`, `pdfEnsureSpace`, `pdfSectionTitle`, `pdfParagraph`, `pdfKpiRow`, y el generador de insights `chartInsight(key, src)` que escribe un párrafo interpretativo distinto según el tipo de gráfico (vencido/aging/topClientes/historical/impacto). Si agregas un nuevo tipo de gráfico exportable, tienes que:
1. Agregarlo a `exportSources` (dentro de `renderDashboard`)
2. Agregarlo a `CHART_TITLES`
3. Agregarlo a `chartLabels` (el dict que arma los checkboxes del panel)
4. Agregar un caso en `chartInsight()` para que tenga interpretación propia en el PDF

## Integración con Slack (Opción A — solo push, sin bot bidireccional)

Se ofrecieron 2 opciones al usuario:
- **A) Botón que empuja un resumen a Slack** — esto es lo que se implementó.
- **B) Bot que responde preguntas en Slack** — requeriría backend/servidor propio, NO se implementó (está fuera del alcance de un archivo HTML estático). Si el usuario lo pide, hay que explicarle que se necesita hosting externo (Render/Railway/Vercel/Cloud Function) y que Claude no puede desplegarlo desde este entorno.

Implementación de la Opción A (`sendSlackSummary()`, sección Exportar):
- El usuario pega su **Incoming Webhook URL** de Slack en un input (`#slackWebhookUrl`) — NO se guarda en ningún lado (ni localStorage, ni backend), solo vive en memoria durante la sesión. Hay que volver a pegarla cada vez que se abre el archivo.
- Se manda un mensaje con Slack Block Kit con: DSO Total, AR, % Vencido, Churn, el bloque de Impacto Inactivos, y DSO Nacional/Internacional.
- **Truco técnico importante:** se usa `fetch(url, {mode:'no-cors', headers:{'Content-Type':'text/plain'}, body: JSON.stringify(payload)})`. El `mode:'no-cors'` + `Content-Type: text/plain` evita el preflight CORS que el navegador bloquearía si se mandara como `application/json` desde un archivo local. La consecuencia es que la respuesta queda "opaca" — **no se puede confirmar desde el navegador si Slack realmente recibió el mensaje**, solo si la petición de red se disparó sin error. Esto se le explicó al usuario.

## Login — Supabase Auth (actualizado, ya NO es el candado hardcodeado)

**⚠️ CAMBIO IMPORTANTE (julio 2026):** el login dejó de comparar un usuario/contraseña hardcodeados en el código. Ahora usa **Supabase Auth** (`supabase.auth.signInWithPassword`). El `AUTH_USER`/`AUTH_PASS` en texto plano fue eliminado.

```js
const SUPABASE_URL = 'https://rupmnortthcjyqlioxqz.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'; // ya completado en index.html
const supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
```

✅ Estos dos valores ya están completados en `index.html` (proyecto `rupmnortthcjyqlioxqz`). Falta un solo paso manual:
1. ✅ Proyecto creado, URL y anon key ya pegados en `index.html`.
2. En **Authentication → Providers**, verificar que "Email" esté habilitado (viene así por defecto).
3. ⬜ **Pendiente:** en **Authentication → Users**, crear manualmente el usuario `gzerpa@lemontech.com` con una contraseña nueva (o invitarlo por correo). Ya no se usa `Lemontech2026` — sin este paso el login no va a funcionar porque todavía no existe ningún usuario en el proyecto de Supabase.
4. (Opcional, recomendado) En **Authentication → Settings**, desactivar "Confirm email" si no se quiere el paso de verificación por correo para un usuario único interno.

Funciones relevantes en el código:
- `handleLogin(e)` — llama a `supabaseClient.auth.signInWithPassword()`.
- `handleLogout()` — botón "Cerrar sesión" en el pie del sidebar.
- `initAuth()` + `onAuthStateChange` — revisan si ya hay sesión activa al cargar la página (Supabase guarda el token de sesión en el navegador), para no pedir login en cada visita.

**Notas de seguridad que siguen vigentes:**
- Esto es autenticación real (no se puede "saltar" inspeccionando el DOM como antes), pero el dashboard sigue siendo un archivo estático sin backend propio — los datos de AR/DSO que el usuario carga siguen viviendo solo en memoria del navegador, no se guardan en Supabase todavía. Si más adelante se pide persistir esos datos, es un cambio aparte (tablas + RLS en Supabase, ya no solo Auth).
- El anon key va embebido en el HTML público — es esperado y seguro para Supabase siempre que las tablas tengan Row Level Security activada (no aplica aún porque no hay tablas).

## Despliegue

Repo pensado para vivir en GitHub y desplegarse en Vercel como sitio estático (no requiere build step, `index.html` es la raíz).

1. **GitHub:** el repo ya existe → https://github.com/genesiszerpa/DSO-analytics. Desde esta carpeta:
   ```bash
   git init
   git add .
   git commit -m "Initial commit: DSO dashboard con Supabase Auth"
   git branch -M main
   git remote add origin https://github.com/genesiszerpa/DSO-analytics.git
   git push -u origin main
   ```
   (Git te pedirá autenticarte — usa un Personal Access Token de GitHub como contraseña, no tu password normal de la cuenta.)
2. **Vercel:** en https://vercel.com/new, importar el repo de GitHub. No requiere configurar build command ni output directory (Vercel detecta el `index.html` estático automáticamente; si pregunta, Framework Preset = "Other").
3. Después de cada `git push` a `main`, Vercel redeploya solo.

## Cosas que el usuario pidió y luego revirtió (para no repetir el mismo camino)

1. **Navbar horizontal** → el usuario lo probó y pidió volver a **sidebar vertical**. No cambiar sin confirmar.
2. **"Histórico DSO" como primera sección** → el usuario luego pidió que **"Resumen" fuera primero**. El orden vigente está documentado arriba.
3. **DSO con 1 decimal** → se implementó y luego se revirtió a enteros, y finalmente se fijó la regla de "siempre redondea hacia arriba" (ver sección de cálculo del DSO arriba).

## Estructura de archivos de este proyecto

- `DSO_Dashboard.html` — el archivo único y final, lista para entregar/abrir. **Todo vive aquí** (HTML + CSS + JS inline, logo en base64, sin dependencias locales).
- Este `README.md` — este mismo documento.

## Ideas pendientes / que se ofrecieron pero no se pidieron todavía

- Scroll-spy en el sidebar (resaltar automáticamente la sección visible mientras se hace scroll manual, sin clic) — se ofreció, el usuario no lo pidió aún.
- Bot de Slack bidireccional (Opción B) — requiere backend externo.
- Detección de clientes inactivos por otro método (columna de estado explícita, antigüedad sin compras) en vez del substring "inactivo" en el nombre.
- Persistencia de la URL del webhook de Slack entre sesiones.
- Renombrar "Con inactivos" / "Sin inactivos" a algo más explícito como "DSO Total (Activos + Inactivos)" / "DSO Solo Activos" — se ofreció, no se pidió.

## Convenciones de código a mantener

- CSS con variables en `:root` — reusar la paleta existente, no inventar colores nuevos sueltos.
- Todo en español (labels, mensajes de error, textos de UI) — el usuario y su equipo trabajan en español.
- Formato de moneda: `fmtFull()` / `fmt()` (con sufijos K/M) — no usar `toLocaleString` crudo en otros lados.
- Formato de fecha: `fmtDate()` — formato `es-CL`.
- Cualquier valor de DSO: pasar siempre por `fmtDSO()` o `roundUpDSO()`, nunca mostrar un número crudo.
- No usar `localStorage`/`sessionStorage` salvo que el usuario lo pida explícitamente y entienda el trade-off (puede fallar en preview de Claude.ai).
