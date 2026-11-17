-- 17/11/2026: numeración correlativa por año de las propuestas sin número (P26-0001, P26-0002…)
-- Antes se usaba el id interno (P26-0018). El primer pedido real de ESMEFAVEN se renumeró a P26-0001.
create or replace function public.crm_presu_numero() returns trigger language plpgsql as $function$
declare v_pref text; v_n int;
begin
  if TG_OP = 'INSERT' and NEW.numero is null then
    v_pref := 'P' || to_char(coalesce(NEW.fecha, current_date), 'YY') || '-';
    select coalesce(max(substring(numero from length(v_pref) + 1)::int), 0) + 1 into v_n
      from crm_presupuestos where numero ~ ('^' || v_pref || '[0-9]{4}$');
    NEW.numero := v_pref || lpad(v_n::text, 4, '0');
  end if;
  NEW.actualizado := now();
  return NEW;
end $function$;
