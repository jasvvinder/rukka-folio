# ADR 2026-10-04 — A suspended device is refused the invite routes (desk 108)

**Status:** accepted (owner-ruled, 4 Oct 2026).
**Amends:** ADR 2026-10-03c §3.

## Context

ADR 2026-10-03c §3 gated `rf.my_invites` and `rf.accept_invite` on `rf.device_live_for`, which counts a
suspended device as live. Suspended means the server asserted a revocation without a signed record (ADR
2026-09-05b §2; a support revocation lands after its 24 h cancellable delay — ADR 2026-09-05d §3; 06 §8
support CAN). A suspended device is already refused a new access token (`auth-challenge/index.ts:370`), and
`rf.recovery_shares` (0020) also excludes suspended; the invite routes did not.

## Decision 🔒 ⟦tests: E-03c-3, E-03c-4, F1-03c-5, F1-03c-6⟧

### 1. A suspended device cannot read or accept its user's invites

Both routes refuse a suspended device exactly as a revoked one: the same refusal, same name
(`unknown_candidate_device` in the database, `403 unknown_request` at the edge); the caller cannot tell
suspended from revoked. `rf.device_live_for` itself is unchanged, so `rf.has_guardian_set` keeps 0025(c)'s
reading. The app names the refusal in words true for both states (desk 109).

**Why:** an access token minted before suspension stays valid for up to 15 minutes (`ACCESS_TTL_S`,
`_shared/claims.ts:10`); in that window a suspended phone — possibly a stolen one — could still read offers
and join a book. Refusing at the routes closes it. A legitimate user loses nothing they had: a suspended
phone cannot sync anyway, and a cancel from any certified device restores it.

## Consequences

- **Build, `lane-server`:** 0028 edited in place before its first deploy (desk 110 applies it); RLS suite.
- **Build, `lane-ui`:** app message (desk 109).
- **Build, MemStore parity.**
