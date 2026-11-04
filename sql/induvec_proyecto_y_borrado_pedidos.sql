-- 5/11/2026: descargas del catálogo → proyecto «Induvec (catálogo conjunto)»; el director puede borrar pedidos web
begin;
drop policy if exists p_pw_borrar on crm_pedidos_web;
create policy p_pw_borrar on crm_pedidos_web for delete to authenticated using (crm_es_director());
delete from crm_pedidos_web where id in (1, 2);

create or replace function public.induvec_recibir_descarga(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_correo text; v_prod text; v_id bigint; n int;
  v_javi uuid := 'b9974cda-2bbf-40e9-9c83-88d2bf1aef2f'; v_koen uuid := '2a58e7e6-8141-46be-89b6-6f6907dc1e50';
begin
  if p is null or jsonb_typeof(p) <> 'object' or length(p::text) > 5000 then raise exception 'Datos no válidos'; end if;
  v_correo := lower(trim(coalesce(p->>'correo', '')));
  if v_correo !~ '^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$' then raise exception 'Correo no válido'; end if;
  select count(*) into n from crm_leads where origen = 'Descarga catálogo' and creado > now() - interval '1 hour';
  if n >= 30 then raise exception 'Demasiadas descargas seguidas. Inténtelo más tarde'; end if;
  v_prod := left(trim(coalesce(p->>'producto', '')), 200);
  -- ¿ya existe ese contacto? se anota la descarga en su ficha
  select id into v_id from crm_leads where lower(email) = v_correo order by actualizado desc limit 1;
  if v_id is not null then
    insert into crm_actividad (lead_id, autor_id, tipo, texto) values (v_id, v_javi, 'nota', 'Ha descargado el catálogo técnico desde induvec.com' || case when v_prod <> '' then ' · le interesa: ' || v_prod else '' end);
    update crm_leads set actualizado = now() where id = v_id;
    return v_id;
  end if;
  insert into crm_leads (proyecto_id, empresa, contacto, email, telefono, etapa, prioridad, origen, closer_id, setter_id, creado_por, extra, proximo_paso, proximo_paso_fecha)
  values ('induvec', coalesce(nullif(left(trim(p->>'empresa'), 160), ''), left(trim(p->>'nombre'), 120), v_correo), nullif(left(trim(p->>'nombre'), 120), ''), v_correo,
          nullif(left(trim(p->>'telefono'), 40), ''), 'Nuevo', 'media', 'Descarga catálogo', v_javi, v_koen, v_javi,
          jsonb_strip_nulls(jsonb_build_object('Origen web', 'Descarga del catálogo técnico', 'Producto de interés', nullif(v_prod, ''))), 'Llamar: ha descargado el catálogo técnico', current_date)
  returning id into v_id;
  insert into crm_actividad (lead_id, autor_id, tipo, texto) values (v_id, v_javi, 'nota', 'Contacto nuevo desde induvec.com: ha descargado el catálogo técnico' || case when v_prod <> '' then ' · le interesa: ' || v_prod else '' end);
  return v_id;
end $$;
revoke all on function public.induvec_recibir_descarga(jsonb) from public;
grant execute on function public.induvec_recibir_descarga(jsonb) to anon, authenticated;

-- el contacto de descarga que ya había entrado en José Bernad pasa a Induvec
update crm_leads set proyecto_id = 'induvec' where origen = 'Descarga catálogo' and proyecto_id in ('jose-bernad', 'cayfi');
commit;
select (select count(*) from crm_pedidos_web) as pedidos_web, (select count(*) from crm_leads where proyecto_id = 'induvec') as leads_induvec;
