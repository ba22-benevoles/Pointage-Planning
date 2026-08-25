-- ============================================================
-- MIGRATION — Annotation "destination" sur une affectation de planning
-- (usage principal : signaler qu'un chauffeur va à Saint-Brieuc ce jour-là)
-- ============================================================

alter table planning add column destination text;
