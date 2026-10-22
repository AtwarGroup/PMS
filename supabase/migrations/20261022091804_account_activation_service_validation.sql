-- The server-side account creation API validates modules through an invoker trigger.
-- Grant only schema lookup and the existing validator to its service role.
grant usage on schema private to service_role;
grant execute on function private.validate_module_keys(text[]) to service_role;
