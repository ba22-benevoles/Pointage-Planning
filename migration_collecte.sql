-- =====================================================================
-- Module COLLECTE (collecte nationale annuelle, début novembre)
-- Page : Dossier_netlify/collecte.html
--
-- Rôles :
--   - responsable collecte : voit et modifie tout (les admins de l'outil
--     le sont automatiquement, via la table admins)
--   - référent magasin    : voit et remplit uniquement son/ses magasin(s)
-- Connexion par lien magique (comme absence.html), sans fiche bénévole :
-- l'accès est accordé par la table collecte_acces.
-- Les inscriptions sont en texte libre, NON reliées à la table benevoles.
-- RGPD : à la clôture (collecte_cloturer), noms et téléphones sont effacés et
-- les référents sans accord de conservation supprimés.
-- Politique de confidentialité : Dossier_netlify/confidentialite-collecte.html
-- Équipages : 2 chauffeurs (bénévoles qualifiés « Chauffeur ») + un camion par
-- tournée et par jour ; affectations effacées à la clôture.
-- =====================================================================

-- ---------- 1. Tables ------------------------------------------------

-- Paramètres de l'édition en cours (une seule ligne)
create table if not exists collecte_parametres (
  id            int primary key default 1 check (id = 1),
  jours         date[] not null,
  heure_debut   time not null default '09:00',
  heure_fin     time not null default '19:00',
  duree_minutes int  not null default 120 check (duree_minutes between 30 and 480),
  cloturee_le   timestamptz   -- renseigné par collecte_cloturer() : données personnelles effacées
);

create table if not exists collecte_magasins (
  id            uuid primary key default gen_random_uuid(),
  nom           text not null,
  commune       text,
  besoin_defaut int  not null default 2 check (besoin_defaut between 0 and 2),
  tournee       int  check (tournee between 1 and 99),  -- n° de tournée des chauffeurs
  actif         boolean not null default true,
  created_at    timestamptz not null default now()
);

create table if not exists collecte_creneaux (
  id          uuid primary key default gen_random_uuid(),
  magasin_id  uuid not null references collecte_magasins(id) on delete cascade,
  jour        date not null,
  heure_debut time not null,
  heure_fin   time not null,
  besoin      int  not null default 2 check (besoin between 0 and 2),
  unique (magasin_id, jour, heure_debut)
);

create table if not exists collecte_inscriptions (
  id          uuid primary key default gen_random_uuid(),
  creneau_id  uuid not null references collecte_creneaux(id) on delete cascade,
  nom         text not null check (length(trim(nom)) > 0),
  telephone   text,
  email       text,         -- facultatif
  remarque    text,
  cree_par    text default (auth.jwt() ->> 'email'),
  created_at  timestamptz not null default now()
);

create table if not exists collecte_acces (
  id          uuid primary key default gen_random_uuid(),
  email       text not null,
  role        text not null check (role in ('responsable', 'referent')),
  magasin_id  uuid references collecte_magasins(id) on delete cascade,
  invite_le   timestamptz,
  consentement_le timestamptz,  -- référent : accord pour conserver son accès jusqu'à la prochaine collecte
  check (role = 'responsable' or magasin_id is not null)
);
create unique index if not exists uq_collecte_acces
  on collecte_acces (lower(email), role, coalesce(magasin_id, '00000000-0000-0000-0000-000000000000'));

-- Équipage d'une tournée pour un jour : camion + 2 chauffeurs (bénévoles de la BA)
create table if not exists collecte_equipages (
  id          uuid primary key default gen_random_uuid(),
  tournee     int  not null check (tournee between 1 and 99),
  jour        date not null,
  camion      text,
  chauffeur_1 uuid references benevoles(id) on delete set null,
  chauffeur_2 uuid references benevoles(id) on delete set null,
  accompagnateur text,   -- facultatif, texte libre (bénévole de la BA)
  unique (tournee, jour),
  check (chauffeur_1 is null or chauffeur_2 is null or chauffeur_1 <> chauffeur_2)
);
-- un camion ne fait qu'une tournée par jour
create unique index if not exists uq_collecte_camion_jour
  on collecte_equipages (jour, lower(trim(camion)))
  where camion is not null and trim(camion) <> '';

