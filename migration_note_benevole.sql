-- ============================================================
-- MIGRATION — Champ "Note" libre sur la fiche bénévole
-- (ex. pense-bête pour les cas particuliers : "Frais le lundi,
-- Tri le mercredi"). "if not exists" au cas où ce champ aurait
-- déjà été créé lors d'un import antérieur.
-- ============================================================

alter table benevoles add column if not exists note text;
