# Property inventory: platform evidence

Research date: 2026-10-08. These are technical findings, not an approved feature specification. No frontend, API, migration or live deployment was implemented or exercised.

## Static hosting

Next.js App Router supports `output: 'export'` and emits `out/`. Server Components can run at build time, but request-dependent route handlers, Server Actions, cookies, Proxy and unknown dynamic routes are not supported. Browser components can fetch authenticated data at runtime. Client Components are also prerendered, so browser-only APIs must not run during prerendering.

Source: [Next.js static exports](https://nextjs.org/docs/app/guides/static-exports).

Cloudflare Pages documents a Next.js Static HTML Export preset with `npx next build` and output directory `out`. No request-time Next.js backend is supplied by this configuration.

Source: [Cloudflare Pages static Next.js](https://developers.cloudflare.com/pages/framework-guides/nextjs/deploy-a-static-nextjs-site/).

Fixed pages with runtime query parameters can represent inventory and record details without enumerating private property IDs at build time. The final route names remain a feature decision. Do not fetch private inventory or user sessions into exported HTML or build artifacts.

## Browser authentication

Supabase supports browser email/password authentication and email OTP or magic-link authentication. Passwordless sign-in creates new Auth users by default; `shouldCreateUser: false` disables that behavior for the request. Email OTP requires an email template containing the token; magic links require approved redirect URLs. Project signup settings are a separate provisioning decision.

Sources: [Password sign-in](https://supabase.com/docs/reference/javascript/auth-signinwithpassword), [passwordless email](https://supabase.com/docs/guides/auth/auth-email-passwordless).

`getSession()` returns the stored session and refreshes it if necessary; it is not proof of SGN organization authorization. RLS derives authority from the authenticated identity, active staff and current private memberships. Use Auth state events to clear application state on sign-out; cached rows are not authorization evidence.

Sources: [getSession](https://supabase.com/docs/reference/javascript/auth-getsession), [Auth state events](https://supabase.com/docs/reference/javascript/auth-onauthstatechange), [SGN identity contract](../DATABASE_CONTRACT.md#tenant-identity-and-authorization-contract).

`signOut({ scope: 'local' })` signs out the current session; the default is global. Already-issued access tokens remain usable until expiry, subject to database authorization. Clearing the application's displayed and cached inventory on logout is required independently of token expiry.

Source: [signOut](https://supabase.com/docs/reference/javascript/auth-signout).

## Precision-preserving reads without a new backend

PostgREST documents `select=full_name,salary::text`, returning `salary` as a JSON string. The database casts before JSON serialization, so JavaScript's normal JSON parser does not round the selected numeric value. Casting applies to selected columns; horizontal filters cannot cast their operands. Filter and sort on the original database numeric columns rather than their string representations.

Source: [PostgREST column casting](https://docs.postgrest.org/en/v14/references/api/tables_views.html#casting-columns).

For SGN, a candidate SELECT projection is `id::text,organization_id::text,display_code,width_m::text,length_m::text,land_area_m2::text` on `crm.properties`. Listing projections must likewise cast IDs and `asking_sale_price_vnd` / `asking_rent_vnd`; address projections must cast IDs and any selected decimal coordinates. Select explicit fields, not `*`. Preserve nullable values as null. Check every included numeric field, including nested records, before claiming the adapter is lossless.

Sources: [SGN field dictionary](../SCHEMA.md#crmproperties), [SGN scalar contract](../DATABASE_CONTRACT.md#scalar-and-null-conventions).

This documented option does not require a schema change or service credentials. It must still be exercised against the explicitly selected project's actual Data API, client version, foreign-key embedding and response types. No live Supabase target or deployed PostgREST version has been established in this repository. Generated TypeScript declarations alone do not establish wire precision.

A read adapter should reject a numeric response where the contract requires a decimal string; converting an already-parsed number with `String()` cannot restore lost digits. Browser formatting and filter input must also avoid converting bigint IDs or VND to JavaScript Number.

## When a separately deployed backend is needed

Existing authenticated SELECT policies can serve read-only inventory without exposing `crm_private.memberships` or returning role labels. Roles can be specified in the feature's access matrix while RLS determines the returned rows. Role badges or privileged capability bootstrap would require a reviewed trusted lookup; do not use `legacy_role` or user-editable metadata instead.

Sources: [SGN authorization contract](../DATABASE_CONTRACT.md#tenant-identity-and-authorization-contract), [authoritative SQL](../../supabase/migrations/20261008083455_sgn_crm_v1.sql) (`current_staff`, `has_role`, `org_read`, `property_read`, `listing_read`).

Ordinary CRUD and uploads require a trusted backend under the existing contract. Supabase Edge Functions support user-authenticated handlers and a caller-JWT RLS client; service-role clients bypass RLS and require the contract's explicit authorization and actor-attribution strategy. This is distinct from an optional read-only transport adapter. It is not part of browsing merely because the frontend is statically hosted.

Sources: [Securing Edge Functions](https://supabase.com/docs/guides/functions/auth), [SGN write boundary](../DATABASE_CONTRACT.md#required-backend-behavior-for-ordinary-crud).

If an Edge Function is chosen for precision-preserving transport, it must either request SQL text casts or parse the raw upstream response losslessly before any ordinary JSON parse, then emit decimal-string DTOs. Normal `supabase-js` parsing followed by a BigInt/string replacer is not a lossless relay. Forward the real caller's JWT for reads; do not substitute a service-role query and approximate the RLS rules in application code. Validate the session, requested scope and allowed query shape, and configure browser CORS for the function.

## Scope, embedding and caching

PostgREST supports foreign-key resource embedding and filters on embedded resources. Left versus inner embedding changes which parent rows remain, so exact property/listing/address composition needs a live API acceptance scenario. A visible property does not authorize returning all sibling listings; SGN has separate property and listing SELECT predicates.

Sources: [PostgREST resource embedding](https://docs.postgrest.org/en/v14/references/api/resource_embedding.html), [SGN SQL](../../supabase/migrations/20261008083455_sgn_crm_v1.sql) (`property_read`, `address_read`, `listing_read`).

Removing the active staff flag or the final membership changes subsequent RLS queries without refreshing the JWT. This does not erase data already delivered to a browser. Key in-memory results by identity and organization; clear them on logout or organization switch, discard late responses from old scopes, and explicitly define revalidation behavior. Do not persist inventory or introduce offline/private-response CDN caching silently.

Sources: [SGN authorization contract](../DATABASE_CONTRACT.md#tenant-identity-and-authorization-contract), [live integration gate 9](../../tests/SUPABASE_INTEGRATION.md).

The supplied local Auth config permits signup and lacks production redirect settings. Invite-only access, email delivery and redirects need explicit environment configuration; a static repository layout does not provision identities or organizations.

Sources: [local Supabase configuration](../../supabase/config.toml), [deployment bootstrap](../DEPLOYMENT.md#apply-to-a-development-project).

## Verification boundary

During discovery, an ephemeral PGlite scenario using the existing migration and synthetic Auth/Storage representations observed:

- A manager can read an approved listing even when its property is archived and its commercial status is withdrawn.
- A manager can read their own pending listing, but not a same-team colleague's pending listing or a hidden sibling listing on a visible property.
- Adding operations membership broadens visibility to all organization properties, including a property with no listing.
- Disabling the staff row without changing the JWT removes organization, property and listing results.
- SQL `::text` preserves bigint `9007199254740993` and whole-VND `999999999999999999`.

This is evidence of current SQL predicates and SQL casting, not live Auth/PostgREST transport, browser behavior, deployment or production readiness. The [Supabase integration checklist](../../tests/SUPABASE_INTEGRATION.md) remains unexecuted here.
