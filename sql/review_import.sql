-- Read-only review queries; trusted database connection only.
select * from crm_import.reconciliation order by organization_id,batch_id,sheet_name;
select r.organization_id,r.batch_id,r.sheet_name,r.row_number,r.legacy_id,i.code,i.severity,i.resolved
from crm_import.issues i join crm_import.source_rows r on r.organization_id=i.organization_id and r.id=i.source_row_id
order by i.resolved,i.severity,r.sheet_name,r.row_number;
-- Use explicit source_system='appsheet' aliases after recovering source metadata.
-- Never infer BDS-N from row N. Each alias maps to exactly one verified property.
-- Promotion is reviewed and backend-only; no automatic mass conversion here.
-- Example (replace every parameter with reviewed values):
-- select crm_import.promote_property(ORG_ID,SOURCE_ROW_ID,
-- '{"approved_by_staff_id":STAFF_ID,"identity_verified":true,
--   "identity_evidence":"Recovered original application ID + reviewed address",
--   "display_code":"SGN-000001","purpose":"sale",
--   "asking_sale_price_vnd":23000000000,"price_verified":true,
--   "price_evidence":"Source price 23 confirmed in billion VND",
--   "property_type_code":"house","road_access_code":"car_alley",
--   "land_area_m2":64,"width_m":4,"length_m":16}'::jsonb);
-- For a later source row referring to an existing property, provide
-- existing_property_id after identity review. It creates a listing, not a
-- second physical property, and does not overwrite the current address.
