-- STAGING ONLY: eeaedzisysjarwvolbwq. Snapshot of the change applied 2026-10-30.
-- Never apply to production. Preserves existing trial expiry and synthetic users.
-- The fixed existing administrator signs in only through the owner-verified gateway.
CREATE OR REPLACE FUNCTION private.current_user_is_active()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,private AS $$
SELECT EXISTS (
 SELECT 1 FROM public.profiles p
 WHERE p.id=auth.uid() AND p.active AND p.status='active'
 AND (
  p.email LIKE '%@atwar-staging.test'
  OR (p.id='719473c6-5354-4775-b6f4-c0239a86c385'::uuid
      AND p.email='helpdesk@tiradorstores.com' AND p.role='admin')
  OR EXISTS (SELECT 1 FROM private.trial_participants t
             WHERE t.profile_id=p.id AND t.enabled AND t.expires_at>now())
 )
);
$$;
-- CREATE OR REPLACE preserves the existing function owner and grants.
-- Rollback: remove only the fixed UUID/email/admin OR clause above.
-- No public trial-list entry, password, approval flow, or salary modification.
