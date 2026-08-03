# DSO Dashboard — Documentación del Proyecto

> **Para el próximo Claude que trabaje en este archivo:** este README resume TODO lo construido hasta ahora en conversaciones anteriores, las decisiones de diseño, los bugs que se encontraron y corrigieron, y las cosas que el usuario debe saber (limitaciones de seguridad, credenciales hardcodeadas, etc). Léelo completo antes de tocar el código.

## Estado del repo (actualizado — ahora conectado a Supabase)

**Repo:** https://github.com/genesiszerpa/DSO-analytics
**Backend:** Supabase (Postgres + Auth) — ver `supabase/`

- **Archivo principal:** `index.html` (todo el HTML/CSS/JS vive en un solo archivo — ver detalle técnico completo más abajo). Se usa el nombre `index.html` a propósito: es la convención que GitHub Pages, Vercel y Netlify esperan por default en la raíz del repo, así que sirve el sitio sin configuración extra apenas se conecte el hosting.
- **Sin build step:** no hay `package.json`, no hay bundler. Es HTML puro + librerías cargadas por CDN (Chart.js, jsPDF, SheetJS, Google Fonts, supabase-js). Cualquier hosting estático (GitHub Pages, Vercel, Netlify, Cloudflare Pages) lo sirve tal cual, sin pasos de build.
- **⚠️ Ya NO usa `localStorage` ni `AUTH_USERS` hardcodeado.** El usuario pidió explícitamente migrar a Supabase y proporcionó las credenciales de su proyecto (`SUPABASE_URL`/`SUPABASE_ANON_KEY`, ya están en `index.html`). Todo lo que antes se guardaba en el navegador ("Mis Análisis") ahora vive en una base de datos Postgres compartida, y el login usa Supabase Auth real. **Ver la carpeta `supabase/`** para el detalle completo:
  - `supabase/schema.sql` — el esquema (tablas `profiles` y `analyses`, políticas RLS, triggers). Ya se corrió en el proyecto del usuario.
  - `supabase/SETUP.md` — guía paso a paso de configuración del lado de Supabase (crear proyecto, usuarios, roles). Los pasos 1-6 (crear proyecto, correr esquema, crear los 3 usuarios y asignarles rol) son responsabilidad del usuario, hechos fuera de este repo — Claude nunca tuvo ni tiene acceso a esas credenciales de administración.
  - `supabase/MIGRATION_PLAN.md` — el detalle técnico exacto de qué función cambió y por qué (útil para depurar). **Ya está aplicado**, no es un plan a futuro.
  - Ver la sección "Persistencia (Supabase)" más abajo en este documento para el resumen de la arquitectura resultante.

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

## Flujo de la app (Inicio + 3 pasos + dashboard)

0. **Inicio** (`screen-home`): pantalla de aterrizaje con la tabla de "Mis Análisis" guardados anteriormente (ver sección de Multi-localidad → tabla más abajo). Es la pantalla con la que arranca la app.
1. **Carga de Datos** (`screen-upload`): elige Localidad, sube el/los archivo(s) de AR Aging (NetSuite) — **CSV, XLSX o XLS** son válidos (ver `setupDrop()`, que detecta la extensión y usa PapaParse o SheetJS según corresponda), ingresa manualmente el/los monto(s) de ventas del mes + mes/año, y opcionalmente sube un archivo de histórico de DSO (solo Chile — ver Multi-localidad).
2. **Mapeo de Columnas** (`screen-mapping`): el usuario mapea qué columna del archivo corresponde a cada campo requerido (cliente, fecha factura, fecha vencimiento, monto, saldo, moneda — esta última opcional en modo dual-moneda, ver Multi-localidad).
3. **Generar Dashboard** → `generateDashboard()` calcula todo y llama a `renderDashboard(...)`. ⚠️ Ya NO guarda automáticamente — el guardado es una acción explícita (botón "💾 Guardar DSO" en Resumen, ver sección de Persistencia más abajo).
4. **Dashboard** (`screen-dashboard`): TODAS las secciones quedan siempre visibles y apiladas verticalmente (no se ocultan entre sí). La navegación por el sidebar hace **scroll suave** hacia la sección (`scrollToSection(id)`), no las oculta/muestra.

## Multi-localidad: Chile / Perú / México — agregado a pedido del usuario

El usuario pidió separar el análisis por localidad: *"lo que hicimos es Chile, debes crear un importador para Perú... para México igual"*. No se creó un "importador" separado por país (mismo flujo de carga/mapeo de columnas para los 3) — en cambio, se agregó una **dimensión de Localidad** que se elige al principio del flujo y que determina moneda, si se pide histórico manual, y la clave de guardado.

### Configuración (`LOCALITIES`)

```js
const LOCALITIES={
  chile:{label:'Chile',flag:'🇨🇱',currencySymbol:'$',currencyName:'pesos chilenos',showHistoricalUpload:true},
  peru:{label:'Perú',flag:'🇵🇪',currencySymbol:'S/',currencyName:'soles',showHistoricalUpload:false},
  mexico:{label:'México',flag:'🇲🇽',currencySymbol:'$',currencyName:'pesos mexicanos',showHistoricalUpload:false}
};
```

- **Selector de Localidad** (`.locality-picker`, función `selectLocality(key)`) — primera tarjeta de la pantalla "Carga de Datos". Al cambiar, actualiza: el prefijo/label del campo de ventas (moneda), y muestra/oculta la tarjeta de "Histórico de DSO".
- **`selectedLocality`** — localidad elegida en el formulario de carga (variable global, default `'chile'`).
- **`currentLocality`** — localidad del análisis que está actualmente renderizado en el dashboard (puede diferir de `selectedLocality` si se abrió un análisis guardado de otra localidad desde "Mis Análisis").

### ⚠️ Chile SÍ pide histórico manual, Perú y México NO

El usuario fue explícito: *"sin histórico porque el histórico se irá construyendo mes a mes"*. Esto se implementó así:

