# Authenticated, organization-scoped property inventory browsing

**Status:** Agreed after shared-understanding confirmation on 2026-10-08. Not implemented.

Implementation-ready specification: [GitHub issue #1](https://github.com/Leonard-Data/SGN/issues/1), labelled `ready-for-agent`. The issue records the confirmed browser verification seam and release criteria; publication does not mean the application is implemented.

## Goal and boundary

An existing, invited SGN staff member can sign in, select an authorized organization, search/filter its readable physical properties, open a read-only property detail, and sign out without exposing another organization or losing numeric precision.

This feature uses Supabase database/Auth, Next.js App Router with TypeScript, Cloudflare Pages static export and the conventional root application structure portable to Vercel and v0. Database contract v1 is a constraint; no authorization, lifecycle or financial redesign is proposed.

In scope: email/password sign-in, invitation acceptance, password recovery, session restoration/sign-out, organization discovery/selection, property results and detail, selected-address information, readable listing previews/detail pagination, search/filters, exact property counts and the states below.

Out of scope: public signup UI, staff/organization administration, property/listing edits or approvals, photos/Storage, contacts or phone reveal, agreements, imported history, deals/commission, exports, maps, offline inventory, fuzzy or accent-insensitive address search, and role-specific dashboards/badges. Inviting users and binding verified Auth identities to active staff/private memberships remain trusted administrative provisioning, not browser functionality.

## Authority and vocabulary

- [Database contract](../DATABASE_CONTRACT.md), [field dictionary](../SCHEMA.md), [machine catalog](../schema.json) and [integration metadata](../database-contract.json) define the existing integration contract.
- [Versioned SQL](../../supabase/migrations/20261008083455_sgn_crm_v1.sql) is executable authority, particularly `current_staff`, `has_role`, `can_read_property`, `org_read`, `property_read`, `address_read` and `listing_read`.
- [Root glossary](../../CONTEXT.md) distinguishes organization, staff member, property, listing, deal, approved listing and asking amounts.
- [ADR-0001](../adr/0001-static-browser-inventory-reads.md) records the static caller-JWT read/precision boundary; [ADR-0002](../adr/0002-property-centric-inventory.md) records property-centric result/count semantics.
- [Platform evidence](../research/property-inventory-platform.md) records primary sources and the limits of current verification.

## Identity, roles and organization selection

All five existing membership roles use the same read-only browsing surface. Database roles are additive, not a frontend-selected mode.

| Existing roles | Property and listing scope within the organization |
|---|---|
| `admin`, `finance`, `operations` | All organization properties/listings, including properties without listings |
| `sales`, `manager` without a broader role | Listings that are approved, assigned to that staff member, or created by that staff member; properties with at least one such listing |

A manager has no team-wide inventory exception. A visible property does not authorize every sibling listing. RLS does not exclude archived properties, sold/withdrawn listings, unverified identity/address/asking price or an owned/created unapproved listing.

Authentication and application behavior:

1. Use Supabase browser email/password Auth for provisioned accounts. Include valid invitation acceptance/password setup and password recovery through prebuilt callback/password pages. A URL marker alone never authorizes changing a password; a verified Auth session does.
2. Configure approved environment-specific redirect URLs and email delivery. Default Supabase verification links can land on the static callback with a verified browser session; consume and remove callback credentials from the URL without logging them. Exercise actual invitation and recovery flows, including expired/used links, rather than substituting Next.js server handlers.
3. No public signup UI; disable public signup for the approved application environment. The supplied local config currently permits signup, so it is not an invite-only deployment configuration as-is. Auth identity creation does not establish organization membership.
4. Restore the supported browser Auth session before requesting private inventory. Stored session/user metadata, email, submitted staff/organization IDs and `legacy_role` are not authority.
5. Discover organizations with a caller-JWT SELECT of `crm.organizations`, projecting `id::text,name`. This is the deliberate organization-discovery query before a selected scope exists; RLS supplies the authorized list.
6. An explicit valid URL organization takes precedence over remembered selection. Otherwise restore the last currently authorized organization for that Auth identity; auto-select a sole organization; show a chooser if several remain and no authorized selection can be restored.
7. Keep the selected organization name and switcher visible. Resolve the caller's own active staff ID using an explicitly organization-scoped `crm.staff_profiles` read, projecting only ID and display name and matching the real Auth UUID; use it for 'assigned to me'. Do not request staff phone, email or legacy role.
8. Treat URL/saved organization IDs only as requested scope. Revalidate organization access on entry, focus/visibility return, query changes and explicit refresh/retry. The existing database predicates, not a frontend role cache, enforce all reads.
9. Remember only the last organization choice under the Auth identity; do not persist inventory rows/counts/detail. A tab's current organization does not silently switch because another tab saved a different choice. Auth sign-out/account-change events clear every affected tab's private state.
10. Sign out the current browser session explicitly with local scope. Clear inventory, counts, detail, in-flight requests and remembered organization choice; another account must not inherit the previous account's state. Already-issued access tokens are not claimed to be instantly revoked.

## Read architecture and precision

Planned structure, not existing application files:

- One root application package, preserving the existing database/import/test tooling.
- `src/app/` for fixed route shells; `src/components/` for reusable conventional React UI; `src/lib/` for Auth, typed read projections, scope/query adapters and decimal-safe formatting; `@/*` maps to `src/*`.
- `output: 'export'`, build output `out/`. Private data is fetched after browser authentication; no private build-time data, request-time Next.js handlers, Server Actions, cookie-based server authorization or default server image optimizer.
- Fixed exported routes `/login/`, `/auth/callback/`, `/auth/password/`, `/inventory/` and `/inventory/property/`. Organization/property IDs, filters, sort and page are runtime query parameters. Do not generate private per-property paths or need a host-specific catch-all rewrite.
- Separate UI from Auth and data access. Isolate Supabase/provider details in adapters; v0 components do not acquire service credentials or perform table mutations.

Browser requests use the publishable/anonymous client key with the actual user's access JWT and select `crm` explicitly. Every tenant inventory/staff/detail query includes the selected organization. Composite tenant FKs constrain embedded children to the same organization; explicit child scope/filter conditions must not broaden that scope. Global type/road/admin-unit references are the existing authenticated reference reads. Never expose `crm_private` or `crm_import`.

No new trusted read backend, inventory view or read RPC is required merely for this feature's numeric transport. Actual private role labels are unnecessary. Ordinary CRUD/upload operations, if later implemented, require a separately deployed trusted backend, preferably Supabase Edge Functions, with the contract's session, membership, scope, transaction and actor-attribution checks; no such backend is claimed here.

Use explicit SELECT projections, not `*`. Cast every selected bigint/numeric column to SQL text before Data API JSON serialization, including nested records and nullable foreign IDs. Validate decimal-string/nullable response shapes at the adapter boundary. IDs and VND stay strings; dimensions/area also stay decimal strings. Filter/order on original typed SQL columns using exact decimal-string operands. Never use `Number`, `parseFloat` or `String()` after an unsafe parse to transport, compare or format these values. Timestamps remain ISO-8601 and null remains null.

PostgREST documents selected-column casts and foreign-key/empty-resource embedding. Use parent-level matching semantics (`!inner` or non-null matching embeds), not an embedded filter alone: filtering only an embedded collection would leave nonmatching properties and incorrect counts. An independent empty matching-address embed can support code-prefix OR address matching without restricting the displayed selected address. Use original numeric columns for filters/order; casts in horizontal filters are not supported. Live API acceptance must validate exact projections, FK disambiguation, nesting, per-parent preview limits and count semantics with the selected client/project.

## Result grain, display and detail

One result and one unit of filtered total mean one **physical property**. Several listings never duplicate that property. A property with no readable listings remains visible to a role that can read the property when no listing filters are active.

Default scope is all readable properties with `archived=false`. An 'include archived properties' toggle removes that exclusion; it does not mutate an asset. No default purpose, commercial-status, approval or verification exclusion is added.

List field allowlist:

- Property ID/organization ID, display code, property-type code/label, land area, identity verification, archived flag and creation time.
- Selected current address (`is_current=true`) original text, stored province/commune version IDs/labels, verification status and address-as-of date. The current-address relation has zero or one selected record; do not arbitrarily choose from multiple records.
- Up to two readable listings matching all active listing filters, ordered by `updated_at DESC, id DESC`: listing ID, purpose, status, approval state, corresponding asking amount, rental period, price-verification flag and assignment ID needed for the chosen filters.

Original address text is primary. Mapped administrative labels, verification and as-of date are secondary. No selected address produces an explicit unavailable/unknown address value without hiding the property. A selected or verified record is not advertised as automatically legally current today. Do not show historical addresses or reinterpret them as current.

Listing summaries are explicitly **previews**; they are not an authoritative single property price or a complete listing count. Show each preview's own purpose/status/approval/asking amount/period. Price verification is independent of approval and identity/address verification. Missing asking amount is unknown, not zero, negotiable, an opposite-purpose fallback or a financial sale price. For rentals, display the stored month/year/day/other/unknown period honestly; never imply monthly.

Read-only property detail adds reviewed width/length, direction and road-access code/label, using existing columns. It paginates the full readable listing set independently of list-preview filters in 25-listing pages with caller-scoped readable counts and deterministic `updated_at DESC, id DESC` order. An explicitly scoped, fresh property read is required for direct detail navigation; a cached row is not sufficient. There are no edit/approve actions.

Do not request contact relations/phones, staff contact fields, raw `area_raw`, free-text structure descriptions, listing notes/source notes/legacy payloads, files, history, deals or commission data. This is a feature field allowlist, not a new database column-security boundary: authenticated callers retain the database contract's existing SELECT privileges. Sensitive free-text legacy data still requires stewardship under the database contract; projections do not make contaminated readable columns inaccessible through alternate direct API requests.

## Search and filters

Use an explicit Apply/Search action (including Enter) and Clear action. Applied state, not an unsubmitted draft, is represented in the URL. Apply/sort/filter/archive changes reset property pagination to page 1. Switching organizations clears entity-dependent search/filter/detail/page state before loading the new scope. Returning from detail restores the applied list URL; same-origin permitted return paths only.

Search is one trimmed input. Empty/whitespace input removes the search condition. A property matches if either:

- `display_code` has the case-insensitive **literal prefix** entered; or
- its selected current address's existing `search_text` matches all complete query tokens using `plainto_tsquery('simple', ...)` semantics, in any order.

Address search is case-insensitive but accent-sensitive; no partial-word, fuzzy, unaccent or historical-address matching. Explain this near the control. The existing search text contains original address/district/ward, house number/street and mapped province/commune names; it does not independently include property codes, notes or `original_province`. Safely encode PostgREST filters and escape LIKE wildcards/reserved grammar; user input never becomes raw SQL or tsquery syntax.

| Control | Semantics |
|---|---|
| Property type | One existing code or all; include an explicit unknown/null choice |
| Province / commune | Selected current address's stored version IDs, not guessed names or today's inferred hierarchy; commune options belong to the selected province version and reset when it changes |
| Address verification | All, one existing verification state, or no selected address; never coerce a missing record to unresolved |
| Listing purpose | All, sale or rent |
| Listing status | All or one existing status, including `sold_legacy`, `sold`, `withdrawn` |
| Listing approval | All or one existing approval state; `legacy_approved` is not a substitute |
| Assigned to me | Require `assigned_staff_id` equal to the caller's active staff ID; creation alone does not satisfy this filter |
| Asking-price bounds | Inclusive whole-VND decimal-string minimum/maximum for the selected purpose; null amounts do not match active bounds |
| Rental period | All periods when no rent price bound is active; an explicit month/year/day is required for rental budget comparison; no conversion between periods |
| Land-area bounds | Inclusive square-metre decimal-string minimum/maximum, up to the stored three decimal places; null area does not match active bounds |
| Include archived | Default off; on includes both archived and non-archived readable properties |

AND combines different controls. All applied purpose/status/approval/assignment/period/price conditions must be true of **one same readable listing**. A hidden listing cannot qualify the property, contribute a preview/count or provide a price. With no listing filters, keep readable properties without listings; with any listing filter, require a matching listing.

Known but unverified asking amounts can match budgets and are visibly marked unverified. Require a specific sale/rent purpose before enabling price bounds. Rent `other`/unknown periods cannot be compared with budget bounds. Changing purpose or an incompatible period clears its prior budget bounds rather than reinterpreting them; expose that reset in the UI. Validate complete nonnegative finite range inputs and minimum <= maximum before applying; VND bounds are whole decimals, area bounds have at most three places. Invalid range/enum/ID URL input is an invalid-filter/link state, not a silently broadened query.

Province/commune choices use actual stored administrative versions with disambiguating dates when needed; do not filter the entire browsing vocabulary to units valid today. With no sourced administrative directory, show unavailable geographic selectors and continue code/address-text/other browsing. Never seed guessed administrative units to make the UI appear complete.

## Pagination and URL state

- 25 distinct properties per page; previous/next controls, current page and an exact RLS-scoped filtered property total.
- Default order: property `created_at DESC, id DESC`. Display-code orders ascending/descending are available with corresponding deterministic ID tie-breakers. Sort in the database, not lexically by transported ID/price strings.
- Counts have the same organization, archive, search and matching-listing constraints as rows. Never fetch the whole inventory to filter/count/sort in the browser.
- Page, sort, applied filters, organization and detail property ID are URL-backed; reload, browser back/forward and an authenticated shared link restore the requested view after scope validation. IDs remain decimal strings throughout.
- No frozen snapshot between page requests is promised. If fresh data makes the requested page out of range, show that page is unavailable and offer return to page 1; do not call it an empty organization.

## State and failure contract

| State | Required behavior |
|---|---|
| Session restoring / scope validating / querying | Distinct loading state; no previous identity/scope rows, detail or counts |
| Signed out | Login surface; private routes restore only after valid Auth and scope validation |
| Invalid credentials | Generic authentication failure, without account or organization enumeration |
| Recovery request | Neutral confirmation independent of whether the email belongs to an account; expose actual delivery/API failure separately without identifying account existence |
| Invalid/expired/used invitation or recovery link | Explain unusable link and provide appropriate sign-in/recovery/admin path; never update a password solely from URL type |
| No accessible organization | Explain that no organization access is available and direct the user to their administrator; do not distinguish nonexistent/inactive/roleless staff using privileged lookups |
| Requested organization no longer accessible | Clear its rows/detail/counts and saved selection; offer currently authorized choices or the no-access state |
| Default browse returns zero | 'No readable non-archived properties' meaning, not 'this organization has no properties' |
| Applied search/filter returns zero | No matches in the caller's readable scope; retain controls and offer Clear |
| Selected address / property attribute / asking amount unavailable | Explicit unknown/unavailable value; do not fabricate zero, approval, units or evidence |
| No readable detail listings | Explicit no-readable-listings state, without asserting hidden listings do not exist |
| Detail row absent or not readable | One generic property-unavailable outcome for missing, hidden or wrong-scope IDs; no existence probe |
| Network/API/precision-shape failure | Hide prior rows/detail/counts; retain applied inputs and offer Retry. A failed query is never rendered as an empty result |
| Authentication cannot refresh | Clear private state and return to sign-in with a safe internal return destination |
| Requested page no longer exists | Page-unavailable state and return-to-first-page action |

Revalidation occurs on entry, focus/visibility return, query changes and explicit refresh/retry. On unsuccessful revalidation, hide inventory until success. Current RLS reflects active-staff/final-membership revocation on subsequent requests without refreshing JWTs; the UI is not an instant revocation push mechanism and cannot erase data already delivered to a browser.

Keep only same-session in-memory results, keyed by Auth identity, organization and applied query. Clear them on logout/account/organization changes; cancel requests where supported and discard late responses from prior identities/scopes/queries regardless. Do not introduce offline, service-worker inventory caching or personalized-response CDN caching. Do not log passwords, callback credentials, raw address/search/note payloads or phone data.

## End-to-end acceptance gates

These are future implementation/release requirements, not checks already passed. Use synthetic records only, separate real Auth sessions, an explicitly selected Supabase development project and the actual Cloudflare static preview. A local SQL suite alone cannot pass this feature's end-to-end gate.

| Scenario | Observable acceptance |
|---|---|
| Static build and routes | `next build` exports `out/`; direct loads/reloads of all fixed routes work without a Next.js server. No private property pages/data, service key or session credentials enter static artifacts |
| Auth lifecycle | Valid email/password sign-in, session restoration, actual invitation/password setup, actual recovery, expired/used link failures and local sign-out work in the deployed browser surface |
| Provisioning and no-access | Auth-only, inactive-staff and active-but-roleless accounts see no organization inventory; no signup UI or email-to-staff authorization shortcut exists |
| Organization selection | Sole organization auto-selects; multiple organizations use authorized saved choice or chooser; valid URL scope overrides memory; inaccessible saved/URL scope cannot leak names/rows/counts |
| Role matrix and union | Sales/manager read approved, assigned and created listings only; manager cannot read a same-team colleague's pending listing solely because of team membership; operations/finance/admin read organization inventory; a sales+operations member gets the broader existing scope |
| Hidden sibling listings | A readable property with an approved listing and a hidden pending sibling returns only readable previews/detail rows; hidden sibling price/status never affects matches or visible counts |
| Cross-tenant and detail existence | Forged organization/property combinations, another tenant's IDs and nonexistent IDs produce scoped/generic unavailable outcomes; no alternate service-role/private-schema existence lookup occurs |
| Revocation and races | Deactivate staff/remove final membership while retaining JWT, then trigger revalidation: rows/counts/detail disappear. Delay a response, switch organization/account or logout, then release it: old data never reappears |
| Property grain and archive | One property with several sale/rent listings counts once. Readable unlisted properties survive unfiltered browsing. Archived assets are excluded by default and included by the toggle without mutation |
| Search | Property-code prefix, address-token case/order, accent mismatch, incomplete word, whitespace, literal wildcard/reserved punctuation and a historical-only address produce the specified scoped matches without query-grammar injection |
| Combined listing filters | A property with separate sale/rent or differently assigned/status/price listings cannot satisfy a compound filter by combining different siblings; a hidden matching sibling cannot qualify it |
| Range boundaries and unknowns | Exact inclusive VND/area boundaries match; nulls exclude only under active bounds; known unverified amounts match with warning; purpose/period resets and other/unknown rental periods are enforced; invalid bounds trigger input state rather than a query |
| Address/reference gaps | Missing selected address and unseeded admin directory do not hide readable assets. Original text is primary; stored old versions/as-of/verification are honest and not labeled legally fresh today |
| Previews and detail | At most two newest matching readable previews appear; full readable detail listings paginate deterministically, including more than one API row limit's worth of synthetic children, without silent truncation or invented single-price/listing-total claims |
| Exact totals and navigation | >25 matching properties yield correct distinct filtered totals and stable tie-breakers on a fixed fixture. Apply resets page 1; URL reload/back/forward/shared links restore scope/query; removed-page handling is not an empty-inventory claim |
| Precision over actual HTTP | Bigint `9007199254740993`, VND `999999999999999999`, decimal measurements and nullable nested IDs arrive as strings/null and display/filter exactly. A numeric wire value where a string is required causes a visible integration failure, not lossy conversion |
| Empty versus failed | Successful zero rows, no access, missing/hidden detail, invalid inputs, API denial, network failure and session-expiry states remain distinct; refresh failure hides prior private rows/counts/detail and Retry can recover |
| Data minimization | App requests/responses/bundles/logs contain no contact/phone/staff-contact fields, raw source notes, imported history, file/deal/financial payloads or service credentials; no phone-reveal RPC or mutation is invoked |
| Actual UI surface | Vietnamese labels and exact VND/metric formatting, Asia/Ho_Chi_Minh timestamps, desktop 1440×900 and narrow 360×800 layouts, keyboard/focus/accessible state announcements work in the real browser |
| Performance | Synthetic organization with 20,000 properties and multiple visible/hidden listings meets the gate below, including exact property counts |

Performance gate: p95 <=3 seconds from initiating an inventory query to usable first-page rows and exact count. Measure 30 warmed runs per scenario for default browse, code-prefix search, current-address tokens and combined listing-price/area filters, with both privileged and sales/manager scopes. Document browser/device, client/network, Supabase tier/region, preview location, dataset/visible-row distribution and warm-up procedure. Exclude email delivery and sign-in from this query measure; do not exclude the count or silently change scope. Fix any failing query/index behavior through a separately reviewed change while preserving RLS; never use a service-role read shortcut or weaken the test.

## Implementation prerequisites and completion evidence

- Select an approved development Supabase project and Cloudflare preview environment; configure `crm` exposure, exact Auth redirects, email delivery/invitation/recovery, public-signup policy and environment-specific browser public keys. No populated credentials belong in the repository.
- Provision synthetic Auth users, active staff and authoritative memberships through trusted administration; create synthetic tenant/reference/inventory fixtures without deploying/resetting a linked production database or inventing official administrative data.
- Preserve existing commands/tooling. Run the database baseline when implementing the feature; if an accepted additive migration becomes necessary, use the CLI to create a forward migration and update human/machine contracts, examples and meaningful tests, then run the required catalog/contract commands.
- Record actual static-build, browser interaction, live Auth/PostgREST precision/embedding/RLS and performance results. Feature-relevant [Supabase integration gates](../../tests/SUPABASE_INTEGRATION.md) include Data API scope and old-JWT revocation; that checklist's other financial/Storage/concurrency gates remain separate whole-system production requirements, not claims that this read-only feature implements them.

Current evidence is limited to inspected SQL/catalogs/primary docs and ephemeral PGlite authorization/text-search/text-casting smoke scenarios. The feature, live project, browser surface and performance benchmark have not been implemented or exercised.
