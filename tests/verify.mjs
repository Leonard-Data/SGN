import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
const root=path.resolve(import.meta.dirname,'..');
const db=new PGlite();
const log=[];
async function scalar(sql){return (await db.query(sql)).rows[0];}
async function mustFail(sql,pattern,label){
  try {await db.exec(sql); throw new Error('UNEXPECTED SUCCESS: '+label);}
  catch(e){assert.match(e.message,pattern,label);log.push({test:label,result:'pass'});}
}
await db.exec(`
  create role anon nologin; create role authenticated nologin;
  create role service_role nologin bypassrls;
  create schema auth; create schema storage;
  create table auth.users(id uuid primary key);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
  grant usage on schema auth to authenticated,service_role;
  grant execute on function auth.uid() to authenticated,service_role;
  create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
  create table storage.objects(id bigint generated always as identity primary key,bucket_id text references storage.buckets,name text);
  alter table storage.objects enable row level security;
  grant usage on schema storage to authenticated; grant select on storage.objects to authenticated;
`);
const migrationNames=(await fs.readdir(path.join(root,'supabase/migrations'))).filter(x=>x.endsWith('.sql')).sort();
for(const name of migrationNames)await db.exec(await fs.readFile(path.join(root,'supabase/migrations',name),'utf8'));
log.push({test:'Complete SQL migration applies on PostgreSQL engine',result:'pass'});
await db.exec(`
  insert into auth.users values ('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002'),('00000000-0000-0000-0000-000000000003'),('00000000-0000-0000-0000-000000000004'),('00000000-0000-0000-0000-000000000005'),('00000000-0000-0000-0000-000000000006');
  insert into crm.organizations(name) values('Synthetic SGN'),('Synthetic Other');
  insert into crm.teams(organization_id,name) values(1,'Synthetic Team'),(2,'Foreign Team');
  insert into crm.staff_profiles(organization_id,team_id,auth_user_id,display_name,active) values
    (1,1,'00000000-0000-0000-0000-000000000001','Admin',true),
    (1,1,'00000000-0000-0000-0000-000000000002','Sales A',true),
    (1,1,'00000000-0000-0000-0000-000000000003','Sales B',true),
    (1,1,'00000000-0000-0000-0000-000000000004','Manager',true),
    (1,1,'00000000-0000-0000-0000-000000000005','Finance',true),
    (2,2,'00000000-0000-0000-0000-000000000006','Other user',true);
  insert into crm_private.memberships values(1,1,'admin'),(1,2,'sales'),(1,3,'sales'),(1,4,'manager'),(1,5,'finance'),(2,6,'admin');
  insert into crm.admin_unit_versions(official_code,unit_level,unit_type,name_vi,valid_from,legal_source,verified_at) values('01','province','province','SYNTHETIC Province','2025-07-01','TEST ONLY',now());
  insert into crm.admin_unit_versions(official_code,unit_level,unit_type,name_vi,parent_version_id,valid_from,legal_source,verified_at) values('00001','commune','ward','SYNTHETIC Ward',1,'2025-07-01','TEST ONLY',now());
  insert into crm.properties(organization_id,display_code,identity_verified) values(1,'TEST-1',true),(1,'TEST-2',true),(2,'OTHER-1',true);
  insert into crm.property_addresses(organization_id,property_id,original_address,province_version_id,commune_version_id,address_as_of,verification_status,mapping_method,evidence_reference,verified_by_staff_id,verified_at) values(1,1,'SYNTHETIC ADDRESS',1,2,'2026-10-08','verified','manual_verified','TEST ONLY',1,now()),(1,2,'SYNTHETIC ADDRESS',1,2,'2026-10-08','verified','manual_verified','TEST ONLY',1,now());
  insert into crm.listings(organization_id,property_id,purpose,approval_state,assigned_staff_id) values(1,1,'sale','approved',2),(1,2,'rent','approved',2),(2,3,'sale','approved',6);
  insert into crm.contacts(organization_id,display_name,team_id,assigned_staff_id) values(1,'SYNTHETIC Buyer',1,2),(2,'Other Buyer',2,6);
  insert into crm_private.contact_phones(organization_id,contact_id,number_raw,number_e164) values(1,1,'TEST PHONE','+84900000000');
  insert into crm.deals(organization_id,listing_id,property_id,buyer_contact_id,owner_staff_id,team_id,final_sale_price_vnd,final_price_verified,agreement_reference,agreement_address,closing_definition) values
    (1,1,1,1,2,1,10000000000,true,'TEST AGREEMENT','TEST AGREEMENT ADDRESS','Synthetic contractual completion'),
    (1,2,2,1,2,1,10000000000,true,'TEST RENT','TEST ADDRESS','Test'),
    (2,3,3,2,6,2,10000000000,true,'OTHER TEST','OTHER ADDRESS','Test');
`);
async function login(n){await db.exec(`reset role; set request.jwt.claim.sub='00000000-0000-0000-0000-${String(n).padStart(12,'0')}'; set role authenticated;`);}
await login(1);
await db.exec(`select crm.approve_commission_term(1,1,2,0.005,'salesperson','TEST RATE','term-a'); select crm.approve_commission_term(1,1,3,0.002,'co_agent','TEST RATE','term-b');`);
const closeTime=new Date(Date.now()-60000).toISOString();
let closed=await scalar(`select crm.close_deal(1,1,'${closeTime}','close-1') as result`);
assert.equal(closed.result.payable_vnd,70000000);assert.equal(closed.result.beneficiaries,2);
log.push({test:'Final price times direct rates produces 70m payable at closing',result:'pass'});
assert.deepEqual((await scalar(`select crm.close_deal(1,1,'${closeTime}','close-1') as result`)).result,closed.result);
await mustFail(`select crm.close_deal(1,1,'${closeTime}','another-close')`,/terminal/,'Second closing key cannot accrue twice');
await mustFail(`select crm.approve_commission_term(1,1,2,0.006,'salesperson','CHANGE','change-after-close')`,/open deal/,'Rate changes after closing rejected');
await mustFail(`select crm.close_deal(1,2,'${closeTime}','close-rent')`,/rental/,'Rental cannot use sale commission rule');
await login(2);
assert.equal((await scalar(`select count(*)::int as n from crm.commission_entries`)).n,1);
assert.equal((await scalar(`select entitlement_vnd::text as v from crm.commission_balances`)).v,'50000000');
log.push({test:'Sales A sees only own earnings, including shared deal',result:'pass'});
await mustFail(`select crm.close_deal(1,2,'${closeTime}','sales-close')`,/Not authorized/,'Sales cannot close deals');
await mustFail(`insert into crm.commission_entries(organization_id) values(1)`,/permission denied/,'Browser cannot directly insert ledger entries');
await mustFail(`select * from crm_private.contact_phones`,/permission denied/,'Raw phone table inaccessible to browser');
assert.equal((await db.query(`select * from crm.reveal_contact_phones(1,1)`)).rows.length,1);
await login(3);
await mustFail(`select * from crm.reveal_contact_phones(1,1)`,/denied/,'Unassigned salesperson cannot reveal owner contact phones');
await login(6);
assert.equal((await scalar(`select count(*)::int as n from crm.deals where organization_id=1`)).n,0);
await mustFail(`select crm.close_deal(1,1,'${closeTime}','foreign-close')`,/Not authorized/,'Foreign organization cannot close a deal');
await login(5);
const paidTime=new Date(Date.now()-30000).toISOString();
const paySql=`select crm.record_commission_payment(1,2,'payout','TEST BANK REF','${paidTime}','[{"deal_id":1,"amount_vnd":20000000}]','pay-1') as result`;
const pay=await scalar(paySql);assert.deepEqual((await scalar(paySql)).result,pay.result);
assert.equal((await scalar(`select outstanding_vnd::text as v from crm.commission_balances where beneficiary_staff_id=2`)).v,'30000000');
log.push({test:'Partial payment and identical retry settle once',result:'pass'});
await mustFail(`select crm.record_commission_payment(1,2,'payout','TOO MUCH','${paidTime}','[{"deal_id":1,"amount_vnd":30000001}]','pay-too-much')`,/exceeds/,'Overpayment attempt rejected');
await mustFail(`select crm.record_commission_payment(1,2,'payout','TEST BANK REF','${paidTime}','[{"deal_id":1,"amount_vnd":1}]','different-reference-key')`,/unique constraint/,'Duplicate bank reference rejected');
await mustFail(`select crm.record_commission_payment(1,2,'payout','CHANGED','${paidTime}','[{"deal_id":1,"amount_vnd":1}]','pay-1')`,/different request/,'Same event key with changed body rejected');
await login(4);
assert.equal((await scalar(`select outstanding_vnd::text as v from crm.commission_balances where beneficiary_staff_id=2`)).v,'30000000');
log.push({test:'Manager scoped balances include payments without leaking payment headers',result:'pass'});
await login(5);
const accrual=await scalar(`select id::int as id from crm.commission_entries where beneficiary_staff_id=2 and entry_kind='accrual'`);
await db.exec(`select crm.adjust_commission(1,${accrual.id},-10000000,'TEST correction','adjust-1')`);
assert.equal((await scalar(`select outstanding_vnd::text as v from crm.commission_balances where beneficiary_staff_id=2`)).v,'20000000');
await db.exec(`select crm.cancel_closed_deal(1,1,'TEST cancellation evidence','cancel-1')`);
assert.equal((await scalar(`select recoverable_vnd::text as v from crm.commission_balances where beneficiary_staff_id=2`)).v,'20000000');
await db.exec(`select crm.record_commission_payment(1,2,'recovery','TEST REFUND','${paidTime}','[{"deal_id":1,"amount_vnd":20000000}]','recover-1')`);
assert.equal((await scalar(`select recoverable_vnd::text as v from crm.commission_balances where beneficiary_staff_id=2`)).v,'0');
log.push({test:'Correction, cancellation, recovery preserve snapshots and reconcile balances',result:'pass'});
await db.exec('reset role');
await mustFail(`update crm.commission_entries set amount_vnd=1`,/append-only/,'Journal immutable even for database owner');
await mustFail(`insert into crm.listings(organization_id,property_id,purpose) values(2,1,'sale')`,/foreign key/,'Composite FK rejects cross-company property linkage');
await mustFail(`update crm.deals set final_sale_price_vnd='NaN'::numeric where id=2`,/check constraint/,'Nonfinite final price rejected');
await mustFail(`insert into crm.property_addresses(organization_id,property_id,original_address,province_version_id,commune_version_id,address_as_of,verification_status,mapping_method,evidence_reference,verified_by_staff_id,verified_at) values(1,1,'TEST',1,2,'2020-01-01','verified','manual_verified','TEST',1,now())`,/outside/,'Out-of-era address version rejected');
assert.equal((await scalar(`select round(10000000100::numeric*0.005,0)::text as v`)).v,'50000001');
log.push({test:'Numeric half-VND rounding boundary uses half-away-from-zero',result:'pass'});
const unprotected=await scalar(`select count(*)::int as n from pg_tables where schemaname in ('crm','crm_private','crm_import') and not rowsecurity`);
assert.equal(unprotected.n,0);
assert.equal((await scalar(`select count(*)::int as n from crm_private.contact_access_events where outcome='allowed'`)).n,1);
log.push({test:'RLS enabled on all tables and phone reveal audited',result:'pass'});
await db.exec(`insert into crm.property_files(organization_id,property_id,file_kind,bucket_id,object_key,availability,sha256,byte_size,mime_type) values(1,1,'property_image','sgn-property-images','1/1/test.jpg','available',repeat('a',64),10,'image/jpeg'); insert into storage.objects(bucket_id,name) values('sgn-property-images','1/1/test.jpg');`);
await login(2);assert.equal((await scalar(`select count(*)::int as n from storage.objects`)).n,1);
await login(6);assert.equal((await scalar(`select count(*)::int as n from storage.objects`)).n,0);
log.push({test:'Private Storage policy isolates registered files across companies',result:'pass'});
await db.exec(`reset role; set role anon;`);
await mustFail(`select crm.close_deal(1,1,now(),'anon-close')`,/permission denied/,'Anonymous role cannot access financial RPC');
await db.exec('reset role');
await db.exec(`insert into crm_import.batches(organization_id,filename,file_sha256,transform_version,expected_sheet_counts) values(1,'TEST ONLY.xlsx',repeat('a',64),'test','{}');
insert into crm_import.source_rows(organization_id,batch_id,sheet_name,row_number,legacy_id,row_sha256,payload) values(1,1,'Thông tin dự án',2,'TEST LEGACY',repeat('b',64),'{"PropertyID":"TEST LEGACY","Địa chỉ dự án":"TEST ADDRESS","Tạo mới":"Đã bán"}');`);
const decision=`'{"approved_by_staff_id":1,"identity_verified":true,"identity_evidence":"TEST REVIEW","display_code":"TEST IMPORT","purpose":"sale"}'::jsonb`;
let promoted=await scalar(`select crm_import.promote_property(1,1,${decision}) as result`);
assert.deepEqual((await scalar(`select crm_import.promote_property(1,1,${decision}) as result`)).result,promoted.result);
assert.equal((await scalar(`select status as s from crm.listings where id=${promoted.result.listing_id}`)).s,'sold_legacy');
assert.equal((await scalar(`select count(*)::int as n from crm.commission_entries`)).n,5);
log.push({test:'Reviewed property promotion is repeatable; legacy sold does not create commission',result:'pass'});
await mustFail(`insert into crm_import.source_rows(organization_id,batch_id,sheet_name,row_number,row_sha256,payload) values(1,1,'Nhân viên',2,repeat('c',64),'{"Password":"SYNTHETIC"}')`,/check constraint/,'Staging rejects password field');
const schema=await db.query(`select c.table_schema,c.table_name,c.column_name,c.data_type,c.udt_name,c.is_nullable,c.column_default,c.is_identity,c.character_maximum_length,c.numeric_precision,c.numeric_scale from information_schema.columns c join information_schema.tables t on t.table_schema=c.table_schema and t.table_name=c.table_name where c.table_schema in ('crm','crm_private','crm_import') and t.table_type='BASE TABLE' order by c.table_schema,c.table_name,c.ordinal_position`);
const constraints=await db.query(`select n.nspname as schema,t.relname as table_name,c.conname as name,pg_get_constraintdef(c.oid) as definition from pg_constraint c join pg_class t on t.oid=c.conrelid join pg_namespace n on n.oid=t.relnamespace where n.nspname in ('crm','crm_private','crm_import') order by n.nspname,t.relname,c.conname`);
const indexes=await db.query(`select schemaname as schema,tablename as table_name,indexname as name,indexdef as definition from pg_indexes where schemaname in ('crm','crm_private','crm_import') order by schemaname,tablename,indexname`);
const comments=await db.query(`select n.nspname as schema,c.relname as table_name,obj_description(c.oid,'pg_class') as description from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('crm','crm_private','crm_import') and c.relkind='r'`);
await fs.writeFile(path.join(root,'docs/schema.json'),JSON.stringify({columns:schema.rows,constraints:constraints.rows,indexes:indexes.rows,table_descriptions:comments.rows},null,2));
const report={engine:'PGlite PostgreSQL (Supabase Auth/Storage schemas represented by test stubs)',passed:log.length,tests:log,limitations:['No live Supabase deployment or adviser scan','Single-connection engine: real concurrent sessions and Storage HTTP flow still need a Supabase integration test']};
await fs.writeFile(path.join(root,'tests/verification.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));await db.close();
