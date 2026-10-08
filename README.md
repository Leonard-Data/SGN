# SGN Real Estate CRM backend

Database foundation for migrating the company's AppSheet/Google Sheets property inventory to Supabase and calculating sales commissions from verified closing prices.

**Start with [docs/DATABASE_CONTRACT.md](docs/DATABASE_CONTRACT.md).** Agents working anywhere in this project must also read [AGENTS.md](AGENTS.md).

The initial backend provides 30 application tables, tenant foreign keys, role-scoped reads, audited phone access, private file access, reviewed import staging, and transactional commission RPCs. No frontend or HTTP CRUD server has been implemented, and no live Supabase project has been deployed.

The first application feature is defined in [authenticated property inventory browsing](docs/features/property-inventory.md), with domain terms in [CONTEXT.md](CONTEXT.md) and architectural decisions in [docs/adr/](docs/adr/). This is a feature definition, not an implemented or deployed application.

| Path | Responsibility |
|---|---|
| `AGENTS.md` | Project-wide agent instructions |
| `docs/DATABASE_CONTRACT.md` | Domain rules, authorization, lifecycle and API contract |
| `docs/database-contract.json` | Machine-readable integration contract and RPC arguments |
| `docs/SCHEMA.md` / `docs/schema.json` | All fields, constraints, indexes and source mappings |
| `CONTEXT.md` | Canonical domain glossary |
| `docs/features/property-inventory.md` | First end-to-end feature scope, behavior and acceptance gates |
| `docs/adr/` | Recorded architectural decisions |
| `supabase/migrations/` | Authoritative versioned database SQL |
| `supabase/config.toml` | Local Supabase configuration; exposes only `crm` |
| `scripts/stage_workbook.py` | Redacted workbook-to-review-staging generator |
| `sql/` | Bootstrap, import review, financial examples and deployment checks |
| `tests/` | Synthetic PostgreSQL checks and live integration checklist |
| `docs/DEPLOYMENT.md` | Installation, reviewed migration and cutover procedure |

## Local verification

Node 22+ and Python 3.10+ are recommended. Install Python requirements when working with source imports.

```bash
npm ci
python -m pip install -r requirements.txt
npm test
npm run docs
npm run check:contract
```

The database tests use PGlite with Auth/Storage schema stubs. They do not need Docker. For a complete local Supabase stack, Docker is required:

```bash
npx supabase start
npx supabase db reset
```

Use the local reset command without `--linked`. Consult [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for a selected cloud development project and bootstrap steps. The schema migration creates fresh schemas; it does not overwrite an existing installation.

## Business behavior

Each beneficiary receives `round(verified_final_sale_price_vnd × approved_rate_fraction, 0)`, payable at closing. Payments are recorded separately and allocated by deal. Adjustments, cancellations and recoveries preserve the posted history.

New-property addresses use current province and commune/ward versions. Legacy addresses retain the original district/ward and may use reviewed crosswalk suggestions. Official administrative codes and boundary evidence must be loaded from verified sources; they are not included as guessed seeds.

The source dry run covered 118,774 rows across 13 sheets. Ambiguous property identities, broken links, invalid prices and partial address mappings remain review work. The source workbook and private generated staging data are excluded from this public repository.
