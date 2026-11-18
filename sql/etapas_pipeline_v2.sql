-- 18/11/2026: nuevas etapas del pipeline (las etapas dicen lo que ya ha pasado; lo pendiente va en «próximo paso»)
-- Nuevo · No contesta · Contactado · Info enviada · Reunión · Negociación · Seguimiento · Cierre ganado · Cierre perdido · Descartado
begin;
alter table crm_leads drop constraint if exists crm_leads_etapa_check;
update crm_leads set etapa = 'No contesta' where etapa = 'No contactado';
-- (18/11 21:45) «Propuesta» se mantiene: pendiente de enviar propuesta
update crm_leads set etapa = 'Descartado' where etapa = 'No interesa / No cualifica';
alter table crm_leads add constraint crm_leads_etapa_check check (etapa = any (array['Nuevo','No contesta','Contactado','Info enviada','Reunión','Propuesta','Negociación','Seguimiento','Cierre ganado','Cierre perdido','Descartado']));
commit;
select etapa, count(*) from crm_leads group by etapa order by 2 desc;
