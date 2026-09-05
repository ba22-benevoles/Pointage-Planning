-- ============================================================
-- CORRECTIF — Le déclencheur de retrait du planning en cas de congé
-- s'exécutait avec les droits de la personne qui insère le congé.
-- Si c'est le bénévole lui-même (lien magique, pas un admin), les
-- règles de sécurité (RLS) bloquaient silencieusement la suppression
-- dans "planning". Passage en SECURITY DEFINER pour que ça fonctionne
-- systématiquement, peu importe qui déclare le congé.
-- ============================================================

create or replace function retirer_planning_si_conge()
returns trigger
security definer
set search_path = public
as $$
begin
  delete from planning
  where benevole_id = NEW.benevole_id
    and date >= NEW.debut
    and date <= NEW.fin;
  return NEW;
end;
$$ language plpgsql;

-- Même précaution pour le déclencheur sur changement de statut
create or replace function retirer_planning_si_statut_change()
returns trigger
security definer
set search_path = public
as $$
begin
  if NEW.statut is distinct from OLD.statut and NEW.statut <> 'actif' then
    delete from planning where benevole_id = NEW.id;
  end if;
  return NEW;
end;
$$ language plpgsql;
