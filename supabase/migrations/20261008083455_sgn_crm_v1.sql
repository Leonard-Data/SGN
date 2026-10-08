-- SGN Real Estate CRM v1. Fresh-schema migration; PostgreSQL 15+ / Supabase.
-- No customer data, login credentials or unverified administrative codes are seeded.
begin;
create schema crm;
create schema crm_private;
create schema crm_import;
revoke all on schema crm, crm_private, crm_import from public, anon;
grant usage on schema crm, crm_private to authenticated;
grant usage on schema crm, crm_private, crm_import to service_role;
alter default privileges in schema crm revoke all on tables from anon, authenticated;
alter default privileges in schema crm_private revoke execute on functions from public;
alter default privileges in schema crm revoke execute on functions from public;

create table crm.organizations (
  id bigint generated always as identity primary key,
  name text not null check (btrim(name) <> ''),
  timezone text not null default 'Asia/Ho_Chi_Minh' check (timezone = 'Asia/Ho_Chi_Minh'),
  currency text not null default 'VND' check (currency = 'VND'),
  created_at timestamptz not null default now()
);
create table crm.teams (
  id bigint generated always as identity primary key,
  organization_id bigint not null references crm.organizations,
  name text not null check (btrim(name) <> ''),
  active boolean not null default true,
  unique (organization_id, id), unique (organization_id, name)
);
create table crm.staff_profiles (
  id bigint generated always as identity primary key,
  organization_id bigint not null references crm.organizations,
  team_id bigint,
  auth_user_id uuid references auth.users(id) on delete set null,
  display_name text not null check (btrim(display_name) <> ''),
  email text,
  phone text,
  avatar_object_key text,
  active boolean not null default false,
  legacy_role text,
  created_at timestamptz not null default now(),
  unique (organization_id, id), unique (organization_id, auth_user_id),
  foreign key (organization_id, team_id) references crm.teams(organization_id, id),
  check (email is null or email = lower(btrim(email)))
);
create unique index staff_email_unique on crm.staff_profiles(organization_id, email) where email is not null;
create index staff_team_idx on crm.staff_profiles(organization_id, team_id);
create table crm_private.memberships (
  organization_id bigint not null references crm.organizations,
  staff_id bigint not null,
  role text not null check (role in ('sales','manager','operations','finance','admin')),
  primary key (organization_id, staff_id, role),
  foreign key (organization_id, staff_id) references crm.staff_profiles(organization_id,id)
);
comment on table crm_private.memberships is 'Authoritative roles. Backend-only writes; no JWT user_metadata authorization.';

create table crm.admin_unit_versions (
  id bigint generated always as identity primary key,
  official_code text not null,
  unit_level text not null check (unit_level in ('province','commune')),
  unit_type text not null check (unit_type in ('province','central_city','ward','commune','special_zone')),
  name_vi text not null check (btrim(name_vi) <> ''),
  parent_version_id bigint references crm.admin_unit_versions,
  valid_from date not null,
  valid_to date,
  legal_source text not null check (btrim(legal_source) <> ''),
  verified_at timestamptz not null,
  unique (official_code,valid_from),
  check (valid_to is null or valid_to > valid_from),
  check ((unit_level='province' and official_code ~ '^[0-9]{2}$' and parent_version_id is null and unit_type in ('province','central_city')) or
         (unit_level='commune' and official_code ~ '^[0-9]{5}$' and parent_version_id is not null and unit_type in ('ward','commune','special_zone')))
);
create index admin_parent_idx on crm.admin_unit_versions(parent_version_id);
create table crm.admin_unit_crosswalks (
  id bigint generated always as identity primary key,
  original_province text not null,
  original_district text not null default '',
  original_ward text not null,
  original_regime text not null,
  successor_version_id bigint not null references crm.admin_unit_versions,
  mapping_kind text not null check (mapping_kind in ('whole_unit','partial_unit','rename')),
  effective_from date not null,
  location_rule text,
  legal_source text not null,
  unique (original_province,original_district,original_ward,original_regime,successor_version_id),
  check (mapping_kind <> 'partial_unit' or nullif(btrim(location_rule),'') is not null)
);
create table crm.property_types (code text primary key, label_vi text not null);
create table crm.road_access_types (code text primary key, label_vi text not null);
insert into crm.property_types values ('house','Nhà'),('land','Đất ở'),('apartment','Chung cư'),('villa','Biệt thự'),('serviced_apartment','Căn hộ dịch vụ'),('warehouse','Kho xưởng'),('building','Cao ốc'),('unknown','Chưa xác định');
insert into crm.road_access_types values ('frontage','Mặt tiền'),('car_alley','Hẻm ô tô'),('motorbike_alley','Hẻm xe máy'),('tricycle_alley','Hẻm ba gác'),('unknown','Chưa xác định');

create table crm.properties (
  id bigint generated always as identity primary key,
  organization_id bigint not null references crm.organizations,
  display_code text not null,
  legacy_property_id text, -- deliberately NOT unique: workbook collision exists
  property_type_code text references crm.property_types,
  road_access_code text references crm.road_access_types,
  width_m numeric(12,3) check (width_m > 0 and width_m < 'Infinity'::numeric),
  length_m numeric(12,3) check (length_m > 0 and length_m < 'Infinity'::numeric),
  land_area_m2 numeric(14,3) check (land_area_m2 > 0 and land_area_m2 < 'Infinity'::numeric),
  area_raw text,
  direction text check (direction in ('N','NE','E','SE','S','SW','W','NW')),
  structure_description text,
  identity_verified boolean not null default false,
  archived boolean not null default false,
  created_at timestamptz not null default now(),
  unique (organization_id,id), unique (organization_id,display_code)
);
create index properties_legacy_idx on crm.properties(organization_id,legacy_property_id);
create table crm.property_addresses (
  id bigint generated always as identity primary key,
  organization_id bigint not null,
  property_id bigint not null,
  original_address text not null,
  original_province text, original_district text, original_ward text,
  source_regime text not null default 'unknown',
  house_number text, street text,
  province_version_id bigint references crm.admin_unit_versions,
  commune_version_id bigint references crm.admin_unit_versions,
  address_as_of date,
  latitude numeric(10,7) check (latitude between -90 and 90),
  longitude numeric(10,7) check (longitude between -180 and 180),
  verification_status text not null default 'unresolved' check (verification_status in ('unresolved','suggested','needs_review','verified')),
  mapping_method text check (mapping_method in ('current_unit','whole_unit_crosswalk','official_street_rule','authoritative_boundary','manual_verified')),
  evidence_reference text,
  verified_by_staff_id bigint,
  verified_at timestamptz,
  is_current boolean not null default true,
  search_text text not null default '',
  created_at timestamptz not null default now(),
  unique (organization_id,id), unique (organization_id,property_id,id),
  foreign key (organization_id,property_id) references crm.properties(organization_id,id),
  foreign key (organization_id,verified_by_staff_id) references crm.staff_profiles(organization_id,id),
  check ((latitude is null)=(longitude is null)),
  check (verification_status <> 'verified' or (province_version_id is not null and commune_version_id is not null and address_as_of is not null and mapping_method is not null and nullif(btrim(evidence_reference),'') is not null and verified_by_staff_id is not null and verified_at is not null))
);
create unique index addresses_one_current on crm.property_addresses(organization_id,property_id) where is_current;
create index addresses_ward_idx on crm.property_addresses(organization_id,commune_version_id) where is_current;
create index addresses_old_district_idx on crm.property_addresses(organization_id,original_district) where is_current;
create index addresses_search_idx on crm.property_addresses using gin(to_tsvector('simple',search_text));

