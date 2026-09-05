-- ============================================================
-- MIGRATION — Lavage des camions
-- Techniquement un poste comme un autre (réutilise toute la mécanique
-- existante : édition, persistance, impression, email), mais affiché
-- fusionné en une ligne supplémentaire dans le tableau Chauffeur,
-- jamais comme un tableau séparé (géré côté appli).
-- ============================================================

insert into postes (id, nom, effectif_min, effectif_max)
select coalesce(max(id), 0) + 1, 'Lavage des camions', 0, 1 from postes;
