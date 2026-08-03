# Conectar el DSO Dashboard a Supabase — guía paso a paso

> ✅ **El código de `index.html` ya está conectado** a tu proyecto de Supabase
> (`SUPABASE_URL`/`SUPABASE_ANON_KEY` ya están puestos). Lo que sigue pendiente
> por hacer **tú, desde el panel de Supabase**, son los pasos 2-5 de abajo: correr
> el esquema, activar el login por correo, y crear/asignar rol a los 3 usuarios
> reales — sin eso, nadie puede entrar todavía aunque el código ya esté listo.

Esto reemplaza dos cosas que hoy son "falsas" en el dashboard (documentado en
el README principal): el `localStorage` del navegador (para "Mis Análisis") y
el login con contraseña en texto plano (`AUTH_USERS`). Con Supabase, ambos
pasan a ser reales: una base de datos compartida en la nube, y autenticación
real con Supabase Auth.

**Nada de esto lo puede hacer Claude por ti** — crear la cuenta, el proyecto y
los usuarios son acciones que requieren tu cuenta personal.

---

## 1. Crear el proyecto en Supabase

1. Ve a [supabase.com](https://supabase.com) → **Start your project** → crea una cuenta o inicia sesión (puedes usar tu cuenta de GitHub).
2. **New Project** → elige una organización, nombre (ej. `dso-dashboard`), una contraseña para la base de datos (guárdala, no la vuelvas a ver) y la región más cercana a tus usuarios (ej. `South America (São Paulo)`).
3. Espera 1-2 minutos a que se aprovisione el proyecto.

## 2. Correr el esquema (crea las tablas)

1. En el panel izquierdo, ve a **SQL Editor**.
2. Click **New query**.
3. Abre el archivo [`supabase/schema.sql`](./schema.sql) de este repo, copia **todo** el contenido, pégalo en el editor.
4. Click **Run** (o `Ctrl/Cmd + Enter`).
5. Deberías ver "Success. No rows returned". Si da error, revisa que copiaste el archivo completo (incluye comentarios que empiezan con `--`, son parte del SQL válido).

Esto crea 2 tablas (`profiles`, `analyses`), sus políticas de seguridad (RLS), y un trigger que crea automáticamente un perfil cada vez que se registra un usuario nuevo.

## 3. Activar el login por correo/contraseña

1. Ve a **Authentication → Providers**.
2. Confirma que **Email** esté habilitado (viene activado por default).
3. (Opcional pero recomendado para uso interno) en **Authentication → Settings**, desactiva "Enable email confirmations" si no quieres que cada usuario nuevo tenga que confirmar su correo antes de poder entrar — para una herramienta interna de la empresa esto suele ser más simple.

## 4. Crear los 3 usuarios (Administrador / Collection Analyst / Consultor)

1. Ve a **Authentication → Users** → **Add user** → **Create new user**.
2. Crea los 3 usuarios reales de tu equipo (correo + contraseña). Ejemplo:
   - `gzerpa@lemontech.com` (será Administrador)
   - el correo real de tu Collection Analyst
   - el correo real de tu Consultor
3. Cada uno que crees dispara el trigger del paso 2 y aparece automáticamente en la tabla `profiles` con `role = 'consultor'` (el más restrictivo, por seguridad).

## 5. Asignar el rol correcto a cada usuario

Por defecto todos quedan como `consultor`. Hay que subir manualmente al Administrador y al Collection Analyst:

1. Ve a **Table Editor → profiles**.
2. Busca la fila del correo que debe ser Administrador → edita la columna `role` → cámbiala a `admin`.
3. Busca la fila del correo que debe ser Collection Analyst → cambia `role` a `analyst`.
4. Deja el resto (Consultor) como `consultor`.

## 6. Copiar tus credenciales del proyecto

1. Ve a **Project Settings** (ícono de engranaje) **→ API**.
2. Copia dos valores:
   - **Project URL** (algo como `https://xxxxxxxxxxxx.supabase.co`)
   - **anon public** key (una key larga, empieza distinto a la `service_role` — **nunca uses la `service_role` key en el frontend**, esa sí es secreta de verdad).

## 7. Probar el login con cada rol

Una vez hechos los pasos 1-6, abre `index.html` y prueba:

1. Entra con el correo que marcaste como `admin` → deberías ver el botón "+ Nuevo Análisis", "💾 Guardar DSO", y los botones 🗑️ eliminar en "Mis Análisis".
2. Cierra sesión, entra con el correo `analyst` → no deberían aparecer los botones de cargar/eliminar, pero sí los de descargar (📄/📊).
3. Cierra sesión, entra con el correo `consultor` → solo debería poder ver, sin ningún botón de descarga ni de carga.
4. Genera y guarda un análisis con el usuario `admin`, luego entra con `analyst` o `consultor` y confirma que **ya lo ven en "Mis Análisis"** sin haberlo cargado ellos — esa es la prueba de que los datos ya viven en Supabase (compartidos), no en el navegador de cada uno.

Si algo no funciona, revisa la consola del navegador (F12 → Console) — los errores de Supabase suelen indicar directamente si es un problema de RLS, de credenciales, o de que falta la fila en `profiles`.

---

## Qué gana la empresa con esto (vs. la versión actual con localStorage)

| | Antes (localStorage) | Después (Supabase) |
|---|---|---|
| ¿Dónde viven los análisis guardados? | En el navegador de cada persona, por separado | En una base de datos compartida en la nube |
| ¿Ve Collection Analyst lo que guardó el Administrador? | No — cada navegador tiene su propia copia | Sí — todos ven los mismos datos |
| ¿La contraseña es real? | No, texto plano en el código | Sí, hasheada por Supabase Auth |
| ¿Se puede acceder desde el celular u otra computadora? | No | Sí |
| ¿Qué pasa si se borra el caché del navegador? | Se pierden todos los análisis guardados | No pasa nada, siguen en la base de datos |