create table crm.listings (
  id bigint generated always as identity primary key,
  organization_id bigint not null,
  property_id bigint not null,
  purpose text not null check (purpose in ('sale','rent')),
  status text not null default 'new' check (status in ('new','available','negotiating','under_offer','sold_legacy','sold','withdrawn')),
  legacy_status text,
  asking_sale_price_vnd numeric(18,0) check (asking_sale_price_vnd > 0 and asking_sale_price_vnd < 'Infinity'::numeric),
  asking_rent_vnd numeric(18,0) check (asking_rent_vnd > 0 and asking_rent_vnd < 'Infinity'::numeric),
  rent_period text check (rent_period in ('month','year','day','other')),
  price_verified boolean not null default false,
  approval_state text not null default 'unknown' check (approval_state in ('unknown','pending','approved','rejected')),
  legacy_approved boolean,
  assigned_staff_id bigint,
  created_by_staff_id bigint,
  source_updated_by_staff_id bigint,
  source_created_at timestamptz, source_updated_at timestamptz,
  notes text, source_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,id), unique (organization_id,id,property_id),
  foreign key (organization_id,property_id) references crm.properties(organization_id,id),
  foreign key (organization_id,assigned_staff_id) references crm.staff_profiles(organization_id,id),
  foreign key (organization_id,created_by_staff_id) references crm.staff_profiles(organization_id,id),
  foreign key (organization_id,source_updated_by_staff_id) references crm.staff_profiles(organization_id,id)
);
create index listing_search_idx on crm.listings(organization_id,status,purpose,asking_sale_price_vnd);
create index listing_property_idx on crm.listings(organization_id,property_id);
create index listing_assigned_idx on crm.listings(organization_id,assigned_staff_id);
create index listing_creator_idx on crm.listings(organization_id,created_by_staff_id);
create index listing_editor_idx on crm.listings(organization_id,source_updated_by_staff_id);
create table crm.contacts (
  id bigint generated always as identity primary key,
  organization_id bigint not null references crm.organizations,
  display_name text not null,
  contact_kind text not null default 'unknown' check (contact_kind in ('person','company','unknown')),
  team_id bigint,
  assigned_staff_id bigint,
  email text,
  notes text,
  created_at timestamptz not null default now(),
  unique (organization_id,id),
  foreign key (organization_id,team_id) references crm.teams(organization_id,id),
  foreign key (organization_id,assigned_staff_id) references crm.staff_profiles(organization_id,id)
);
create index contacts_team_idx on crm.contacts(organization_id,team_id);
create index contacts_staff_idx on crm.contacts(organization_id,assigned_staff_id);
create table crm_private.contact_phones (
  id bigint generated always as identity primary key,
  organization_id bigint not null,
  contact_id bigint not null,
  number_raw text not null,
  number_e164 text check (number_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  verification_status text not null default 'unverified' check (verification_status in ('unverified','verified','invalid','disconnected')),
  is_primary boolean not null default false,
  unique (organization_id,id),
  foreign key (organization_id,contact_id) references crm.contacts(organization_id,id)
);
create index phones_contact_idx on crm_private.contact_phones(organization_id,contact_id);
create table crm.property_contacts (
  organization_id bigint not null,
  property_id bigint not null,
  contact_id bigint not null,
  relationship text not null check (relationship in ('owner','representative','broker','other')),
  verified boolean not null default false,
  primary key (organization_id,property_id,contact_id,relationship),
  foreign key (organization_id,property_id) references crm.properties(organization_id,id),
  foreign key (organization_id,contact_id) references crm.contacts(organization_id,id)
);
create index property_contacts_contact_idx on crm.property_contacts(organization_id,contact_id);

create table crm.deals (
  id bigint generated always as identity primary key,
  organization_id bigint not null,
  listing_id bigint not null,
  property_id bigint not null,
  buyer_contact_id bigint not null,
  owner_staff_id bigint not null,
  team_id bigint not null,
  stage text not null default 'lead' check (stage in ('lead','viewing','negotiation','deposit','closed_won','closed_lost','cancelled')),
  final_sale_price_vnd numeric(18,0) check (final_sale_price_vnd > 0 and final_sale_price_vnd < 'Infinity'::numeric),
  final_price_verified boolean not null default false,
  agreement_reference text,
  agreement_address text,
  closing_definition text,
  closed_at timestamptz,
  closed_by_staff_id bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,id),
  foreign key (organization_id,listing_id,property_id) references crm.listings(organization_id,id,property_id),
  foreign key (organization_id,buyer_contact_id) references crm.contacts(organization_id,id),
  foreign key (organization_id,owner_staff_id) references crm.staff_profiles(organization_id,id),
  foreign key (organization_id,team_id) references crm.teams(organization_id,id),
  foreign key (organization_id,closed_by_staff_id) references crm.staff_profiles(organization_id,id),
  check (stage <> 'closed_won' or (final_sale_price_vnd is not null and final_price_verified and closed_at is not null and closed_by_staff_id is not null and nullif(btrim(agreement_reference),'') is not null and nullif(btrim(agreement_address),'') is not null and nullif(btrim(closing_definition),'') is not null))
);
create unique index one_closed_sale_per_listing on crm.deals(organization_id,listing_id) where stage='closed_won';
create index deals_property_idx on crm.deals(organization_id,property_id);
create index deals_owner_idx on crm.deals(organization_id,owner_staff_id);
create index deals_buyer_idx on crm.deals(organization_id,buyer_contact_id);
create index deals_team_idx on crm.deals(organization_id,team_id,stage,closed_at);
create index deals_closed_by_idx on crm.deals(organization_id,closed_by_staff_id);
create table crm.activities (
  id bigint generated always as identity primary key,
  organization_id bigint not null,
  contact_id bigint,
  listing_id bigint,
  deal_id bigint,
  owner_staff_id bigint not null,
  kind text not null check (kind in ('follow_up','viewing','note','call')),
  body text not null,
  due_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (organization_id,id),
  foreign key (organization_id,contact_id) references crm.contacts(organization_id,id),
  foreign key (organization_id,listing_id) references crm.listings(organization_id,id),
  foreign key (organization_id,deal_id) references crm.deals(organization_id,id),
  foreign key (organization_id,owner_staff_id) references crm.staff_profiles(organization_id,id),
  check (contact_id is not null or listing_id is not null or deal_id is not null)
);
create index activities_owner_due_idx on crm.activities(organization_id,owner_staff_id,due_at) where completed_at is null;
create index activities_contact_idx on crm.activities(organization_id,contact_id);
create index activities_listing_idx on crm.activities(organization_id,listing_id);
create index activities_deal_idx on crm.activities(organization_id,deal_id);
create table crm.deal_commission_terms (
  id bigint generated always as identity primary key,
  organization_id bigint not null,
  deal_id bigint not null,
  beneficiary_staff_id bigint not null,
  participant_role text not null default 'salesperson',
  version integer not null check (version > 0),
  rate_fraction numeric(9,8) not null check (rate_fraction > 0 and rate_fraction <= 1),
  basis text not null default 'final_sale_price' check (basis='final_sale_price'),
  payable_trigger text not null default 'deal_close' check (payable_trigger='deal_close'),
  is_current boolean not null default true,
  approval_evidence text not null check (btrim(approval_evidence) <> ''),
  approved_by_staff_id bigint not null,
  approved_at timestamptz not null default now(),
  unique (organization_id,id), unique (organization_id,deal_id,beneficiary_staff_id,version),
  foreign key (organization_id,deal_id) references crm.deals(organization_id,id),
  foreign key (organization_id,beneficiary_staff_id) references crm.staff_profiles(organization_id,id),
  foreign key (organization_id,approved_by_staff_id) references crm.staff_profiles(organization_id,id),
  check (beneficiary_staff_id <> approved_by_staff_id)
);
create unique index terms_one_current on crm.deal_commission_terms(organization_id,deal_id,beneficiary_staff_id) where is_current;
create index terms_beneficiary_idx on crm.deal_commission_terms(organization_id,beneficiary_staff_id);
create index terms_approver_idx on crm.deal_commission_terms(organization_id,approved_by_staff_id);
create table crm.commission_entries (
  id bigint generated always as identity primary key,
  organization_id bigint not null,
  deal_id bigint not null,
  beneficiary_staff_id bigint not null,
  entry_kind text not null check (entry_kind in ('accrual','adjustment','reversal')),
  amount_vnd numeric(18,0) not null check (amount_vnd <> 0 and amount_vnd > '-Infinity'::numeric and amount_vnd < 'Infinity'::numeric), -- SIGNED journal amount
  term_id bigint,
  price_snapshot_vnd numeric(18,0),
  rate_snapshot numeric(9,8),
  rounding_rule text not null default 'round_numeric_half_away_from_zero',
  payable_at timestamptz not null,
  event_key text not null check (btrim(event_key) <> ''),
  reason text not null,
  reference_entry_id bigint,
  posted_by_staff_id bigint not null,
  posted_at timestamptz not null default now(),
  unique (organization_id,id),
  unique (organization_id,deal_id,beneficiary_staff_id,event_key),
  unique (organization_id,id,deal_id,beneficiary_staff_id),
  foreign key (organization_id,deal_id) references crm.deals(organization_id,id),
  foreign key (organization_id,beneficiary_staff_id) references crm.staff_profiles(organization_id,id),
  foreign key (organization_id,term_id) references crm.deal_commission_terms(organization_id,id),
  foreign key (organization_id,reference_entry_id,deal_id,beneficiary_staff_id) references crm.commission_entries(organization_id,id,deal_id,beneficiary_staff_id),
  foreign key (organization_id,posted_by_staff_id) references crm.staff_profiles(organization_id,id),
  check ((entry_kind='accrual' and amount_vnd>0 and term_id is not null and price_snapshot_vnd>0 and rate_snapshot>0 and amount_vnd=round(price_snapshot_vnd*rate_snapshot,0) and reference_entry_id is null) or
         (entry_kind='adjustment' and reference_entry_id is not null and term_id is null and price_snapshot_vnd is null and rate_snapshot is null) or
         (entry_kind='reversal' and amount_vnd<0 and reference_entry_id is not null and term_id is null and price_snapshot_vnd is null and rate_snapshot is null))
);
create unique index entries_one_accrual on crm.commission_entries(organization_id,deal_id,beneficiary_staff_id) where entry_kind='accrual';
create index entries_beneficiary_idx on crm.commission_entries(organization_id,beneficiary_staff_id,payable_at);
create index entries_term_idx on crm.commission_entries(organization_id,term_id);
create index entries_reference_idx on crm.commission_entries(organization_id,reference_entry_id);
create index entries_poster_idx on crm.commission_entries(organization_id,posted_by_staff_id);
create table crm.commission_payments (
  id bigint generated always as identity primary key,
  organization_id bigint not null,
  beneficiary_staff_id bigint not null,
  payment_kind text not null check (payment_kind in ('payout','recovery')),
  amount_vnd numeric(18,0) not null check (amount_vnd>0 and amount_vnd<'Infinity'::numeric),
  payment_reference text not null check (btrim(payment_reference) <> ''),
  paid_at timestamptz not null,
  recorded_by_staff_id bigint not null,
  event_key text not null,
  created_at timestamptz not null default now(),
  unique (organization_id,id), unique (organization_id,id,beneficiary_staff_id,payment_kind),
  unique (organization_id,payment_reference), unique (organization_id,event_key),
  foreign key (organization_id,beneficiary_staff_id) references crm.staff_profiles(organization_id,id),
  foreign key (organization_id,recorded_by_staff_id) references crm.staff_profiles(organization_id,id)
);
create index payments_beneficiary_idx on crm.commission_payments(organization_id,beneficiary_staff_id,paid_at);
create index payments_recorder_idx on crm.commission_payments(organization_id,recorded_by_staff_id);
create table crm.commission_payment_allocations (
  organization_id bigint not null,
  payment_id bigint not null,
  deal_id bigint not null,
  beneficiary_staff_id bigint not null,
  payment_kind text not null check (payment_kind in ('payout','recovery')),
  amount_vnd numeric(18,0) not null check (amount_vnd>0 and amount_vnd<'Infinity'::numeric),
  primary key (organization_id,payment_id,deal_id),
  foreign key (organization_id,payment_id,beneficiary_staff_id,payment_kind) references crm.commission_payments(organization_id,id,beneficiary_staff_id,payment_kind),
  foreign key (organization_id,deal_id) references crm.deals(organization_id,id),
  foreign key (organization_id,beneficiary_staff_id) references crm.staff_profiles(organization_id,id)
);
create index allocations_balance_idx on crm.commission_payment_allocations(organization_id,deal_id,beneficiary_staff_id);
create table crm.property_files (
  id bigint generated always as identity primary key,
  organization_id bigint not null,
  property_id bigint not null,
  deal_id bigint,
  file_kind text not null check (file_kind in ('property_image','agreement','other')),
  bucket_id text not null check (bucket_id in ('sgn-property-images','sgn-agreements')),
  object_key text not null,
  original_path text,
  mime_type text,
  byte_size bigint check (byte_size>=0),
  sha256 text check (sha256 ~ '^[a-f0-9]{64}$'),
  availability text not null default 'missing' check (availability in ('missing','pending','available')),
  created_at timestamptz not null default now(),
  unique (organization_id,id), unique (bucket_id,object_key),
  foreign key (organization_id,property_id) references crm.properties(organization_id,id),
  foreign key (organization_id,deal_id) references crm.deals(organization_id,id),
  check (object_key like organization_id::text||'/'||property_id::text||'/%'),
  check ((file_kind='property_image' and bucket_id='sgn-property-images' and deal_id is null) or (file_kind='agreement' and bucket_id='sgn-agreements' and deal_id is not null) or (file_kind='other' and bucket_id='sgn-agreements' and deal_id is not null)),
  check (availability<>'available' or (sha256 is not null and byte_size is not null and mime_type is not null))
);
create index files_property_idx on crm.property_files(organization_id,property_id);
create index files_deal_idx on crm.property_files(organization_id,deal_id);
create table crm.property_change_history (
  id bigint generated always as identity primary key,
  organization_id bigint not null,
  property_id bigint not null,
  legacy_history_id text not null,
  actor_staff_id bigint,
  source_at timestamptz not null,
  legacy_approved boolean,
  payload jsonb not null,
  unique (organization_id,id), unique (organization_id,legacy_history_id),
  foreign key (organization_id,property_id) references crm.properties(organization_id,id),
  foreign key (organization_id,actor_staff_id) references crm.staff_profiles(organization_id,id)
);
create index history_property_idx on crm.property_change_history(organization_id,property_id,source_at);
create index history_actor_idx on crm.property_change_history(organization_id,actor_staff_id);
create table crm_private.contact_access_events (
  id bigint generated always as identity primary key,
  organization_id bigint not null,
  contact_id bigint,
  property_id bigint,
  actor_staff_id bigint,
  legacy_event_id text,
  occurred_at timestamptz not null default now(),
  outcome text not null check (outcome in ('allowed','denied','legacy')),
  unique (organization_id,legacy_event_id),
  foreign key (organization_id,contact_id) references crm.contacts(organization_id,id),
  foreign key (organization_id,property_id) references crm.properties(organization_id,id),
  foreign key (organization_id,actor_staff_id) references crm.staff_profiles(organization_id,id)
);
create index access_property_idx on crm_private.contact_access_events(organization_id,property_id,occurred_at);
create index access_contact_idx on crm_private.contact_access_events(organization_id,contact_id);
create index access_actor_idx on crm_private.contact_access_events(organization_id,actor_staff_id);
create table crm_private.audit_events (
  id bigint generated always as identity primary key,
  organization_id bigint,
  actor_user_id uuid,
  database_session_user text not null default session_user,
  entity_table text not null,
  action text not null,
  before_data jsonb, after_data jsonb,
  occurred_at timestamptz not null default now()
);
create index audit_org_time_idx on crm_private.audit_events(organization_id,occurred_at);
create table crm_private.operation_requests (
  organization_id bigint not null references crm.organizations,
  operation_kind text not null,
  event_key text not null check (btrim(event_key)<>''),
  payload jsonb not null,
  result jsonb not null,
  actor_user_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (organization_id,operation_kind,event_key)
);