create index if not exists idx_coll_creneaux_magasin on collecte_creneaux(magasin_id);
create index if not exists idx_coll_inscr_creneau   on collecte_inscriptions(creneau_id);

-- ---------- 2. Fonctions de droits (security definer : évite la
--               récursion RLS, cf. README) --------------------------

create or replace function collecte_est_responsable()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins where user_id = auth.uid())
      or exists (select 1 from collecte_acces
                 where lower(email) = lower(auth.jwt() ->> 'email')
                   and role = 'responsable');
$$;

create or replace function collecte_gere_magasin(p_magasin uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select collecte_est_responsable() or exists (
    select 1 from collecte_acces
    where lower(email) = lower(auth.jwt() ->> 'email')
      and role = 'referent' and magasin_id = p_magasin);
$$;

create or replace function collecte_gere_creneau(p_creneau uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select collecte_gere_magasin((select magasin_id from collecte_creneaux where id = p_creneau));
$$;

-- Avant d'envoyer le lien magique : cet email a-t-il un accès collecte ?
-- (appelable sans être connecté, ne renvoie qu'un booléen)
create or replace function collecte_email_autorise(p_email text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from collecte_acces where lower(email) = lower(trim(p_email)))
      or exists (select 1 from admins a join auth.users u on u.id = a.user_id
                 where lower(u.email) = lower(trim(p_email)));
$$;

grant execute on function collecte_est_responsable()     to authenticated;
grant execute on function collecte_gere_magasin(uuid)    to authenticated;
grant execute on function collecte_gere_creneau(uuid)    to authenticated;
grant execute on function collecte_email_autorise(text)  to anon, authenticated;

-- ---------- 3. RLS ---------------------------------------------------

alter table collecte_parametres   enable row level security;
alter table collecte_magasins     enable row level security;
alter table collecte_creneaux     enable row level security;
alter table collecte_inscriptions enable row level security;
alter table collecte_acces        enable row level security;
alter table collecte_equipages    enable row level security;

create policy "collecte parametres lecture" on collecte_parametres for select to authenticated
  using (collecte_est_responsable() or exists (
    select 1 from collecte_acces where lower(email) = lower(auth.jwt() ->> 'email')));
create policy "collecte parametres ecriture" on collecte_parametres for all to authenticated
  using (collecte_est_responsable()) with check (collecte_est_responsable());

create policy "collecte magasins lecture" on collecte_magasins for select to authenticated
  using (collecte_gere_magasin(id));
create policy "collecte magasins ecriture" on collecte_magasins for all to authenticated
  using (collecte_est_responsable()) with check (collecte_est_responsable());

create policy "collecte creneaux lecture" on collecte_creneaux for select to authenticated
  using (collecte_gere_magasin(magasin_id));
create policy "collecte creneaux ecriture" on collecte_creneaux for all to authenticated
  using (collecte_est_responsable()) with check (collecte_est_responsable());

create policy "collecte inscriptions" on collecte_inscriptions for all to authenticated
  using (collecte_gere_creneau(creneau_id)) with check (collecte_gere_creneau(creneau_id));

-- Équipages : responsables uniquement (les référents n'y ont pas accès)
create policy "collecte equipages" on collecte_equipages for all to authenticated
  using (collecte_est_responsable()) with check (collecte_est_responsable());

create policy "collecte acces lecture" on collecte_acces for select to authenticated
  using (lower(email) = lower(auth.jwt() ->> 'email') or collecte_est_responsable());
create policy "collecte acces ecriture" on collecte_acces for all to authenticated
  using (collecte_est_responsable()) with check (collecte_est_responsable());

-- ---------- 4. Génération des créneaux ------------------------------
-- Idempotente : ajoute seulement les créneaux manquants.

-- Fonction interne (sans contrôle), non exposée à l'API
create or replace function _collecte_generer()
returns int language plpgsql security definer set search_path = public as $$
declare n int; p collecte_parametres;
begin
  select * into p from collecte_parametres where id = 1;
  if p is null then raise exception 'Paramètres de collecte absents'; end if;

  insert into collecte_creneaux (magasin_id, jour, heure_debut, heure_fin, besoin)
  select m.id, j, h::time, (h + make_interval(mins => p.duree_minutes))::time, m.besoin_defaut
  from collecte_magasins m
  cross join unnest(p.jours) as j
  cross join generate_series('2000-01-01'::timestamp + p.heure_debut,
                             '2000-01-01'::timestamp + p.heure_fin - make_interval(mins => p.duree_minutes),
                             make_interval(mins => p.duree_minutes)) as h
  where m.actif
  on conflict (magasin_id, jour, heure_debut) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function _collecte_generer() from public, anon, authenticated;

-- Version appelable depuis la page (responsable uniquement)
create or replace function collecte_generer_creneaux()
returns int language plpgsql security definer set search_path = public as $$
begin
  if not collecte_est_responsable() then raise exception 'Réservé au responsable collecte'; end if;
  return _collecte_generer();
end $$;
grant execute on function collecte_generer_creneaux() to authenticated;

-- Un nouveau magasin reçoit automatiquement ses créneaux
create or replace function collecte_trg_nouveau_magasin()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform _collecte_generer();
  return new;
end $$;
drop trigger if exists trg_collecte_nouveau_magasin on collecte_magasins;
create trigger trg_collecte_nouveau_magasin after insert on collecte_magasins
  for each row execute function collecte_trg_nouveau_magasin();

-- ---------- 5. Nouvelle édition (et purge RGPD) ---------------------
-- Exige que la collecte précédente soit clôturée (section 9). Efface créneaux
-- et bilan anonyme précédents, enregistre les nouvelles dates (2 collectes par
-- an), régénère les créneaux. Magasins, tournées, responsables et référents
-- ayant donné leur accord sont conservés ; leur accord est à redonner.

create or replace function collecte_nouvelle_edition(p_jours date[])
returns int language plpgsql security definer set search_path = public as $$
begin
  if not collecte_est_responsable() then raise exception 'Réservé au responsable collecte'; end if;
  -- on ne démarre pas une nouvelle édition sans avoir clôturé la précédente
  if exists (select 1 from collecte_inscriptions)
     and not exists (select 1 from collecte_parametres where id = 1 and cloturee_le is not null) then
    raise exception 'Clôture d''abord la collecte en cours (effacement des données personnelles)';
  end if;
  insert into collecte_parametres (id, jours, cloturee_le) values (1, p_jours, null)
    on conflict (id) do update set jours = excluded.jours, cloturee_le = null;
  delete from collecte_creneaux where true;  -- cascade sur les inscriptions (déjà anonymes)
  delete from collecte_equipages where true;
  -- l'accord de conservation vaut « jusqu'à la prochaine collecte » : à redonner à chaque édition
  update collecte_acces set consentement_le = null where role = 'referent';
  return _collecte_generer();
end $$;
grant execute on function collecte_nouvelle_edition(date[]) to authenticated;

-- ---------- 6. Limite : 2 bénévoles maximum par créneau --------------
-- Le besoin (0, 1 ou 2) est aussi le plafond d'inscriptions du créneau.
-- Contrôlé côté base : tient même si deux référents saisissent en même temps.

create or replace function collecte_trg_limite_inscriptions()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_besoin int; v_nb int;
begin
  -- verrou sur le créneau : deux ajouts simultanés passent l'un après l'autre
  select besoin into v_besoin from collecte_creneaux where id = new.creneau_id for update;
  select count(*) into v_nb from collecte_inscriptions
   where creneau_id = new.creneau_id and id <> new.id;
  if exists (select 1 from collecte_parametres where id = 1 and cloturee_le is not null) then
    raise exception 'Collecte clôturée : plus aucune inscription possible';
  end if;
  if v_nb >= v_besoin then
    raise exception 'Créneau complet : % bénévole(s) maximum', v_besoin;
  end if;
  return new;
end $$;
drop trigger if exists trg_collecte_limite_inscriptions on collecte_inscriptions;
create trigger trg_collecte_limite_inscriptions
  before insert or update of creneau_id on collecte_inscriptions
  for each row execute function collecte_trg_limite_inscriptions();

-- On ne peut pas baisser le besoin sous le nombre d'inscrits déjà présents
create or replace function collecte_trg_besoin_creneau()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_nb int;
begin
  select count(*) into v_nb from collecte_inscriptions where creneau_id = new.id;
  if new.besoin < v_nb then
    raise exception 'Créneau déjà rempli : % inscrit(s), retirer d''abord des bénévoles', v_nb;
  end if;
  return new;
end $$;
drop trigger if exists trg_collecte_besoin_creneau on collecte_creneaux;
create trigger trg_collecte_besoin_creneau
  before update of besoin on collecte_creneaux
  for each row execute function collecte_trg_besoin_creneau();

-- ---------- 7. Invitations : état de connexion des accès ------------
-- Pour la responsable : chaque email déclaré a-t-il déjà cliqué sur un lien ?
-- (lit auth.users, donc security definer + contrôle du rôle)

create or replace function collecte_etat_acces()
returns table (email text, derniere_connexion timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not collecte_est_responsable() then raise exception 'Réservé au responsable collecte'; end if;
  return query
    select distinct lower(a.email), u.last_sign_in_at
    from collecte_acces a
    left join auth.users u on lower(u.email) = lower(a.email);
end $$;
grant execute on function collecte_etat_acces() to authenticated;

-- ---------- 8. Consentement des référents --------------------------
-- Le référent coche (ou décoche) lui-même l'accord de conservation de son
-- accès jusqu'à la prochaine collecte. Il ne peut modifier que ses propres lignes.

create or replace function collecte_mon_consentement(p_accord boolean)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare v timestamptz := case when p_accord then now() else null end;
begin
  update collecte_acces set consentement_le = v
   where lower(email) = lower(auth.jwt() ->> 'email') and role = 'referent';
  return v;
end $$;
grant execute on function collecte_mon_consentement(boolean) to authenticated;

-- ---------- 9. Clôture de la collecte (RGPD) ------------------------
-- 1. Bénévoles inscrits : nom, téléphone, email, remarque effacés ; équipages
--    (chauffeurs et camions affectés aux tournées) supprimés. Seul reste le
--    nombre d'inscrits par créneau (bilan anonyme).
-- 2. Référents SANS accord de conservation : accès supprimés, et leur compte
--    de connexion aussi s'il ne sert à rien d'autre (ni admin, ni bénévole).
-- 3. Plus aucune inscription possible jusqu'à la prochaine édition.

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
grant execute on function collecte_cloturer() to authenticated;

-- ---------- 10. Équipages : liste des chauffeurs et contrôle ---------
-- La responsable collecte n'a pas accès à la table benevoles : cette fonction
-- ne lui donne que nom, prénom et téléphone des bénévoles actifs qualifiés
-- « Chauffeur » (+ ceux déjà affectés, au cas où leur statut aurait changé).

create or replace function collecte_liste_chauffeurs()
returns table (id uuid, nom text, prenom text, telephone text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not collecte_est_responsable() then raise exception 'Réservé au responsable collecte'; end if;
  return query
    select b.id, b.nom, b.prenom, b.telephone
    from benevoles b
    where (b.statut = 'actif' and exists (
             select 1 from benevole_postes bp join postes p on p.id = bp.poste_id
             where bp.benevole_id = b.id and p.nom = 'Chauffeur'))
       or b.id in (select chauffeur_1 from collecte_equipages union select chauffeur_2 from collecte_equipages)
    order by b.nom, b.prenom;
end $$;
grant execute on function collecte_liste_chauffeurs() to authenticated;

-- Un chauffeur ne peut pas être sur deux tournées le même jour
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
drop trigger if exists trg_collecte_equipage on collecte_equipages;
create trigger trg_collecte_equipage before insert or update on collecte_equipages
  for each row execute function collecte_trg_equipage();

-- ---------- 11. Amorçage ---------------------------------------------
insert into collecte_parametres (id, jours)
values (1, array['2026-11-06', '2026-11-07']::date[])
on conflict (id) do nothing;

-- Responsable collecte (remplacer l'email) :
-- insert into collecte_acces (email, role) values ('prenom.nom@exemple.fr', 'responsable');
-- Magasins et référents : à saisir depuis collecte.html, onglet « Magasins & accès ».
