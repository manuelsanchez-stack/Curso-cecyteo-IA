import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.117.1';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const roles = ['Personal Administrativo', 'Administrador', 'Docente', 'Supervisor'];

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Método no permitido.' }, 405);
  const auth = req.headers.get('Authorization');
  if (!auth) return json({ error: 'Inicia sesión para continuar.' }, 401);

  const url = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const adminClient = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: { user }, error: authError } = await adminClient.auth.getUser(auth.replace(/^Bearer\s+/i, ''));
  if (authError || !user) return json({ error: 'Sesión no válida.' }, 401);

  let body: { action?: string; email?: string; full_name?: string; department?: string; role?: string; user_id?: string };
  try { body = await req.json(); } catch { return json({ error: 'Solicitud inválida.' }, 400); }

  if (body.action === 'complete-password') {
    const { error } = await adminClient.auth.admin.updateUserById(user.id, {
      app_metadata: { ...user.app_metadata, must_change_password: false },
    });
    return error ? json({ error: error.message }, 400) : json({ completed: true });
  }

  const { data: caller } = await adminClient.from('profiles').select('role').eq('id', user.id).maybeSingle();
  if (caller?.role !== 'Administrador') return json({ error: 'Solo el administrador puede administrar usuarios.' }, 403);
  const temporaryPassword = newPassword();

  if (body.action === 'reset-password') {
    if (!body.user_id) return json({ error: 'Falta el usuario que se restablecerá.' }, 400);
    const { data: target, error: targetError } = await adminClient.auth.admin.getUserById(body.user_id);
    if (targetError || !target.user) return json({ error: 'No se encontró el usuario.' }, 404);
    const { error } = await adminClient.auth.admin.updateUserById(body.user_id, {
      password: temporaryPassword,
      app_metadata: { ...target.user.app_metadata, must_change_password: true },
    });
    return error ? json({ error: error.message }, 400) : json({ temporary_password: temporaryPassword });
  }

  if (body.action !== 'create-user') return json({ error: 'Acción no válida.' }, 400);
  const email = body.email?.trim().toLowerCase();
  const full_name = body.full_name?.trim();
  const department = body.department?.trim();
  const role = body.role?.trim();
  if (!email || !email.endsWith('@cecyteo.edu.mx') || !full_name || !department || !role || !roles.includes(role)) {
    return json({ error: 'Completa los campos con un correo @cecyteo.edu.mx y un rol válido.' }, 400);
  }
  const { data, error } = await adminClient.auth.admin.createUser({
    email,
    password: temporaryPassword,
    email_confirm: true,
    user_metadata: { full_name, department },
    app_metadata: { role, must_change_password: true },
  });
  if (error || !data.user) return json({ error: error?.message || 'No se pudo crear el usuario.' }, 400);
  const { error: profileError } = await adminClient.from('profiles').update({ full_name, department, role }).eq('id', data.user.id);
  if (profileError) {
    await adminClient.auth.admin.deleteUser(data.user.id);
    return json({ error: `No se pudo guardar el perfil: ${profileError.message}` }, 500);
  }
  return json({ created: true, temporary_password: temporaryPassword });
});

function newPassword() {
  const bytes = crypto.getRandomValues(new Uint8Array(24));
  return Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('');
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}