-- Staging is intentionally not exposed through the Data API.
create table crm_import.batches (
  id bigint generated always as identity primary key,
  organization_id bigint not null references crm.organizations,
  filename text not null,
  file_sha256 text not null check (file_sha256 ~ '^[a-f0-9]{64}$'),
  source_exported_at timestamptz,
  transform_version text not null,
  expected_sheet_counts jsonb not null,
  status text not null default 'staged' check (status in ('staged','reviewing','approved','imported')),
  created_at timestamptz not null default now(),
  unique (organization_id,id), unique (organization_id,file_sha256)
);
create table crm_import.source_rows (
  id bigint generated always as identity primary key,
  organization_id bigint not null,
  batch_id bigint not null,
  sheet_name text not null,
  row_number integer not null check (row_number>1),
  legacy_id text,
  row_sha256 text not null check (row_sha256 ~ '^[a-f0-9]{64}$'),
  payload jsonb not null check (jsonb_typeof(payload)='object' and not (payload ?| array['Password','password','PASSWORD'])),
  disposition text not null default 'pending' check (disposition in ('pending','imported','quarantined','excluded')),
  disposition_reason text,
  unique (organization_id,id), unique (organization_id,batch_id,sheet_name,row_number),
  foreign key (organization_id,batch_id) references crm_import.batches(organization_id,id),
  check (disposition='pending' or nullif(btrim(disposition_reason),'') is not null)
);
create index source_legacy_idx on crm_import.source_rows(organization_id,sheet_name,legacy_id);
create index source_disposition_idx on crm_import.source_rows(organization_id,batch_id,disposition);
create table crm_import.issues (
  id bigint generated always as identity primary key,
  organization_id bigint not null,
  source_row_id bigint not null,
  code text not null,
  severity text not null check (severity in ('info','warning','blocking')),
  details jsonb not null default '{}',
  resolved boolean not null default false,
  resolution_note text,
  unique (organization_id,source_row_id,code),
  foreign key (organization_id,source_row_id) references crm_import.source_rows(organization_id,id),
  check (not resolved or nullif(btrim(resolution_note),'') is not null)
);
create table crm_import.property_aliases (
  organization_id bigint not null,
  source_system text not null,
  legacy_id text not null,
  property_id bigint not null,
  evidence_reference text not null check (btrim(evidence_reference)<>''),
  verified_by_staff_id bigint not null,
  verified_at timestamptz not null default now(),
  primary key (organization_id,source_system,legacy_id),
  foreign key (organization_id,property_id) references crm.properties(organization_id,id),
  foreign key (organization_id,verified_by_staff_id) references crm.staff_profiles(organization_id,id)
);
create index alias_property_idx on crm_import.property_aliases(organization_id,property_id);
create index alias_verifier_idx on crm_import.property_aliases(organization_id,verified_by_staff_id);
create table crm_import.property_promotions (
  organization_id bigint not null,
  source_row_id bigint not null,
  property_id bigint not null,
  listing_id bigint not null,
  decision jsonb not null,
  approved_by_staff_id bigint not null,
  imported_at timestamptz not null default now(),
  primary key (organization_id,source_row_id),
  foreign key (organization_id,source_row_id) references crm_import.source_rows(organization_id,id),
  foreign key (organization_id,listing_id,property_id) references crm.listings(organization_id,id,property_id),
  foreign key (organization_id,approved_by_staff_id) references crm.staff_profiles(organization_id,id)
);
create index promotions_property_idx on crm_import.property_promotions(organization_id,property_id);
create index promotions_listing_idx on crm_import.property_promotions(organization_id,listing_id);
create index promotions_approver_idx on crm_import.property_promotions(organization_id,approved_by_staff_id);

