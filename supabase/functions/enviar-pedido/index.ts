// Envía un pedido de INDUVEC a un fabricante desde javier@induvec.com (SMTP de IONOS, puerto 465),
// siempre con copia a comercial@induvec.com, y guarda una copia en «Elementos enviados» (IMAP de IONOS).
// Solo puede usarlo el director del CRM. La contraseña está en los secretos de Supabase (SMTP_PASS), nunca en el código.
import nodemailer from "npm:nodemailer@6.9.14";
import MailComposer from "npm:nodemailer@6.9.14/lib/mail-composer/index.js";
import { ImapFlow } from "npm:imapflow@1.0.164";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const ORIGENES = ["https://agenda.cdvbyjcerezo.com"];
const cors = (origen: string | null) => ({
  "Access-Control-Allow-Origin": origen && ORIGENES.includes(origen) ? origen : ORIGENES[0],
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
});
const emailOk = (s: unknown) => typeof s === "string" && /^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$/.test(s) && s.length <= 160;

Deno.serve(async (req) => {
  const h = cors(req.headers.get("origin"));
  const json = (cuerpo: unknown, estado = 200) => new Response(JSON.stringify(cuerpo), { status: estado, headers: { ...h, "Content-Type": "application/json" } });
  if (req.method === "OPTIONS") return new Response("ok", { headers: h });
  if (req.method !== "POST") return json({ ok: false, error: "Método no permitido" }, 405);
  try {
    const auth = req.headers.get("Authorization") || "";
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
    const { data: esDir, error: eDir } = await sb.rpc("crm_es_director");
    if (eDir || esDir !== true) return json({ ok: false, error: "Solo el director puede enviar pedidos" }, 403);

    const b = await req.json();
    const { presupuesto_id, para, asunto, texto, pdf_base64, pdf_nombre } = b || {};
    if (!emailOk(para)) return json({ ok: false, error: "Correo de destino no válido" }, 400);
    if (typeof asunto !== "string" || !asunto.trim() || asunto.length > 200) return json({ ok: false, error: "Asunto no válido" }, 400);
    if (typeof texto !== "string" || texto.length > 20000) return json({ ok: false, error: "Texto no válido" }, 400);
    if (typeof pdf_base64 !== "string" || pdf_base64.length < 100 || pdf_base64.length > 7_000_000) return json({ ok: false, error: "PDF no válido" }, 400);
    // El pedido tiene que existir y verlo quien envía (RLS)
    const { data: pz, error: ePz } = await sb.from("crm_presupuestos").select("id, numero, estado").eq("id", presupuesto_id).single();
    if (ePz || !pz || pz.estado !== "aceptado") return json({ ok: false, error: "Pedido no encontrado" }, 404);

    const usuario = Deno.env.get("SMTP_USER") || "javier@induvec.com";
    const t = nodemailer.createTransport({ host: Deno.env.get("SMTP_HOST") || "smtp.ionos.es", port: 465, secure: true, auth: { user: usuario, pass: Deno.env.get("SMTP_PASS") } });
    const COPIA = Deno.env.get("COPIA_PEDIDOS") || "comercial@induvec.com";
    const correo = {
      from: `"Javier Cerezo · INDUVEC" <${usuario}>`, to: para, cc: para.toLowerCase() === COPIA.toLowerCase() ? undefined : COPIA, replyTo: usuario,
      subject: asunto.trim(), text: texto, date: new Date(),
      attachments: [{ filename: String(pdf_nombre || `Pedido ${pz.numero}.pdf`).replace(/[\\/:*?"<>|\r\n]/g, "").slice(0, 120), content: pdf_base64, encoding: "base64", contentType: "application/pdf" }],
    };
    const info = await t.sendMail(correo);
    // Copia en «Elementos enviados» de javier@induvec.com. Si falla, el correo ya ha salido: se avisa pero no es error.
    let enviados = "";
    try {
      const raw = await new MailComposer({ ...correo, messageId: info.messageId }).compile().build();
      const imap = new ImapFlow({ host: Deno.env.get("IMAP_HOST") || "imap.ionos.es", port: 993, secure: true, auth: { user: usuario, pass: Deno.env.get("SMTP_PASS")! }, logger: false });
      await imap.connect();
      const carpetas = await imap.list();
      const sent = carpetas.find((c: { specialUse?: string }) => c.specialUse === "\\Sent")
        || carpetas.find((c: { path: string }) => /^(INBOX[./])?(elementos enviados|enviados|sent items|sent)$/i.test(c.path));
      if (sent) { await imap.append(sent.path, raw, ["\\Seen"]); enviados = sent.path; }
      await imap.logout();
    } catch (e) { enviados = "no guardado: " + String((e as Error)?.message || e).slice(0, 120); }
    return json({ ok: true, id: info.messageId, copia: correo.cc || null, enviados });
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message || e).slice(0, 300) }, 500);
  }
});
