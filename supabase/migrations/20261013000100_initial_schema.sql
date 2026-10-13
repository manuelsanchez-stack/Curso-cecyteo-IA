create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text not null unique,
  role text not null default 'Personal Administrativo'
    check (role in ('Personal Administrativo','Administrador','Docente','Supervisor')),
  department text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.activities (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 180),
  bottleneck text not null check (char_length(bottleneck) between 1 and 500),
  solution text not null check (char_length(solution) between 1 and 3000),
  status text not null default 'Pendiente' check (status in ('Pendiente','En Proceso','Optimizado')),
  priority text not null default 'Media' check (priority in ('Alta','Media','Baja')),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.evidence_files (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.activities(id) on delete cascade,
  path text not null unique,
  name text not null,
  size bigint not null check (size > 0 and size <= 10485760),
  content_type text not null,
  uploaded_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create index if not exists activities_created_at_idx on public.activities(created_at desc);
create index if not exists evidence_activity_id_idx on public.evidence_files(activity_id);

create or replace function public.seed_default_activities(p_creator uuid)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  if exists (select 1 from public.activities) then return; end if;
  insert into public.activities (title,bottleneck,solution,status,priority,created_by)
  values
    ('1. Bajas de Inventario','Capturas de información.','Automatización por escáner: implementar lectores de códigos de barras o QR para evitar la captura manual.','Pendiente','Alta',p_creator),
    ('2. Capturas de calificaciones','Errores de ortografía, partes de texto faltantes.','Validación de datos con plantillas que aseguren campos obligatorios y reduzcan errores.','En Proceso','Alta',p_creator),
    ('3. Revisión de solicitudes p/ Servicio Social','Poco tiempo de entrega de los maestros.','Calendario escalonado con recordatorios automáticos antes de las fechas de corte.','Pendiente','Media',p_creator),
    ('4. Cartas de Buena conducta','Entrega de todas juntas de una generación.','Generación masiva de cartas a partir de una base de datos validada.','Optimizado','Media',p_creator),
    ('5. Altas y bajas de bienes Muebles','Captura en diferentes programas.','Centralizar el registro en un único sistema para evitar doble captura.','En Proceso','Alta',p_creator),
    ('6. Revisión de E-mails','Clasificación y registro.','Configurar reglas y etiquetas para clasificar automáticamente los mensajes.','Optimizado','Baja',p_creator),
    ('7. Levantamiento de Inventario','Fuga de información.','Respaldo en la nube, controles de acceso e historial de cambios.','Pendiente','Alta',p_creator);
end;
$$;
revoke all on function public.seed_default_activities(uuid) from public, anon, authenticated;

create or replace function public.handle_first_profile()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  perform public.seed_default_activities(new.id);
  return new;
end;
$$;
revoke all on function public.handle_first_profile() from public, anon, authenticated;

drop trigger if exists seed_initial_activities on public.profiles;
create trigger seed_initial_activities after insert on public.profiles
for each row execute function public.handle_first_profile();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name, email, department)
  values (new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.email,
    coalesce(new.raw_user_meta_data ->> 'department', ''))
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;
revoke all on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.activities enable row level security;
alter table public.evidence_files enable row level security;

grant select on public.profiles to authenticated;
grant update (full_name, department) on public.profiles to authenticated;
grant select, insert, delete on public.activities to authenticated;
grant update (title, bottleneck, solution, status, priority) on public.activities to authenticated;
grant select, insert, delete on public.evidence_files to authenticated;

create policy "Signed-in users can read profiles" on public.profiles
for select to authenticated using (true);
create policy "Users can update their own contact details" on public.profiles
for update to authenticated using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create policy "Signed-in users can read activities" on public.activities
for select to authenticated using (true);
create policy "Signed-in users can create activities" on public.activities
for insert to authenticated with check (created_by = (select auth.uid()));
create policy "Signed-in users can update activities" on public.activities
for update to authenticated using (true) with check (true);
create policy "Only administrators can delete activities" on public.activities
for delete to authenticated using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'Administrador');

create policy "Signed-in users can read evidence metadata" on public.evidence_files
for select to authenticated using (true);
create policy "Signed-in users can register evidence" on public.evidence_files
for insert to authenticated with check (uploaded_by = (select auth.uid()));
create policy "Uploader or administrator can delete evidence metadata" on public.evidence_files
for delete to authenticated using (uploaded_by = (select auth.uid()) or
  (select auth.jwt() -> 'app_metadata' ->> 'role') = 'Administrador');

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('evidencias', 'evidencias', false, 10485760,
  array['application/pdf','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/msword','image/png','image/jpeg','image/webp'])
on conflict (id) do update set public = false, file_size_limit = 10485760;

create policy "Signed-in users can read institutional evidence" on storage.objects
for select to authenticated using (bucket_id = 'evidencias');
create policy "Signed-in users can upload institutional evidence" on storage.objects
for insert to authenticated with check (bucket_id = 'evidencias');
create policy "Uploader or administrator can delete institutional evidence" on storage.objects
for delete to authenticated using (bucket_id = 'evidencias' and
  (owner_id = (select auth.uid())::text or
   (select auth.jwt() -> 'app_metadata' ->> 'role') = 'Administrador'));

-- Seed once whether the migration runs before or after the first user exists.
select public.seed_default_activities(id)
from public.profiles
order by created_at
limit 1;
