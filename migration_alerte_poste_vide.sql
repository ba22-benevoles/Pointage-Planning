-- ============================================================
-- MIGRATION — Alerte automatique quand un poste tombe à zéro
-- suite au retrait d'un bénévole (congé déclaré après validation
-- du planning). Envoie un email à tous les bénévoles qualifiés
-- sur ce poste, leur demandant s'ils peuvent venir combler le trou.
--
-- ⚠️ Remplace TON_PROJET et TA_SERVICE_ROLE_KEY avant d'exécuter
-- (mêmes valeurs que pour l'envoi automatique du planning).
-- ============================================================

create extension if not exists pg_net;

create or replace function retirer_planning_si_conge()
returns trigger
security definer
set search_path = public
as $$
declare
  r record;
begin
  -- Mémorise les (poste, date) concernés avant de les retirer un par un
  for r in
    select poste_id, date from planning
    where benevole_id = NEW.benevole_id
      and date >= NEW.debut and date <= NEW.fin
  loop
    delete from planning
    where benevole_id = NEW.benevole_id and poste_id = r.poste_id and date = r.date;

    -- Ce poste est-il maintenant vide ce jour-là ?
    if not exists (select 1 from planning where poste_id = r.poste_id and date = r.date) then
      perform net.http_post(
        url := 'https://pljyvybrcjrhmguewrzy.supabase.co/functions/v1/alerte-poste-vide',
        headers := jsonb_build_object(
          'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBsanl2eWJyY2pyaG1ndWV3cnp5Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NjY0NTYxNSwiZXhwIjoyMTAyMjIxNjE1fQ.MeaM43q6m7-CqbfTbTVNFu3x3iwrEjGtgFbdmb-48ys',
          'Content-Type', 'application/json'
        ),
        body := jsonb_build_object('poste_id', r.poste_id, 'date', r.date::text)
      );
    end if;
  end loop;
  return NEW;
end;
$$ language plpgsql;
