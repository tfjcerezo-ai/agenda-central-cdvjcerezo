// Envía un pedido de INDUVEC a un fabricante desde javier@induvec.com (SMTP de IONOS, puerto 465).
// Solo puede usarlo el director del CRM. La contraseña está en los secretos de Supabase (SMTP_PASS), nunca en el código.
import nodemailer from "npm:nodemailer@6.9.14";
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
    const info = await t.sendMail({
      from: `"Javier Cerezo · INDUVEC" <${usuario}>`, to: para, bcc: usuario, replyTo: usuario,
      subject: asunto.trim(), text: texto,
      attachments: [{ filename: String(pdf_nombre || `Pedido ${pz.numero}.pdf`).replace(/[\\/:*?"<>|\r\n]/g, "").slice(0, 120), content: pdf_base64, encoding: "base64", contentType: "application/pdf" }],
    });
    return json({ ok: true, id: info.messageId });
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message || e).slice(0, 300) }, 500);
  }
});
