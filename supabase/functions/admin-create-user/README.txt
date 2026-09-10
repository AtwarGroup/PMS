ATWAR ONE - admin-create-user Edge Function

Deploy once from a machine with Supabase CLI authenticated to this project:
  supabase functions deploy admin-create-user --project-ref mjmxebkyswuphbgsukdt

Do NOT put the Service Role key in any HTML/JS file.
Supabase Edge Functions provide SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY as server-side environment variables.

The function validates that the caller is an active profile with role=admin, creates the Auth user, then creates public.profiles. If profile creation fails it rolls back by deleting the newly-created Auth user.
