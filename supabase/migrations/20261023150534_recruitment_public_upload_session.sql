-- A public upload receipt has identical capabilities with or without an existing login.
-- This changes no read permission and does not enable uploads to private referral applications.
create or replace function private.recruitment_resume_allowed(p_name text,p_write boolean)returns boolean language plpgsql stable security definer set search_path=pg_catalog,private,public as $$
declare a private.recruitment_applications%rowtype;r private.recruitment_requests%rowtype;begin
 if p_name!~'^[0-9a-f-]{36}/resume.pdf$'then return false;end if;
 select * into a from private.recruitment_applications where resume_token=split_part(p_name,'/',1)::uuid;if not found then return false;end if;
 select * into strict r from private.recruitment_requests where id=a.request_id;
 if p_write and a.created_at>now()-interval '1 hour'and r.published and r.status='open'and r.route='advertised'then return true;end if;
 if auth.uid()is null then return false;end if;
 return private.recruitment_visible(r.id)and(not p_write or(private.recruitment_permission('recruitment.manage')or r.created_by=auth.uid()));end$$;
