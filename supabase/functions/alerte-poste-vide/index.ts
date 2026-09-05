// Edge Function : alerte-poste-vide
// Déclenchée automatiquement par la base (trigger sur "conges") dès qu'un
// poste tombe à zéro personne un jour donné, suite au retrait d'un
// bénévole (absence déclarée après validation du planning).
// Envoie un email à tous les bénévoles qualifiés sur ce poste, qu'ils
// soient prévus ce jour-là ou non, pour demander de l'aide.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const BREVO_API_KEY = Deno.env.get('BREVO_API_KEY')!;
const SENDER_EMAIL = Deno.env.get('SENDER_EMAIL') ?? 'pointage@esl22.fr';
const ADMIN_EMAIL = 'ba220.benevoles@banquealimentaire.org';
const SENDER_NAME = 'Pointage BA22';

const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function formatDateFr(iso: string): string {
  const [y, m, d] = iso.split('-');
  return `${d}/${m}/${y}`;
}

async function envoyerEmailBrevo(destinataire: { email: string; prenom: string }, sujet: string, htmlContenu: string) {
  const res = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: { 'accept': 'application/json', 'api-key': BREVO_API_KEY, 'content-type': 'application/json' },
    body: JSON.stringify({
      sender: { email: SENDER_EMAIL, name: SENDER_NAME },
      to: [{ email: destinataire.email, name: destinataire.prenom }],
      subject: sujet,
      htmlContent: htmlContenu,
    }),
  });
  if (!res.ok) console.error(`Échec envoi à ${destinataire.email} :`, await res.text());
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const { poste_id, date } = await req.json();

    const { data: poste } = await sb.from('postes').select('nom').eq('id', poste_id).single();
    if (!poste) throw new Error('Poste introuvable');

    const { data: qualifies } = await sb
      .from('benevole_postes')
      .select('benevoles(prenom, email, statut)')
      .eq('poste_id', poste_id);

    const destinataires = (qualifies || [])
      .map((q: any) => q.benevoles)
      .filter((b: any) => b && b.statut === 'actif' && b.email);

    const sujet = `⚠️ Besoin d'aide — ${poste.nom} le ${formatDateFr(date)}`;
    const html = `
      <div style="font-family: sans-serif; color: #23261F; max-width: 600px;">
        <h2 style="color: #B4462F;">Besoin d'un coup de main</h2>
        <p>Le poste <strong>${poste.nom}</strong> n'a plus personne d'affecté le <strong>${formatDateFr(date)}</strong>
        (un désistement de dernière minute).</p>
        <p>Si tu es disponible ce jour-là et que tu peux venir, merci d'écrire à
        <strong>${ADMIN_EMAIL}</strong> pour te proposer — le planning sera mis à jour en conséquence.</p>
        <p style="color:#6B6A5E; font-size:13px; margin-top:24px;">Banque Alimentaire de Lannion — Pointage BA22</p>
      </div>`;

    let envoyes = 0;
    for (const d of destinataires) {
      await envoyerEmailBrevo(d, sujet, html);
      envoyes++;
    }

    // Copie systématique à l'adresse institutionnelle, dans tous les cas
    // (même si aucun bénévole qualifié n'a pu être notifié).
    const htmlAdmin = `
      <div style="font-family: sans-serif; color: #23261F; max-width: 600px;">
        <h2 style="color: #B4462F;">Poste vide détecté</h2>
        <p>Le poste <strong>${poste.nom}</strong> est tombé à zéro personne le <strong>${formatDateFr(date)}</strong>
        (retrait automatique suite à un congé déclaré après validation du planning).</p>
        <p>${envoyes} bénévole(s) qualifié(s) sur ce poste ${envoyes > 1 ? 'ont' : 'a'} été prévenu(s) par email.</p>
        <p style="color:#6B6A5E; font-size:13px; margin-top:24px;">Banque Alimentaire de Lannion — Pointage BA22</p>
      </div>`;
    await envoyerEmailBrevo({ email: ADMIN_EMAIL, prenom: 'Équipe' }, `[Alerte] ${sujet}`, htmlAdmin);

    return new Response(JSON.stringify({ status: 'alerte_envoyee', destinataires: envoyes }), {
      status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error(err);
    return new Response(JSON.stringify({ status: 'erreur', message: String(err) }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
