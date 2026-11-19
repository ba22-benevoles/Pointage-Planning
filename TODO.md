# TODO — branche `cerfa-publipostage`

À faire **avant de fusionner** dans `main` et de déployer.

## 1. Compteur des reçus fiscaux (Supabase)

Le compteur contient une valeur de **test** (`99990000`). Une fois le dernier
numéro réellement émis confirmé avec le comptable, dans le SQL Editor :

```sql
update recus_compteur set dernier_numero = <VRAI_DERNIER_NUMERO> where id = 1;
delete from recus_lots;
```

Vérifier : `select * from recus_compteur;`

## 2. Adresse ngrok du publipostage

Dans `Dossier_netlify/index.html`, remplacer la valeur provisoire :

```js
const URL_PUBLIPOSTAGE = 'https://VOTRE-DOMAINE.ngrok-free.app';
```

## 3. Emails invalides (virgule à la place du point)

Lister les fiches concernées :

```sql
select numero, nom, prenom, email from benevoles where email like '%,%';
```

Corriger avant d'envoyer les reçus par le publipostage.

## 4. Validation avec le comptable

- [ ] Règle de numérotation (continue ou par année)
- [ ] Calcul du montant (distance × taux km) conforme
- [ ] Texte du reçu, n° RNA, signataire
- [ ] Archivage des reçus émis

## Rappels

- Modèle publipostage : `Cerfa/modele_cerfa.docx` — placeholders **sans espaces** (`{{nom}}`)
- Reçus à envoyer **avant le 1er mars** (anonymisation des bénévoles partis)
- Ne jamais commiter les CSV exportés ni les PDF générés (données personnelles)
