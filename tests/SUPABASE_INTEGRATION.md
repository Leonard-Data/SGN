# Supabase development integration gates

Run these on the explicitly selected development project, with synthetic data and separate Auth sessions. The local verification report does not claim these have already passed.

[Issue #2 deployment evidence](../docs/DEPLOYMENT.md#approved-development-deployment-evidence) records the live baseline catalog/adviser review and selected real Auth/Data API scope and unchanged-JWT revocation checks. This is partial evidence for gates 1 and 9, not completion of every scenario below; the human administrator bootstrap remains pending.

1. Expose crm only in Data API and confirm authenticated user requests return the same scoped rows as the SQL tests. Anonymous and nonmember users must not read CRM data or invoke financial RPCs.
2. Use two team managers in different teams within one company. Each should see only their team's financial terms/entries/allocations. A payment spanning teams must not leak its complete header amount to either manager.
3. Fire two close_deal requests simultaneously for one deal with the same key and identical body. Both must return the same result and exactly one accrual per beneficiary must exist.
4. Fire simultaneous close requests for separate deals on the same listing. At most one may close; the other fails without journal entries.
5. Fire two payouts for the same beneficiary/deal, each individually fitting the initial balance but jointly exceeding it. One must fail after locking/rechecking; the balance must never become an unintended overpayment.
6. Run a payout concurrently with a downward adjustment or cancellation. The serial outcome must be correct: either payout is rejected after the reduced balance, or the later correction creates a visible recoverable amount. No journal/payment row may be lost.
7. Retry the same payment key with identical and changed payloads. Identical returns the original result; changed fails. Duplicate external payment reference under a new key must fail.
8. Upload a synthetic photo through the authorized backend. Register the file metadata and mark available only after checksum/existence verification. Authorized staff can read it; another company and anonymous users cannot. Test HTTP signed links and expiry.
9. Revoke a user's active flag or memberships without refreshing their JWT. Database reads and RPCs must immediately fail or become empty, because authorization uses current database memberships.
10. Review all security/performance advisers and existing Storage policies. Verify database and object-file recovery, staged source totals, and final cutover balance reconciliation.