comment on table crm.properties is 'Physical asset identity. A source legacy ID is not guaranteed unique.';
comment on table crm.listings is 'Inventory asking prices; never an authoritative commission basis.';
comment on table crm.deals is 'Sale transaction; verified final price and closing evidence drive commission.';
comment on table crm.commission_entries is 'Append-only signed amounts. Accruals become payable on closing; adjustments never rewrite history.';
comment on table crm.commission_payments is 'Actual cash settlement recording. Recovery reduces net paid after an overpayment.';
comment on table crm.admin_unit_versions is 'Official dated province/commune versions; valid_to is exclusive. No unverified code seeds.';
comment on table crm_import.property_promotions is 'Reviewed source row to canonical property/listing mapping. No row-number inferred BDS joins.';

-- All definer functions live outside the exposed API schema. They use DB roles,
-- an active staff row and auth.uid(), never caller-supplied actor IDs or metadata.
create function crm_private.current_staff(p_org bigint) returns bigint
language sql stable security definer set search_path='' as $$
  select s.id from crm.staff_profiles s
  where auth.uid() is not null and s.organization_id=p_org and s.auth_user_id=auth.uid() and s.active
$$;
create function crm_private.has_role(p_org bigint,p_roles text[]) returns boolean
language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and exists (
    select 1 from crm_private.memberships m
    where m.organization_id=p_org and m.staff_id=crm_private.current_staff(p_org) and m.role=any(p_roles))
$$;
create function crm_private.is_member(p_org bigint) returns boolean
language sql stable security definer set search_path='' as $$
  select crm_private.has_role(p_org,array['sales','manager','operations','finance','admin'])
$$;
create function crm_private.manages_team(p_org bigint,p_team bigint) returns boolean
language sql stable security definer set search_path='' as $$
  select crm_private.has_role(p_org,array['admin','finance']) or
    (crm_private.has_role(p_org,array['manager']) and exists (
       select 1 from crm.staff_profiles s where s.id=crm_private.current_staff(p_org) and s.organization_id=p_org and s.team_id=p_team))
$$;
create function crm_private.can_read_property(p_org bigint,p_property bigint) returns boolean
language sql stable security definer set search_path='' as $$
  select crm_private.is_member(p_org) and (
    crm_private.has_role(p_org,array['admin','finance','operations']) or exists (
      select 1 from crm.listings l where l.organization_id=p_org and l.property_id=p_property and (
        l.approval_state='approved' or l.assigned_staff_id=crm_private.current_staff(p_org) or
        l.created_by_staff_id=crm_private.current_staff(p_org))))
$$;
create function crm_private.can_read_contact(p_org bigint,p_contact bigint) returns boolean
language sql stable security definer set search_path='' as $$
  select crm_private.is_member(p_org) and exists (
    select 1 from crm.contacts c where c.organization_id=p_org and c.id=p_contact and (
      crm_private.has_role(p_org,array['admin','finance','operations']) or
      c.assigned_staff_id=crm_private.current_staff(p_org) or crm_private.manages_team(p_org,c.team_id)))
$$;
create function crm_private.can_read_deal(p_org bigint,p_deal bigint) returns boolean
language sql stable security definer set search_path='' as $$
  select crm_private.is_member(p_org) and exists (
    select 1 from crm.deals d where d.organization_id=p_org and d.id=p_deal and (
      crm_private.manages_team(p_org,d.team_id) or crm_private.has_role(p_org,array['operations']) or
      d.owner_staff_id=crm_private.current_staff(p_org) or exists (
        select 1 from crm.deal_commission_terms t where t.organization_id=p_org and t.deal_id=p_deal and
          t.beneficiary_staff_id=crm_private.current_staff(p_org))))
$$;
create function crm_private.can_read_commission(p_org bigint,p_deal bigint,p_staff bigint) returns boolean
language sql stable security definer set search_path='' as $$
  select crm_private.is_member(p_org) and (p_staff=crm_private.current_staff(p_org) or exists (
    select 1 from crm.deals d where d.organization_id=p_org and d.id=p_deal and crm_private.manages_team(p_org,d.team_id)))
$$;
create function crm_private.can_read_payment(p_org bigint,p_staff bigint) returns boolean
language sql stable security definer set search_path='' as $$
  -- Payment headers can span several teams; managers use scoped allocation rows.
  select crm_private.is_member(p_org) and (p_staff=crm_private.current_staff(p_org) or crm_private.has_role(p_org,array['admin','finance']))
$$;

create function crm_private.audit_row() returns trigger
language plpgsql security definer set search_path='' as $$
declare b jsonb; a jsonb; o bigint;
begin
  if tg_op<>'INSERT' then b=to_jsonb(old); end if;
  if tg_op<>'DELETE' then a=to_jsonb(new); end if;
  o=coalesce((a->>'organization_id')::bigint,(b->>'organization_id')::bigint);
  insert into crm_private.audit_events(organization_id,actor_user_id,entity_table,action,before_data,after_data)
    values(o,auth.uid(),tg_table_schema||'.'||tg_table_name,tg_op,b,a);
  if tg_op='DELETE' then return old; end if; return new;
end $$;
create function crm_private.immutable_row() returns trigger
language plpgsql set search_path='' as $$
begin raise exception 'Posted records are append-only; use an adjustment, reversal or recovery' using errcode='55000'; end $$;
create function crm_private.financial_writer_only() returns trigger
language plpgsql set search_path='' as $$
begin
  if current_user <> pg_get_userbyid((select nspowner from pg_namespace where nspname='crm_private')) then
    raise exception 'Financial writes require an authorized CRM operation' using errcode='42501';
  end if;
  return new;
end $$;
create function crm_private.guard_term() returns trigger
language plpgsql set search_path='' as $$
begin
  if exists(select 1 from crm.deals where organization_id=old.organization_id and id=old.deal_id and stage in ('closed_won','cancelled')) or
     (to_jsonb(new)-'is_current')<>(to_jsonb(old)-'is_current') or new.is_current then
    raise exception 'Approved terms cannot be rewritten; approve a new version before closing';
  end if;
  return new;
end $$;
create function crm_private.guard_deal() returns trigger
language plpgsql set search_path='' as $$
begin
  if tg_op='UPDATE' and (old.stage in ('closed_won','cancelled') and old.closed_at is not null) and
     (to_jsonb(new)-'stage'-'updated_at')<>(to_jsonb(old)-'stage'-'updated_at') then
    raise exception 'Closed deal snapshots cannot be rewritten';
  end if;
  if ((tg_op='UPDATE' and old.closed_at is not null) or new.stage='closed_won') and
      current_user<>pg_get_userbyid((select nspowner from pg_namespace where nspname='crm_private')) then
    raise exception 'Closing and cancellation require an authorized CRM operation' using errcode='42501';
  end if;
  new.updated_at=now(); return new;