- **Chile** (`showHistoricalUpload:true`): mantiene el CSV opcional de histórico de DSO tal como estaba antes de esta feature (sin cambios, para no arriesgar el flujo ya probado).
- **Perú y México** (`showHistoricalUpload:false`): NO se muestra la tarjeta de carga de histórico (se oculta `#histCard`, se muestra en su lugar `#histAutoNote` con una nota explicativa). En su lugar, la función `buildAutoHistorical(locality, excludeMonth, excludeYear)` construye el histórico **leyendo los análisis ya guardados de esa misma localidad** (filtra por `locality`, excluye el período que se está generando en este momento para no duplicarlo, ordena cronológicamente). El primer mes que se guarda para Perú/México va a mostrar un histórico de un solo punto — es esperado, se va llenando a medida que se guarda cada mes con "Guardar DSO".

### Botón "💾 Guardar DSO" — ya NO hay autoguardado silencioso

Antes, `generateDashboard()` guardaba automáticamente al terminar de renderizar. El usuario pidió que hubiera un **botón explícito** ("la carga que se genere debe tener un botón que diga Guardar DSO, y eso será lo que se verá en análisis anteriores"). Cambios:

- `generateDashboard()` ya **no llama a `saveCurrentAnalysis()`**. Solo calcula, renderiza, y guarda los parámetros del cálculo en `lastGenerated` (variable global) — el dashboard se ve, pero no queda persistido todavía.
- Hay un botón **"💾 Guardar DSO"** (`#btnSaveDSO`) en el `page-head` de la sección Resumen, que llama a `saveDSO()`. Esa función toma `lastGenerated`, llama a `saveCurrentAnalysis(...)`, actualiza `currentAnalysisId`, refresca el sidebar, y da feedback visual (el botón cambia a "✅ Guardado" por ~1.8s).
- Al **abrir un análisis guardado** desde "Mis Análisis" (`openSavedAnalysis`), también se reconstruye `lastGenerated` — así el botón "Guardar DSO" sigue funcionando ahí también (por si se quiere re-confirmar/sobrescribir, aunque sería un guardado idéntico — no rompe nada, es idempotente).

### Clave de unicidad: período (mes+año) + localidad

El usuario pidió explícitamente: *"debe existir solo un análisis por período y por localidad, si hay una guardada y se guarda la última, esta reemplaza la anterior"*. `saveCurrentAnalysis(...)` ahora recibe un parámetro `locality` y el filtro de deduplicación es:

```js
let list=loadSavedAnalyses().filter(a=>!(a.params.dsoMonth===dsoMonth&&a.params.dsoYear===dsoYear&&a.locality===locality));
```

Esto permite que **coexistan** Chile-Junio-2026, Perú-Junio-2026 y México-Junio-2026 (mismo período, distinta localidad → 3 análisis separados), pero si se guarda Chile-Junio-2026 dos veces, la segunda **reemplaza** a la primera.

### "Mis Análisis" ahora se ve agrupado por período (mes)

El usuario pidió explícitamente: *"en análisis anteriores debe verse por periodo (mes)"*. `renderHomeList()` ahora:

1. Filtra por búsqueda (si hay query).
2. Agrupa el resultado con `groupSavedByPeriod(list)` → un objeto por cada combinación única de mes+año, con sus items (1 a 3, uno por localidad) ordenados según `LOCALITY_ORDER=['chile','peru','mexico']`.
3. Renderiza un encabezado de período (`.home-period-head`, ej. "Junio 2026") seguido de las tarjetas de cada localidad de ese período (`.home-period-cards`).
4. El selector de orden (`#homeSortSelect`) ahora solo tiene 2 opciones — **orden de períodos** (más recientes / más antiguos primero) — se quitaron las opciones de "mayor/menor DSO" que existían antes de esta feature, porque no tenía sentido combinarlas con el agrupado por período (mezclaría los grupos). Si se necesita ordenar por DSO en el futuro, probablemente tenga más sentido como un sub-orden dentro de cada grupo de período, no como reemplazo del agrupado.

Cada tarjeta dentro de un grupo de período ya no repite el mes/año en el título (eso ahora vive en el encabezado del grupo) — el título de la tarjeta es solo la localidad (`🇨🇱 Chile`, `🇵🇪 Perú`, `🇲🇽 México`).

### Descargar informe (PDF por tarjeta) y exportar todo (XLSX global)

El usuario pidió: *"al lado del ojo debe existir una opción de descargar el informe que se genera en PDF y también se debe poder descargar en global en xlsx"*. Se agregaron dos exports nuevos, distintos entre sí:

**1. Botón 📄 por tarjeta (`downloadAnalysisPDF(id)`)** — junto al 👁️ y al 🗑️ en cada tarjeta de "Mis Análisis". Genera el mismo informe PDF "gerencial" (tamaño Carta, con interpretación automática por sección) que ya existía en la sección Exportar — pero calculado **directamente desde los datos guardados de ESE análisis específico**, sin necesidad de abrirlo primero. Esto requería poder recalcular las fuentes de gráficos (vencido/vigente, antigüedad, top clientes, impacto de inactivos) sin tocar el DOM ni los canvases — para eso se creó:

```js
function computeExportSourcesFromParams(p){ ... }
```

Toma `entry.params` (los datos ya guardados) y devuelve el mismo objeto `exportSources` que normalmente se construye dentro de `renderDashboard()`, pero de forma **standalone** (pura función de datos → datos, sin efectos secundarios sobre la UI). Esto es posible porque las facturas guardadas ya tienen todos los campos numéricos que hacen falta (`balance`, `isVencida`, `isChurn`, `daysOverdue`, `portfolio`, `cn`) — no hace falta reconstruir los `Date` ni re-renderizar nada en pantalla.

**2. Refactor de la generación de informes** — la lógica que antes vivía solo dentro de `exportSelectedCharts()` se extrajo a dos funciones reutilizables:
- `buildInformePDF(sources, keys, reportTitle, periodLabel, filename)`
- `buildInformeXLSX(sources, keys, periodLabel, filename)`

