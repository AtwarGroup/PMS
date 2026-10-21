import { createClient } from 'npm:@supabase/supabase-js@2.117.0'

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

    const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } })

    const { data: userData, error: userError } = await admin.auth.getUser(token)
    if (userError || !userData.user) return json({ error: 'Invalid or expired session' }, 401)

    let callerProfile: any = null
    const { data: profileById, error: profileByIdError } = await admin
      .from('profiles').select('id,role,active,status,email,full_name').eq('id', userData.user.id).maybeSingle()
    if (profileByIdError) console.error('Profile lookup by id failed:', profileByIdError)
    callerProfile = profileById

    if (!callerProfile && userData.user.email) {
      const { data: profileByEmail, error: profileByEmailError } = await admin
        .from('profiles').select('id,role,active,status,email,full_name').ilike('email', userData.user.email).maybeSingle()
      if (profileByEmailError) console.error('Profile lookup by email failed:', profileByEmailError)
      callerProfile = profileByEmail
    }

    if (!callerProfile) return json({ error: 'Admin profile not found' }, 403)
    if (callerProfile.role !== 'admin' || callerProfile.active !== true || callerProfile.status !== 'active') {
      return json({ error: 'Admin permission required' }, 403)
    }

    const body = await req.json().catch(() => ({}))
    const action = String(body?.action || 'create')

    const audit = async (auditAction: string, targetType: string, targetId: string | null, detail: Record<string, unknown> = {}) => {
      const { error: auditError } = await admin.from('admin_audit_log').insert({
        actor_id: callerProfile.id,
        actor_name_snapshot: callerProfile.full_name || callerProfile.email || userData.user.email || 'Admin',
        action: auditAction, target_type: targetType, target_id: targetId, detail,
      })
      if (auditError) console.error('Admin audit log failed:', auditError)
    }

    if (action === 'list') {
      const { data, error } = await admin.from('profiles')
        .select('id,full_name,email,job_title,department,role,status,active,manager_id,firebase_uid')
        .order('full_name', { ascending: true })
      if (error) throw error
      return json({ users: data || [] })
    }

    if (action === 'create') {
      let modules = body.allowed_modules ?? []
      if (!Array.isArray(modules) || modules.some((key: unknown) => typeof key !== 'string')) throw new Error('Invalid module selection')
      const caller = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } })
      const { data: moduleContext, error: moduleError } = await caller.rpc('account_module_context')
      if (moduleError || moduleContext?.role !== 'admin') return json({ error: 'Admin permission required' }, 403)
      if (body.allowed_modules === undefined) modules = moduleContext.catalog.filter((m: any) => m.ready).map((m: any) => m.key)
      if (modules.some((key: string) => !moduleContext.catalog.some((m: any) => m.key === key && m.ready))) throw new Error('Invalid module selection')
      const email = String(body.email || '').trim().toLowerCase()
      const password = String(body.password || '')
      const fullName = String(body.full_name || '').trim()
      const role = String(body.role || 'employee')
      const status = String(body.status || 'active')
      const managerId = body.manager_id || null
      const jobTitle = String(body.job_title || '').trim() || null
      const department = String(body.department || '').trim() || null

      if (!email || !email.includes('@')) throw new Error('Valid email is required')
      if (password.length < 6) throw new Error('Password must be at least 6 characters')
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
        email, password, email_confirm: true, user_metadata: { full_name: fullName },
      })
      if (createErr || !created.user) throw createErr || new Error('Could not create auth user')

      const id = created.user.id
      const { error: insertErr } = await admin.from('profiles').insert({
        id, full_name: fullName, email, role, status, active: status === 'active',
        manager_id: managerId, job_title: jobTitle, department, firebase_uid: null, allowed_modules: modules,
      })
      if (insertErr) {
        await admin.auth.admin.deleteUser(id)
        throw insertErr
      }
      await audit('USER_CREATE', 'user', id, { email, full_name: fullName, role, status, manager_id: managerId, allowed_modules: modules })
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
      if (targetId === callerProfile.id && (role !== 'admin' || status !== 'active')) {
        throw new Error('You cannot remove your own admin access or deactivate your own account')
      }
      if (managerId) {
        const { data: mgr, error: mgrErr } = await admin.from('profiles')
          .select('id,role,active,status').eq('id', managerId).single()
        if (mgrErr || !mgr || !mgr.active || mgr.status !== 'active' || !['manager', 'admin'].includes(mgr.role)) {
          throw new Error('Selected manager is invalid or inactive')
        }
      }

      const { data: beforeUpdate } = await admin.from('profiles')
        .select('id,full_name,email,job_title,department,role,status,active,manager_id').eq('id', targetId).maybeSingle()

      const { data, error } = await admin.from('profiles').update({
        full_name: fullName, role, status, active: status === 'active', manager_id: managerId,
        job_title: jobTitle, department,
      }).eq('id', targetId)
        .select('id,full_name,email,job_title,department,role,status,active,manager_id,firebase_uid')
        .single()
      if (error) throw error
      await audit('USER_UPDATE', 'user', targetId, { before: beforeUpdate || null, after: data })
      return json({ user: data })
    }

    if (action === 'reset_password') {
      const targetId = String(body.id || '').trim()
      const password = String(body.password || '')
      if (!targetId) throw new Error('User id is required')
      if (password.length < 6) throw new Error('Password must be at least 6 characters')

      const { data: target, error: targetErr } = await admin.from('profiles')
        .select('id,full_name,email').eq('id', targetId).maybeSingle()
      if (targetErr) throw targetErr
      if (!target) throw new Error('User profile not found')

      const { error: updatePasswordErr } = await admin.auth.admin.updateUserById(targetId, { password })
      if (updatePasswordErr) throw updatePasswordErr
      await audit('PASSWORD_RESET', 'user', targetId, { email: target.email, full_name: target.full_name })

      return json({ updated: true, id: targetId })
    }

    if (action === 'delete') {
      const targetId = String(body.id || '').trim()
      if (!targetId) throw new Error('User id is required')
      if (targetId === callerProfile.id || targetId === userData.user.id) {
        throw new Error('You cannot delete your own admin account')
      }

      const { data: target, error: targetErr } = await admin.from('profiles')
        .select('id,full_name,email').eq('id', targetId).maybeSingle()
      if (targetErr) throw targetErr
      if (!target) throw new Error('User profile not found')

      const [createdTask, assignedTask, activity, managedUser] = await Promise.all([
        admin.from('tasks').select('id').eq('creator_id', targetId).limit(1),
        admin.from('tasks').select('id').eq('assignee_id', targetId).limit(1),
        admin.from('task_activity').select('id').eq('actor_id', targetId).limit(1),
        admin.from('profiles').select('id').eq('manager_id', targetId).limit(1),
      ])
      for (const q of [createdTask, assignedTask, activity, managedUser]) if (q.error) throw q.error

      if ((createdTask.data?.length || 0) > 0 || (assignedTask.data?.length || 0) > 0 || (activity.data?.length || 0) > 0) {
        throw new Error('Cannot delete a user with task history. Deactivate the account instead.')
      }
      if ((managedUser.data?.length || 0) > 0) {
        throw new Error('Cannot delete a manager who still has direct reports. Reassign them first.')
      }

      await audit('USER_DELETE', 'user', targetId, { email: target.email, full_name: target.full_name })

      const { error: authDeleteErr } = await admin.auth.admin.deleteUser(targetId)
      if (authDeleteErr) throw authDeleteErr

      const { error: profileDeleteErr } = await admin.from('profiles').delete().eq('id', targetId)
      if (profileDeleteErr) throw profileDeleteErr

      return json({ deleted: true, id: targetId })
    }

    throw new Error('Unsupported action')
  } catch (e) {
    console.error(e)
    return json({ error: e instanceof Error ? e.message : String(e) }, 400)
  }
})