end $$;
create function crm_private.validate_address() returns trigger
language plpgsql set search_path='' as $$
declare p crm.admin_unit_versions; c crm.admin_unit_versions;
begin
  if new.province_version_id is not null then
    select * into p from crm.admin_unit_versions where id=new.province_version_id;
    if p.unit_level<>'province' then raise exception 'Province version must have province level'; end if;
  end if;
  if new.commune_version_id is not null then
    select * into c from crm.admin_unit_versions where id=new.commune_version_id;
    if c.unit_level<>'commune' or new.province_version_id is null or c.parent_version_id<>new.province_version_id then
      raise exception 'Commune must belong to the selected province version';
    end if;
  end if;
  if new.verification_status='verified' and (
    new.address_as_of<p.valid_from or new.address_as_of<c.valid_from or
    new.address_as_of>=coalesce(p.valid_to,'infinity'::date) or new.address_as_of>=coalesce(c.valid_to,'infinity'::date)) then
    raise exception 'Address date falls outside the selected unit versions';
  end if;
  new.search_text=lower(concat_ws(' ',new.original_address,new.original_district,new.original_ward,new.house_number,new.street,p.name_vi,c.name_vi));
  return new;
end $$;
create function crm_private.validate_unit() returns trigger
language plpgsql set search_path='' as $$
begin
  perform pg_advisory_xact_lock(hashtext(new.official_code));
  if new.parent_version_id is not null and not exists (
      select 1 from crm.admin_unit_versions p where p.id=new.parent_version_id and p.unit_level='province' and
        new.valid_from>=p.valid_from and coalesce(new.valid_to,'infinity'::date)<=coalesce(p.valid_to,'infinity'::date)) then
    raise exception 'Administrative parent level or effective dates are invalid';
  end if;
  if exists(select 1 from crm.admin_unit_versions x where x.id<>coalesce(new.id,0) and x.official_code=new.official_code and
      daterange(x.valid_from,x.valid_to,'[)') && daterange(new.valid_from,new.valid_to,'[)')) then
    raise exception 'Overlapping versions of an administrative code';
  end if;
  return new;
end $$;
create function crm_private.validate_file() returns trigger
language plpgsql set search_path='' as $$
begin
  if new.deal_id is not null and not exists(select 1 from crm.deals where organization_id=new.organization_id and id=new.deal_id and property_id=new.property_id) then
    raise exception 'File property and deal property do not match'; end if;
  return new;
end $$;
create function crm_private.validate_accrual() returns trigger
language plpgsql set search_path='' as $$
begin
  if new.entry_kind='accrual' and not exists(
    select 1 from crm.deal_commission_terms t join crm.deals d on d.organization_id=t.organization_id and d.id=t.deal_id
    where t.organization_id=new.organization_id and t.id=new.term_id and t.deal_id=new.deal_id and
      t.beneficiary_staff_id=new.beneficiary_staff_id and t.rate_fraction=new.rate_snapshot and t.is_current and
      d.stage='closed_won' and d.final_sale_price_vnd=new.price_snapshot_vnd and d.closed_at=new.payable_at) then
    raise exception 'Accrual must match approved terms and closed deal snapshots'; end if;
  return new;
end $$;
create function crm_private.check_payment_total() returns trigger
language plpgsql set search_path='' as $$
declare h crm.commission_payments; p bigint;
begin
  if tg_table_name='commission_payments' then p=new.id; else p=new.payment_id; end if;
  select * into h from crm.commission_payments where organization_id=new.organization_id and id=p;
  if h.amount_vnd<>(select coalesce(sum(amount_vnd),0) from crm.commission_payment_allocations where organization_id=h.organization_id and payment_id=h.id) then
    raise exception 'Payment amount must equal allocation total'; end if;
  return null;
end $$;
create trigger address_validation before insert or update on crm.property_addresses for each row execute function crm_private.validate_address();
create trigger unit_validation before insert or update on crm.admin_unit_versions for each row execute function crm_private.validate_unit();
create trigger file_validation before insert or update on crm.property_files for each row execute function crm_private.validate_file();
create trigger deal_guard before insert or update on crm.deals for each row execute function crm_private.guard_deal();
create trigger term_guard before update on crm.deal_commission_terms for each row execute function crm_private.guard_term();
create trigger term_no_delete before delete on crm.deal_commission_terms for each row execute function crm_private.immutable_row();
create trigger accrual_validation before insert on crm.commission_entries for each row execute function crm_private.validate_accrual();
create constraint trigger payment_total_header after insert on crm.commission_payments deferrable initially deferred for each row execute function crm_private.check_payment_total();
create constraint trigger payment_total_allocation after insert on crm.commission_payment_allocations deferrable initially deferred for each row execute function crm_private.check_payment_total();
do $$ declare t text; begin
  foreach t in array array['deal_commission_terms','commission_entries','commission_payments','commission_payment_allocations'] loop
    execute format('create trigger financial_writer before insert on crm.%I for each row execute function crm_private.financial_writer_only()',t);
    if t<>'deal_commission_terms' then
      execute format('create trigger immutable_posted before update or delete on crm.%I for each row execute function crm_private.immutable_row()',t);
    end if;
  end loop;
  foreach t in array array['staff_profiles','teams','properties','property_addresses','listings','contacts','property_contacts','deals','deal_commission_terms','commission_entries','commission_payments','commission_payment_allocations','property_files'] loop
    execute format('create trigger audit_change after insert or update or delete on crm.%I for each row execute function crm_private.audit_row()',t);
  end loop;
end $$;

create function crm_private.previous_result(p_org bigint,p_kind text,p_key text,p_payload jsonb) returns jsonb
language plpgsql set search_path='' as $$
declare r crm_private.operation_requests;
begin
  if nullif(btrim(p_key),'') is null then raise exception 'An idempotency event key is required'; end if;
  select * into r from crm_private.operation_requests where organization_id=p_org and operation_kind=p_kind and event_key=p_key;
  if found then
    if r.payload<>p_payload or r.actor_user_id<>auth.uid() then raise exception 'Event key already used for a different request'; end if;
    return r.result;
  end if;
  return null;
end $$;
create function crm_private.save_result(p_org bigint,p_kind text,p_key text,p_payload jsonb,p_result jsonb) returns jsonb
language plpgsql set search_path='' as $$
begin
  insert into crm_private.operation_requests(organization_id,operation_kind,event_key,payload,result,actor_user_id)
    values(p_org,p_kind,p_key,p_payload,p_result,auth.uid());
  return p_result;