`exportSelectedCharts()` (el botón de la sección Exportar, que sigue funcionando igual que antes) ahora es solo un wrapper delgado sobre estas dos funciones. Si se agrega un nuevo tipo de gráfico/fuente exportable en el futuro, **actualizar `CHART_TITLES` y `chartInsight()` es suficiente** — ambos puntos de entrada (exportar desde pantalla, exportar por tarjeta) los usan automáticamente.

### ⚠️ CAMBIO IMPORTANTE: "Mis Análisis" ya NO se ve en el sidebar — pasó a ser una tabla propia

El usuario pidió explícitamente revertir el diseño anterior: *"Mis análisis no debería verse el detalle en el sidebar, debiese ser en una pantalla tipo listas, con paginadores y filtros"*. Esto significa que **todo lo relacionado a `renderSidebarRecent()`, `shortLabel`, `MAX_RECENT_IN_SIDEBAR`, tarjetas (`.home-card`), `renderHomeList()` y `downloadAllAnalysesXLSX()` YA NO EXISTE** — se eliminó por completo. Si ves código o instrucciones de una sesión anterior que lo mencionen, están desactualizadas.

**Estado actual del sidebar (elementos permanentes):**
- Logo clickeable (`onclick="goHome()"`).
- Botón **"+ Nuevo Análisis"** (`.sidebar-cta`).
- Botón **"📋 Mis Análisis"** (`.sidebar-permanent-link`, estilo `.nav-item` pero estático, no gestionado por `renderSidebarNav`) — sin ningún detalle, solo el enlace.
- Divider.
- Nav de fase (`#sidebarNav`, igual que antes).
- Fecha + badge de usuario/rol + botón de logout al pie.

**"Mis Análisis" (`screen-home`) es una tabla real**, construida con el mismo motor genérico `createTable()` que ya usan las tablas de "Clientes Churn" y "Detalle de Facturas" (ver la sección de esas tablas más abajo). Función: `refreshMisAnalisisTable()`.

- **Columnas:** Localidad (con bandera), Período, DSO, AR Total, % Vencido, Churn, Facturas, Generado, Acciones.
- **Buscador** (`#misAnalisisSearch`) — por texto del `label` (que incluye localidad + mes + año).
- **Filtros** — por localidad (`#misAnalisisFilterLocalidad`, Todas/Chile/Perú/México) y por **período** (`#misAnalisisFilterPeriodo`, a pedido explícito del usuario). Las opciones del filtro de período se generan **dinámicamente** dentro de `refreshMisAnalisisTable()`, leyendo los meses/años únicos que existan entre los análisis guardados, ordenados del más reciente al más antiguo. Ambos filtros usan el mecanismo estándar `data-table="misAnalisis" data-filter="..."` de `createTable`.
- **Paginación** — igual que las otras tablas.
- **Selección + export** — `exportTableData('misAnalisis','pdf'/'xlsx')`: exporta la selección, o si no hay nada seleccionado, exporta todo lo que esté filtrado en ese momento (esta es la ÚNICA forma de descargar "todo" — no existe un botón separado).
- **Columna Acciones** — 👁️ Ver (`openSavedAnalysis`), 📄 PDF individual con el informe gerencial completo (`downloadAnalysisPDF`), 🗑️ Eliminar (`deleteSavedAnalysis`) — estos dos últimos se ocultan según el rol del usuario logueado (ver sección de Roles y Permisos más abajo). Usan la clase base `.icon-btn`.

### Persistencia y guardado — resumen rápido

- **Guardado explícito ("💾 Guardar DSO"):** NO es automático. Al generar el dashboard (`generateDashboard()`) solo se calcula y se muestra — se guarda recién cuando se aprieta el botón "💾 Guardar DSO" en Resumen, que llama a `saveDSO()` → `saveCurrentAnalysis(...)`.
- `saveCurrentAnalysis(...)` serializa TODO lo necesario para reconstruir el dashboard (el array `invoices` completo, con `invDate`/`dueDate` convertidos a ISO string ya que `Date` no serializa a JSON directamente, más todos los totales/DSO/histData) y hace un `upsert` en la tabla `analyses` de Supabase (antes: `localStorage`, key `dso_saved_analyses_v1` — **ya no se usa**, ver sección "Persistencia (Supabase)" más abajo).
- **Reemplazo, no duplicado:** si ya existe un análisis guardado para el mismo mes/año **y misma localidad**, se reemplaza. Distintas localidades del mismo mes SÍ coexisten.
- **Límite:** máximo 20 análisis guardados (`MAX_SAVED_ANALYSES`), el más antiguo se descarta cuando se supera.
- **Estado vacío:** si no hay nada guardado, se muestra un mensaje con ícono + CTA "+ Comenzar" (`#homeEmptyState`).

### ⚠️ HISTÓRICO: por qué se usó `localStorage` al principio, y por qué ya no

**Esto ya no aplica — se deja como referencia histórica.** En un principio se usó `localStorage` (con sus limitaciones: por navegador, por origen, se pierde al limpiar caché, cada persona veía solo lo que ella misma había guardado). El usuario pidió explícitamente migrar esto a Supabase (ver "Persistencia (Supabase)" más abajo) — ahora es una tabla Postgres real, compartida entre todos los usuarios sin importar navegador o dispositivo.
- Si en el futuro se necesita que la persistencia sea confiable entre dispositivos/navegadores, la única solución real es un backend (mismo tema discutido para el bot de Slack — ver esa sección).

### Nav "Inicio" en el sidebar (histórico de esta feature — 3 iteraciones)

Documentado para que el próximo Claude no se confunda si ve referencias viejas:

