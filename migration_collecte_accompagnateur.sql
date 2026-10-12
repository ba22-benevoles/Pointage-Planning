-- =====================================================================
-- Collecte : accompagnateur facultatif dans l'équipage d'une tournée
-- (à exécuter une fois dans le SQL Editor ; rejouable sans risque)
-- L'accompagnateur est effacé à la clôture avec le reste de l'équipage.
-- =====================================================================
alter table collecte_equipages add column if not exists accompagnateur text;

create or replace function collecte_trg_equipage()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_autre int;
begin
  select e.tournee into v_autre from collecte_equipages e
   where e.jour = new.jour and e.tournee <> new.tournee
     and (e.chauffeur_1 in (new.chauffeur_1, new.chauffeur_2) or e.chauffeur_2 in (new.chauffeur_1, new.chauffeur_2))
   limit 1;
  if v_autre is not null then
    raise exception 'Chauffeur déjà affecté à la tournée % ce jour-là', v_autre;
  end if;
  new.camion := nullif(trim(new.camion), '');
  new.accompagnateur := nullif(trim(new.accompagnateur), '');
  return new;
end $$;
