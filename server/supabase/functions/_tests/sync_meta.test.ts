// sync-meta (05 §5 🔒; ADR 2026-09-05b §1; ADR 2026-09-06 §3). Ids E-05-9, E-05-10.
import { assert, assertEquals, assertExists } from "@std/assert";
import { b64url } from "../_shared/bytes.ts";
import { handler as meta } from "../sync-meta/index.ts";
import { body, edKeypair, get, member, post, rig, signedRecord } from "./harness.ts";

Deno.test("E-05-9 meta: tables, per-table cursors, signed records after seq, guardian-set history by share_set_version, min-version", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  const book = r.db.addBook(tenant);
  const admin = await member(r, tenant, book, "admin");
  const peer = await member(r, tenant, book, "member");
  r.db.addWrappedKey({ kind: "bk_for_user", user_id: admin.user, book_id: book, key_version: 1 });
  r.db.addWrappedKey({ kind: "bk_for_user", user_id: peer.user, book_id: book, key_version: 1 });
  r.db.device_certs.push({
    device_id: admin.device.id,
    cert: new Uint8Array(64),
    issued_by_device: null,
    issued_at: r.clock.now,
    umk_key_version: 1,
    updated_at: r.clock.now,
  });
  const g1 = await edKeypair(), g2 = await edKeypair(), g3 = await edKeypair();
  r.db.addGuardianSet(admin.user, 1, 2, [{ user_id: peer.user, umk_pub_ed: g1.pub }, {
    user_id: r.db.addUser().id,
    umk_pub_ed: g2.pub,
  }]);
  r.db.addGuardianSet(admin.user, 2, 2, [{ user_id: peer.user, umk_pub_ed: g1.pub }, {
    user_id: r.db.addUser().id,
    umk_pub_ed: g3.pub,
  }, { user_id: r.db.addUser().id, umk_pub_ed: g2.pub }]);
  r.db.config.set("min_client_version.sync", "0.1.0");

  let first: any;
  await t.step(
    "bootstrap page carries every table the engine consumes, own keys only",
    async () => {
      first = await body(await meta(get("/sync-meta", { token: admin.token }), r.deps));
      for (
        const k of [
          "store_epoch",
          "signed_records",
          "wrapped_keys",
          "devices",
          "device_certs",
          "memberships",
          "book_roles",
          "guardian_sets",
          "invites",
          "verification_events",
          "subscriptions",
          "entitlement_tokens",
          "min_client_version",
          "has_more",
          "next",
        ]
      ) {
        assert(k in first, k);
      }
      assertEquals(first.memberships.length, 2);
      assertEquals(first.book_roles.map((x: any) => x.role).sort(), ["admin", "member"]);
      assertEquals(first.devices.length, 2, "fellow members' devices are visible");
      assertEquals(first.wrapped_keys.length, 1, "only keys addressed to me");
      assertEquals(first.wrapped_keys[0].user_id, admin.user);
      assertEquals(first.device_certs[0].device_id, admin.device.id);
      assertEquals(typeof first.device_certs[0].cert.signature, "string");
      assertEquals(first.min_client_version.sync, "0.1.0");
      assertEquals(first.has_more, false, "bootstrap fits one page");
      assertExists(first.next, "resume cursor always present");
      assertEquals(
        first.memberships[0].id,
        `${first.memberships[0].tenant_id}:${first.memberships[0].user_id}`,
      );
    },
  );
  await t.step(
    "guardian history keeps every share_set_version with its own k and members",
    async () => {
      assertEquals(first.guardian_sets.map((s: any) => s.share_set_version), [1, 2]);
      assertEquals(first.guardian_sets[1].n, 3);
      assertEquals(first.guardian_sets[1].guardian_user_ids.length, 3);
      assertEquals(first.guardian_sets[0].guardians[0].umk_pub_ed, b64url.enc(g1.pub));
      // a tenant-mate can ask for the subject's history — needed to count the k records (ADR 2026-09-06 §3)
      const theirs = await body(
        await meta(get(`/sync-meta?subject_user_id=${admin.user}`, { token: peer.token }), r.deps),
      );
      assertEquals(theirs.guardian_sets.length, 2);
    },
  );
  await t.step("resuming from the cursor yields only changes since", async () => {
    const again = await body(
      await meta(get(`/sync-meta?after=${first.next}`, { token: admin.token }), r.deps),
    );
    assertEquals(again.memberships, []);
    assertEquals(again.devices, []);
    r.clock.now = new Date(r.clock.now.getTime() + 1000);
    r.db.addWrappedKey({ kind: "bk_for_user", user_id: admin.user, book_id: book, key_version: 2 });
    const later = await body(
      await meta(get(`/sync-meta?after=${first.next}`, { token: admin.token }), r.deps),
    );
    assertEquals(later.wrapped_keys.length, 1);
    assertEquals(later.wrapped_keys[0].key_version, 2);
    assertEquals(
      (await meta(get("/sync-meta?after=not-a-cursor", { token: admin.token }), r.deps)).status,
      400,
    );
  });
  await t.step("more than a page sets `has_more`; following `next` drains", async () => {
    for (let i = 0; i < 250; i++) {
      r.db.addWrappedKey({
        kind: "umk_for_device",
        user_id: admin.user,
        device_id: admin.device.id,
      });
    }
    const p1 = await body(await meta(get("/sync-meta", { token: admin.token }), r.deps));
    assertEquals(p1.has_more, true);
    assertExists(p1.next);
    assertEquals(p1.wrapped_keys.length, 200);
    const p2 = await body(
      await meta(get(`/sync-meta?after=${p1.next}`, { token: admin.token }), r.deps),
    );
    assertEquals(p2.has_more, false);
    assertExists(p2.next);
    assertEquals(p1.wrapped_keys.length + p2.wrapped_keys.length, 252);
  });
  await t.step("OTP-only (uncertified) device sees only itself (ADR 05d §2)", async () => {
    const u = await member(r, tenant, book, "member", { status: "registered" });
    const m = await body(await meta(get("/sync-meta", { token: u.token }), r.deps));
    assertEquals(m.memberships, []);
    assertEquals(m.book_roles, []);
    assertEquals(m.devices.map((d: any) => d.id), [u.device.id]);
    assertEquals(m.guardian_sets, []);
    assertEquals(m.signed_records, []);
  });
});

