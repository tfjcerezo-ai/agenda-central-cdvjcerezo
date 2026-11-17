-- 17/11/2026 · Direcciones de entrega en la ficha de cliente y en cada pedido (documento 08)
-- No se pierde nada: la columna «direccion» de crm_leads sigue igual y pasa a mostrarse como dirección fiscal.
begin;

-- Ficha de cliente: lista de direcciones de entrega y casilla «la entrega es en la dirección fiscal»
-- Cada elemento: {id, etiqueta, direccion, cp, poblacion, provincia, contacto, telefono, defecto}
alter table crm_leads add column if not exists entregas jsonb not null default '[]'::jsonb;
alter table crm_leads add column if not exists entrega_fiscal boolean not null default true;

-- Pedido o propuesta: dirección de entrega, persona de contacto y teléfono de ese pedido concreto
-- {etiqueta, direccion, cp, poblacion, provincia, contacto, telefono}
alter table crm_presupuestos add column if not exists entrega jsonb;

-- Pedidos web que ya habían entrado con «Entrega» pero sin procesar no necesitan cambios:
-- el dato sigue en crm_pedidos_web.datos->cliente->entrega y el CRM lo lleva ahora al pedido.

-- ESMEFAVEN, S.L.: fiscal C/ Altozano 1 - 1ºE; entrega en C/ Juan Blasco Baquero 9 (Almendralejo)
update crm_leads set entrega_fiscal = false,
  entregas = '[{"id":"e1","etiqueta":"Entrega","direccion":"C/ Juan Blasco Baquero, 9","cp":"06200","poblacion":"Almendralejo","provincia":"Badajoz","contacto":null,"telefono":null,"defecto":true}]'::jsonb
where id = 107;
update crm_presupuestos set entrega = '{"etiqueta":"Entrega","direccion":"C/ Juan Blasco Baquero, 9","cp":"06200","poblacion":"Almendralejo","provincia":"Badajoz","contacto":null,"telefono":null}'::jsonb
where id = 18;

commit;
select id, empresa, direccion, entrega_fiscal, entregas from crm_leads where id = 107;
