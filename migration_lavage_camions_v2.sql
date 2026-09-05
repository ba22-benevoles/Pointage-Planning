-- ============================================================
-- MIGRATION — Lavage des camions (marqueur simple par jour)
-- Remplace l'approche précédente (poste avec sélection de personne)
-- par un simple marqueur "ce jour-là, c'est lavage", sans lier
-- ça à un bénévole précis — c'est l'équipe du jour qui s'en charge.
-- ============================================================

create table lavage_camions (
  date date primary key
);

alter table lavage_camions enable row level security;

create policy "lavage - lecture publique"
  on lavage_camions for select
  using (true);

create policy "lavage - admin gere"
  on lavage_camions for all
  using (exists (select 1 from admins where user_id = auth.uid()));

-- Le poste technique "Lavage des camions" créé précédemment n'est plus utilisé,
-- on peut le retirer proprement (aucune ligne de planning n'y était jamais rattachée).
delete from postes where nom = 'Lavage des camions';