1. **Primera versión:** un tercer "stage" `'home'` en `renderSidebarNav(stage)`, con un ítem "🏠 Inicio" dentro del nav en las 3 etapas.
2. **Segunda versión:** "Inicio" salió del nav-por-fase y se agregó una lista compacta de análisis recientes directamente en el sidebar (`.sidebar-recent`, `renderSidebarRecent()`) con un botón "Ver todos →" hacia la pantalla completa.
3. **Versión final (vigente):** el usuario pidió explícitamente sacar el detalle del sidebar (*"Mis análisis no debería verse el detalle en el sidebar"*) — se eliminó la lista compacta por completo, dejando solo un botón permanente "📋 Mis Análisis" sin detalle (ver "Layout: SIDEBAR" más arriba), y la pantalla Inicio pasó de tarjetas a una tabla con buscador/filtro/paginación (ver la sección "Mis Análisis ya NO se ve en el sidebar" en "Multi-localidad" más abajo).

## Perú y México: doble moneda (2 archivos AR + 2 montos de venta) — agregado a pedido del usuario

El usuario notó un problema real y pidió corregirlo explícitamente: *"en el importador de Perú y México debes agregar dos ventas del mes, ya que se vende en Dólares USD y en la moneda local... y el DSO se debe calcular por moneda"*.

### El problema que esto resuelve

Antes, el DSO por cartera (Nacional/Internacional) para **cualquier** localidad se calculaba repartiendo proporcionalmente un solo monto de ventas según el peso del AR de cada cartera:
```js
const nacPct = nacARBal / totalARBal;
const dsoNac = calcDSO(nacARBal, manualSales * nacPct, daysInMonth); // aproximación
```
Esto es una aproximación razonable **solo si** el peso de ventas por moneda coincide con el peso de AR por moneda — pero en Perú/México, donde de verdad existen dos flujos de venta independientes (uno en soles/pesos, otro en USD), esa aproximación puede dar un DSO por moneda completamente equivocado. Ejemplo real probado numéricamente: con AR de 8.000 USD y ventas reales de solo 40.000 USD ese mes, el DSO real en USD es 8 días — pero el método proporcional (que ignora la venta real en USD y solo mira el peso del AR) daba 3 días, escondiendo un problema de cobranza en la cartera USD.

### La solución: 2 archivos + 2 montos de venta, solo para Perú/México

```js
const LOCALITIES={
  chile:{...,dualCurrency:false},   // sin cambios: 1 archivo, columna Moneda, 1 venta
  peru:{...,dualCurrency:true},
  mexico:{...,dualCurrency:true}
};
```

Cuando `dualCurrency:true` (Perú/México):
- **Carga de Datos** muestra 2 dropzones de AR (`#dropARLocal` / `#dropARUSD`) en vez de 1, y 2 campos de Ventas del mes (`#salesInputLocal` / `#salesInputUSD`) en vez de 1. `selectLocality()` alterna la visibilidad (`#arCardSingle`/`#arCardDual`, `#salesSingleBlock`/`#salesDualBlock`) y los textos de ayuda.
- **La cartera se asigna por archivo de origen, no por columna de moneda** — todo lo que viene de `rawARLocal` es `portfolio:'nacional'`, todo lo que viene de `rawARUSD` es `portfolio:'internacional'`. El campo "Moneda" del mapeo pasa a ser **opcional** en este modo (`buildMappingUI()` y la validación de campos requeridos en `generateDashboard()` ambas chequean `loc.dualCurrency` para esto).
- **Cada archivo tiene su propio mapeo de columnas** (agregado a pedido explícito del usuario: *"en el mapeo de columnas debes crear dos mapeos, por los dos archivos diferentes"*). La pantalla de Mapeo muestra 2 tarjetas independientes cuando `dualCurrency:true` — `#mappingCardLocal` y `#mappingCardUSD` (en vez de la única `#mappingCardSingle` que usa Chile), cada una con su propio grid de selects (`map_local_{campo}` / `map_usd_{campo}`), poblados con las columnas reales de CADA archivo (`arColsLocal`/`arColsUSD`, capturadas por separado en `setupDrop`). Esto permite que los dos archivos tengan estructuras de columnas completamente distintas entre sí — ya no se asume que son el mismo export solo filtrado por moneda. `generateDashboard()` construye `arMapLocal` y `arMapUSD` por separado y valida los campos requeridos de cada archivo de forma independiente (el mensaje de error indica a cuál de los dos archivos le falta cada columna). La función `buildFieldRow(f, cols, idPrefix, skipCurrencyNote)` es la pieza reutilizada por `buildMappingUI()` tanto para el modo single-file (Chile) como para los 2 grids del modo dual.
- **DSO por moneda, ya sin aproximar:**
  ```js
  dsoNac = calcDSO(nacARBal, salesLocal, daysInMonth); // AR local / venta local real
  dsoInt = calcDSO(intARBal, salesUSD, daysInMonth);   // AR USD / venta USD real
  ```
  `dsoTotal` (el KPI combinado en Resumen) sigue siendo una suma naive de ambos AR y ambas ventas — igual de aproximado que antes, porque mezclar montos de distintas monedas sin tipo de cambio ya era una simplificación aceptada desde el diseño original de Chile (nunca se hizo conversión de divisas en esta app). Lo que cambia es que ahora **el desglose por moneda sí es exacto**, que es lo que pidió el usuario.

### Terminología: "Moneda Local / USD Internacional" en vez de "Nacional/Internacional" — solo para Perú/México

El usuario pidió explícitamente: *"en Mexico y Peru no uses en el detalle del analisis el concepto de cartera nacional, utiliza moneda local o USD Internacional... estos cambios tambien son para los exportables"*. Se agregó una función central para esto:

```js
function portfolioLabel(locality,which,short){
  const loc=LOCALITIES[locality]||LOCALITIES.chile;
  if(!loc.dualCurrency)return which==='nacional'?'Nacional':'Internacional';   // Chile: sin cambios
  if(which==='nacional')return short?'Local':'Moneda Local';                  // Perú/México
  return short?'USD':'USD Internacional';
}
```

`which` siempre es el valor interno del campo `portfolio` (`'nacional'` o `'internacional'` — esos valores de datos **no cambiaron**, solo cómo se muestran). `short` da la versión compacta para badges/celdas de tabla (`'Local'`/`'USD'`) vs. la versión larga para títulos/headers (`'Moneda Local'`/`'USD Internacional'`).

