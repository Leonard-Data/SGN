# SGN Real Estate CRM schema and SQL migration

Version 1.0.0, 8 October 2026. This package builds a fresh Supabase database schema for a small property and sales commission CRM. It is based on the supplied Databases.xlsx workbook and the agreed rules: **commission is a percentage of verified final property sale price and becomes payable at deal closing**.

The accepted baseline is deployed to an explicitly approved development project; the evidence and remaining bootstrap prerequisite are recorded below. No production user data, passwords, Auth accounts, commission rates, or invented administrative codes are included in the package. No production deployment or cutover has been performed.

## Files

| File | Purpose |
|---|---|
| supabase/migrations/20261008083455_sgn_crm_v1.sql | Authoritative schema, functions, policies, reference classifications and private Storage buckets |
| docs/SCHEMA.md | Detailed table and field dictionary, relationships, constraints, indexes and source mapping |
| docs/schema.json | Machine-readable catalog extracted from the tested migration |
| scripts/stage_workbook.py | Redacted and repeatable XLSX-to-SQL staging generator |
| sql/bootstrap.sql | Company/team/admin setup using an existing Supabase Auth user |
| sql/review_import.sql | Review and source promotion examples |
| sql/operations_examples.sql | Commission and phone-reveal RPC usage |
| sql/verify_deployment.sql | Post-deployment RLS, permissions and journal checks |
| tests/verify.mjs | Synthetic PostgreSQL-engine tests; no customer data |
| tests/verification.json | Executed test results and limitations |
| docs/workbook_staging_summary.json | Aggregate workbook extraction counts and detected issue categories |

## Apply to a development project

The SQL creates new crm, crm_private and crm_import schemas. It is transactional and deliberately fails if these already exist, instead of overwriting an existing database. Use a fresh development project first. The schema depends on Supabase-managed auth.users, auth.uid(), storage.buckets and storage.objects. PostgreSQL 15 or newer is required for invoker views.

1. Install the pinned development dependencies with `npm ci`. Use Node 22 or newer.
2. Review supabase/config.toml. The supplied local configuration exposes only crm, uses PostgreSQL 17, and disables data seeds. Match the major version to your selected remote project.
3. For local Supabase verification, run `npx supabase start`, then `npx supabase db reset` **without --linked**. These local-stack commands require Docker.
4. For a selected development cloud project, authenticate and link using the installed CLI's help, then preview with `npx supabase db push --dry-run`. Apply with `npx supabase db push` after reviewing the proposed changes.
5. In the Supabase Data API settings, add **crm** to exposed schemas. **Do not expose crm_private or crm_import**. Use `supabase.schema('crm')` from the client. Explicit grants and RLS are already in the migration.
6. Invite the initial administrator through Supabase Auth. Run sql/bootstrap.sql through a trusted psql connection with the existing Auth UUID and the company/admin names. No password is migrated.
7. Add reviewed staff profiles and private membership roles. Keep former staff identities inactive. Do not bind emails to login users without verifying the account.
8. Run sql/verify_deployment.sql and the Supabase security/performance advisers. Audit any pre-existing broad Storage policies before enabling these buckets.

The canonical migration can also be run in Supabase SQL Editor for a fresh project. If doing so, reconcile migration history before switching to CLI deployment later; do not run the same create-schema migration twice. The default package workflow is versioned CLI migrations.

## Approved development deployment evidence

