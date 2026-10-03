// Desk 83 on MemStore — the edge's own record authority (E-06-91 … E-06-95). The scenarios and the
// fingerprint each refusal is checked for live in record_authority_world.ts; the same scenarios run
// on PgStore as rf_api in tests/rls/edge_record_authority.test.ts, so both stores answer alike.
//
// MemStore holds 0022 too (rf.may_file_record at the record insert; rf.project_membership,
// rf.project_book_role and rf.project_device_status's authorisation), so every refusal below would
// still be a refusal with the edge check deleted — which is why each one is ALSO asserted to carry
// the edge's fingerprint (no insert asked for; or stored, noted, answered with its seq, and no
// projection asked for). Delete an edge check and keep the store's: these tests fail.
import {
  authorsFirstRecord,
  bookRoles,
  differentTenants,
  filedElsewhere,
  founder,
  intake,
  inviteReadmission,
  lateApplication,
  memWorld,
  pendingGuardian,
  publishTenant,
  refusedRemoval,
  revocations,
  storeHolds,
  subjectRemoved,
  usedBook,
} from "./record_authority_world.ts";

Deno.test("E-06-91 [MemStore] intake: the edge asks the database (rf.may_file_record) whether the caller may file in the record's tenant BEFORE it stores anything — a certified admin of tenant A filing any kind into B, B's removed and blocked members, a tenant that does not exist and a memberless tenant offered anything but the founder's membership_status are each answered rejected:unauthorized (check rls, no seq) with no insert asked of the store; a pending member's device_added and an admin's designation are acked; and a stored record re-sent after its author's removal is answered as stored (desk 68(a))", async () => {
  await intake(memWorld());
});

Deno.test("E-06-92 [MemStore] the founder bootstrap is the database's answer, not a count of the rows the caller can see: the founder of a memberless tenant takes its own membership at active (acked), while founding it for someone else, or at joined_pending_verification / removed / invited, and a non-admin's membership_status or member_removal in a tenant with members, are refused by the edge with check not_admin, stored and noted, no projection asked for; the founder's \"no member at all\" is asked of the database again at apply, so a founding record stored while the tenant was empty and replayed after another founded it is refused not_admin by the edge (desk 68(a) replays skip intake)", async () => {
  await founder(memWorld());
});

Deno.test("E-06-93 [MemStore] a book role needs an admin OF THAT BOOK (06 §1.0 🔒): the admin of another book of the tenant, a member of the book, and a pending member are refused not_admin by the edge; a role-less book's first role is only the caller's own admin role, only on a book that holds no envelope, and on a personal book only its owner's; a book outside the record's tenant answers rejected:unknown_book like one that does not exist; the book's admin grants and revokes", async () => {
  await bookRoles(memWorld());
});

Deno.test("E-06-94 [MemStore] a device is revoked by its own user or that user's guardians inside a tenant the user is in: a non-guardian member and a completing guardian on a record of a tenant the subject is not in are refused not_revoker by the edge, the device stays certified; k guardians in the set's tenant (the subject's) revoke it, and an owner revokes its own other device", async () => {
  await revocations(memWorld());
});

Deno.test("E-06-95 [MemStore] without the edge, the store itself holds 0022 as PgStore does: rf.may_file_record's answers (active and pending members yes; removed, strangers, unknown tenants no; a memberless tenant only a membership_status), a stranger's insert refused rls, a non-admin's membership not_admin, another book's admin's book role not_admin, a device record that certifies revoke_only, a fellow member's revocation not_revoker", async () => {
  await storeHolds(memWorld());
});

// Desk 89 — ADR 2026-10-03b (0026): the guardian set's tenant, and the count the database keeps.
Deno.test("E-03b-1 [MemStore] an approval filed outside the guardian set's tenant never counts: g1's approval in A — a tenant the subject is in, but the set was set up in B — is refused not_revoker; g2's in B is \"counted 1 of 2\", rf.revocation_count says 1 of 2, and the store refuses to project on g1's A record or on one counted approval; g1's approval in B completes the revocation at the k-th counted seq", async () => {
  await filedElsewhere(memWorld());
});

