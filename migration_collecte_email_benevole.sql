-- =====================================================================
-- Collecte : email facultatif des bénévoles inscrits sur un créneau
-- (à exécuter une fois dans le SQL Editor ; rejouable sans risque)
-- L'email est effacé à la clôture, comme le nom et le téléphone.
-- =====================================================================
alter table collecte_inscriptions add column if not exists email text;

create or replace function collecte_cloturer()
returns json language plpgsql security definer set search_path = public as $$
declare
  v_inscr int; v_acces int; v_comptes int := 0;
  v_emails text[];
begin
  if not collecte_est_responsable() then raise exception 'Réservé au responsable collecte'; end if;
  if exists (select 1 from collecte_parametres where id = 1 and cloturee_le is not null) then
    raise exception 'Collecte déjà clôturée';
  end if;

  update collecte_inscriptions
     set nom = '—', telephone = null, email = null, remarque = null, cree_par = null
   where true;
  get diagnostics v_inscr = row_count;

  -- affectations des chauffeurs (et camions) aux tournées
  delete from collecte_equipages where true;

  select array_agg(distinct lower(email)) into v_emails
    from collecte_acces where role = 'referent' and consentement_le is null;
  delete from collecte_acces where role = 'referent' and consentement_le is null;
  get diagnostics v_acces = row_count;

  -- comptes de connexion devenus inutiles
  begin
    delete from auth.users u
     where lower(u.email) = any (coalesce(v_emails, '{}'))
       and not exists (select 1 from collecte_acces a where lower(a.email) = lower(u.email))
       and not exists (select 1 from admins ad where ad.user_id = u.id)
       and not exists (select 1 from benevoles b where b.auth_user_id = u.id);
    get diagnostics v_comptes = row_count;
  exception when others then
    raise warning 'Comptes de connexion non supprimés : %', sqlerrm;
  end;

  update collecte_parametres set cloturee_le = now() where id = 1;
  return json_build_object('inscriptions', v_inscr, 'acces', v_acces, 'comptes', v_comptes);
end $$;
