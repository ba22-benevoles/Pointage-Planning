# Pointage-Planning BA22

Outil de pointage, planning et gestion des bénévoles pour la Banque Alimentaire de Lannion (Côtes d'Armor). Remplace un ancien système Excel/macros devenu fragile et difficile à maintenir.

## Fonctionnalités

- **Pointage** (kiosque tactile) — arrivée/départ par nom ou numéro à 3 chiffres, sans connexion
- **Espace admin** — gestion des bénévoles/salariés, congés, fermetures, planning hebdomadaire, bilans annuels (heures valorisées, indemnités kilométriques)
- **Planning persistant** — proposition automatique puis validation, éditable manuellement (n'importe quel bénévole sur n'importe quel poste), avec gestion des cas particuliers (destination Saint-Brieuc pour les chauffeurs, accompagnants, lavage des camions, salariés multi-postes)
- **Espace bénévole autonome** (`absence.html`) — connexion par lien magique (email, sans mot de passe), consultation de son propre planning et de celui de son équipe, déclaration/annulation d'absences
- **Automatisations** — retrait automatique du planning en cas de congé ou de changement de statut, fermeture automatique des sessions de pointage oubliées, anonymisation RGPD des bénévoles partis, alerte email si un poste tombe à zéro suite à un désistement, envoi automatique du planning hebdomadaire (email)
- **Jours fériés français** calculés automatiquement (dates fixes + Pâques et dérivés)

## Stack technique

- **Frontend** : HTML/CSS/JS vanilla (aucun framework, aucune étape de build) — deux fichiers principaux
- **Backend** : [Supabase](https://supabase.com) (PostgreSQL + Auth + Edge Functions), plan gratuit
- **Hébergement** : [Netlify](https://netlify.com), déploiement par glisser-déposer
- **Emails** : [Brevo](https://brevo.com), API transactionnelle (pas de SMTP pour les envois automatisés ; SMTP utilisé uniquement pour Supabase Auth)

## Structure du dépôt

```
Dossier_netlify/
  index.html       — kiosque de pointage + espace admin (une seule page, deux vues)
  absence.html     — espace bénévole autonome (lien magique)
supabase/
  functions/
    envoyer-planning-hebdo/   — email automatique du vendredi
    alerte-poste-vide/        — alerte si un poste tombe à zéro
migration_*.sql    — migrations SQL, dans l'ordre chronologique (voir plus bas)
.gitignore         — exclut les fichiers contenant des données personnelles réelles
```

## Mise en place (nouveau déploiement)

### 1. Base de données (Supabase)

Créer un nouveau projet Supabase, puis exécuter les migrations. Deux options :

- **Recommandé** : exporter le schéma exact d'un projet déjà en production (`supabase db dump --schema public`) plutôt que de rejouer chaque migration une par une — élimine tout risque d'divergence.
- **Sinon** : rejouer les fichiers `migration_*.sql` à la racine du dépôt, **dans l'ordre chronologique** (voir l'historique Git pour l'ordre exact — de nombreux ajustements/corrections se sont accumulés au fil du temps).

Activer les extensions `pg_cron` et `pg_net` (Database → Extensions) — nécessaires pour les tâches planifiées et les appels HTTP sortants.

### 2. Frontend (Netlify)

Glisser-déposer le contenu de `Dossier_netlify/` (les deux fichiers `.html`) sur [Netlify Drop](https://app.netlify.com/drop) ou un site Netlify existant. Mettre à jour, dans les deux fichiers, les constantes `SUPABASE_URL` et `SUPABASE_ANON_KEY` avec celles du nouveau projet.

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

- **URL Configuration** : renseigner le "Site URL" et les "Redirect URLs" avec le vrai domaine (une valeur oubliée sur `localhost:3000` casse les liens magiques)
- **SMTP** : configurer un relais SMTP (Brevo ou autre) pour l'envoi des emails de connexion — l'envoi par défaut de Supabase est très limité en volume
- Vérifier que le suivi de clics du service SMTP est neutre vis-à-vis des liens à usage unique (certains outils de tracking invalident les liens avant même que l'utilisateur ne clique)

### 5. Planification automatique

Exécuter les migrations qui programment les tâches `pg_cron` (envoi hebdomadaire, fermeture des sessions oubliées, anonymisation RGPD) — chacune contient l'URL et la clé de service à adapter au nouveau projet.

## Points d'attention pour la maintenance

- **RLS (Row Level Security)** : activée sur toutes les tables sensibles. Une politique qui référence sa propre table dans une sous-requête provoque une erreur de récursion infinie — passer par une fonction `security definer` pour contourner.
- **Enregistrement du planning** : passe par une fonction Postgres unique (`enregistrer_planning_semaine`), pas par un couple suppression/insertion séparé côté client — évite toute perte de données si l'insertion échoue après la suppression.
- **Le kiosque fonctionne sans authentification** (accès anonyme) — toute nouvelle donnée qu'il doit lire nécessite une politique RLS explicite de lecture publique, sinon la requête échoue silencieusement (aucune ligne retournée, pas d'erreur visible).
- **Déploiement des Edge Functions** : passe par Docker en local — en cas de blocage, vérifier `docker ps` et nettoyer les conteneurs orphelins avant de relancer.

## Historique

Développé par Serge Louvel (bénévole, responsable technique BA22) avec l'assistance de Claude (Anthropic), à partir de mi-2026, en remplacement d'un système Excel/macros. Pensé pour être repris et maintenu par quelqu'un d'autre sans dépendre d'une seule personne.
