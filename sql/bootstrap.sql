-- psql -v ON_ERROR_STOP=1 -v organization_name='SGN Real Estate' 
--   -v admin_user_id='EXISTING_SUPABASE_AUTH_UUID' -v admin_name='Administrator' -f bootstrap.sql
-- Invite the first admin using Supabase Auth first. Do not insert Auth passwords.
begin;
select 1 / (exists(select 1 from auth.users where id=:'admin_user_id'::uuid))::integer as auth_user_exists;
insert into crm.organizations(name) values(:'organization_name') returning id as organization_id \gset
insert into crm.teams(organization_id,name) values(:organization_id,'SGN Main Team') returning id as team_id \gset
insert into crm.staff_profiles(organization_id,team_id,auth_user_id,display_name,active)
values(:organization_id,:team_id,:'admin_user_id'::uuid,:'admin_name',true) returning id as staff_id \gset
insert into crm_private.memberships values(:organization_id,:staff_id,'admin');
commit;
select :organization_id::bigint as organization_id,:team_id::bigint as team_id,:staff_id::bigint as admin_staff_id;
