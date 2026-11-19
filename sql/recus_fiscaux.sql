-- =====================================================================
-- Numérotation des reçus fiscaux (CERFA abandon de frais kilométriques)
-- À exécuter UNE FOIS dans Supabase : SQL Editor → coller → Run
-- =====================================================================

-- 1. Compteur : une seule ligne (id = 1)
create table if not exists public.recus_compteur (
  id             int primary key default 1 check (id = 1),
  prefixe        text   not null,          -- ex. 'BA220-'
  dernier_numero bigint not null,          -- dernier numéro DÉJÀ émis (partie chiffrée)
  mis_a_jour     timestamptz not null default now()
);

-- 2. Historique des lots émis (traçabilité)
create table if not exists public.recus_lots (
  id          bigserial primary key,
  annee_dons  int    not null,             -- année des dons (ex. 2025)
  premier     text   not null,             -- ex. 'BA220-20230655'
  dernier     text   not null,
  nb          int    not null,
  cree_le     timestamptz not null default now(),
  cree_par    uuid   default auth.uid()
);

-- 3. Sécurité : lecture réservée aux admins, aucune écriture directe
--    (les écritures passent uniquement par la fonction ci-dessous)
alter table public.recus_compteur enable row level security;
alter table public.recus_lots     enable row level security;

drop policy if exists "admins lisent le compteur" on public.recus_compteur;
create policy "admins lisent le compteur" on public.recus_compteur
  for select to authenticated
  using (exists (select 1 from public.admins a where a.user_id = auth.uid()));

drop policy if exists "admins lisent les lots" on public.recus_lots;
create policy "admins lisent les lots" on public.recus_lots
  for select to authenticated
  using (exists (select 1 from public.admins a where a.user_id = auth.uid()));

-- 4. Réservation atomique de p_nb numéros consécutifs
create or replace function public.reserver_numeros_recus(p_annee int, p_nb int)
returns table (prefixe text, premier bigint, dernier bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prefixe text;
  v_dernier bigint;
begin
  if not exists (select 1 from admins a where a.user_id = auth.uid()) then
    raise exception 'Réservé aux administrateurs';
  end if;
  if p_nb is null or p_nb < 1 then
    raise exception 'Nombre de reçus invalide';
  end if;

  -- UPDATE verrouille la ligne : deux exports simultanés ne peuvent pas
  -- obtenir les mêmes numéros
  update recus_compteur c
     set dernier_numero = c.dernier_numero + p_nb, mis_a_jour = now()
   where c.id = 1
  returning c.prefixe, c.dernier_numero into v_prefixe, v_dernier;

  if not found then
    raise exception 'Compteur non initialisé (table recus_compteur vide)';
  end if;

  insert into recus_lots (annee_dons, premier, dernier, nb)
  values (p_annee, v_prefixe || (v_dernier - p_nb + 1), v_prefixe || v_dernier, p_nb);

  return query select v_prefixe, v_dernier - p_nb + 1, v_dernier;
end;
$$;

revoke all on function public.reserver_numeros_recus(int, int) from public, anon;
grant execute on function public.reserver_numeros_recus(int, int) to authenticated;

-- 5. Initialisation : METTRE ICI LE DERNIER NUMÉRO DÉJÀ ÉMIS
--    (exemple : si le dernier reçu émis est BA220-20230654)
insert into public.recus_compteur (id, prefixe, dernier_numero)
values (1, 'BA220-', 99990000)
on conflict (id) do nothing;
