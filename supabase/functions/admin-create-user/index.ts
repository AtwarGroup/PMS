import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  try {
    const url = Deno.env.get('SUPABASE_URL')
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!url || !service) throw new Error('Supabase server environment is not available')

    const authHeader = req.headers.get('Authorization') || ''
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7).trim() : ''
    if (!token) return json({ error: 'Authentication required' }, 401)

    // One server-side client only. Service Role never leaves the Edge Function.
    const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } })

    // Verify the caller token directly with Supabase Auth.
    const { data: userData, error: userError } = await admin.auth.getUser(token)
    if (userError || !userData.user) return json({ error: 'Invalid or expired session' }, 401)

    const { data: callerProfile, error: profileError } = await admin
      .from('profiles')
      .select('id,role,active,status')
      .eq('id', userData.user.id)
      .single()

    if (profileError || !callerProfile) return json({ error: 'Admin profile not found' }, 403)
    if (callerProfile.role !== 'admin' || !callerProfile.active || callerProfile.status !== 'active') {
      return json({ error: 'Admin permission required' }, 403)
    }

    const body = await req.json().catch(() => ({}))
    const action = String(body?.action || 'create')

    if (action === 'list') {
      const { data, error } = await admin
        .from('profiles')
        .select('id,full_name,email,job_title,department,role,status,active,manager_id,firebase_uid')
        .order('full_name', { ascending: true })
      if (error) throw error
      return json({ users: data || [] })
    }

    if (action === 'create') {
      const email = String(body.email || '').trim().toLowerCase()
      const password = String(body.password || '')
      const fullName = String(body.full_name || '').trim()
      const role = String(body.role || 'employee')
      const status = String(body.status || 'active')
      const managerId = body.manager_id || null
      const jobTitle = String(body.job_title || '').trim() || null
      const department = String(body.department || '').trim() || null

      if (!email || !email.includes('@')) throw new Error('Valid email is required')
      if (password.length < 8) throw new Error('Password must be at least 8 characters')
      if (!fullName) throw new Error('Full name is required')
      if (!['employee', 'manager', 'admin'].includes(role)) throw new Error('Invalid role')
      if (!['active', 'inactive'].includes(status)) throw new Error('Invalid status')

      if (managerId) {
        const { data: mgr, error: mgrErr } = await admin.from('profiles')
          .select('id,role,active,status').eq('id', managerId).single()
        if (mgrErr || !mgr || !mgr.active || mgr.status !== 'active' || !['manager', 'admin'].includes(mgr.role)) {
          throw new Error('Selected manager is invalid or inactive')
        }
      }

      const { data: created, error: createErr } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { full_name: fullName },
      })
      if (createErr || !created.user) throw createErr || new Error('Could not create auth user')

      const id = created.user.id
      const { error: insertErr } = await admin.from('profiles').insert({
        id,
        full_name: fullName,
        email,
        role,
        status,
        active: status === 'active',
        manager_id: managerId,
        job_title: jobTitle,
        department,
        firebase_uid: null,
      })
      if (insertErr) {
        await admin.auth.admin.deleteUser(id)
        throw insertErr
      }
      return json({ id, email })
    }

    if (action === 'update') {
      const targetId = String(body.id || '')
      const fullName = String(body.full_name || '').trim()
      const role = String(body.role || '')
      const status = String(body.status || '')
      const managerId = body.manager_id || null
      const jobTitle = String(body.job_title || '').trim() || null
      const department = String(body.department || '').trim() || null

      if (!targetId) throw new Error('User id is required')
      if (!fullName) throw new Error('Full name is required')
      if (!['employee', 'manager', 'admin'].includes(role)) throw new Error('Invalid role')
      if (!['active', 'inactive'].includes(status)) throw new Error('Invalid status')
      if (managerId && managerId === targetId) throw new Error('A user cannot be their own manager')
      if (targetId === userData.user.id && (role !== 'admin' || status !== 'active')) {
        throw new Error('You cannot remove your own admin access or deactivate your own account')
      }
      if (managerId) {
        const { data: mgr, error: mgrErr } = await admin.from('profiles')
          .select('id,role,active,status').eq('id', managerId).single()
        if (mgrErr || !mgr || !mgr.active || mgr.status !== 'active' || !['manager', 'admin'].includes(mgr.role)) {
          throw new Error('Selected manager is invalid or inactive')
        }
      }

      const { data, error } = await admin.from('profiles').update({
        full_name: fullName,
        role,
        status,
        active: status === 'active',
        manager_id: managerId,
        job_title: jobTitle,
        department,
      }).eq('id', targetId)
        .select('id,full_name,email,job_title,department,role,status,active,manager_id,firebase_uid')
        .single()
      if (error) throw error
      return json({ user: data })
    }

    throw new Error('Unsupported action')
  } catch (e) {
    console.error(e)
    return json({ error: e instanceof Error ? e.message : String(e) }, 400)
  }
})