Recorded at **2026-10-09T07:02:48Z** for [issue #2](https://github.com/Leonard-Data/SGN/issues/2), on explicitly approved development project `hiapaaudzwqykdalfyqn` in `ap-northeast-2`. Management access used a project-scoped token; no credentials or private identity records are included here.

| Acceptance item | Observed evidence |
|---|---|
| Target and freshness | Live `server_version` is **17.11**; project release is `17.11.0.003`. Before application, migration history, SGN schemas, Storage buckets and Storage object policies were empty. No linked reset or existing-schema overwrite was performed. |
| Reviewed application | CLI **2.120.0** dry run proposed only `20261008083455_sgn_crm_v1.sql`, with no seeds or roles. The unchanged baseline was applied once with `db push --project-ref … --skip-vault`; live history contains version `20261008083455`, name `sgn_crm_v1`. Baseline SHA-256: `a359decfece080f575995f58e44c134f94b4ff3f83c1a31c75866b01d97d0588`. |
| Catalog and privileges | All **30** application tables have RLS. The **six** `crm` RPCs have the contracted signatures, invoker security, empty search paths, authenticated EXECUTE and no anonymous EXECUTE. `commission_balances` is an invoker view. Authenticated roles have no application-table write grants or private-table SELECT grants; private definers have empty search paths and no anonymous EXECUTE. `sql/verify_deployment.sql` also completed successfully. |
| Data API and Storage | Exposed schemas are exactly `crm`; extra search path is `extensions`. Both private schema profiles return HTTP **406 / PGRST106** with an authenticated JWT. Both SGN buckets are private with the contracted MIME allowlists and 10/20 MiB limits. The sole Storage object policy is the scoped authenticated SELECT policy `sgn_objects_read`; no pre-existing permissive policies existed. |
| Real Auth and tenant access | Three disposable users signed in through real Auth password sessions. Auth-only/nonmember requests returned no organizations. Trusted provisioning created two synthetic organizations, teams, active UUID-bound staff and private admin memberships; the same JWTs then read exactly their own organization and scoped staff, with bigint IDs cast to text before JSON serialization. Reciprocal foreign-organization reads returned no rows. Anonymous CRM reads returned **401 / 42501**; nonmember/foreign-organization financial RPCs returned **403 / 42501** under actual Auth-issued JWTs. |
| Unchanged-JWT revocation | Deactivating staff or removing its last authoritative membership removed organization access on the next request without refreshing the JWT. Restored membership/active status restored scoped staff reads. |
| Initial human administrator | **Blocked.** The operator selected local `.env` identity handoff, but `SGN_BOOTSTRAP_ADMIN_EMAIL` or `SGN_BOOTSTRAP_ADMIN_USER_ID`, and `SGN_BOOTSTRAP_ADMIN_NAME`, were not supplied. No human administrator invitation or persistent organization/staff/membership bootstrap has been performed. `SGN_BOOTSTRAP_ORGANIZATION_NAME` may override the default `SGN Real Estate`. |

The three synthetic Auth accounts were signed out and deleted, and their two organization/team/staff/membership sets were removed. Private synthetic audit history is retained. Financial journals, payments, allocations and operation requests remained empty after the denied calls. The disposable CLI workdir was removed; the populated local `.env` was neither changed nor copied.

Security advisers returned **no warnings or errors** and 10 informational notices for intentionally policy-free private/import tables. Performance advisers returned four `auth_rls_initplan` warnings on the global reference policies, 12 unindexed-FK notices and 48 unused-index notices. These are adviser observations, not measured workload performance; no schema/RPC correction or forward migration was applied.

The local `.env` has a non-assignment/non-comment first line that the CLI rejects. Deployment used a disposable directory containing the unchanged `supabase` configuration/migration, with the token passed only through the process environment. Correct that first line before running CLI commands directly from this clone; keep credentials out of command output and source control.

Issue #2 remains open for the verified human administrator bootstrap. Invitation delivery/acceptance, application Auth redirects, inventory/browser behavior, successful financial posting/concurrency, Storage HTTP/signed links, recovery and production cutover were not exercised. The observed Auth configuration has no custom SMTP and uses `http://localhost:3000` as its site URL; no invitation-delivery readiness is claimed. Complete the applicable [integration gates](../tests/SUPABASE_INTEGRATION.md) before production.

Repository checks after deployment passed: `npm test` (**27** synthetic SQL scenarios), `npm run docs` (30 tables, 286 fields, 408 constraints and 118 indexes), and `npm run check:contract` (contract `1.0.0`, six exposed RPCs). These local checks remain separate from the live evidence above.

## Workbook data migration

Install Python dependencies with `python -m pip install -r requirements.txt`. Confirm the source application's time convention before passing --source-timezone. The worksheet times appear to be local Vietnam times, but the generator makes that assumption explicit.

```bash
mkdir -p private-imports
python scripts/stage_workbook.py /path/to/Databases.xlsx \
  --organization-id YOUR_ORGANIZATION_ID \
  --source-timezone Asia/Ho_Chi_Minh \
  --output private-imports/staging.sql \
  --summary private-imports/summary.json
```

Run the generated staging.sql using a trusted database connection with ON_ERROR_STOP enabled. It loads **review staging only**, keyed by file SHA256 and source sheet/row. The first run records issue flags and dispositions. Identical reruns preserve reviewer decisions. A different transform/timezone for the same source hash is rejected rather than silently mixing payloads. Generated staging SQL contains private company/contact data and belongs outside source control.

Review sql/review_import.sql and resolve blocking issues. Recover old BDS IDs from AppSheet metadata or earlier authoritative exports; the current row-number suffix hypothesis does not reliably match contacts. Do not create aliases for the duplicated legacy PropertyID until the collision is resolved. An alias must identify one canonical property, with reviewer/evidence details.

`crm_import.promote_property` creates a reviewed canonical property/listing from one staged property row. Provide identity evidence, an active reviewer, purpose, and explicitly reviewed VND prices. Dimensions and area are also supplied as reviewed numeric values. A null price remains unknown. The function preserves the original address, leaves its current administrative mapping unresolved, keeps source approval separate from publishing, and records the source-to-target relationship. Identical source promotion retries return the same IDs. Supplying an existing canonical property ID after review creates another listing without replacing the physical asset/address.

Related Contacts, Historical, Attachments and clicks records remain staged until proven aliases and contact identities are established. The package intentionally does not automatically join unresolved references, merge people by phone suffix, upload files from relative path strings, or synthesize closed deals from “Đã bán”. Import those reviewed records with explicit organization-scoped foreign keys and source dispositions. This is a reviewed migration contract, not an automatic correction of every workbook defect.

The aggregate source dry run covered **118,774 nonempty rows across 13 sheets**. It identified 24,221 issue flags; flags can overlap and are not a count of unique bad properties. See docs/workbook_staging_summary.json for per-sheet counts and disposition totals. Date-typed price cells, source formula errors, inconsistent units and source identity collisions require explicit decisions.

## Address policy implementation

Load official province and commune code versions, including applicable changes after the July 2025 baseline. Codes are text, with 2 or 5 digits. valid_to is exclusive. Commune parent and effective dates are checked, and overlapping versions of one code are rejected. Crosswalks support full and partial successor mappings, plus the source address era.

Retain original province/district/ward/address. Current addresses require verified province/commune versions, date, method, reviewer and evidence. Partial old-ward splits require official street/block evidence or verified coordinates with authoritative dated boundaries. An approximate geocoder result remains a suggestion. Signed agreement addresses are separate immutable deal snapshots.

The schema seeds property/road classifications only. It does not seed the 34-province/commune directory or claim that old wards have already been mapped. If a code version is retired after address verification, the steward must review affected current addresses; do not leave expired units labelled current.

## Application write contract

Browser roles have **RLS-protected read access and explicitly authorized RPCs**. They have no direct INSERT/UPDATE/DELETE grants. Ordinary property, contact, activity and open-deal edits go through a trusted server using the service role. That server must validate the real user's session and company/team/assignment permissions before any write; the service role bypasses RLS. Do not expose its key to the browser. Stamp and log the actor using the user context; null actor audit rows from a background import identify background operations, not an authenticated salesperson.

Financial actions use the authenticated user's JWT and the supplied crm RPCs. Actor identity is resolved from active staff_profiles and private memberships. A beneficiary cannot approve their own terms, adjustment or payment. Finance/admin settles payments; a team manager can approve/close only their team deals. The server must not simulate user identity using an arbitrary caller-provided UUID.

Functions lock the deal, and sale closing also locks the listing. Payout/recovery requests lock every affected deal in ascending order. Unique event keys and accrual constraints prevent duplicate posting. Reusing a key with a different payload or actor fails. An identical successful request returns its original result. One failed RPC transaction posts nothing.

Use decimal-safe values for money/rates and string-form bigint IDs in clients where necessary. Do not use JavaScript Number for values above its safe integer range. numeric(18,0) can hold larger values than that range. User-facing percentages must be converted to fractions: 0.5% → 0.005.

## Commission accounting

Closed deal price and current approved rate versions are snapshotted into accrual entries. No brokerage-fee collection condition is applied. The formula is `round(final_sale_price_vnd * rate_fraction, 0)`. Rate totals above 100% are rejected as a sanity bound; company-specific ceilings must be configured in application approval rules until an agreed policy is supplied.

Posted journal rows, payment headers and payment allocations are immutable. Corrections are signed adjustments. Cancellation reverses remaining entitlement and withdraws the listing for review; it does not erase payments or automatically publish the property for sale again. A paid commission exceeding the revised entitlement is a recoverable balance. Record a positive “recovery” settlement only up to that amount. This records a confirmed cash event; it does not initiate a bank transfer.

commission_balances returns entitlement, net paid, outstanding and recoverable per deal/beneficiary. It is an invoker view. Allocation payment_kind is constrained to match its header, allowing team managers to see correct scoped paid balances without reading a payment header spanning multiple teams.

Unknown price/rate/beneficiary produces no commission. A positive amount that rounds to zero blocks closing for review. Historical unpaid commission balances need a separate finance-approved migration with the necessary deal/rate evidence; no opening liability is invented from sold listing status. Statutory tax/withholding, payroll integration and rental commission rules are outside v1.

## Verification

Run `npm test`, then `npm run docs`. Tests use a real PostgreSQL engine through PGlite with minimal representations of Supabase-managed Auth/Storage tables. The supplied results verify DDL execution, commission arithmetic, retries, immutability, tenant isolation, phone authorization, file row policies, source promotion and password rejection.

The engine is single-connection. It does not validate live Supabase Auth, PostgREST schema exposure, HTTP file uploads, adviser output, or truly concurrent sessions. Complete tests/SUPABASE_INTEGRATION.md on the selected development project before production deployment. No live production target was selected or changed during this work.

Back up database and object files separately before cutover. Freeze AppSheet edits, import the final reviewed delta, reconcile source dispositions and financial balances, and keep the old application read-only. If rollback follows new CRM writes, export and reconcile those writes before restoring the old process.