**Dónde se usa (todo dentro de `renderDashboard()`, ejecutado cada vez que se genera o abre un análisis):**
- Resumen: nueva tarjeta KPI "DSO USD Internacional" (`#kpiDSOUSDCard`, oculta por default, visible solo si `dualCurrency`) junto al KPI que antes decía "DSO Total" — ahora se relabela a "DSO {Moneda Local}" y muestra el DSO real de esa moneda (no un combinado ambiguo). `.kpi-row` pasó de `repeat(4,1fr)` a `repeat(auto-fit,minmax(190px,1fr))` para acomodar la 5ª tarjeta sin CSS especial por caso.
- Sección "Por Cartera": título (`#carteraSectionTitle`, cambia a "💱 Concentración por Moneda"), subtítulo (`#carteraSectionSub`), headers de cada columna (`#carteraNacHeader`/`#carteraIntHeader`), labels de mini-KPI (`#kpiDSONacLabel`/`#kpiDSOIntLabel`) y títulos de los gráficos de antigüedad (`#agingNacHeader`/`#agingIntHeader`) — todos se actualizan con `textContent`/`innerHTML` usando `portfolioLabel(currentLocality,...)`.
- Tablas "Clientes Churn" y "Detalle de Facturas": la columna "Cartera" (badge, usa la versión larga) y las opciones del filtro dropdown (`#churnOptNacional`/`#churnOptInternacional`, `#invoicesOptNacional`/`#invoicesOptInternacional`) — estas opciones son HTML estático con `id` agregado solo para poder re-etiquetarlas por JS; el `value` del filtro (`"nacional"`/`"internacional"`) no cambió.
- **Exportables** (el pedido explícito de "estos cambios también son para los exportables"):
  - `exportSources` (fuentes de gráficos en pantalla, dentro de `renderDashboard()`) y `chartLabels` (checkboxes del panel Exportar) construyen sus títulos con `portfolioLabel(currentLocality,...)` en vez de string fijo.
  - `computeExportSourcesFromParams(p,locality)` — ahora recibe `locality` como segundo parámetro (antes no lo recibía) y lo usa igual que `renderDashboard()`. Su único call-site (`downloadAnalysisPDF`) le pasa `entry.locality`.
  - `chartInsight(key,src,locality)` — ahora recibe `locality` y ajusta el texto de interpretación de los gráficos "Vencidas vs Vigentes": para Chile sigue diciendo *"Del saldo nacional de..."*, para Perú/México dice *"Del saldo en Moneda Local de..."* / *"Del saldo en USD Internacional de..."*.
  - `buildInformePDF(sources,keys,reportTitle,periodLabel,filename,locality)` — nuevo 6º parámetro `locality`, se lo pasa a `chartInsight`. Además, el título de cada sección del PDF ahora prioriza `src.title` (ya correctamente localizado) por sobre el objeto estático `CHART_TITLES` (`src.title||CHART_TITLES[key]` — antes era al revés, lo cual hacía que `CHART_TITLES` pisara el título correcto). Mismo cambio de prioridad en `buildInformeXLSX` para el listado de "Gráficos incluidos" en la hoja de metadatos.
  - `CHART_TITLES` (objeto estático, con textos fijos "Nacional"/"Internacional") **ya no se usa como fuente principal** — quedó solo como *fallback* de emergencia por si algún `src.title` viniera vacío. No hace falta tocarlo si se agrega una nueva localidad en el futuro, siempre que esa fuente ya traiga su `.title` correctamente armado con `portfolioLabel()`.

**Qué NO se relabeló** (decisión de alcance, no fue pedido explícitamente): el nombre de columna genérico "Cartera" en las tablas (Churn/Facturas) se deja igual — el objetivo era evitar el *concepto compuesto* "Cartera Nacional"/"Cartera Internacional", no la palabra "Cartera" sola como encabezado de columna, que sigue siendo un nombre de columna razonable aunque sus valores ahora digan "Moneda Local"/"USD" para Perú/México.

### "DSO por Moneda" (gráfico + fuente exportable) — agregado a pedido del usuario

El usuario pidió explícitamente: *"debes incluir lo nuevo en los pdf guardando estructura, responsividad y adaptabilidad"*. Se agregó una comparación directa DSO Local vs DSO USD como un elemento más del sistema de fuentes exportables ya existente (no se creó nada paralelo):

- **Gráfico en el dashboard**: barra comparativa dentro de "Por Cartera" (`#dsoPorMonedaBox` / `#chartDSOPorMoneda`), oculto por completo para Chile, visible solo si `dualCurrency`.
- **Fuente exportable**: `exportSources.dsoPorMoneda` (dentro de `renderDashboard()`) y su equivalente `sources.dsoPorMoneda` (dentro de `computeExportSourcesFromParams(p,locality)`, para análisis ya guardados) — mismo formato `{title,sheet,headers,rows}` que todas las demás fuentes.
- **Aparece automáticamente en:**
  - El panel "Exportar" (checkbox nuevo, vía `chartLabels.dsoPorMoneda`).
  - El informe PDF y el XLSX — **sin tocar el layout ni la paginación del informe**: `buildInformePDF`/`buildInformeXLSX` ya iteran genéricamente sobre `keys`/`Object.keys(sources)`, así que agregar esta fuente al objeto es suficiente para que aparezca como una sección más, con la misma estructura (título numerado, párrafo de interpretación, 3 KPIs, tabla) y el mismo comportamiento de salto de página adaptativo (`pdfEnsureSpace`) que ya tenían "Impacto Inactivos" y el resto. Esto es lo que el usuario pidió como "guardando estructura, responsividad y adaptabilidad" — no se reinventó el generador de PDF, solo se le agregó una fuente más.
  - El botón 📄 individual de cada tarjeta en "Mis Análisis" (`downloadAnalysisPDF`), porque usa el mismo `Object.keys(sources)`.
