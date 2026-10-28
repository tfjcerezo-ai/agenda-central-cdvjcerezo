begin;
-- 1) Las propuestas aceptadas de CAYFI también crean la venta con su comisión (10 % = 5 % Javier + 5 % Koenraad)
create or replace function public.crm_compra_a_venta()
 returns trigger language plpgsql security definer set search_path to 'public' as $function$
DECLARE
  v_lead crm_leads%ROWTYPE; v_pz crm_presupuestos%ROWTYPE; v_proy text;
  v_margen numeric := 0; v_sin_neta int := 0; v_nota text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM ventas WHERE crm_compra_id = OLD.id AND estado = 'pendiente';
    RETURN OLD;
  END IF;
  IF NEW.presupuesto_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO v_lead FROM crm_leads WHERE id = NEW.lead_id;
  SELECT * INTO v_pz FROM crm_presupuestos WHERE id = NEW.presupuesto_id;
  IF v_lead.proyecto_id NOT IN ('jose-bernad', 'cayfi') THEN RETURN NEW; END IF;
  SELECT nombre INTO v_proy FROM crm_proyectos WHERE id = v_lead.proyecto_id;
  SELECT coalesce(sum(CASE WHEN n.neta IS NOT NULL THEN
           (l->>'cantidad')::numeric * ((l->>'precio')::numeric * (1 - coalesce((l->>'dto')::numeric,0)/100) - n.neta) END), 0),
         count(*) FILTER (WHERE n.neta IS NULL AND NOT coalesce((l->>'fuera')::boolean, false))
    INTO v_margen, v_sin_neta
    FROM jsonb_array_elements(coalesce(v_pz.lineas,'[]'::jsonb)) l
    LEFT JOIN crm_catalogo_neta n ON n.id = l->>'id';
  v_nota := 'Desde el CRM · propuesta ' || coalesce(v_pz.numero, '#' || v_pz.id::text)
            || CASE WHEN v_lead.proyecto_id = 'cayfi' THEN ' · CAYFI factura al cliente y paga el 10 %' ELSE '' END
            || CASE WHEN v_sin_neta > 0 THEN ' · ' || v_sin_neta || ' línea(s) sin comisión calculada: añadirla a mano' ELSE '' END;
  IF TG_OP = 'INSERT' THEN
    INSERT INTO ventas (id, cliente, proyecto, producto, importe, closer, setter, fecha_cobro, estado, tipo_cobro,
                        com_cdv, com_closer, com_setter, com_jr, notas, crm_compra_id)
    VALUES ((extract(epoch FROM clock_timestamp()) * 1000)::bigint, v_lead.empresa, coalesce(v_proy, 'José Bernad'), NULL, NEW.importe,
            'Javier Cerezo', 'Koenraad', NEW.fecha::text, 'pendiente', 'unico',
            0, round(v_margen / 2, 2), round(v_margen / 2, 2), 0, v_nota, NEW.id)
    ON CONFLICT DO NOTHING;
  ELSE
    UPDATE ventas SET importe = NEW.importe, com_closer = round(v_margen / 2, 2), com_setter = round(v_margen / 2, 2), notas = v_nota
     WHERE crm_compra_id = NEW.id AND estado = 'pendiente';
  END IF;
  RETURN NEW;
END $function$;

-- 2) Descarga del catálogo técnico desde induvec.com → contacto nuevo «Descarga catálogo» (sin duplicar por correo)
create or replace function public.induvec_recibir_descarga(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_correo text; v_prod text; v_proy text; v_id bigint; n int;
  v_javi uuid := 'b9974cda-2bbf-40e9-9c83-88d2bf1aef2f'; v_koen uuid := '2a58e7e6-8141-46be-89b6-6f6907dc1e50';
begin
  if p is null or jsonb_typeof(p) <> 'object' or length(p::text) > 5000 then raise exception 'Datos no válidos'; end if;
  v_correo := lower(trim(coalesce(p->>'correo', '')));
  if v_correo !~ '^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$' then raise exception 'Correo no válido'; end if;
  select count(*) into n from crm_leads where origen = 'Descarga catálogo' and creado > now() - interval '1 hour';
  if n >= 30 then raise exception 'Demasiadas descargas seguidas. Inténtelo más tarde'; end if;
  v_prod := left(trim(coalesce(p->>'producto', '')), 200);
  v_proy := case when v_prod ~* '(revest|friso|techo|panel|pared|escocia|perfil base|rodapi|z[oó]calo-rodapi|covindu|policarb)' then 'cayfi' else 'jose-bernad' end;
  -- ¿ya existe ese contacto? se anota la descarga en su ficha
  select id into v_id from crm_leads where lower(email) = v_correo order by actualizado desc limit 1;
  if v_id is not null then
    insert into crm_actividad (lead_id, autor_id, tipo, texto) values (v_id, v_javi, 'nota', 'Ha descargado el catálogo técnico desde induvec.com' || case when v_prod <> '' then ' · le interesa: ' || v_prod else '' end);
    update crm_leads set actualizado = now() where id = v_id;
    return v_id;
  end if;
  insert into crm_leads (proyecto_id, empresa, contacto, email, telefono, etapa, prioridad, origen, closer_id, setter_id, creado_por, extra, proximo_paso, proximo_paso_fecha)
  values (v_proy, coalesce(nullif(left(trim(p->>'empresa'), 160), ''), left(trim(p->>'nombre'), 120), v_correo), nullif(left(trim(p->>'nombre'), 120), ''), v_correo,
          nullif(left(trim(p->>'telefono'), 40), ''), 'Nuevo', 'media', 'Descarga catálogo', v_javi, v_koen, v_javi,
          jsonb_strip_nulls(jsonb_build_object('Origen web', 'Descarga del catálogo técnico', 'Producto de interés', nullif(v_prod, ''))), 'Llamar: ha descargado el catálogo técnico', current_date)
  returning id into v_id;
  insert into crm_actividad (lead_id, autor_id, tipo, texto) values (v_id, v_javi, 'nota', 'Contacto nuevo desde induvec.com: ha descargado el catálogo técnico' || case when v_prod <> '' then ' · le interesa: ' || v_prod else '' end);
  return v_id;
end $$;
revoke all on function public.induvec_recibir_descarga(jsonb) from public;
grant execute on function public.induvec_recibir_descarga(jsonb) to anon, authenticated;
commit;
