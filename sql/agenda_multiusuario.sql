-- 25/11/2026: Agenda Central multiusuario.
-- Cada usuario activo del CRM tiene su propia agenda (tareas, citas, notas, tiempo, finanzas personales y familiares).
-- Nadie ve la agenda de otro, salvo el director, que puede ver la de todos.
-- Todo lo que existe hoy pasa a ser de Javier (javier@cdvbyjcerezo.com). No se borra ningún dato.
-- Liga (mov_liga), equipo y ventas no cambian: siguen siendo del director (y los socios leen las ventas de sus proyectos).
-- Además: se quitan los permisos sobrantes del usuario sin sesión (anon) en crm_pedidos_web y en las tablas futuras.
begin;

do $$
declare
  t text;
  v_javier uuid := (select id from public.crm_perfiles where lower(email) = 'javier@cdvbyjcerezo.com' and rol = 'director');
begin
  if v_javier is null then raise exception 'No se encuentra el perfil de director de javier@cdvbyjcerezo.com'; end if;
  foreach t in array array['tareas','eventos','notas','registros','proyectos','incubacion','fin_personal','fin_familiar'] loop
    execute format('alter table public.%I add column if not exists usuario_id uuid references public.crm_perfiles(id)', t);
    execute format('update public.%I set usuario_id = %L where usuario_id is null', t, v_javier);
    execute format('alter table public.%I alter column usuario_id set default auth.uid()', t);
    execute format('alter table public.%I alter column usuario_id set not null', t);
    execute format('create index if not exists %I on public.%I (usuario_id)', t || '_usuario_idx', t);
    execute format('drop policy if exists p_agenda_director on public.%I', t);
    execute format('drop policy if exists p_agenda_propia on public.%I', t);
    execute format($p$create policy p_agenda_propia on public.%I for all to authenticated
      using (crm_es_director() or (crm_activo() and usuario_id = auth.uid()))
      with check (crm_es_director() or (crm_activo() and usuario_id = auth.uid()))$p$, t);
  end loop;
end $$;

-- Permisos sobrantes del usuario sin sesión
revoke all on table public.crm_pedidos_web from anon;
revoke all on sequence public.crm_pedidos_web_id_seq from anon;
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;

commit;

-- Comprobación
select t as tabla,
  (select count(*) from information_schema.columns where table_schema='public' and table_name=t and column_name='usuario_id') as tiene_usuario,
  (select count(*) from pg_policies where schemaname='public' and tablename=t and policyname='p_agenda_propia') as politica
from unnest(array['tareas','eventos','notas','registros','proyectos','incubacion','fin_personal','fin_familiar']) t;