- **Interpretación automática**: nuevo caso `key==='dsoPorMoneda'` en `chartInsight()` — compara ambos DSO y da una alerta si la diferencia es ≥10 días ("la gestión de cobranza no es homogénea entre ambas monedas...").

### "Mis Análisis" ahora refleja ambos DSO — agregado a pedido del usuario

Pedido explícito: *"En las listas de Mis Analisis, necesito que refleje ambos DSO"*. Antes la columna "DSO" de la tabla mostraba un solo número (`meta.dsoTotal`) sin importar la localidad. Cambios:

- `saveCurrentAnalysis(...)` ahora guarda `dsoNac` y `dsoInt` dentro de `meta` (antes solo estaban dentro de `params`, que no se lee para renderizar la tabla — por eso hacía falta duplicarlos en `meta` para no tener que reconstruir el análisis completo solo para mostrar una columna).
- La columna "DSO" en `refreshMisAnalisisTable()` ahora chequea `LOCALITIES[a.locality].dualCurrency`: si es Perú/México, muestra las dos cifras apiladas (ej. `Local: 6d` / `USD: 8d`, usando `portfolioLabel(a.locality,which,true)` para las etiquetas cortas); si es Chile, se comporta exactamente igual que antes (un solo número).

### Indicadores de moneda en los gráficos — agregado a pedido del usuario

Pedido explícito: *"en los graficos debes indicar que moneda es la que tomaste en cuenta para la construccion del grafico"*. Como varios gráficos combinan ambas monedas sin conversión de tipo de cambio cuando la localidad es dual-moneda (Concentración Total, Top Clientes, Histórico DSO, Impacto Inactivos — todos calculados sobre el array `invoices` completo, que mezcla facturas de ambos archivos), se agregó una nota visible en el `section-sub` de cada uno, solo para `dualCurrency`:

> ⚠️ Combina {Moneda Local} + {USD Internacional} SIN conversión de tipo de cambio

Los gráficos "Vencidas vs Vigentes" dentro de "Por Cartera" (que SÍ son de una sola moneda cada uno) también indican la moneda directamente en su título (`#vencidoNacHeader`/`#vencidoIntHeader`, ej. "Vencidas vs Vigentes (Moneda Local)"). Todo esto vive dentro del mismo bloque de `renderDashboard()` donde ya se relabelaban "Nacional"/"Internacional" — buscar el comentario `// Indicador de qué moneda(s) se usaron para construir cada gráfico`.

### Qué NO cambió (importante para no romper Chile)

- Chile sigue funcionando exactamente igual: 1 archivo AR, columna "Moneda" (`detectPortfolio(currency)`) para separar nacional/internacional dentro del mismo archivo, 1 solo monto de ventas, y el DSO por cartera sigue usando el reparto proporcional (aproximado) — el usuario no pidió cambiar esto para Chile, solo para Perú/México.
- El resto del pipeline (`renderDashboard`, `exportSources`, guardado (hoy en Supabase, antes en `localStorage`), tablas, export PDF/XLSX, "Impacto Inactivos", histórico) **no necesitó ningún cambio** — todo ya trabajaba de forma genérica sobre el array `invoices[]` y su campo `.portfolio`, sin importar cómo se determinó ese campo. La función nueva `parseARRows(rows, arMap, portfolioOverride)` es la única pieza que cambió, y la reutilizan ambos modos (single-file y dual-currency).

## Layout: SIDEBAR, no navbar

⚠️ Se probó un navbar horizontal en algún punto de la conversación, pero el usuario pidió explícitamente **volver al sidebar vertical**. No lo cambies a navbar de nuevo sin confirmar con el usuario.

### Estructura del sidebar (versión vigente — el detalle de "Mis Análisis" YA NO vive aquí)

Esto pasó por 2 iteraciones. La primera versión (con una lista compacta de análisis recientes dentro del sidebar) **fue revertida explícitamente por el usuario**: *"Mis análisis no debería verse el detalle en el sidebar, debiese ser en una pantalla tipo listas, con paginadores y filtros"*. La versión vigente es más simple:

**1. Elementos PERMANENTES (siempre visibles, sin importar la fase o pantalla actual):**
- **Logo/marca** (`.sidebar-brand`) — clickeable, `onclick="goHome()"`. Convención "click en el logo = ir a Inicio".
- **Botón "+ Nuevo Análisis"** (`.sidebar-cta`) → `startNewAnalysis()` — accesible desde cualquier pantalla.
- **Botón "📋 Mis Análisis"** (`.sidebar-permanent-link`) → `goHome()` — **sin ningún detalle**, es solo un enlace a la pantalla completa. (Antes había una lista compacta con los últimos análisis directamente en el sidebar — se eliminó por completo, ver la sección "Multi-localidad" → "Mis Análisis ya NO se ve en el sidebar" más abajo para el detalle completo de qué se quitó y con qué se reemplazó.)
- La fecha de hoy + botón de logout al pie (`.sidebar-footer-block`).

**2. Elementos POR FASE (cambian según `renderSidebarNav(stage)`):**
- `stage='setup'` → `NAV_SETUP` = [Carga de Datos, Mapeo de Columnas] — se ocultan/muestran exclusivamente vía `showScreen(id)` (es un wizard secuencial, tiene sentido que se tapen entre sí).
- `stage='dashboard'` → `navDashboardItems()` — usan `scrollToSection(id)`, NO se ocultan (todas las secciones del dashboard están siempre montadas en el DOM).
- `stage='home'` → nav de fase vacío (`[]`) — en Inicio no hay nada "de fase" que mostrar.

**`refreshSidebar(stage)`** hoy es solo un wrapper de `renderSidebarNav(stage)` (antes también llamaba a `renderSidebarRecent()`, que ya no existe). Se mantuvo el nombre de la función para no tener que tocar todos los call-sites, pero ya no hace nada "extra" más allá del nav por fase.

⚠️ **Ya NO existe** un ítem de nav "🏠 Inicio" dentro de `NAV_SETUP`/`navDashboardItems()`, ni la función `goBack()`. El acceso a Inicio es vía el logo clickeable o el botón permanente "📋 Mis Análisis".

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

