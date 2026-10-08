# SGN real-estate CRM

SGN manages organization-owned property inventory and its related commercial listings, contacts and sales workflow.

## Language

**Organization**:
The business tenant that owns its property inventory and other business records. A person may belong to more than one organization.
_Avoid_: Account, team used to mean the tenant

**Staff member**:
An organization-specific person record that may be linked to a login identity. Active status and organization membership determine whether that person can exercise an organization role.
_Avoid_: Login user used interchangeably with staff member

**Membership role**:
An authoritative organization role held by an active staff member: sales, manager, operations, finance or admin. A staff member may hold several roles at once.
_Avoid_: Legacy role, self-declared role

**Property**:
The physical real-estate asset, distinct from its commercial listings and sales deals. Its display code identifies it within an organization; a legacy property identifier is not guaranteed unique.
_Avoid_: Listing, deal, legacy identifier used as property identity

**Listing**:
An offer to sell or rent a property, with its own asking price, commercial status, approval state and staff assignment. A property can have several listings.
_Avoid_: Property, deal

**Deal**:
A sales-workflow record associated with a particular listing and property. Its agreed final sale price is distinct from the listing's asking price.
_Avoid_: Listing, property

**Current address record**:
The selected address record for a property, preserving its original address text and any reviewed administrative mapping. Selection does not by itself establish that the administrative units are legally current today.
_Avoid_: Verified address used to mean automatic present-day legal freshness

**Approved listing**:
A listing whose approval state is approved, independently of its commercial status, price verification and any legacy approval value.
_Avoid_: Available listing, verified property, legacy-approved listing used interchangeably with approved listing

**Property inventory**:
The collection of physical properties owned by an organization, including retained archived assets. Commercial listings describe offers concerning those assets, not additional properties.
_Avoid_: Listing inventory used to mean the physical property collection

**Asking sale price**:
The amount requested by a sale listing, not a verified final transaction price or a commission basis. An unknown asking amount is not zero or an assertion that the price is negotiable.
_Avoid_: Sale price used without distinguishing asking from agreed final price

**Rental asking amount**:
The amount requested by a rental listing for its stated rental period. An absent or unspecified period does not mean monthly rent.
_Avoid_: Monthly rent when the listing's period is unknown or different
