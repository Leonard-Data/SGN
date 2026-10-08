-- Run after deployment to the selected development Supabase project.
-- All results in the first three queries should be empty.
select schemaname,tablename from pg_tables
where schemaname in ('crm','crm_private','crm_import') and not rowsecurity;
select n.nspname,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname in ('crm','crm_private') and p.prosecdef and has_function_privilege('anon',p.oid,'EXECUTE');
select table_schema,table_name,privilege_type from information_schema.role_table_grants
where grantee='authenticated' and table_schema in ('crm','crm_private','crm_import') and privilege_type<>'SELECT';
select id,name,public,file_size_limit from storage.buckets where id in ('sgn-property-images','sgn-agreements');
select organization_id,deal_id,beneficiary_staff_id,count(*) from crm.commission_entries where entry_kind='accrual'
group by organization_id,deal_id,beneficiary_staff_id having count(*)>1;
select p.organization_id,p.id,p.amount_vnd,coalesce(sum(a.amount_vnd),0) as allocated
from crm.commission_payments p left join crm.commission_payment_allocations a on a.organization_id=p.organization_id and a.payment_id=p.id
group by p.organization_id,p.id,p.amount_vnd having p.amount_vnd<>coalesce(sum(a.amount_vnd),0);
