# Static browser inventory uses caller-scoped Data API reads

SGN's first authenticated inventory feature uses a conventional root Next.js App Router/TypeScript application, statically exported to Cloudflare Pages, with Supabase browser Auth and organization-scoped `crm` SELECTs under the actual caller's JWT. Selected bigint and decimal fields are cast to text before Data API JSON serialization and validated as strings at the application boundary, preserving the database contract without introducing a service-role read backend, new view or RPC merely for numeric transport. A Supabase Edge read adapter was considered but rejected for this read-only scope because it adds a deployment and network boundary without requiring different authorization; privileged CRUD and uploads remain outside the feature and require a separate trusted backend when implemented.

## Consequences

- Keep the root `src/app/`, `src/components/` and `src/lib/` structure and `@/*` alias portable to Vercel and v0; do not add request-time Next.js handlers, Server Actions or personalized build data.
- The database's existing active-staff/private-membership predicates remain authoritative. The browsing UI does not need an exposed role-label endpoint or rely on legacy roles or user-editable metadata.
- Every selected numeric field, including embedded records, needs an explicit precision-safe projection. Filter and order on original typed database columns; do not repair numbers after ordinary JSON parsing.
- Documented casting capability is not live acceptance evidence. Verify the selected Supabase project's actual projections, embeddings, RLS and string response types before release.

Evidence: [platform research](../research/property-inventory-platform.md), [database contract](../DATABASE_CONTRACT.md#scalar-and-null-conventions), [stack constraints](../agents/domain.md#target-stack-and-structure).
