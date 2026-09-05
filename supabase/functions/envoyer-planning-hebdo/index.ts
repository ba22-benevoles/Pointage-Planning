// Edge Function : envoyer-planning-hebdo
// Déclenchée chaque vendredi par pg_cron. Envoie le planning de la semaine
// À VENIR (lundi suivant → vendredi) à tous les bénévoles/salariés actifs.
// Si aucun planning n'est encore enregistré pour cette semaine, envoie une
// alerte à l'admin à la place (aucun email aux bénévoles dans ce cas).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const BREVO_API_KEY = Deno.env.get('BREVO_API_KEY')!;
const ADMIN_ALERT_EMAIL = Deno.env.get('ADMIN_ALERT_EMAIL')!; // ex. l'email de Serge
const SENDER_EMAIL = Deno.env.get('SENDER_EMAIL') ?? 'pointage@esl22.fr';
const SENDER_NAME = 'Pointage BA22';

const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

const JOURS_SEMAINE = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi'];

// En-têtes CORS : indispensables pour que le navigateur (bouton admin)
// soit autorisé à appeler cette fonction depuis pointage.esl22.fr.
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function formatDateFr(iso: string): string {
  const [y, m, d] = iso.split('-');
  return `${d}/${m}/${y}`;
}

function ajouterJours(iso: string, n: number): string {
  const d = new Date(iso + 'T12:00:00Z');
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

function prochainLundi(): string {
  // Cette fonction n'est censée tourner que le vendredi (planifiée ainsi).
  // Le lundi suivant est donc toujours à +3 jours.
  const aujourdhui = new Date();
  const iso = aujourdhui.toISOString().slice(0, 10);
  return ajouterJours(iso, 3);
}

async function envoyerEmailBrevo(destinataire: { email: string; prenom: string }, sujet: string, htmlContenu: string) {
  const res = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: {
      'accept': 'application/json',
      'api-key': BREVO_API_KEY,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      sender: { email: SENDER_EMAIL, name: SENDER_NAME },
      to: [{ email: destinataire.email, name: destinataire.prenom }],
      subject: sujet,
      htmlContent: htmlContenu,
    }),
  });
  if (!res.ok) {
    const detail = await res.text();
    console.error(`Échec envoi à ${destinataire.email} :`, detail);
  }
}

function construireHtmlPlanning(lundi: string, vendredi: string, postesConfig: any[], planningParPoste: Record<string, any[][]>, joursLavage: Set<string>): string {
  let html = `
    <div style="font-family: sans-serif; color: #23261F; max-width: 700px;">
      <h2 style="color: #33513F;">Planning de la semaine du ${formatDateFr(lundi)} au ${formatDateFr(vendredi)}</h2>
  `;

  for (const poste of postesConfig) {
    const lignesParJour = planningParPoste[poste.nom] || [[], [], [], [], []];
    const maxRows = Math.max(1, ...lignesParJour.map((j: any[]) => j.length));

    html += `
      <h3 style="color: #33513F; margin-top: 24px; margin-bottom: 6px;">${poste.nom}</h3>
      <table style="border-collapse: collapse; width: 100%; font-size: 13px;">
        <thead>
          <tr>
            <th style="border:1px solid #E5DFCF; background:#E4EBE3; padding:6px;">N°</th>
            ${JOURS_SEMAINE.map((j, i) => `<th style="border:1px solid #E5DFCF; background:#E4EBE3; padding:6px;">${j}<br>${formatDateFr(ajouterJours(lundi, i))}</th>`).join('')}
          </tr>
        </thead>
        <tbody>
    `;
    for (let row = 0; row < maxRows; row++) {
      html += `<tr><td style="border:1px solid #E5DFCF; padding:6px; text-align:center;">${row + 1}</td>`;
      for (let jourIdx = 0; jourIdx < 5; jourIdx++) {
        const b = lignesParJour[jourIdx][row];
        const badgeDest = (b && b.destination) ? ` <span style="background:#3E6B8F;color:white;font-size:11px;padding:1px 6px;border-radius:6px;">🚚 ${b.destination}</span>` : '';
        const badgeAccomp = (b && b.accompagnant) ? ` <span style="background:#8A6D3B;color:white;font-size:11px;padding:1px 6px;border-radius:6px;">👤 Accompagnant</span>` : '';
        html += `<td style="border:1px solid #E5DFCF; padding:6px;">${b ? b.prenom + ' ' + b.nom + badgeDest + badgeAccomp : ''}</td>`;
      }
      html += `</tr>`;
    }

    // Ligne "Lavage des camions" : simple marqueur par jour, uniquement sous Chauffeur
    if (poste.nom === 'Chauffeur') {
      html += `<tr style="background:#F5F2E8;"><td style="border:1px solid #E5DFCF; padding:6px; text-align:center; font-size:11px;">Lav.</td>`;
      for (let jourIdx = 0; jourIdx < 5; jourIdx++) {
        const dateJour = ajouterJours(lundi, jourIdx);
        const marque = joursLavage.has(dateJour);
        html += `<td style="border:1px solid #E5DFCF; padding:6px; font-style:italic; ${marque ? 'background:#F5E6C8; font-weight:600;' : ''}">${marque ? 'Lavage' : ''}</td>`;
      }
      html += `</tr>`;
    }

    html += `</tbody></table>`;
  }

  html += `<p style="color:#6B6A5E; font-size:13px; margin-top:24px;">Banque Alimentaire de Lannion — Pointage BA22</p></div>`;
  return html;
}

