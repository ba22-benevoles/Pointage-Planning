-- ============================================================
-- MIGRATION — Seuil d'alerte configurable par poste
-- Remplace le déclenchement "uniquement à zéro" par un seuil
-- réglable poste par poste (ex. Chauffeur : alerte dès 6, même
-- si le max est 9). Un seuil non renseigné (null) désactive
-- l'alerte pour ce poste — comportement par défaut, rien ne se
-- déclenche tant que l'admin n'a pas explicitement réglé un seuil.
-- ============================================================

alter table postes add column seuil_alerte int;

create or replace function retirer_planning_si_conge()
returns trigger
security definer
set search_path = public
as $$
declare
  r record;
  nb_restant int;
  seuil int;
  nom_poste text;
begin
  for r in
    select poste_id, date from planning
    where benevole_id = NEW.benevole_id
      and date >= NEW.debut and date <= NEW.fin
  loop
    delete from planning
    where benevole_id = NEW.benevole_id and poste_id = r.poste_id and date = r.date;

    select count(*) into nb_restant from planning where poste_id = r.poste_id and date = r.date;
    select seuil_alerte, nom into seuil, nom_poste from postes where id = r.poste_id;

    if seuil is not null and nb_restant <= seuil then
      perform net.http_post(
        url := 'https://TON_PROJET.supabase.co/functions/v1/alerte-poste-vide',
        headers := jsonb_build_object(
          'Authorization', 'Bearer TA_SERVICE_ROLE_KEY',
          'Content-Type', 'application/json'
        ),
        body := jsonb_build_object('poste_id', r.poste_id, 'date', r.date::text, 'nb_restant', nb_restant, 'seuil', seuil)
      );
    end if;
  end loop;
  return NEW;
end;
$$ language plpgsql;
