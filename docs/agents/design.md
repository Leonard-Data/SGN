# SGN Agent Design Rules

Use `DESIGN.md` as the primary design and system reference. This file contains the agent-facing checklist for applying it consistently.

## Before implementation

- Read `AGENTS.md`, `DESIGN.md`, `CONTEXT.md`, and the relevant database contract/schema sections.
- Confirm whether the task is UI-only, Auth, a tenant-scoped read, a trusted write, an RPC, import, or financial behavior.
- Reuse existing components, tokens, localization, and theme infrastructure before adding new patterns.

## UI pattern

- Default locale is Vietnamese; all new user-facing copy must have Vietnamese and English translations.
- Use semantic design tokens from `src/app/globals.css`; do not introduce raw brand colors in feature CSS.
- Preserve day/night mode through `AppProvider` and test both themes when the change is visual.
- Prefer semantic HTML, accessible labels, visible focus, keyboard support, responsive flex/grid layouts, and explicit loading/error/empty states.
- Keep route files thin. Put reusable UI in `src/components/` and Supabase adapters in `src/lib/`.
- Do not use localStorage for application data persistence.

## Supabase boundary

- Browser code uses only the publishable key and supported Auth/RLS reads.
- Use `crm` explicitly; never expose or query `crm_private`/`crm_import` from the browser.
- Every tenant query must be scoped by the authenticated organization and authoritative membership.
- Ordinary CRUD requires a trusted server boundary. Never expose `SUPABASE_SERVICE_ROLE_KEY` to client code.
- Financial operations must use the supplied `crm` RPCs with the actual user's JWT.
- Verify real schema, nullability, defaults, RLS, and RPC signatures before writing data access code. Never infer fields from UI requirements.

## Domain safety

Keep property, listing, and deal distinct. Preserve original addresses and evidence. Treat approved listing state separately from commercial status. Use decimal-safe strings for VND/rates and decimal strings for bigint IDs. Posted journals, payments, and allocations are immutable; corrections append history.

## Validation

- Run the narrowest relevant check first.
- For UI changes, verify the route in a real browser at representative desktop/mobile sizes.
- For contract or database changes, run `npm test`, `npm run docs`, and `npm run check:contract`.
- Remove temporary debug logging before completion.
- Synchronize Git after the final file change.
