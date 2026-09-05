-- ============================================================
-- MIGRATION — Retrait automatique du planning quand un bénévole
-- passe à un statut autre qu'"actif" (longue absence, congés, inactif)
-- ============================================================

create or replace function retirer_planning_si_statut_change()
returns trigger as $$
begin
  if NEW.statut is distinct from OLD.statut and NEW.statut <> 'actif' then
    delete from planning where benevole_id = NEW.id;
  end if;
  return NEW;
end;
$$ language plpgsql;

create trigger trg_retirer_planning_si_statut_change
after update on benevoles
for each row execute function retirer_planning_si_statut_change();
