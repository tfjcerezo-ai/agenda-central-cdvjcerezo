-- 20/11/2026 · Pedidos web: la línea guarda también «piezas» y «metros_pieza» (documento 13)
-- La web manda cantidad en metros y precio en €/m; para productos que se sirven en piezas enteras añade piezas y metros_pieza.
begin;
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
    limpio := limpio || jsonb_build_array(jsonb_build_object('ref', x->>'ref', 'cantidad', greatest(0, least(100000, coalesce((x->>'cantidad')::numeric, 0))), 'precio_web', (x->>'precio')::numeric)
      || case when coalesce(x->>'piezas', '') ~ '^[0-9]+(\.[0-9]+)?$' then jsonb_build_object('piezas', least(100000, (x->>'piezas')::numeric)) else '{}'::jsonb end
      || case when coalesce(x->>'metros_pieza', '') ~ '^[0-9]+(\.[0-9]+)?$' then jsonb_build_object('metros_pieza', least(100, (x->>'metros_pieza')::numeric)) else '{}'::jsonb end);
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
