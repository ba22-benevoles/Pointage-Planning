-- ============================================================
-- CORRECTIF — Pointages manquants pour LE MERRER Louis et Ghislaine
-- (bug d'extraction corrigé, ces 2 personnes avaient été zappées)
-- ============================================================

insert into pointages (benevole_id, date, heure_arrivee, heure_depart, type)
select b.id, v.date_ptg::date, '00:00:00'::time,
       ('00:00:00'::time + (v.minutes * interval '1 minute'))::time, 'presence'
from benevoles b
join (values
  (755, '2026-01-09', 89),
  (755, '2026-01-16', 180),
  (755, '2026-01-23', 110),
  (755, '2026-01-30', 105),
  (755, '2026-02-06', 180),
  (755, '2026-02-13', 109),
  (755, '2026-02-20', 102),
  (755, '2026-02-27', 97),
  (755, '2026-03-06', 105),
  (755, '2026-03-13', 180),
  (755, '2026-03-20', 180),
  (755, '2026-03-27', 45),
  (755, '2026-04-03', 180),
  (755, '2026-04-17', 79),
  (755, '2026-04-24', 180),
  (755, '2026-05-22', 87),
  (755, '2026-05-29', 99),
  (755, '2026-06-05', 108),
  (755, '2026-06-19', 125),
  (755, '2026-06-26', 128),
  (755, '2026-07-03', 180),
  (755, '2026-07-17', 105),
  (755, '2026-07-24', 130),
  (755, '2026-07-31', 113),
  (103, '2026-01-09', 89),
  (103, '2026-01-16', 180),
  (103, '2026-01-23', 110),
  (103, '2026-02-06', 180),
  (103, '2026-02-13', 109),
  (103, '2026-02-20', 102),
  (103, '2026-02-27', 97),
  (103, '2026-03-06', 106),
  (103, '2026-03-13', 180),
  (103, '2026-03-20', 180),
  (103, '2026-03-27', 45),
  (103, '2026-04-17', 80),
  (103, '2026-04-24', 180),
  (103, '2026-05-22', 86),
  (103, '2026-05-29', 1),
  (103, '2026-06-05', 108),
  (103, '2026-06-19', 125),
  (103, '2026-06-26', 128),
  (103, '2026-07-03', 180),
  (103, '2026-07-17', 105),
  (103, '2026-07-24', 129),
  (103, '2026-07-31', 112)
) as v(numero, date_ptg, minutes) on b.numero = v.numero;

-- Recalcule le compteur nb_presences pour tout le monde (rapide, sans risque)
update benevoles b
set nb_presences = coalesce((select count(distinct date) from pointages p where p.benevole_id = b.id and p.type = 'presence'), 0);

-- Vérification ciblée sur ces 2 personnes
select b.numero, b.nom, b.prenom,
  (select count(distinct p.date) from pointages p where p.benevole_id = b.id and p.type = 'presence') as jours_calcules,
  round((select coalesce(sum(extract(epoch from duree_pointage(p.heure_arrivee, p.heure_depart)) / 3600.0), 0)
    from pointages p where p.benevole_id = b.id and p.type = 'presence')::numeric, 2) as heures_calculees
from benevoles b where b.nom = 'LE MERRER' and b.prenom in ('Louis', 'Ghislaine');
