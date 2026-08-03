-- ============================================================================
-- DSO Dashboard — Esquema de Supabase
-- ============================================================================
-- Cómo usar: Supabase → tu proyecto → SQL Editor → pega este archivo completo
-- → Run. Es seguro volver a ejecutarlo (usa IF NOT EXISTS / OR REPLACE donde
-- corresponde), salvo que ya tengas datos y no quieras recrear las policies.
--
-- Reemplaza en el frontend (index.html):
--   - localStorage (guardado de "Mis Análisis")           → tabla `analyses`
--   - AUTH_USERS hardcodeado (login con contraseña plana) → Supabase Auth + tabla `profiles`
-- ============================================================================

-- ── 1. PROFILES ─────────────────────────────────────────────────────────────
-- Un perfil por usuario de Supabase Auth, con su rol (Administrador/Collection
-- Analyst/Consultor). Los permisos reales (canUpload/canDelete/canDownload)
-- siguen viviendo en el frontend (PERMISSIONS en index.html) y en las RLS
-- policies de abajo — este `role` es la fuente de verdad para ambos lados.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  name text not null default '',
  role text not null default 'consultor' check (role in ('admin','analyst','consultor')),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Cada usuario puede ver su propio perfil (para saber su rol al hacer login).
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);

-- Nadie puede editar su propio rol desde el cliente (evita que un Consultor se
-- auto-asigne Administrador). Los cambios de rol se hacen desde el SQL Editor
-- o el Table Editor de Supabase directamente.
-- (No se crea policy de UPDATE/INSERT/DELETE a propósito → todo queda
-- bloqueado por RLS excepto el service_role, que nunca se usa en el frontend.)

-- Trigger: cuando se crea un usuario nuevo en auth.users, crear su perfil
-- automáticamente con rol 'consultor' por defecto (el más restrictivo — hay
-- que subirlo a 'admin' o 'analyst' a mano desde Supabase si corresponde).
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)),
    'consultor'
  );
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── 2. ANALYSES ──────────────────────────────────────────────────────────────
-- Un análisis guardado ("Guardar DSO") por período (mes+año) y localidad.
-- Reemplaza el array que hoy vive en localStorage bajo la key
-- 'dso_saved_analyses_v1'. Es una tabla COMPARTIDA (no hay una fila por
-- usuario) — cualquiera con sesión puede leerla, solo un Administrador puede
-- escribir/eliminar (ver policies abajo).
create table if not exists public.analyses (
  id uuid primary key default gen_random_uuid(),
  locality text not null check (locality in ('chile','peru','mexico')),
  dso_month int not null check (dso_month between 1 and 12),
  dso_year int not null check (dso_year between 2000 and 2100),
  label text not null,
  short_label text not null,
  meta jsonb not null,        -- {dsoTotal,dsoNac,dsoInt,totalARBal,invoiceCount,clientCount,vencPct,churnCount}
  params jsonb not null,      -- {invoices[],totalARBal,nacARBal,intARBal,dsoTotal,dsoNac,dsoInt,manualSales,daysInMonth,dsoMonth,dsoYear,histData}
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (locality, dso_month, dso_year)   -- "solo un análisis por período y por localidad"
);

create index if not exists analyses_period_idx on public.analyses (dso_year desc, dso_month desc);
create index if not exists analyses_locality_idx on public.analyses (locality);

alter table public.analyses enable row level security;

-- Cualquier usuario autenticado (Administrador, Collection Analyst o
-- Consultor) puede VER todos los análisis guardados.
drop policy if exists "analyses_select_all" on public.analyses;
create policy "analyses_select_all" on public.analyses
  for select using (auth.role() = 'authenticated');

-- Solo Administrador puede crear (Guardar DSO) o actualizar (reemplazar el
-- análisis de un mismo período+localidad) un análisis.
drop policy if exists "analyses_insert_admin" on public.analyses;
create policy "analyses_insert_admin" on public.analyses
  for insert with check (
    exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );

drop policy if exists "analyses_update_admin" on public.analyses;
create policy "analyses_update_admin" on public.analyses
  for update using (
    exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );

-- Solo Administrador puede eliminar.
drop policy if exists "analyses_delete_admin" on public.analyses;
create policy "analyses_delete_admin" on public.analyses
  for delete using (
    exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );

-- Mantener updated_at al día en cada UPDATE.
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists analyses_set_updated_at on public.analyses;
create trigger analyses_set_updated_at
  before update on public.analyses
  for each row execute function public.set_updated_at();

-- ============================================================================
-- Fin del esquema. Siguiente paso: supabase/SETUP.md
-- ============================================================================