## Persistencia (Supabase) — resumen de la arquitectura vigente

Reemplaza todo lo que este documento describía antes sobre `localStorage`. Detalle completo en `supabase/schema.sql`, `supabase/SETUP.md` y `supabase/MIGRATION_PLAN.md`.

- **`profiles`** — un perfil por usuario de Supabase Auth, con columna `role` (`admin`/`analyst`/`consultor`). Se crea automáticamente vía trigger cuando alguien se registra; el rol por defecto es `consultor` (el más restrictivo) y hay que subirlo a mano desde el Table Editor de Supabase.
- **`analyses`** — tabla compartida (no una fila por usuario) con `unique(locality, dso_month, dso_year)`, que reemplaza uno a uno el array que vivía en `localStorage`. RLS: cualquier usuario autenticado puede `select`; solo `role='admin'` puede `insert`/`update`/`delete` (políticas `analyses_select_all`/`analyses_insert_admin`/`analyses_update_admin`/`analyses_delete_admin`).
- **Login real:** `handleLogin()` usa `supabase.auth.signInWithPassword(...)`, no comparación de texto plano. `AUTH_USERS` **ya no existe** en el código.
- **Sesión persistente:** el SDK `supabase-js` guarda su propio token en `localStorage` (mecanismo interno del SDK, no relacionado con la vieja key `dso_saved_analyses_v1`) — por eso `restoreSession()` puede reconectar sin pedir login de nuevo si la sesión sigue vigente.
- **Funciones que pasaron de síncronas a `async`** (todas devuelven/reciben Promises ahora): `loadSavedAnalyses`, `saveCurrentAnalysis`, `deleteSavedAnalysis`, `buildAutoHistorical`, `openSavedAnalysis`, `refreshMisAnalisisTable`, `downloadAnalysisPDF`, `generateDashboard`, `applyRolePermissions`, `goHome`. Si se agrega una función nueva que llame a cualquiera de estas, **tiene que ser `async` y usar `await`** — de lo contrario el código sigue ejecutándose antes de que la consulta a Supabase termine y falla silenciosamente.
- **`persistSavedAnalyses` y `MAX_SAVED_ANALYSES` ya no existen** — el límite de 20 análisis era un workaround del tamaño de `localStorage`; Postgres no lo necesita.
- **Las credenciales del proyecto** (`SUPABASE_URL`/`SUPABASE_ANON_KEY`) están hardcodeadas al inicio del `<script>` principal. La `anon key` es segura de tener ahí — está diseñada para ser pública; la seguridad real la dan las políticas RLS de `schema.sql`. **Nunca** poner la `service_role` key en este archivo.

## Login (Supabase Auth real, YA NO es "candado básico") + Logout + Roles y Permisos

Se agregó una pantalla de login (`#loginScreen`) que tapa todo el `#appLayout` hasta que se ingresan credenciales correctas. **Esto migró de un candado falso (comparación de texto plano contra un objeto hardcodeado) a autenticación real con Supabase Auth** — ver la sección "Persistencia (Supabase)" arriba para el resumen completo. `handleLogin()` llama a `supabase.auth.signInWithPassword(...)`.

### 3 roles con permisos distintos (esto no cambió con la migración)

El usuario pidió explícitamente crear tipos de usuario con permisos diferenciados:

| Rol | Puede cargar (subir/generar/guardar) | Puede eliminar | Puede descargar (PDF/XLSX/Slack) |
|---|---|---|---|
| **Administrador** | ✅ | ✅ | ✅ |
| **Collection Analyst** | ❌ | ❌ | ✅ |
| **Consultor** | ❌ | ❌ | ❌ (solo puede ver) |

```js
const ROLE_LABELS={admin:'Administrador',analyst:'Collection Analyst',consultor:'Consultor'};
const PERMISSIONS={
  admin:{canUpload:true,canDelete:true,canDownload:true},
  analyst:{canUpload:false,canDelete:false,canDownload:true},
  consultor:{canUpload:false,canDelete:false,canDownload:false}
};
```

⚠️ **`AUTH_USERS` ya NO existe en el código.** Los usuarios reales (correo + contraseña) viven en Supabase Auth (Authentication → Users, en el panel de Supabase), y el rol de cada uno vive en la columna `role` de la tabla `profiles` — **no en este archivo**. Para crear un usuario nuevo o cambiarle el rol a alguien, hay que hacerlo desde el panel de Supabase (ver `supabase/SETUP.md`, pasos 4-5), no editando `index.html`.

### Cómo se aplican los permisos

`applyRolePermissions()` se llama una sola vez, justo después de un login exitoso (dentro de `handleLogin()`), y hace 2 cosas:

1. **Oculta elementos por clase CSS** — cualquier elemento con clase `.perm-upload`, `.perm-delete` o `.perm-download` se oculta (`display:none`) si el rol actual no tiene ese permiso. Estas clases están puestas en HTML estático sobre: el botón "+ Nuevo Análisis" (sidebar, Inicio, estado vacío), el botón "💾 Guardar DSO", y todos los botones de exportar PDF/XLSX (gráficos, tablas de Churn/Facturas/Mis Análisis) + el panel de Slack.
2. **Re-renderiza la tabla de Mis Análisis** (`refreshMisAnalisisTable()`) — porque la columna "Acciones" de esa tabla se construye dinámicamente en JS (no es HTML estático), así que el botón 📄 (PDF) y 🗑️ (eliminar) se agregan condicionalmente dentro de la función `render()` de esa columna, consultando `currentPermissions()` en el momento de dibujar cada fila. El botón 👁️ (ver) siempre se muestra — ver está permitido para los 3 roles.

