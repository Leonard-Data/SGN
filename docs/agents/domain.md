# Domain docs

## Read before exploring

1. Read `docs/DATABASE_CONTRACT.md` for business rules, authorization
   boundaries, integration interfaces and implementation status.
2. Read root `CONTEXT.md` when present, then relevant decisions in `docs/adr/`.
3. For database-facing work, read the relevant `docs/SCHEMA.md` sections
   and machine catalogs `docs/schema.json` and `docs/database-contract.json`.
   Versioned SQL in `supabase/migrations/` is executable authority.

Layout: single-context. Root `CONTEXT.md` holds the glossary and domain
model; `docs/adr/` holds numbered architectural decisions.

If CONTEXT or ADR files are absent, proceed silently.
The domain-modeling skill creates them when terminology or decisions
are resolved; their absence does not require placeholder files.

Use glossary terms in tickets, code and tests. Until a glossary exists,
use the database contract's vocabulary. Flag conflicts with existing
ADRs explicitly rather than silently overriding them.

## Application purpose

SGN is a multi-tenant real-estate CRM covering property inventory,
listings, contacts, sales workflow, address evidence and commission settlement.
Property, listing and deal are separate concepts.
The database contract owns their detailed rules; this document does
not redefine financial or authorization behavior.

## Target stack and structure

These are implementation constraints, not claims of existing frontend
or deployment functionality.

- Backend services: Supabase database, Auth and private Storage.
- Frontend: Next.js App Router with TypeScript.
- Use one root application package with `src/app/` for routes,
  `src/components/` for reusable UI and `src/lib/` for application adapters.
  Preserve existing database, import and test directories and commands.
- Keep UI components separate from authorization and data-access code.
  Use conventional React components and an `@/*` alias mapped to `src/*`
  so v0-generated components can be integrated without a separate app.
- Primary frontend hosting: Cloudflare Pages using Next.js static export
  (`output: 'export'`, build output `out/`).
- Pages static export cannot supply request-time Next.js server rendering,
  Server Actions or dynamic route handlers. Put privileged CRUD and upload
  operations in a separately deployed trusted backend, preferably Supabase
  Edge Functions, with the database contract's session, role, tenant,
  transaction and actor-attribution checks.
- Keep service credentials exclusively in that trusted backend.
  Financial writes use authorized RPCs with the actual user's JWT.
  Preserve bigint and decimal precision in transport adapters.
- Do not substitute browser table writes for missing backend operations.
- If a feature requires full-stack Next.js, explicitly revisit hosting:
  use an appropriate Cloudflare Workers deployment or Vercel rather than
  claiming those features run in the Pages static export.
- Keep the standard Next.js project portable to Vercel. Isolate any
  provider-specific integration from UI and domain logic.
- Use the existing GitHub repository for Vercel/v0 import and synchronization.
  Review generated code against the database contract before merging.
  Configure deployment secrets and Supabase Auth redirect URLs separately
  for each approved environment; repository structure alone does not connect accounts.

## Hosting references

- Cloudflare Pages static Next.js:
  https://developers.cloudflare.com/pages/framework-guides/nextjs/deploy-a-static-nextjs-site/
- Cloudflare full-stack Next.js guidance:
  https://developers.cloudflare.com/pages/framework-guides/nextjs/
- v0 GitHub integration:
  https://v0.app/docs/github
