-- ============================================================
-- MIGRATION — Distinction chauffeur / accompagnant sur le planning
-- (permis vérifié vs bénévole qui accompagne sans conduire)
-- ============================================================

alter table planning add column accompagnant boolean not null default false;