Deno.serve(async (req) => {
  // Requête préliminaire envoyée automatiquement par le navigateur avant l'appel réel
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Déclenchement manuel (bouton admin) : la semaine est précisée dans le corps,
    // avec éventuellement un email de test pour limiter l'envoi à une seule adresse.
    // Déclenchement automatique (cron du vendredi) : aucun corps, on calcule le lundi suivant.
    let lundi: string;
    let declenchementManuel = false;
    let emailTest: string | null = null;
    try {
      const body = await req.json();
      if (body && body.lundi) {
        lundi = body.lundi;
        declenchementManuel = true;
        emailTest = body.emailTest || null;
      } else {
        lundi = prochainLundi();
      }
    } catch (_) {
      lundi = prochainLundi();
    }
    const vendredi = ajouterJours(lundi, 4);

    // 1. Le planning de cette semaine est-il déjà enregistré ?
    const { data: planningRows, error: planningErr } = await sb
      .from('planning')
      .select('date, poste_id, benevole_id, destination, accompagnant, postes(nom), benevoles(nom, prenom)')
      .gte('date', lundi)
      .lte('date', vendredi);

    if (planningErr) throw planningErr;

    if (!planningRows || planningRows.length === 0) {
      if (declenchementManuel) {
        // Envoi manuel sans planning enregistré : on prévient simplement l'appelant,
        // pas besoin d'un email (l'admin est déjà dans l'appli).
        return new Response(JSON.stringify({ status: 'aucun_planning' }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }
      // Cron automatique : alerte admin par email, aucun envoi aux bénévoles
      await envoyerEmailBrevo(
        { email: ADMIN_ALERT_EMAIL, prenom: 'Admin' },
        `⚠️ Planning non établi pour la semaine du ${formatDateFr(lundi)}`,
        `<p>Le planning de la semaine du ${formatDateFr(lundi)} au ${formatDateFr(vendredi)} n'est pas encore enregistré.</p>
         <p>Aucun email n'a été envoyé aux bénévoles. Pense à établir et enregistrer le planning dès que possible.</p>`
      );
      return new Response(JSON.stringify({ status: 'alerte_admin_envoyee' }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // 2. Construction du contenu HTML à partir du planning enregistré
    const { data: postesConfig } = await sb.from('postes').select('id, nom, effectif_min, effectif_max').order('id');
    const planningParPoste: Record<string, any[][]> = {};
    (postesConfig || []).forEach((p) => { planningParPoste[p.nom] = [[], [], [], [], []]; });

    (planningRows || []).forEach((row: any) => {
      const posteNom = row.postes?.nom;
      if (!posteNom || !planningParPoste[posteNom]) return;
      const jourIdx = Math.round((new Date(row.date + 'T12:00:00Z').getTime() - new Date(lundi + 'T12:00:00Z').getTime()) / 86400000);
      if (jourIdx < 0 || jourIdx > 4) return;
      planningParPoste[posteNom][jourIdx].push({ nom: row.benevoles?.nom ?? '', prenom: row.benevoles?.prenom ?? '', destination: row.destination ?? null, accompagnant: row.accompagnant ?? false });
    });

    const { data: lavageRows } = await sb.from('lavage_camions').select('date').gte('date', lundi).lte('date', vendredi);
    const joursLavage = new Set((lavageRows || []).map((r: any) => String(r.date).slice(0, 10)));

    const htmlContenu = construireHtmlPlanning(lundi, vendredi, postesConfig || [], planningParPoste, joursLavage);

    // 3. Envoi : soit à tous les bénévoles/salariés actifs, soit à un seul email de test
    const sujet = `Planning de la semaine du ${formatDateFr(lundi)}`;
    let envoyes = 0;

    if (emailTest) {
      await envoyerEmailBrevo({ email: emailTest, prenom: 'Test' }, sujet, htmlContenu);
      envoyes = 1;
    } else {
      const { data: destinataires, error: destErr } = await sb
        .from('benevoles')
        .select('email, prenom')
        .eq('statut', 'actif')
        .not('email', 'is', null);

      if (destErr) throw destErr;

      for (const dest of destinataires || []) {
        if (!dest.email) continue;
        await envoyerEmailBrevo(dest, sujet, htmlContenu);
        envoyes++;
      }
    }

    return new Response(JSON.stringify({ status: 'planning_envoye', destinataires: envoyes }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (err) {
    console.error(err);
    // Erreur inattendue : on tente quand même d'alerter l'admin
    try {
      await envoyerEmailBrevo(
        { email: ADMIN_ALERT_EMAIL, prenom: 'Admin' },
        '⚠️ Erreur lors de l\'envoi automatique du planning',
        `<p>Une erreur technique est survenue : ${String(err)}</p>`
      );
    } catch (_) { /* ignore */ }
    return new Response(JSON.stringify({ status: 'erreur', message: String(err) }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
