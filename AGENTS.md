# SGN project instructions

These instructions apply to the entire repository, including future frontend, backend, automation and reporting code.

## Read before working

1. Read `docs/DATABASE_CONTRACT.md` for domain rules, write boundaries and exact RPC interfaces.
2. Read the relevant tables in `docs/SCHEMA.md`. Use `docs/schema.json` for the machine-readable field/constraint catalog and `docs/database-contract.json` for integration metadata.
3. Treat versioned SQL in `supabase/migrations/` as the authoritative implementation. If a document disagrees with the SQL, inspect the SQL and fix the documentation; do not invent a missing column or RPC.
4. Read `docs/DEPLOYMENT.md` before migration/import operations and `tests/SUPABASE_INTEGRATION.md` before claiming production readiness.

## Non-negotiable implementation rules

- Qualify database objects by schema. Application reads and authorized RPCs use `crm`. Never expose `crm_private` or `crm_import` through the Data API.
- Scope every tenant query and write by the authenticated organization. A request-supplied organization ID is a requested scope, never proof of authorization.
- Browser clients have SELECT and explicitly authorized RPCs only. Ordinary CRUD requires a trusted server that validates the session, active staff, authoritative membership role and resource scope before using service credentials.
- Financial writes use the actual user's JWT with the supplied `crm` RPCs. Never directly insert/update/delete journals, terms or payment records; do not fabricate `auth.uid()` from a request actor ID.
- Use decimal strings/decimal arithmetic for VND and rates. Entity bigint IDs use decimal strings at application boundaries. Do not silently parse all database numerics as JavaScript Number.
- Commission is a direct approved rate of verified final property sale price, payable at closing. Asking price and brokerage-fee collection do not determine entitlement.
- Preserve original addresses. New-property forms use current province and commune/ward versions; legacy entry and partial crosswalks require evidence. Official administrative data is not seeded yet.
- Posted financial records are immutable. Corrections, cancellations and recoveries append history through RPCs.
- Never commit customer workbook exports, generated private staging SQL, phone data, passwords, keys or populated environment files. `.env.example` contains placeholders only.

## Changing the database

Create new migration files with the Supabase CLI's `migration new` command. Once a migration is applied or shared as an accepted baseline, add a forward migration rather than rewriting it. Keep grants, RLS, composite tenant foreign keys, invoker views, empty definer search paths and function execution privileges explicit.

For schema or RPC changes, update the contract, machine integration metadata, examples and meaningful tests in the same change. Run `npm test`, `npm run docs`, and `npm run check:contract`. Generated field docs must match the tested catalog. Check `python -m py_compile scripts/stage_workbook.py` when changing the importer.

The local engine does not prove live Supabase Auth/PostgREST, Storage HTTP behavior or concurrent sessions. Complete the integration checklist before production use. Do not deploy, reset a linked database, seed guessed administrative data, or report a live migration as applied merely because local tests pass.

## Repository scope

The initial repository implements database artifacts, import tooling and synthetic tests. It does not implement HTTP CRUD routes, frontend forms, Auth screens, background jobs or a live deployment. Add those components against the existing contract; do not describe them as already available.

## Agent skills

### Issue tracker

Track issues and specs in GitHub Issues for `Leonard-Data/SGN`. Before ticket operations, read `docs/agents/issue-tracker.md`.

### Triage labels

Use the five default triage labels. Before triage, read `docs/agents/triage-labels.md`.

### Domain docs

Use single-context domain documentation. Before exploration or architecture changes, read `docs/agents/domain.md` for consumer rules and stack constraints.
