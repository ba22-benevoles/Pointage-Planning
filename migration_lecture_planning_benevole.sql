-- ============================================================
-- MIGRATION — Lecture du planning par le bénévole lui-même
-- (pour la section "Mon planning" dans l'espace Mes congés)
-- ============================================================

create policy "benevole voit son propre planning"
  on planning for select
  using (benevole_id in (select id from benevoles where auth_user_id = auth.uid()));
