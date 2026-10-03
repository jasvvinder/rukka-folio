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
  bookRoles,
  disjointGuardians,
  founder,
  intake,
  memWorld,
  revocations,
  storeHolds,
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

Deno.test("E-06-94 [MemStore] a device is revoked by its own user or that user's guardians inside a tenant the user is in: a non-guardian member and a completing guardian on a record of a tenant the subject is not in are refused not_revoker by the edge, the device stays certified; k guardians in the subject's tenant revoke it, and an owner revokes its own other device", async () => {
  await revocations(memWorld());
});

// IGNORED, not green: 06 §6 🔒's k guardians, when they share no tenant with each other. Fails today
// ("counted 1 of 2" twice, the device certified): the edge counts only the approvals the caller can
// see, and an approval count over every row needs a SECURITY DEFINER read — a migration (EDGE83
// review finding 2, owner item). Un-ignore with that migration.
Deno.test({
  name:
    "E-06-94 [MemStore] k guardians revoke even when they share no tenant with each other: the subject is in A and B, g1 only in A, g2 only in B, k = 2 — g2's approval in B completes the revocation g1 began in A (IGNORED until the edge can count every approval: EDGE83 finding 2, owner item)",
  ignore: true,
  async fn() {
    await disjointGuardians(memWorld());
  },
});

Deno.test("E-06-95 [MemStore] without the edge, the store itself holds 0022 as PgStore does: rf.may_file_record's answers (active and pending members yes; removed, strangers, unknown tenants no; a memberless tenant only a membership_status), a stranger's insert refused rls, a non-admin's membership not_admin, another book's admin's book role not_admin, a device record that certifies revoke_only, a fellow member's revocation not_revoker", async () => {
  await storeHolds(memWorld());
});