Deno.test("E-05-10 meta/records: signed records are verified under the device key, stored once, projected; the server invents none", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  const book = r.db.addBook(tenant);
  const admin = await member(r, tenant, book, "admin");
  const newbie = r.db.addUser().id;
  const send = (m: Awaited<ReturnType<typeof member>>, records: unknown[]) =>
    meta(post("/sync-meta/records", { records }, { token: m.token }), r.deps);

  await t.step(
    "admin's membership_status record projects a membership row and is acked with seq",
    async () => {
      const rec = await signedRecord(admin, tenant, "membership_status", {
        user_id: newbie,
        status: "active",
      });
      const res = await body(await send(admin, [rec.wire]));
      assertEquals(res.results[0].result, "acked");
      assertExists(res.results[0].seq);
      const row = r.db.memberships.find((m) => m.user_id === newbie)!;
      assertEquals(row.status, "active");
      assertEquals(row.source_record_id, rec.row.id, "row points at the record that made it");
      const replay = await body(await send(admin, [rec.wire]));
      assertEquals(replay.results[0].result, "acked");
      assertEquals(replay.results[0].seq, res.results[0].seq);
      assertEquals(r.db.signed_records.length, 1);
    },
  );
  await t.step(
    "record from a non-admin is stored (it is a signed fact) but refused for projection",
    async () => {
      const peer = await member(r, tenant, book, "member");
      const rec = await signedRecord(peer, tenant, "book_role", {
        book_id: book,
        user_id: newbie,
        role: "viewer",
      });
      const res = await body(await send(peer, [rec.wire]));
      assertEquals(res.results[0].result, "rejected:unauthorized");
      assertEquals(r.db.book_roles.some((x) => x.user_id === newbie), false);
    },
  );
  await t.step(
    "tampered payload or foreign signature → rejected:shape author_sig; wrong author → author_device_id",
    async () => {
      const rec = await signedRecord(admin, tenant, "book_role", {
        book_id: book,
        user_id: newbie,
        role: "viewer",
      });
      const tampered = {
        ...rec.wire,
        payload_json: b64url.enc(
          new TextEncoder().encode(
            JSON.stringify({ book_id: book, user_id: newbie, role: "admin" }),
          ),
        ),
      };
      const res = await body(await send(admin, [tampered]));
      assertEquals(res.results[0], {
        id: rec.row.id,
        result: "rejected:shape",
        check: "author_sig",
      });
      const other = await member(r, tenant, book, "member");
      const res2 = await body(await send(other, [rec.wire]));
      assertEquals(res2.results[0].check, "author_device_id");
    },
  );
  await t.step("money in a record is integer paise or the record is refused", async () => {
    const rec = await signedRecord(admin, tenant, "book_role", {
      book_id: book,
      user_id: newbie,
      role: "operator",
      auto_post_limit_paise: 1250.5,
    });
    const res = await body(await send(admin, [rec.wire]));
    assertEquals(res.results[0].result, "rejected:shape");
    const ok = await signedRecord(admin, tenant, "book_role", {
      book_id: book,
      user_id: newbie,
      role: "operator",
      auto_post_limit_paise: "125000",
    });
    const res2 = await body(await send(admin, [ok.wire]));
    assertEquals(res2.results[0].result, "acked");
    const pulled = await body(await meta(get("/sync-meta", { token: admin.token }), r.deps));
    const role = pulled.book_roles.find((x: any) => x.user_id === newbie);
    assertEquals(role.limits.auto_post_limit_paise, 125000);
    assertEquals(
      pulled.signed_records.length,
      r.db.signed_records.length,
      "records come back with their seq",
    );
    assertEquals(typeof pulled.signed_records[0].seq, "number");
  });
  await t.step("uncertified device cannot author a record", async () => {
    const u = await member(r, tenant, book, "admin", { status: "registered" });
    const rec = await signedRecord(u, tenant, "designation", { user_id: newbie, label: "Munshi" });
    const res = await body(await send(u, [rec.wire]));
    assertEquals(res.results[0].result, "rejected:unauthorized");
  });
  await t.step(
    "k-of-n device revocation: 1 of 2 counted, the 2nd flips the row (ADR 2026-09-06 §3)",
    async () => {
      const subject = await member(r, tenant, book, "member");
      const gA = await member(r, tenant, book, "member");
      const gB = await member(r, tenant, book, "member");
      r.db.addGuardianSet(subject.user, 1, 2, [{ user_id: gA.user, umk_pub_ed: gA.keys.pub }, {
        user_id: gB.user,
        umk_pub_ed: gB.keys.pub,
      }]);
      const payload = {
        revoked_device_id: subject.device.id,
        subject_user_id: subject.user,
        share_set_version: 1,
      };
      const a = await body(
        await send(gA, [(await signedRecord(gA, tenant, "device_revocation", payload)).wire]),
      );
      assertEquals(a.results[0].result, "acked");
      assertEquals(
        r.db.devices.get(subject.device.id)!.status,
        "certified",
        "one guardian is not enough",
      );
      const b = await body(
        await send(gB, [(await signedRecord(gB, tenant, "device_revocation", payload)).wire]),
      );
      assertEquals(b.results[0].result, "acked");
      assertEquals(r.db.devices.get(subject.device.id)!.status, "revoked");
      const stranger = await member(r, tenant, book, "member");
      const s = await body(
        await send(stranger, [
          (await signedRecord(stranger, tenant, "device_revocation", payload)).wire,
        ]),
      );
      assertEquals(s.results[0].result, "rejected:unauthorized");
    },
  );
});
