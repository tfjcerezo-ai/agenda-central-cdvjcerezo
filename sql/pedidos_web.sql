-- Pedidos web de INDUVEC → CRM de CDV by JCerezo
begin;
alter table crm_catalogo add column if not exists ref_web text;
create unique index if not exists crm_catalogo_ref_web_uq on crm_catalogo (ref_web) where ref_web is not null;
alter table crm_presupuestos add column if not exists enviado_fab timestamptz;
alter table crm_presupuestos add column if not exists pedido_web_id bigint;
create table if not exists crm_pedidos_web (
  id bigserial primary key,
  recibido timestamptz not null default now(),
  datos jsonb not null,
  estado text not null default 'nuevo' check (estado in ('nuevo','procesado','descartado')),
  procesado timestamptz
);
alter table crm_pedidos_web enable row level security;
drop policy if exists p_pw_ver on crm_pedidos_web;
drop policy if exists p_pw_crear on crm_pedidos_web;
drop policy if exists p_pw_editar on crm_pedidos_web;
create policy p_pw_ver on crm_pedidos_web for select to authenticated using (crm_es_director());
create policy p_pw_crear on crm_pedidos_web for insert to authenticated with check (crm_es_director());
create policy p_pw_editar on crm_pedidos_web for update to authenticated using (crm_es_director()) with check (crm_es_director());

-- Punto de entrada público para la web (clave anónima): solo puede dejar un pedido «nuevo», validado y limitado
create or replace function induvec_recibir_pedido(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare n int; nid bigint; lin jsonb; limpio jsonb := '[]'::jsonb; x jsonb;
begin
  if p is null or jsonb_typeof(p) <> 'object' or length(p::text) > 20000 then raise exception 'Pedido no válido'; end if;
  lin := p->'lineas';
  if jsonb_typeof(lin) <> 'array' or jsonb_array_length(lin) = 0 or jsonb_array_length(lin) > 150 then raise exception 'Líneas no válidas'; end if;
  if coalesce(p#>>'{cliente,correo}', '') = '' and coalesce(p#>>'{cliente,telefono}', '') = '' then raise exception 'Falta un correo o un teléfono de contacto'; end if;
  for x in select * from jsonb_array_elements(lin) loop
    if coalesce(x->>'ref', '') !~ '^IV-[A-Z0-9]+-[A-Z0-9]+$' then raise exception 'Referencia no válida'; end if;
    limpio := limpio || jsonb_build_array(jsonb_build_object('ref', x->>'ref', 'cantidad', greatest(0, least(100000, coalesce((x->>'cantidad')::numeric, 0))), 'precio_web', (x->>'precio')::numeric));
  end loop;
  select count(*) into n from crm_pedidos_web where recibido > now() - interval '1 hour';
  if n >= 30 then raise exception 'Demasiados pedidos seguidos. Inténtelo más tarde'; end if;
  insert into crm_pedidos_web (datos) values (jsonb_build_object(
    'cliente', jsonb_build_object('nombre', left(p#>>'{cliente,nombre}', 120), 'empresa', left(p#>>'{cliente,empresa}', 160), 'cif', left(p#>>'{cliente,cif}', 20),
      'correo', left(p#>>'{cliente,correo}', 160), 'telefono', left(p#>>'{cliente,telefono}', 40), 'entrega', left(p#>>'{cliente,entrega}', 300), 'observaciones', left(p#>>'{cliente,observaciones}', 1000)),
    'lineas', limpio, 'idioma', left(p->>'idioma', 5), 'origen', 'web')) returning id into nid;
  return nid;
end $$;
revoke all on function induvec_recibir_pedido(jsonb) from public;
grant execute on function induvec_recibir_pedido(jsonb) to anon, authenticated;
commit;
