-- 20/11/2026 · Doc 10: venta por pieza, nombres y descripciones únicos (José Bernad)
begin;
alter table crm_catalogo add column if not exists pieza_m numeric;
update crm_catalogo set pieza_m = 2 where ref_web in ('IV-ZOC-001','IV-ZOC-002','IV-ZOC-003','IV-ZOC-004','IV-ZOC-005','IV-ZOC-006','IV-CHA-001','IV-CHA-002');
update crm_catalogo set pieza_m = 3 where ref_web ~ '^IV-CHA-0(0[3-9]|[12][0-9]|3[01])$';
update crm_catalogo set pieza_m = 4 where ref_web in ('IV-PSA-001','IV-PSA-002','IV-PSA-003','IV-PSA-004');
-- Zócalo sanitario ZS (20 mm)
update crm_catalogo set detalle = 'Polietileno de alta densidad prensado, machihembrado. Espesor 20 mm. Se sirve en piezas enteras de 2 m.' where id in ('jb-zs200','jb-zs300','jb-zs500');
-- Protección de pared doble bisel (15 mm), nombre como en la tarifa de José Bernad
update crm_catalogo set nombre = 'Protección de pared doble bisel 200 mm' where id = 'jb-zs200-2v';
update crm_catalogo set nombre = 'Protección de pared doble bisel 300 mm' where id = 'jb-zs300-2v';
update crm_catalogo set nombre = 'Protección de pared doble bisel 500 mm' where id = 'jb-zs500-2v';
update crm_catalogo set detalle = 'Protector de pared (PRP). Polietileno de alta densidad prensado, machihembrado. Espesor 15 mm, fijaciones cada 633 mm. Se sirve en piezas enteras de 2 m.' where id in ('jb-zs200-2v','jb-zs300-2v','jb-zs500-2v');
commit;
select pieza_m, count(*) from crm_catalogo where pieza_m is not null group by pieza_m order by 1;
