# SGN Design and System Guide

This is the primary product design, system design, and project-structure reference for SGN. The database contract and versioned SQL remain authoritative for data behavior, authorization, and financial rules.

## Product direction

SGN is a calm, trustworthy real-estate CRM for organization-owned property inventory, listings, contacts, deals, address evidence, and commission settlement. The interface should feel operational rather than promotional: clear hierarchy, restrained color, high information density, and explicit status.

Use Vietnamese (`vi`) as the default interface language. English (`en`) is supported through the shared localization provider. User-facing dates display in `Asia/Ho_Chi_Minh`; IDs, VND values, and rates preserve their contract-safe representations.

## Visual system

- **Primary green:** SGN brand green for actions, active states, links, and verified status.
- **Ink:** near-black green-gray for headings and primary text.
- **Surface:** warm white/light gray in day mode; deep green-gray in night mode.
- **Muted:** gray-green for helper text, metadata, and secondary navigation.
- **Semantic status:** use accessible green, amber, red, and blue semantic tokens; never rely on color alone.
- **Typography:** one readable sans-serif family, strong heading contrast, compact labels, generous line height for Vietnamese copy.
- **Shape:** restrained radii, thin borders, subtle shadows only on elevated surfaces.
- **Spacing:** use the existing scale and flex/grid layout; avoid arbitrary absolute positioning.
- **Accessibility:** visible focus rings, keyboard-complete controls, semantic labels, sufficient contrast, and alt text for meaningful images.

Design tokens belong in `src/app/globals.css`. Components consume semantic variables rather than hard-coded colors. Day/night mode is controlled by `AppProvider`; localization and theme controls should be reused instead of reimplemented per page.

## Application architecture

```text
src/
  app/                    App Router routes and page composition
    auth/                 sign-in, sign-up, sign-out, callback, error
  components/             reusable UI and feature components
  lib/
    supabase/             browser/server Supabase adapters
  app/globals.css         design tokens, base styles, responsive rules
supabase/                 local configuration and migrations
scripts/                  import and maintenance tooling
docs/                     contracts, schema, deployment, agent guidance
tests/                    synthetic and integration verification
```

Keep presentation separate from data access and authorization. Browser components may use the publishable Supabase client for supported Auth flows and RLS-protected reads. Do not expose service-role credentials. Ordinary CRUD belongs in a trusted backend that validates the real session, active staff, membership role, organization scope, and resource scope before using service credentials.

## Routing patterns

- `/` is the current placeholder and future authenticated workspace entry.
- `/auth/sign-in` and `/auth/sign-up` are the public email/password entry points.
- `/auth/sign-out` signs out through Supabase Auth.
- `/auth/callback` exchanges the Supabase auth code for a session.
- `/auth/error` is the safe auth failure fallback.

New routes should use App Router conventions, compose reusable components, and keep loading/error/empty states explicit.

## Data and security rules

- Use the `crm` schema explicitly for application reads and authorized RPCs.
- Never expose `crm_private` or `crm_import` through the Data API.
- Scope every request by the authenticated organization; a requested organization ID is not authorization.
- Keep property, listing, and deal as separate entities.
- Use decimal strings/decimal arithmetic for VND and rates; bigint IDs cross application boundaries as decimal strings.
- Financial records are immutable after posting; corrections append history through the contracted RPCs.
- Never use user-editable metadata as authorization.
- Preserve original addresses and evidence for administrative mappings.

For exact predicates, RPC signatures, constraints, and lifecycle rules, read `docs/DATABASE_CONTRACT.md`, `docs/SCHEMA.md`, and the authoritative migration before implementation.

## Implementation workflow

1. Read `AGENTS.md`, `CONTEXT.md`, the relevant contract/schema sections, and applicable `docs/agents/` guidance.
2. Identify the smallest route/component/data boundary that satisfies the feature.
3. Build UI with semantic tokens and shared components first.
4. Add Supabase access only after confirming the live schema and RLS behavior.
5. Validate with the narrowest relevant test, then `npm test`, `npm run docs`, and `npm run check:contract` for contract-affecting changes.
6. Verify user-visible flows in the browser and synchronize the feature branch before completion.

## Avoid

Do not add localStorage-based persistence, mock authentication, unscoped tenant queries, direct financial table writes, guessed schema fields, invented administrative data, populated environment files, customer exports, or decorative UI that competes with operational content.
