# Plan de migración: localStorage/AUTH_USERS → Supabase

> ✅ **Estado: ya aplicado en `index.html`.** Este documento se escribió como
> plan antes de tener las credenciales del proyecto; una vez que se
> proporcionaron el Project URL y la anon key, todo lo descrito abajo (puntos
> 1-8) ya se implementó en el código. Se deja el documento como referencia de
> **qué cambió y por qué** — útil si hay que depurar algo o entender el porqué
> de una función async donde antes era síncrona.

Este documento es la guía técnica de la conexión de `index.html` a Supabase
(ver también `SETUP.md` para la configuración del lado de Supabase — crear
usuarios, asignar roles, etc., eso sí sigue siendo manual y pendiente de que
lo hagas tú).

## 0. Agregar el cliente de Supabase

En el `<head>`, junto a los otros `<script>` de librerías (Chart.js, jsPDF, etc.):

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
```

Y cerca del inicio del `<script>` principal, junto a las otras constantes globales:

```js
const SUPABASE_URL = 'https://xxxxxxxxxxxx.supabase.co';   // ← tu Project URL
const SUPABASE_ANON_KEY = 'eyJ...';                          // ← tu anon public key
const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
```

## 1. Login (`handleLogin`) → `supabase.auth.signInWithPassword`

**Hoy** (`AUTH_USERS` hardcodeado, comparación de texto plano):
```js
function handleLogin(e){
  e.preventDefault();
  const email=document.getElementById('loginEmail').value.trim().toLowerCase();
  const pass=document.getElementById('loginPassword').value;
  const user=AUTH_USERS[email];
  if(user&&user.password===pass){ currentUser={email,role:user.role,name:user.name}; ... }
}
```

**Después** (real, con Supabase Auth + tabla `profiles` para el rol):
```js
async function handleLogin(e){
  e.preventDefault();
  const email=document.getElementById('loginEmail').value.trim().toLowerCase();
  const pass=document.getElementById('loginPassword').value;
  const errEl=document.getElementById('loginError');

  const {data,error}=await supabase.auth.signInWithPassword({email,password:pass});
  if(error){ errEl.textContent='Correo o contraseña incorrectos.'; document.getElementById('loginPassword').value=''; return; }

  const {data:profile}=await supabase.from('profiles').select('name,role').eq('id',data.user.id).single();
  currentUser={email,role:profile.role,name:profile.name};
  errEl.textContent='';
  document.getElementById('loginScreen').style.display='none';
  document.getElementById('appLayout').style.display='';
  await applyRolePermissions();   // ← ahora async, ver punto 4
}
```
`onsubmit="handleLogin(event)"` en el HTML no necesita cambiar — un `onsubmit` async funciona igual, el navegador no espera su resolución para nada crítico aquí.

## 2. Logout (`handleLogout`) → `supabase.auth.signOut()`

```js
async function handleLogout(){
  if(!confirm('¿Cerrar sesión?'))return;
  await supabase.auth.signOut();
  document.getElementById('appLayout').style.display='none';
  document.getElementById('loginScreen').style.display='';
  // ... resto igual
}
```

## 3. Storage de análisis: `loadSavedAnalyses` / `persistSavedAnalyses`

Estas dos funciones son el corazón del cambio — hoy leen/escriben un array
completo en `localStorage`; en Supabase cada análisis es una **fila** de la
tabla `analyses`.

**Hoy:**
```js
function loadSavedAnalyses(){
  try{ const raw=localStorage.getItem(SAVED_ANALYSES_KEY); return raw?JSON.parse(raw):[]; }catch(e){return [];}
}
function persistSavedAnalyses(list){ /* localStorage.setItem(...) */ }
```

**Después** — `loadSavedAnalyses` se vuelve `async` y consulta la tabla:
```js
async function loadSavedAnalyses(){
  const {data,error}=await supabase.from('analyses').select('*').order('dso_year',{ascending:false}).order('dso_month',{ascending:false});
  if(error){console.error(error);return [];}
  // La forma de cada fila en la tabla es snake_case (dso_month, short_label, etc.)
  // — conviene mapearla de vuelta a la forma que ya usa el resto del código
  // (camelCase, con `params.dsoMonth` en vez de `dso_month` en la fila raíz):
  return data.map(row=>({
    id:row.id, createdAt:row.created_at, locality:row.locality,
    label:row.label, shortLabel:row.short_label, meta:row.meta,
    params:{...row.params, dsoMonth:row.dso_month, dsoYear:row.dso_year}
  }));
}
```

`persistSavedAnalyses(list)` ya no tiene sentido tal cual (no se reescribe la
lista completa) — se reemplaza por un **upsert de una sola fila** dentro de
`saveCurrentAnalysis`, y un **delete de una sola fila** dentro de
`deleteSavedAnalysis` (ver puntos 5 y 6). Se puede borrar esta función.

## 4. `applyRolePermissions` — ahora async porque llama a `refreshMisAnalisisTable`

Como el punto 6 vuelve `refreshMisAnalisisTable` async (porque adentro llama a
`loadSavedAnalyses`, que ahora es async), `applyRolePermissions` también debe
volverse `async` y usar `await` al llamarla:

```js
async function applyRolePermissions(){
  // ... igual que antes ...
  await refreshMisAnalisisTable();
}
```

## 5. `saveCurrentAnalysis` → `upsert`

**Hoy** (arma el objeto, filtra la lista completa en memoria, la reescribe entera):
```js
let list=loadSavedAnalyses().filter(a=>!(a.params.dsoMonth===dsoMonth&&a.params.dsoYear===dsoYear&&a.locality===locality));
list.unshift(entry);
persistSavedAnalyses(list);
return entry.id;
```

**Después** — un solo `upsert` que aprovecha el `unique(locality, dso_month, dso_year)` del esquema para reemplazar automáticamente:
```js
async function saveCurrentAnalysis(invoices,totalARBal,nacARBal,intARBal,dsoTotal,dsoNac,dsoInt,manualSales,daysInMonth,dsoMonth,dsoYear,histData,locality){
  locality=locality||'chile';
  const loc=LOCALITIES[locality]||LOCALITIES.chile;
  const clientSet=new Set(invoices.map(i=>i.cn));
  const churnCount=new Set(invoices.filter(i=>i.isChurn).map(i=>i.cn)).size;
  const vencBal=invoices.filter(i=>i.isVencida).reduce((s,i)=>s+i.balance,0);
  const vencPct=totalARBal?Math.round(vencBal/totalARBal*100):0;

  const row={
    locality, dso_month:dsoMonth, dso_year:dsoYear,
    label:loc.flag+' '+loc.label+' — '+MONTH_NAMES[dsoMonth-1]+' '+dsoYear,
    short_label:loc.flag+' '+MONTH_NAMES[dsoMonth-1].substring(0,3)+' '+dsoYear,
    meta:{dsoTotal,dsoNac,dsoInt,totalARBal,invoiceCount:invoices.length,clientCount:clientSet.size,vencPct,churnCount},
    params:{
      invoices:invoices.map(i=>({...i,invDate:i.invDate?i.invDate.toISOString():null,dueDate:i.dueDate?i.dueDate.toISOString():null})),
      totalARBal,nacARBal,intARBal,dsoTotal,dsoNac,dsoInt,manualSales,daysInMonth,histData
    }
  };
  const {data,error}=await supabase.from('analyses')
    .upsert(row,{onConflict:'locality,dso_month,dso_year'})
    .select('id').single();
  if(error){alert('No se pudo guardar en Supabase: '+error.message);return null;}
  return data.id;
}
```
Nota: `dso_month`/`dso_year` salen de `params` en la tabla (columnas propias),
no van duplicados dentro del jsonb `params` — por eso el mapeo de vuelta en el
punto 3 los reinyecta en `params.dsoMonth`/`params.dsoYear` al leer.

`MAX_SAVED_ANALYSES` (el límite de 20) deja de tener sentido — Postgres no
necesita ese límite artificial. Se puede eliminar esa constante y su uso.

## 6. `deleteSavedAnalysis` → `delete`

```js
async function deleteSavedAnalysis(id){
  if(!hasPermission('canDelete')){alert('Tu perfil ('+ROLE_LABELS[currentUser.role]+') no tiene permiso para eliminar análisis.');return;}
  if(!confirm('¿Eliminar este análisis guardado? Esta acción no se puede deshacer.'))return;
  const {error}=await supabase.from('analyses').delete().eq('id',id);
  if(error){alert('No se pudo eliminar: '+error.message);return;}
  if(currentAnalysisId===id)currentAnalysisId=null;
  await refreshMisAnalisisTable();
}
```

## 7. Todo lo que llama a estas funciones necesita `async`/`await`

Buscar cada uno de estos y agregar `async`/`await` según corresponda (el
nombre de la función no cambia, solo se vuelve asíncrona):

- `openSavedAnalysis(id)` — hace `loadSavedAnalyses().find(...)` → `(await loadSavedAnalyses()).find(...)`, y la función pasa a `async function openSavedAnalysis(id){...}`. Sus 2 llamadas (`onclick="openSavedAnalysis('${a.id}')"` en la columna Acciones, y en `downloadAnalysisPDF`) no necesitan cambiar la sintaxis del `onclick` — un `onclick` que llama a una función async funciona igual, solo que ya no se puede encadenar código síncrono inmediatamente después asumiendo que ya terminó.
- `downloadAnalysisPDF(id)` — mismo caso, agregar `async`/`await` alrededor de `loadSavedAnalyses().find(...)`.
- `refreshMisAnalisisTable()` — se vuelve `async`, y su único call-site (`goHome()`, el final de `applyRolePermissions()`, y el `INIT` al final del archivo) deben usar `await refreshMisAnalisisTable()` o `.then()`.
- `buildAutoHistorical(locality,excludeMonth,excludeYear)` — hace `loadSavedAnalyses().filter(...)` → se vuelve `async function`, y su único call-site (dentro de `generateDashboard()`) pasa a `histData=await buildAutoHistorical(...)`. Como consecuencia, **`generateDashboard()` también se vuelve `async`** (ya que espera el resultado).
- El `INIT` final del archivo (`refreshMisAnalisisTable();` como una de las últimas líneas) debe envolverse: `(async()=>{ await refreshMisAnalisisTable(); })();` o simplemente `refreshMisAnalisisTable();` si no importa esperar el resultado ahí (es la carga inicial, no bloquea nada crítico).

## 8. `exportTableData('misAnalisis', ...)` sigue funcionando igual

`createTable()` recibe un array de `rows` ya resuelto (no una función), así
que **no cambia** — simplemente hay que asegurarse de que `refreshMisAnalisisTable()`
haga `await loadSavedAnalyses()` ANTES de llamar a `createTable(...)`, cosa que
ya es natural al volverla `async`.

## 9. Qué NO cambia

- Todo el cálculo de DSO (`calcDSO`, `parseARRows`, `computeExportSourcesFromParams`, `chartInsight`, `buildInformePDF`/`buildInformeXLSX`) sigue **exactamente igual** — solo cambia de dónde vienen los datos (`invoices`, `params`), no cómo se procesan.
- El botón "💾 Guardar DSO" (`saveDSO()`) casi no cambia — solo agregar `await` antes de `saveCurrentAnalysis(...)`.
- Las tablas de Churn/Facturas (dentro del dashboard ya renderizado) no tocan `localStorage` en ningún momento — no les afecta esta migración.

## 10. Checklist de migración (en orden sugerido)

- [ ] Crear el proyecto Supabase y correr `schema.sql` (`SETUP.md`, pasos 1-6)
- [ ] Pegar `SUPABASE_URL`/`SUPABASE_ANON_KEY` en `index.html`
- [ ] Convertir `loadSavedAnalyses` a async + mapeo snake_case→camelCase
- [ ] Convertir `saveCurrentAnalysis` a `upsert`
- [ ] Convertir `deleteSavedAnalysis` a `delete`
- [ ] Eliminar `persistSavedAnalyses` y `MAX_SAVED_ANALYSES` (ya no se usan)
- [ ] Convertir `handleLogin`/`handleLogout` a Supabase Auth
- [ ] Eliminar `AUTH_USERS` del código (las contraseñas reales ya viven en Supabase, no en el HTML)
- [ ] Propagar `async`/`await` a: `applyRolePermissions`, `refreshMisAnalisisTable`, `openSavedAnalysis`, `downloadAnalysisPDF`, `buildAutoHistorical`, `generateDashboard`, e `INIT`
- [ ] Probar el flujo completo con un usuario de cada rol (admin/analyst/consultor) para confirmar que las RLS policies bloquean lo que deben bloquear