end $$;
create function crm_private.approve_term(p_org bigint,p_deal bigint,p_beneficiary bigint,p_rate numeric,p_role text,p_evidence text,p_key text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d crm.deals; actor bigint; v integer; i bigint; b jsonb; r jsonb;
begin
  actor=crm_private.current_staff(p_org);
  select * into d from crm.deals where organization_id=p_org and id=p_deal for update;
  if not found or actor is null or not crm_private.manages_team(p_org,d.team_id) then raise exception 'Not authorized to approve terms' using errcode='42501'; end if;
  if actor=p_beneficiary then raise exception 'A beneficiary cannot approve their own commission'; end if;
  b=jsonb_build_object('deal',p_deal,'beneficiary',p_beneficiary,'rate',p_rate,'role',p_role,'evidence',p_evidence);
  r=crm_private.previous_result(p_org,'approve_term',p_key,b); if r is not null then return r; end if;
  if d.stage in ('closed_won','cancelled','closed_lost') then raise exception 'Terms require an open deal'; end if;
  if p_rate is null or p_rate<=0 or p_rate>1 or p_rate<>round(p_rate,8) then raise exception 'Rate must be a fraction >0 and <=1 with at most 8 decimal places'; end if;
  if not exists(select 1 from crm.staff_profiles where organization_id=p_org and id=p_beneficiary) then raise exception 'Beneficiary not in this organization'; end if;
  select coalesce(max(version),0)+1 into v from crm.deal_commission_terms where organization_id=p_org and deal_id=p_deal and beneficiary_staff_id=p_beneficiary;
  update crm.deal_commission_terms set is_current=false where organization_id=p_org and deal_id=p_deal and beneficiary_staff_id=p_beneficiary and is_current;
  insert into crm.deal_commission_terms(organization_id,deal_id,beneficiary_staff_id,participant_role,version,rate_fraction,approval_evidence,approved_by_staff_id)
    values(p_org,p_deal,p_beneficiary,p_role,v,p_rate,p_evidence,actor) returning id into i;
  return crm_private.save_result(p_org,'approve_term',p_key,b,jsonb_build_object('term_id',i,'version',v));
end $$;
create function crm_private.close_deal(p_org bigint,p_deal bigint,p_closed_at timestamptz,p_key text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d crm.deals; actor bigint; b jsonb; r jsonb; total numeric; n integer;
begin
  actor=crm_private.current_staff(p_org);
  select * into d from crm.deals where organization_id=p_org and id=p_deal for update;
  if not found or actor is null or not crm_private.manages_team(p_org,d.team_id) then raise exception 'Not authorized to close deal' using errcode='42501'; end if;
  b=jsonb_build_object('deal',p_deal,'closed_at',p_closed_at);
  r=crm_private.previous_result(p_org,'close_deal',p_key,b); if r is not null then return r; end if;
  if d.stage in ('closed_won','closed_lost','cancelled') then raise exception 'Deal is already terminal; use correction operations'; end if;
  -- Serialize sale closure on the listing as well as this deal.
  perform 1 from crm.listings where organization_id=p_org and id=d.listing_id and purpose='sale' for update;
  if not found then raise exception 'Sale commission is unavailable for rental listings'; end if;
  if exists(select 1 from crm.deals where organization_id=p_org and listing_id=d.listing_id and stage='closed_won') then raise exception 'Listing already has a closed sale'; end if;
  if p_closed_at is null or p_closed_at>clock_timestamp()+interval '5 minutes' then raise exception 'A valid closing timestamp is required'; end if;
  if d.final_sale_price_vnd is null or not d.final_price_verified then raise exception 'Verified final sale price required'; end if;
  if not exists(select 1 from crm.properties where organization_id=p_org and id=d.property_id and identity_verified) or
     not exists(select 1 from crm.property_addresses where organization_id=p_org and property_id=d.property_id and is_current and verification_status='verified') then
    raise exception 'Verified property identity and current address required'; end if;
  select count(*),sum(rate_fraction) into n,total from crm.deal_commission_terms where organization_id=p_org and deal_id=p_deal and is_current;
  if n=0 or total>1 then raise exception 'Approved beneficiary terms required; aggregate rate cannot exceed 100 percent'; end if;
  if exists(select 1 from crm.deal_commission_terms where organization_id=p_org and deal_id=p_deal and is_current and round(d.final_sale_price_vnd*rate_fraction,0)=0) then
    raise exception 'A beneficiary commission rounds to zero; review the terms'; end if;
  update crm.deals set stage='closed_won',closed_at=p_closed_at,closed_by_staff_id=actor where organization_id=p_org and id=p_deal;
  insert into crm.commission_entries(organization_id,deal_id,beneficiary_staff_id,entry_kind,amount_vnd,term_id,price_snapshot_vnd,rate_snapshot,payable_at,event_key,reason,posted_by_staff_id)
    select p_org,p_deal,beneficiary_staff_id,'accrual',round(d.final_sale_price_vnd*rate_fraction,0),id,d.final_sale_price_vnd,rate_fraction,p_closed_at,p_key,'Deal closed; commission payable immediately',actor
    from crm.deal_commission_terms where organization_id=p_org and deal_id=p_deal and is_current;
  update crm.listings set status='sold',updated_at=now() where organization_id=p_org and id=d.listing_id;
  select sum(amount_vnd) into total from crm.commission_entries where organization_id=p_org and deal_id=p_deal;
  return crm_private.save_result(p_org,'close_deal',p_key,b,jsonb_build_object('deal_id',p_deal,'beneficiaries',n,'payable_vnd',total));
end $$;
create function crm_private.adjust_commission(p_org bigint,p_entry bigint,p_amount numeric,p_reason text,p_key text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare e crm.commission_entries; d crm.deals; actor bigint; i bigint; bal numeric; b jsonb; r jsonb;
begin
  actor=crm_private.current_staff(p_org);
  select * into e from crm.commission_entries where organization_id=p_org and id=p_entry and entry_kind='accrual';
  if not found then raise exception 'Original accrual not found'; end if;
  select * into d from crm.deals where organization_id=p_org and id=e.deal_id for update;
  if actor is null or not crm_private.has_role(p_org,array['finance','admin']) then raise exception 'Finance authorization required' using errcode='42501'; end if;
  if actor=e.beneficiary_staff_id then raise exception 'Cannot approve own commission adjustment'; end if;
  b=jsonb_build_object('entry',p_entry,'amount',p_amount,'reason',p_reason);
  r=crm_private.previous_result(p_org,'adjust_commission',p_key,b); if r is not null then return r; end if;
  if d.stage<>'closed_won' then raise exception 'Adjustments require a closed, noncancelled deal'; end if;
  if p_amount is null or p_amount=0 or p_amount<>trunc(p_amount) or nullif(btrim(p_reason),'') is null then raise exception 'Nonzero whole-VND adjustment and evidence reason required'; end if;
  select coalesce(sum(amount_vnd),0) into bal from crm.commission_entries where organization_id=p_org and deal_id=e.deal_id and beneficiary_staff_id=e.beneficiary_staff_id;
  if bal+p_amount<0 then raise exception 'Entitlement cannot become negative'; end if;
  insert into crm.commission_entries(organization_id,deal_id,beneficiary_staff_id,entry_kind,amount_vnd,payable_at,event_key,reason,reference_entry_id,posted_by_staff_id)
    values(p_org,e.deal_id,e.beneficiary_staff_id,'adjustment',p_amount,e.payable_at,p_key,p_reason,p_entry,actor) returning id into i;
  return crm_private.save_result(p_org,'adjust_commission',p_key,b,jsonb_build_object('entry_id',i,'net_entitlement_vnd',bal+p_amount));
end $$;
create function crm_private.cancel_closed_deal(p_org bigint,p_deal bigint,p_reason text,p_key text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d crm.deals; actor bigint; b jsonb; r jsonb;
begin
  actor=crm_private.current_staff(p_org);
  select * into d from crm.deals where organization_id=p_org and id=p_deal for update;
  if not found or actor is null or not crm_private.has_role(p_org,array['finance','admin']) then raise exception 'Finance authorization required' using errcode='42501'; end if;
  b=jsonb_build_object('deal',p_deal,'reason',p_reason);
  r=crm_private.previous_result(p_org,'cancel_deal',p_key,b); if r is not null then return r; end if;
  if d.stage<>'closed_won' or nullif(btrim(p_reason),'') is null then raise exception 'Closed deal and cancellation evidence required'; end if;
  if exists(select 1 from crm.commission_entries where organization_id=p_org and deal_id=p_deal and beneficiary_staff_id=actor) then raise exception 'Cannot authorize cancellation of own earned commission'; end if;
  insert into crm.commission_entries(organization_id,deal_id,beneficiary_staff_id,entry_kind,amount_vnd,payable_at,event_key,reason,reference_entry_id,posted_by_staff_id)
    select p_org,p_deal,beneficiary_staff_id,'reversal',-sum(amount_vnd),min(payable_at),p_key,p_reason,min(id) filter(where entry_kind='accrual'),actor
    from crm.commission_entries where organization_id=p_org and deal_id=p_deal group by beneficiary_staff_id having sum(amount_vnd)>0;
  update crm.deals set stage='cancelled',updated_at=now() where organization_id=p_org and id=p_deal;
  -- Inventory is withdrawn for review. Cancellation does not silently relist.
  update crm.listings set status='withdrawn',updated_at=now() where organization_id=p_org and id=d.listing_id;
  return crm_private.save_result(p_org,'cancel_deal',p_key,b,jsonb_build_object('deal_id',p_deal,'status','cancelled'));
end $$;
create function crm_private.record_payment(p_org bigint,p_staff bigint,p_kind text,p_reference text,p_paid_at timestamptz,p_allocations jsonb,p_key text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint; i bigint; a record; entitlement numeric; paid numeric; total numeric; n integer; b jsonb; r jsonb;
begin
  actor=crm_private.current_staff(p_org);
  if actor is null or not crm_private.has_role(p_org,array['finance','admin']) then raise exception 'Finance authorization required' using errcode='42501'; end if;
  if actor=p_staff then raise exception 'Cannot record own commission settlement'; end if;
  if p_kind not in ('payout','recovery') or p_kind is null or p_paid_at is null or p_paid_at>clock_timestamp()+interval '5 minutes' or nullif(btrim(p_reference),'') is null then raise exception 'Settlement kind, reference and valid timestamp required'; end if;
  if jsonb_typeof(p_allocations)<>'array' or p_allocations is null or jsonb_array_length(p_allocations)=0 then raise exception 'Allocations must be a nonempty array'; end if;
  select count(*),sum(amount_vnd) into n,total from jsonb_to_recordset(p_allocations) as x(deal_id bigint,amount_vnd numeric);
  if n<>(select count(distinct deal_id) from jsonb_to_recordset(p_allocations) as x(deal_id bigint,amount_vnd numeric)) or
      exists(select 1 from jsonb_to_recordset(p_allocations) as x(deal_id bigint,amount_vnd numeric) where deal_id is null or amount_vnd is null or amount_vnd<=0 or amount_vnd<>trunc(amount_vnd)) then raise exception 'Distinct deals and positive whole-VND allocations required'; end if;
  -- A consistent ordered lock sequence serializes payouts, recoveries and corrections.
  perform d.id from crm.deals d where d.organization_id=p_org and d.id in (select deal_id from jsonb_to_recordset(p_allocations) as x(deal_id bigint,amount_vnd numeric)) order by d.id for update;
  if (select count(*) from crm.deals d where d.organization_id=p_org and d.id in (select deal_id from jsonb_to_recordset(p_allocations) as x(deal_id bigint,amount_vnd numeric)))<>n then raise exception 'Unknown or foreign-organization deal'; end if;
  b=jsonb_build_object('staff',p_staff,'kind',p_kind,'reference',p_reference,'paid_at',p_paid_at,'allocations',p_allocations);
  r=crm_private.previous_result(p_org,'record_payment',p_key,b); if r is not null then return r; end if;
  for a in select * from jsonb_to_recordset(p_allocations) as x(deal_id bigint,amount_vnd numeric) order by deal_id loop
    select coalesce(sum(amount_vnd),0) into entitlement from crm.commission_entries where organization_id=p_org and deal_id=a.deal_id and beneficiary_staff_id=p_staff;
    if p_kind='payout' and p_paid_at<(select min(payable_at) from crm.commission_entries where organization_id=p_org and deal_id=a.deal_id and beneficiary_staff_id=p_staff) then
      raise exception 'A payout cannot precede the closing eligibility timestamp'; end if;
    select coalesce(sum(case when x.payment_kind='payout' then x.amount_vnd else -x.amount_vnd end),0) into paid
      from crm.commission_payment_allocations x
      where x.organization_id=p_org and x.deal_id=a.deal_id and x.beneficiary_staff_id=p_staff;
    if (p_kind='payout' and a.amount_vnd>greatest(entitlement-paid,0)) or (p_kind='recovery' and a.amount_vnd>greatest(paid-entitlement,0)) then
      raise exception 'Allocation exceeds payable balance or recoverable overpayment'; end if;
  end loop;
  insert into crm.commission_payments(organization_id,beneficiary_staff_id,payment_kind,amount_vnd,payment_reference,paid_at,recorded_by_staff_id,event_key)
    values(p_org,p_staff,p_kind,total,p_reference,p_paid_at,actor,p_key) returning id into i;
  insert into crm.commission_payment_allocations(organization_id,payment_id,deal_id,beneficiary_staff_id,payment_kind,amount_vnd)
    select p_org,i,deal_id,p_staff,p_kind,amount_vnd from jsonb_to_recordset(p_allocations) as x(deal_id bigint,amount_vnd numeric);
  return crm_private.save_result(p_org,'record_payment',p_key,b,jsonb_build_object('payment_id',i,'amount_vnd',total));
end $$;
create function crm_private.reveal_phones(p_org bigint,p_contact bigint) returns table(phone_id bigint,number_e164 text,number_raw text,verification_status text)
language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not crm_private.can_read_contact(p_org,p_contact) then raise exception 'Contact access denied' using errcode='42501'; end if;
  insert into crm_private.contact_access_events(organization_id,contact_id,actor_staff_id,outcome)
    values(p_org,p_contact,crm_private.current_staff(p_org),'allowed');
  return query select p.id,p.number_e164,p.number_raw,p.verification_status from crm_private.contact_phones p where p.organization_id=p_org and p.contact_id=p_contact order by p.is_primary desc,p.id;
end $$;

-- API-safe INVOKER wrappers. Only these financial mutations are granted.
create function crm.approve_commission_term(p_org bigint,p_deal bigint,p_beneficiary bigint,p_rate numeric,p_role text,p_evidence text,p_key text) returns jsonb language sql security invoker set search_path='' as $$ select crm_private.approve_term(p_org,p_deal,p_beneficiary,p_rate,p_role,p_evidence,p_key) $$;
create function crm.close_deal(p_org bigint,p_deal bigint,p_closed_at timestamptz,p_key text) returns jsonb language sql security invoker set search_path='' as $$ select crm_private.close_deal(p_org,p_deal,p_closed_at,p_key) $$;
create function crm.adjust_commission(p_org bigint,p_entry bigint,p_amount numeric,p_reason text,p_key text) returns jsonb language sql security invoker set search_path='' as $$ select crm_private.adjust_commission(p_org,p_entry,p_amount,p_reason,p_key) $$;
create function crm.cancel_closed_deal(p_org bigint,p_deal bigint,p_reason text,p_key text) returns jsonb language sql security invoker set search_path='' as $$ select crm_private.cancel_closed_deal(p_org,p_deal,p_reason,p_key) $$;
create function crm.record_commission_payment(p_org bigint,p_staff bigint,p_kind text,p_reference text,p_paid_at timestamptz,p_allocations jsonb,p_key text) returns jsonb language sql security invoker set search_path='' as $$ select crm_private.record_payment(p_org,p_staff,p_kind,p_reference,p_paid_at,p_allocations,p_key) $$;
create function crm.reveal_contact_phones(p_org bigint,p_contact bigint) returns table(phone_id bigint,number_e164 text,number_raw text,verification_status text) language sql security invoker set search_path='' as $$ select * from crm_private.reveal_phones(p_org,p_contact) $$;

create view crm.commission_balances with (security_invoker=true) as
with e as (
  select organization_id,deal_id,beneficiary_staff_id,sum(amount_vnd) as entitlement_vnd,min(payable_at) as payable_at
  from crm.commission_entries group by organization_id,deal_id,beneficiary_staff_id
), p as (
  select x.organization_id,x.deal_id,x.beneficiary_staff_id,
    sum(case when x.payment_kind='payout' then x.amount_vnd else -x.amount_vnd end) as net_paid_vnd
  from crm.commission_payment_allocations x
  group by x.organization_id,x.deal_id,x.beneficiary_staff_id
)
select e.*,coalesce(p.net_paid_vnd,0) as net_paid_vnd,
  greatest(e.entitlement_vnd-coalesce(p.net_paid_vnd,0),0) as outstanding_vnd,
  greatest(coalesce(p.net_paid_vnd,0)-e.entitlement_vnd,0) as recoverable_vnd
from e left join p using(organization_id,deal_id,beneficiary_staff_id);

-- Every data table has RLS; browser access is read-only except audited RPCs.
do $$ declare r record; begin
  for r in select schemaname,tablename from pg_tables where schemaname in ('crm','crm_private','crm_import') loop
    execute format('alter table %I.%I enable row level security',r.schemaname,r.tablename);
  end loop;
end $$;
revoke all on all tables in schema crm,crm_private,crm_import from anon,authenticated;
revoke all on all sequences in schema crm,crm_private,crm_import from anon,authenticated;
revoke execute on all functions in schema crm,crm_private from public,anon,authenticated;
grant select on all tables in schema crm to authenticated;
grant all on all tables in schema crm,crm_private,crm_import to service_role;
grant usage,select on all sequences in schema crm,crm_private,crm_import to service_role;
grant execute on all functions in schema crm to authenticated,service_role;
grant execute on function crm_private.current_staff(bigint),crm_private.has_role(bigint,text[]),crm_private.is_member(bigint),
  crm_private.manages_team(bigint,bigint),crm_private.can_read_property(bigint,bigint),crm_private.can_read_contact(bigint,bigint),
  crm_private.can_read_deal(bigint,bigint),crm_private.can_read_commission(bigint,bigint,bigint),crm_private.can_read_payment(bigint,bigint),
  crm_private.approve_term(bigint,bigint,bigint,numeric,text,text,text),crm_private.close_deal(bigint,bigint,timestamptz,text),
  crm_private.adjust_commission(bigint,bigint,numeric,text,text),crm_private.cancel_closed_deal(bigint,bigint,text,text),
  crm_private.record_payment(bigint,bigint,text,text,timestamptz,jsonb,text),crm_private.reveal_phones(bigint,bigint)
  to authenticated,service_role;
create policy org_read on crm.organizations for select to authenticated using (crm_private.is_member(id));
create policy team_read on crm.teams for select to authenticated using (crm_private.is_member(organization_id));
create policy staff_read on crm.staff_profiles for select to authenticated using (crm_private.is_member(organization_id));
do $$ declare t text; begin
  foreach t in array array['admin_unit_versions','admin_unit_crosswalks','property_types','road_access_types'] loop
    execute format('create policy reference_read on crm.%I for select to authenticated using (auth.uid() is not null)',t);
  end loop;
end $$;
create policy property_read on crm.properties for select to authenticated using (crm_private.can_read_property(organization_id,id));
create policy address_read on crm.property_addresses for select to authenticated using (crm_private.can_read_property(organization_id,property_id));
create policy listing_read on crm.listings for select to authenticated using (
  crm_private.is_member(organization_id) and (approval_state='approved' or assigned_staff_id=crm_private.current_staff(organization_id) or
  created_by_staff_id=crm_private.current_staff(organization_id) or crm_private.has_role(organization_id,array['operations','finance','admin'])));
create policy contact_read on crm.contacts for select to authenticated using (crm_private.can_read_contact(organization_id,id));
create policy relationship_read on crm.property_contacts for select to authenticated using (crm_private.can_read_property(organization_id,property_id) and crm_private.can_read_contact(organization_id,contact_id));
create policy deal_read on crm.deals for select to authenticated using (crm_private.can_read_deal(organization_id,id));
create policy activity_read on crm.activities for select to authenticated using (
  crm_private.is_member(organization_id) and (owner_staff_id=crm_private.current_staff(organization_id) or
  (deal_id is not null and crm_private.can_read_deal(organization_id,deal_id)) or
  crm_private.has_role(organization_id,array['operations','admin','finance'])));
create policy term_read on crm.deal_commission_terms for select to authenticated using (crm_private.can_read_commission(organization_id,deal_id,beneficiary_staff_id));
create policy entry_read on crm.commission_entries for select to authenticated using (crm_private.can_read_commission(organization_id,deal_id,beneficiary_staff_id));
create policy payment_read on crm.commission_payments for select to authenticated using (crm_private.can_read_payment(organization_id,beneficiary_staff_id));
create policy allocation_read on crm.commission_payment_allocations for select to authenticated using (crm_private.can_read_commission(organization_id,deal_id,beneficiary_staff_id));
create policy files_read on crm.property_files for select to authenticated using (
  availability='available' and ((file_kind='property_image' and crm_private.can_read_property(organization_id,property_id)) or
  (file_kind<>'property_image' and crm_private.can_read_deal(organization_id,deal_id))));
create policy history_read on crm.property_change_history for select to authenticated using (
  crm_private.has_role(organization_id,array['operations','admin','finance'])); -- payload may contain old phones

create function crm_private.can_read_file(p_bucket text,p_key text) returns boolean
language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and exists (
    select 1 from crm.property_files f where f.bucket_id=p_bucket and f.object_key=p_key and f.availability='available' and (
      (f.file_kind='property_image' and crm_private.can_read_property(f.organization_id,f.property_id)) or
      (f.file_kind<>'property_image' and crm_private.can_read_deal(f.organization_id,f.deal_id))))
$$;
revoke all on function crm_private.can_read_file(text,text) from public,anon;
grant execute on function crm_private.can_read_file(text,text) to authenticated,service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
  ('sgn-property-images','sgn-property-images',false,10485760,array['image/jpeg','image/png','image/webp']),
  ('sgn-agreements','sgn-agreements',false,20971520,array['application/pdf','image/jpeg','image/png']);
create policy sgn_objects_read on storage.objects for select to authenticated using (
  bucket_id in ('sgn-property-images','sgn-agreements') and crm_private.can_read_file(bucket_id,name));
-- Storage INSERT/UPDATE/DELETE remain backend-only. Existing project-wide
-- permissive policies must be audited before using these buckets in production.

-- Reviewed source promotion. Executable only by a trusted migration/backend role.
create function crm_import.promote_property(p_org bigint,p_source bigint,p_decision jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare s crm_import.source_rows; prior crm_import.property_promotions; property_key bigint; listing_key bigint;
  approver bigint; sale_price numeric; rent_price numeric; purpose text; source_status text; canonical_status text;
begin
  select * into s from crm_import.source_rows where organization_id=p_org and id=p_source for update;
  if not found or s.sheet_name<>'Thông tin dự án' then raise exception 'Property source row not found'; end if;
  select * into prior from crm_import.property_promotions where organization_id=p_org and source_row_id=p_source;
  if found then
    if prior.decision<>p_decision then raise exception 'Source already promoted with different decisions'; end if;
    return jsonb_build_object('property_id',prior.property_id,'listing_id',prior.listing_id);
  end if;
  if nullif(btrim(s.payload->>'PropertyID'),'') is null then raise exception 'Incomplete property source'; end if;
  approver=(p_decision->>'approved_by_staff_id')::bigint;
  if not coalesce((p_decision->>'identity_verified')::boolean,false) or nullif(btrim(p_decision->>'identity_evidence'),'') is null or
    not exists(select 1 from crm.staff_profiles where organization_id=p_org and id=approver and active) then
    raise exception 'Reviewed identity evidence and active approver required'; end if;
  if exists(select 1 from crm_import.issues where organization_id=p_org and source_row_id=p_source and severity='blocking' and not resolved) then
    raise exception 'Resolve blocking source issues before promotion'; end if;
  sale_price=(p_decision->>'asking_sale_price_vnd')::numeric;
  rent_price=(p_decision->>'asking_rent_vnd')::numeric;
  if (sale_price is not null and (sale_price<=0 or sale_price<>trunc(sale_price))) or (rent_price is not null and (rent_price<=0 or rent_price<>trunc(rent_price))) then
    raise exception 'Adopted prices must be positive whole VND'; end if;
  if (sale_price is not null or rent_price is not null) and (not coalesce((p_decision->>'price_verified')::boolean,false) or nullif(btrim(p_decision->>'price_evidence'),'') is null) then
    raise exception 'Explicit currency/unit review evidence required for adopted prices'; end if;
  purpose=p_decision->>'purpose';
  source_status=s.payload->>'Tạo mới';
  canonical_status=case source_status when 'Tạo mới' then 'new' when 'Đang bán' then 'available' when 'Đang Thương lượng' then 'negotiating' when 'Đang giao dịch' then 'under_offer' when 'Đã bán' then 'sold_legacy' when 'Ngưng Bán' then 'withdrawn' end;
  if canonical_status is null then raise exception 'Unrecognized source status'; end if;
  property_key=(p_decision->>'existing_property_id')::bigint;
  if property_key is null then
    insert into crm.properties(organization_id,display_code,legacy_property_id,property_type_code,road_access_code,width_m,length_m,land_area_m2,area_raw,direction,identity_verified)
      values(p_org,p_decision->>'display_code',s.payload->>'PropertyID',p_decision->>'property_type_code',p_decision->>'road_access_code',
        (p_decision->>'width_m')::numeric,(p_decision->>'length_m')::numeric,(p_decision->>'land_area_m2')::numeric,
        s.payload->>'Tổng diện tích',p_decision->>'direction',true) returning id into property_key;
    insert into crm.property_addresses(organization_id,property_id,original_address,original_province,original_district,original_ward,house_number,street)
      values(p_org,property_key,s.payload->>'Địa chỉ dự án',s.payload->>'Thành phố',s.payload->>'Quận',s.payload->>'Phường',s.payload->>'Địa Chỉ',s.payload->>'Tên Đường');
  elsif not exists(select 1 from crm.properties where organization_id=p_org and id=property_key and identity_verified) then
    raise exception 'Existing canonical property must belong to this organization and be verified';
  end if;
  insert into crm.listings(organization_id,property_id,purpose,status,legacy_status,asking_sale_price_vnd,asking_rent_vnd,rent_period,price_verified,
    legacy_approved,created_by_staff_id,source_updated_by_staff_id,source_created_at,source_updated_at,notes,source_note)
    values(p_org,property_key,purpose,canonical_status,source_status,sale_price,rent_price,p_decision->>'rent_period',coalesce((p_decision->>'price_verified')::boolean,false),
      (s.payload->>'Approved')::boolean,(p_decision->>'created_by_staff_id')::bigint,(p_decision->>'updated_by_staff_id')::bigint,
      (s.payload->>'Ngày Tạo')::timestamptz,(s.payload->>'Ngày Chỉnh Sửa gần nhất')::timestamptz,s.payload->>'Ghi Chú Thêm',s.payload->>'Note') returning id into listing_key;
  insert into crm_import.property_promotions(organization_id,source_row_id,property_id,listing_id,decision,approved_by_staff_id)
    values(p_org,p_source,property_key,listing_key,p_decision,approver);
  update crm_import.source_rows set disposition='imported',disposition_reason='Reviewed property promotion' where organization_id=p_org and id=p_source;
  return jsonb_build_object('property_id',property_key,'listing_id',listing_key);
end $$;
revoke execute on function crm_import.promote_property(bigint,bigint,jsonb) from public,anon,authenticated;
grant execute on function crm_import.promote_property(bigint,bigint,jsonb) to service_role;
create view crm_import.reconciliation as
select organization_id,batch_id,sheet_name,count(*) as source_rows,
  count(*) filter(where disposition='imported') as imported,
  count(*) filter(where disposition='quarantined') as quarantined,
  count(*) filter(where disposition='excluded') as excluded,
  count(*) filter(where disposition='pending') as pending
from crm_import.source_rows group by organization_id,batch_id,sheet_name;
revoke all on crm_import.reconciliation from public,anon,authenticated;
grant select on crm_import.reconciliation to service_role;

-- No initial company, user accounts, passwords, rates or official address codes.
-- Bootstrap the company and role holder with sql/bootstrap.sql after migration.
commit;
