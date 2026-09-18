-- ============================================================
-- MIGRATION — Pointage à distance pour certains bénévoles
-- (ex. "relation publique", qui ne viennent jamais à la BA).
-- Indépendant du kiosque et de toute restriction IP future :
-- repose sur leur authentification personnelle (lien magique),
-- plus solide qu'un mot de passe partagé.
-- ============================================================

alter table benevoles add column pointage_distance boolean not null default false;

-- Permet à un bénévole autorisé d'insérer/modifier SES PROPRES pointages,
-- via sa session authentifiée (lien magique) — jamais ceux d'un autre.
create policy "pointage a distance - insertion"
  on pointages for insert
  with check (
    benevole_id in (
      select id from benevoles
      where auth_user_id = auth.uid() and pointage_distance = true
    )
  );

create policy "pointage a distance - modification"
  on pointages for update
  using (
    benevole_id in (
      select id from benevoles
      where auth_user_id = auth.uid() and pointage_distance = true
    )
  );