Deno.test("E-03b-2 [MemStore] guardians who file in different tenants do not complete (replaces the ignored E-06-94 disjoint-guardians case, ADR 2026-10-03b Consequences): the set was set up in A; g1 files in A (counted 1 of 2), g2 — since gone from A — files in B, a tenant the subject is in, and is refused not_revoker; the device stays certified; a set with no tenant (published before 0026) counts nothing", async () => {
  await differentTenants(memWorld());
});

Deno.test("E-03b-3 [MemStore] a guardian still joined_pending_verification in the set's tenant revokes: its approval is answered by the database (rf.guardian_may_revoke) and, as the k-th, completes the revocation and reads the count; a stranger and a guardian removed from the tenant are refused at intake, a pending non-guardian and another subject's guardian not_revoker, and none of them reads the count", async () => {
  await pendingGuardian(memWorld());
});

Deno.test("E-03b-7 [MemStore] the subject's membership in the set's tenant is judged at each approval's own seq (ADR 2026-10-03b §6): two of a k = 3 set's approvals filed while the subject is there count 2 of 3 and KEEP counting after its admin removes the subject; g3's approval filed while the subject is removed — a newcomer having joined since — is refused not_revoker (rf.guardian_may_revoke) and never counts — not after the re-admission either, nor by the store's own projection; a removal in another tenant, and the newcomer's removal in this one, change nothing (the history is the subject's); g3 files again after the re-admission and completes k at that approval's seq", async () => {
  await subjectRemoved(memWorld());
});

Deno.test("E-03b-11 [MemStore] a membership change is a fact when it is applied, never at its record's seq (desk 97 review, finding 1): a re-admission stored unapplied and applied on its re-send (sync-meta's duplicate arm) counts neither approval refused not_revoker while the subject was removed — the count stays empty and the device certified; a removal stored unapplied and applied on its re-send, and the admin's own older designation record applied as a removal, never un-count the approval filed before them; the guardians then complete k", async () => {
  await lateApplication(memWorld());
});

Deno.test("E-03b-12 [MemStore] 06 §7's own re-admission is a membership fact (desk 97 review, finding 2): a subject removed by record and re-admitted through invite → acceptInvite (joined_pending_verification) → the ceremony's verification_event (active) is held again — g2's approval filed after the acceptance counts, and g1's after the ceremony completes k; g1's approval filed while the subject was removed never counts", async () => {
  await inviteReadmission(memWorld());
});

Deno.test("E-03b-9 [MemStore] a membership record the server refused is not a membership fact (0027 §1): a non-admin member's member_removal of the subject and the subject's own device's membership_status removed are refused not_admin and stored, the subject stays active, and the guardians' approvals filed after them count and revoke the device", async () => {
  await refusedRemoval(memWorld());
});

Deno.test("E-03b-8 [MemStore] the server applies the k the subject's own devices apply — one counted record per author (its lowest seq), k of the earliest version among those: g1 names v2 (k = 3), g1's stale device re-files naming v1 (k = 2) and is not counted again, g2 makes 2 of 3 — no revocation; g3 completes it", async () => {
  await authorsFirstRecord(memWorld());
});

Deno.test("E-03b-4 [MemStore] a book whose book_usage.envelope_count is above 0 but which holds no envelope row is not bootstrapped: the edge refuses the creator's first admin role not_admin and so does the store's project_book_role; a book that never held an envelope is claimed", async () => {
  await usedBook(memWorld());
});

Deno.test("E-03b-5 [MemStore] publishing a guardian set requires tenant_id (400 bad_request without), a publisher active there (403 guardian_set_tenant — the same for a pending publisher, a tenant it is not in and one that does not exist) and every guardian not removed there (403 guardian_not_in_tenant; a pending guardian may be chosen); the tenant is written once with the version, relayed as guardian_sets[i].tenant_id on GET /sync-meta, and a re-split may name another", async () => {
  await publishTenant(memWorld());
});
