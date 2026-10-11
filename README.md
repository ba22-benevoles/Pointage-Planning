# Pointage-Planning BA22

Outil de pointage, planning et gestion des bénévoles pour la Banque Alimentaire de Lannion (Côtes d'Armor). Remplace un ancien système Excel/macros devenu fragile et difficile à maintenir.

## Fonctionnalités

- **Pointage** (kiosque tactile) — arrivée/départ par nom ou numéro à 3 chiffres, sans connexion
- **Espace admin** — gestion des bénévoles/salariés, congés, fermetures, planning hebdomadaire, bilans annuels (heures valorisées, indemnités kilométriques)
- **Planning persistant** — proposition automatique puis validation, éditable manuellement (n'importe quel bénévole sur n'importe quel poste), avec gestion des cas particuliers (destination Saint-Brieuc pour les chauffeurs, accompagnants, lavage des camions, salariés multi-postes)
- **Espace bénévole autonome** (`absence.html`) — connexion par lien magique (email, sans mot de passe), consultation de son propre planning et de celui de son équipe, déclaration/annulation d'absences
- **Espace collecte** (`collecte.html`) — application séparée pour les collectes en magasin (2 par an), accessible depuis le bouton « 🛒 Collecte » de l'espace admin ou directement par son adresse. Voir la section [Module Collecte](#module-collecte)
- **Automatisations** — retrait automatique du planning en cas de congé ou de changement de statut, fermeture automatique des sessions de pointage oubliées, anonymisation RGPD des bénévoles partis, alerte email si un poste tombe à zéro suite à un désistement, envoi automatique du planning hebdomadaire (email)
- **Jours fériés français** calculés automatiquement (dates fixes + Pâques et dérivés)

## Stack technique

- **Frontend** : HTML/CSS/JS vanilla (aucun framework, aucune étape de build) — une page par espace (kiosque + admin, bénévole, collecte)
- **Backend** : [Supabase](https://supabase.com) (PostgreSQL + Auth + Edge Functions), plan gratuit
- **Hébergement** : [Netlify](https://netlify.com), déploiement par glisser-déposer
- **Emails** : [Brevo](https://brevo.com), API transactionnelle (pas de SMTP pour les envois automatisés ; SMTP utilisé uniquement pour Supabase Auth)

## Structure du dépôt

```
Dossier_netlify/
  index.html                    — kiosque de pointage + espace admin (une seule page, deux vues)
  absence.html                  — espace bénévole autonome (lien magique)
  collecte.html                 — espace collecte (responsables + référents magasin, lien magique)
  aide.html                     — aide en ligne de l'espace admin
  aide-collecte.html            — aide en ligne de l'espace collecte (référents et responsables)
  confidentialite.html          — politique de confidentialité de l'outil de pointage
  confidentialite-collecte.html — politique de confidentialité de l'espace collecte
supabase/
  functions/
    envoyer-planning-hebdo/     — email automatique du vendredi
    alerte-poste-vide/          — alerte si un poste tombe à zéro
migration_*.sql                 — migrations SQL, dans l'ordre chronologique (voir plus bas)
migration_collecte.sql          — tout le module Collecte, en un seul fichier autonome
.gitignore                      — exclut les fichiers contenant des données personnelles réelles
```

## Mise en place (nouveau déploiement)

### 1. Base de données (Supabase)

Créer un nouveau projet Supabase, puis exécuter les migrations. Deux options :

- **Recommandé** : exporter le schéma exact d'un projet déjà en production (`supabase db dump --schema public`) plutôt que de rejouer chaque migration une par une — élimine tout risque de divergence.
- **Sinon** : rejouer les fichiers `migration_*.sql` à la racine du dépôt, **dans l'ordre chronologique** (voir l'historique Git pour l'ordre exact — de nombreux ajustements/corrections se sont accumulés au fil du temps). `migration_collecte.sql` vient en dernier : il a besoin des tables `admins`, `benevoles`, `postes` et `benevole_postes`.

Activer les extensions `pg_cron` et `pg_net` (Database → Extensions) — nécessaires pour les tâches planifiées et les appels HTTP sortants.

### 2. Frontend (Netlify)

Glisser-déposer **tout le contenu** de `Dossier_netlify/` sur [Netlify Drop](https://app.netlify.com/drop) ou un site Netlify existant (un dépôt manuel remplace tout le site : ne jamais déposer un seul fichier). Mettre à jour les constantes `SUPABASE_URL` et `SUPABASE_ANON_KEY` avec celles du nouveau projet dans `index.html`, `absence.html` et `collecte.html`.

Le site est déployé depuis la branche `main` : vérifier avec `git branch` avant de glisser le dossier.

### 3. Edge Functions

```bash
supabase link --project-ref VOTRE_PROJET
supabase functions deploy envoyer-planning-hebdo
supabase functions deploy alerte-poste-vide
```

Définir les secrets nécessaires :
```bash
supabase secrets set BREVO_API_KEY=...
supabase secrets set ADMIN_ALERT_EMAIL=...
supabase secrets set SENDER_EMAIL=pointage@esl22.fr
```

### 4. Authentification (Supabase Auth)

- **URL Configuration** : renseigner le "Site URL" et les "Redirect URLs" avec le vrai domaine, en incluant `absence.html` **et** `collecte.html` (une valeur oubliée sur `localhost` casse les liens magiques). Pour tester en local (`python3 -m http.server 8000` dans `Dossier_netlify/`), ajouter temporairement `http://localhost:8000/**`, puis le retirer.
- **Modèles d'email** : les modèles « Magic Link » **et** « Confirm signup » sont **communs** à `absence.html` et `collecte.html` — leur texte doit rester neutre (« votre espace de la Banque Alimentaire »). « Confirm signup » est envoyé à la toute première connexion d'une adresse (cas de tous les nouveaux référents de la collecte). Toujours conserver `{{ .ConfirmationURL }}` comme lien.
- **SMTP** : configurer un relais SMTP (Brevo ou autre) pour l'envoi des emails de connexion — l'envoi par défaut de Supabase est très limité en volume
- Vérifier que le suivi de clics du service SMTP est neutre vis-à-vis des liens à usage unique (certains outils de tracking invalident les liens avant même que l'utilisateur ne clique)

### 5. Planification automatique

Exécuter les migrations qui programment les tâches `pg_cron` (envoi hebdomadaire, fermeture des sessions oubliées, anonymisation RGPD) — chacune contient l'URL et la clé de service à adapter au nouveau projet.

## Module Collecte

Application séparée (`collecte.html`) pour organiser les collectes en magasin. Toutes ses tables sont préfixées `collecte_` et elle ne modifie aucune table de l'outil de pointage (elle lit seulement `admins`, `benevoles`, `benevole_postes`, `postes` et `auth.users`).

### Rôles

- **Responsable collecte** — gère tout l'espace collecte. Les admins de l'outil (table `admins`) le sont d'office ; les autres sont déclarés dans `collecte_acces` (rôle `responsable`), par exemple l'adresse dédiée `ba220.collecte@banquealimentaire.org`. Un responsable collecte n'a **aucun accès** à l'outil de pointage.
- **Référent magasin** — invité par email par un responsable, il ne voit et ne remplit que le ou les magasins qui lui sont attribués (`collecte_acces`, rôle `referent`, une ligne par magasin). Les référents n'ont pas besoin de fiche dans `benevoles`.

Le cloisonnement est appliqué par la RLS et des fonctions `security definer` (`collecte_est_responsable`, `collecte_gere_magasin`…), pas seulement par l'affichage.

### Fonctionnement

- **Créneaux** : 5 créneaux de 2 h par jour (9h–19h) et par magasin, créés automatiquement à l'ajout d'un magasin ; 2 bénévoles maximum par créneau (contrôlé en base, y compris en cas de saisies simultanées).
- **Inscriptions** : texte libre (nom, téléphone, remarque), volontairement **non reliées** à la table `benevoles` (beaucoup de bénévoles de collecte sont extérieurs à l'association).
- **Tournées et équipages** : chaque magasin porte un n° de tournée ; pour chaque tournée et chaque jour, un camion et 2 chauffeurs choisis parmi les bénévoles actifs qualifiés « Chauffeur » (fonction `collecte_liste_chauffeurs`, qui n'expose que nom, prénom et téléphone). Un chauffeur ou un camion ne fait qu'une tournée par jour.
- **Impressions** : fiche par magasin, feuille par tournée (équipage + magasins), tableau des chauffeurs.

### Cycle d'une collecte et RGPD

1. Les dates sont dans `collecte_parametres` (6 et 7 novembre 2026 à l'installation).
2. Les responsables saisissent magasins et tournées, invitent les référents ; chaque référent coche (ou non) son accord de conservation.
3. Après la collecte, un responsable clique sur **« Clôturer la collecte »** (`collecte_cloturer`) : noms, téléphones, remarques et équipages sont effacés (seul reste le nombre d'inscrits par créneau), les référents sans accord sont supprimés, la saisie est bloquée. Un rappel s'affiche tant que ce n'est pas fait.
4. Pour la collecte suivante, **« Nouvelle édition »** (`collecte_nouvelle_edition`, refusée tant que la précédente n'est pas clôturée) recrée les créneaux aux nouvelles dates ; les référents conservés redonnent leur accord.

Politique de confidentialité dédiée : `confidentialite-collecte.html`.

### Installation et maintenance

- `migration_collecte.sql` s'exécute **une seule fois** dans le SQL Editor (l'avertissement « destructive operations » de Supabase vient des `drop trigger if exists` et des `delete` à l'intérieur des fonctions : il ne concerne que les tables `collecte_*`). Il n'est **pas** rejouable tel quel (les `create policy` échoueraient) : en cas d'erreur, corriger plutôt que relancer.
- Les magasins ne se suppriment pas depuis la page (seulement désactivables), et une clôture ne s'annule pas depuis la page : passer par le SQL Editor.
- Remise à zéro des données (après des tests, par exemple) :
  ```sql
  delete from collecte_equipages;
  delete from collecte_creneaux;      -- efface aussi les inscriptions
  delete from collecte_acces where email <> 'ba220.collecte@banquealimentaire.org';
  delete from collecte_magasins;
  update collecte_parametres
     set jours = array['2026-11-06','2026-11-07']::date[], cloturee_le = null
   where id = 1;
  ```
- Retrait complet du module (n'affecte pas le reste de l'outil) :
  ```sql
  drop table if exists collecte_equipages, collecte_inscriptions, collecte_creneaux,
                       collecte_acces, collecte_magasins, collecte_parametres cascade;
  drop function if exists
    collecte_est_responsable(), collecte_gere_magasin(uuid), collecte_gere_creneau(uuid),
    collecte_email_autorise(text), _collecte_generer(), collecte_generer_creneaux(),
    collecte_trg_nouveau_magasin(), collecte_nouvelle_edition(date[]),
    collecte_trg_limite_inscriptions(), collecte_trg_besoin_creneau(),
    collecte_etat_acces(), collecte_mon_consentement(boolean), collecte_cloturer(),
    collecte_liste_chauffeurs(), collecte_trg_equipage();
  ```

## Points d'attention pour la maintenance

- **Dépôt public et données personnelles** : le dépôt GitHub est public. Aucun fichier contenant des données réelles (exports, scripts d'import avec des noms, tableurs) ne doit y entrer : le `.gitignore` les exclut, mais il ne protège pas un fichier déjà committé (il faut alors `git rm --cached`, et le purger de l'historique avec `git filter-repo`). Éviter `git add .` / `git add -A` à la racine du dépôt.
- **RLS (Row Level Security)** : activée sur toutes les tables sensibles. Une politique qui référence sa propre table dans une sous-requête provoque une erreur de récursion infinie — passer par une fonction `security definer` pour contourner.
- **Enregistrement du planning** : passe par une fonction Postgres unique (`enregistrer_planning_semaine`), pas par un couple suppression/insertion séparé côté client — évite toute perte de données si l'insertion échoue après la suppression.
- **Le kiosque fonctionne sans authentification** (accès anonyme) — toute nouvelle donnée qu'il doit lire nécessite une politique RLS explicite de lecture publique, sinon la requête échoue silencieusement (aucune ligne retournée, pas d'erreur visible).
- **Une seule base pour tout** : Supabase n'a pas de base de test. Ce qui est saisi lors d'un test local est réellement enregistré en production — nettoyer après les tests.
- **Déploiement des Edge Functions** : passe par Docker en local — en cas de blocage, vérifier `docker ps` et nettoyer les conteneurs orphelins avant de relancer.

## Historique

Développé par Serge Louvel (bénévole, responsable technique BA22) avec l'assistance de Claude (Anthropic), à partir de mi-2026, en remplacement d'un système Excel/macros. Pensé pour être repris et maintenu par quelqu'un d'autre sans dépendre d'une seule personne. Module Collecte ajouté en octobre 2026.
