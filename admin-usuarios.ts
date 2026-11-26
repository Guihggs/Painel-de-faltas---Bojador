// Edge Function "admin-usuarios" – gerencia os acessos do Painel de Faltas.
// Só quem tem papel 'admin' e está ativo em public.painel_usuarios pode usar.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const resp = (b: unknown) =>
  new Response(JSON.stringify(b), { headers: { ...cors, "Content-Type": "application/json" } });
const BAN = "876000h"; // ~100 anos = acesso bloqueado

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    let key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
    if (!key) { try { const k = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}"); key = k.default || Object.values(k)[0] || ""; } catch (_) { /* */ } }
    const db = createClient(Deno.env.get("SUPABASE_URL")!, key as string, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const { data: u } = await db.auth.getUser(jwt);
    if (!u?.user) return resp({ erro: "Sessão inválida. Entre novamente." });
    const { data: me } = await db.from("painel_usuarios").select("papel,ativo").eq("user_id", u.user.id).maybeSingle();
    if (!me || me.papel !== "admin" || !me.ativo) return resp({ erro: "Apenas administradores." });

    const b = await req.json();
    const self = b.user_id && b.user_id === u.user.id;

    switch (b.acao) {
      case "listar": {
        const { data: rows, error } = await db.from("painel_usuarios").select("*").order("papel").order("usuario");
        if (error) throw error;
        const { data: au } = await db.auth.admin.listUsers({ perPage: 1000 });
        const last = new Map((au?.users || []).map((x) => [x.id, x.last_sign_in_at]));
        return resp({ usuarios: rows.map((r) => ({ ...r, ultimo_acesso: last.get(r.user_id) || null })) });
      }
      case "criar": {
        const usuario = String(b.usuario || "").trim().toLowerCase();
        const email = String(b.email || "").trim().toLowerCase();
        const senha = String(b.senha || "");
        const papel = b.papel === "admin" ? "admin" : "instrutor";
        if (!usuario || !email.includes("@")) return resp({ erro: "Usuário inválido." });
        if (senha.length < 6) return resp({ erro: "A senha precisa ter pelo menos 6 caracteres." });
        const { data: c, error } = await db.auth.admin.createUser({
          email, password: senha, email_confirm: true, user_metadata: { usuario, nome: b.nome || null },
        });
        if (error) return resp({ erro: /already/i.test(error.message) ? "Esse usuário já existe." : error.message });
        const { error: e2 } = await db.from("painel_usuarios").upsert({
          user_id: c.user.id, usuario, email, nome: b.nome || null, papel, ativo: true,
        });
        if (e2) { await db.auth.admin.deleteUser(c.user.id); return resp({ erro: e2.message }); }
        return resp({ ok: true });
      }
      case "senha": {
        const senha = String(b.senha || "");
        if (senha.length < 6) return resp({ erro: "A senha precisa ter pelo menos 6 caracteres." });
        const { error } = await db.auth.admin.updateUserById(b.user_id, { password: senha });
        if (error) return resp({ erro: error.message });
        return resp({ ok: true });
      }
      case "atualizar": {
        const p: Record<string, unknown> = {};
        if (b.papel !== undefined) {
          if (self && b.papel !== "admin") return resp({ erro: "Você não pode remover seu próprio acesso de administrador." });
          p.papel = b.papel === "admin" ? "admin" : "instrutor";
        }
        if (b.ativo !== undefined) {
          if (self && !b.ativo) return resp({ erro: "Você não pode desativar o próprio acesso." });
          p.ativo = !!b.ativo;
          const { error } = await db.auth.admin.updateUserById(b.user_id, { ban_duration: b.ativo ? "none" : BAN });
          if (error) return resp({ erro: error.message });
        }
        if (b.nome !== undefined) p.nome = b.nome || null;
        if (b.usuario !== undefined) {
          const usuario = String(b.usuario || "").trim().toLowerCase();
          const email = String(b.email || "").trim().toLowerCase();
          if (!/^[a-z0-9][a-z0-9._-]*$/.test(usuario) || !email.includes("@")) {
            return resp({ erro: "Usuário inválido. Use letras minúsculas sem acento, números, ponto, hífen ou sublinhado." });
          }
          const { data: ja } = await db.from("painel_usuarios").select("user_id")
            .eq("usuario", usuario).neq("user_id", b.user_id).maybeSingle();
          if (ja) return resp({ erro: "Esse usuário já existe." });
          const { error } = await db.auth.admin.updateUserById(b.user_id, {
            email, email_confirm: true, user_metadata: { usuario },
          });
          if (error) return resp({ erro: /already|registered|exists/i.test(error.message) ? "Esse usuário já existe." : error.message });
          p.usuario = usuario;
          p.email = email;
        }
        const { error } = await db.from("painel_usuarios").update(p).eq("user_id", b.user_id);
        if (error) return resp({ erro: error.message });
        return resp({ ok: true });
      }
      case "excluir": {
        if (self) return resp({ erro: "Você não pode excluir o próprio acesso." });
        const { error } = await db.auth.admin.deleteUser(b.user_id);
        if (error) return resp({ erro: error.message });
        return resp({ ok: true });
      }
      default:
        return resp({ erro: "Ação desconhecida." });
    }
  } catch (e) {
    return resp({ erro: (e as Error).message || String(e) });
  }
});
