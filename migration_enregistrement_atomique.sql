-- ============================================================
-- MIGRATION — Enregistrement atomique du planning
-- Avant : suppression puis réinsertion en deux appels séparés —
-- si la réinsertion échouait (ex. contrainte violée), la suppression
-- restait acquise et des données étaient perdues.
-- Après : tout se passe dans une seule transaction côté serveur —
-- soit tout réussit, soit rien ne change.
-- ============================================================

create or replace function enregistrer_planning_semaine(p_lundi date, p_vendredi date, p_lignes jsonb)
returns void
security definer
set search_path = public
as $$
begin
  delete from planning where date between p_lundi and p_vendredi;

  insert into planning (date, poste_id, benevole_id, valide, destination, accompagnant)
  select
    (r->>'date')::date,
    (r->>'poste_id')::int,
    (r->>'benevole_id')::uuid,
    true,
    r->>'destination',
    coalesce((r->>'accompagnant')::boolean, false)
  from jsonb_array_elements(p_lignes) as r;
end;
$$ language plpgsql;