**Defensa en profundidad:** además de ocultar los botones, las funciones que realizan las acciones (`generateDashboard()`, `saveDSO()`, `startNewAnalysis()`, `deleteSavedAnalysis()`, `exportTableData()`, `exportSelectedCharts()`, `downloadAnalysisPDF()`, `sendSlackSummary()`) también empiezan con un chequeo `hasPermission(...)` y muestran un `alert()` si no corresponde. A diferencia de antes de la migración, ahora esto **sí tiene un respaldo real**: aunque alguien evada estos chequeos del cliente (ej. con las herramientas de desarrollador), las políticas RLS de `schema.sql` bloquean en el servidor cualquier `insert`/`update`/`delete` sobre `analyses` que no venga de un usuario con `role='admin'` en la tabla `profiles` — eso Supabase lo hace cumplir sin importar qué JS corra en el navegador de quien intente saltarse los botones.

**Badge de usuario/rol:** `#userRoleBadge` en el sidebar, arriba de la fecha, muestra `"👤 {nombre} · {Rol}"` — se actualiza dentro de `applyRolePermissions()`.

### Qué cambió realmente con la migración a Supabase (ya no es un candado falso)

Antes de esta migración, el login era honestamente "un candado casual" (contraseña en texto plano en el HTML, sin backend, cualquiera con herramientas de desarrollador podía evadirlo). **Eso ya no es así:**
- La contraseña **ya no está en el código** — vive hasheada en Supabase Auth, fuera del archivo.
- Hay un backend real (Supabase) que hace cumplir las políticas RLS del lado del servidor — no depende de que el JS del cliente "se comporte".
- Alguien podría seguir editando el DOM con las herramientas de desarrollador para ocultar/mostrar botones, pero cualquier operación real contra la base de datos (guardar, eliminar) sigue necesitando un JWT válido de un usuario con el rol correcto — eso no se puede falsificar desde el navegador.
- Sigue existiendo una limitación real, pero distinta: la `anon key` y las políticas RLS son tan buenas como se hayan escrito — si en el futuro se agrega una tabla nueva sin RLS, o una policy demasiado permisiva, ahí sí se abre un hueco real. Cualquier cambio al esquema debe revisar sus policies con el mismo cuidado que se usó en `schema.sql`.

**Logout (`handleLogout()`):** botón permanente al pie del sidebar ("🚪 Cerrar sesión", `.sidebar-logout`), debajo del nav y separado por un borde. Al hacer click (con `confirm()` de por medio):
- Llama a `supabase.auth.signOut()` (invalida la sesión de verdad, no solo un flag en memoria).
- Oculta `#appLayout` y vuelve a mostrar `#loginScreen`.
- Limpia los campos de email/contraseña y el mensaje de error del login.
- Resetea `currentAnalysisId=null` y vuelve la app a la pantalla Inicio (`refreshSidebar('home')` + `showScreen('home')`), para que la próxima vez que alguien haga login no quede expuesto un dashboard sin haber vuelto a autenticarse.
- **No borra** los análisis guardados (ahora en Supabase) — el logout solo cierra la sesión de Supabase Auth (`supabase.auth.signOut()`), no toca los datos.

## Cosas que el usuario pidió y luego revirtió (para no repetir el mismo camino)

1. **Navbar horizontal** → el usuario lo probó y pidió volver a **sidebar vertical**. No cambiar sin confirmar.
2. **"Histórico DSO" como primera sección** → el usuario luego pidió que **"Resumen" fuera primero**. El orden vigente está documentado arriba.
3. **DSO con 1 decimal** → se implementó y luego se revirtió a enteros, y finalmente se fijó la regla de "siempre redondea hacia arriba" (ver sección de cálculo del DSO arriba).
4. **Botón "↩️ Nuevo análisis" + función `goBack()`** → se eliminaron al agregar la pantalla "Inicio". Si ves código viejo o instrucciones de una conversación anterior que mencionen `goBack()`, ya no existe — usa `goHome()` / `startNewAnalysis()`.

## Estructura de archivos de este proyecto (repo de GitHub)

```
dso-dashboard/
├── index.html      ← el archivo único y final. TODO vive aquí (HTML + CSS + JS inline, logo en base64, sin dependencias locales)
├── README.md       ← este mismo documento
└── .gitignore      ← ignora archivos de OS/editor y un .env por si en el futuro se agrega config de Supabase
```

No hay `package.json` ni carpeta `src/` — es intencional, no hay build step. Si en el futuro se integra Supabase probablemente convenga agregar un `supabase-config.js` separado (con la URL del proyecto y la *anon key*, que es segura de exponer en el frontend) en vez de hardcodear esos valores dentro de `index.html`, para que sea más fácil de ubicar y rotar si cambia.

## Cómo desplegar este repo (para cuando el usuario conecte el hosting)

Repo real: https://github.com/genesiszerpa/DSO-analytics

Cualquiera de estas opciones sirve el sitio sin build step, apenas se conecte el repo:

- **GitHub Pages:** https://github.com/genesiszerpa/DSO-analytics/settings/pages → Branch: `main` → carpeta `/ (root)` → Save. Queda publicado en `https://genesiszerpa.github.io/DSO-analytics/`.
- **Vercel / Netlify:** "Import Project" → conectar la cuenta de GitHub → elegir `genesiszerpa/DSO-analytics`, sin configurar build command ni output directory (framework: "Other" / "Static").
- **Cloudflare Pages:** similar a Vercel/Netlify, framework preset "None".

⚠️ A diferencia de cuando se escribió este párrafo, **el sitio ya SÍ requiere Supabase para funcionar** — el login y "Mis Análisis" dependen de él. Cualquiera de las opciones de hosting de arriba sirve igual el archivo `index.html`, pero quien lo abra necesita que el proyecto de Supabase esté activo y con los usuarios ya creados (ver `supabase/SETUP.md`).

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
- No usar `localStorage`/`sessionStorage` para datos propios de la app (puede fallar en preview de Claude.ai) — el guardado de análisis y el login ya migraron a Supabase por este motivo, entre otros. La única excepción es el propio SDK de `supabase-js`, que internamente usa su propio `localStorage` para persistir el token de sesión — eso es estándar y no lo gestiona nuestro código.
