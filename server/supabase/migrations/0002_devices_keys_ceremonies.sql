-- 03 §2.2 Devices, keys, ceremonies 🔒 — plaintext rows, opaque blobs.
create table devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id),
  pub_ed bytea not null check (octet_length(pub_ed) = 32),
  pub_x bytea not null check (octet_length(pub_x) = 32),
  model text null,
  os text null,
  attestation jsonb null,                                -- designed now, enforced v2 (06 §3); device_integrity flag
  status text not null default 'registered' check (status in
    ('registered','certified','suspended','revoked')),   -- 'certified' set by the server only (ADR 2026-09-05d §2)
  created_at timestamptz not null default now(),
  revoked_at timestamptz null,
  updated_at timestamptz not null default now()
);
create index devices_user_idx on devices (user_id);
create trigger devices_touch before update on devices for each row execute function rf.touch_updated_at();

create table device_certs (
  device_id uuid primary key references devices(id),
  cert bytea not null check (octet_length(cert) = 64),   -- Ed25519 sig over uuid16‖pub_ed‖pub_x‖i64be(issued_at)
  issued_by_device uuid null references devices(id),
  issued_at timestamptz not null,
  umk_key_version int not null default 1,
  updated_at timestamptz not null default now()
);
create trigger device_certs_touch before update on device_certs for each row execute function rf.touch_updated_at();

create table wrapped_keys (
  id uuid primary key,
  kind text not null check (kind in
    ('umk_for_device','bk_for_user','guardian_share','recovery_blob','escrow_blob')),
  user_id uuid not null references users(id),            -- the addressee / subject (03 §2.5)
  device_id uuid null references devices(id),
  book_id uuid null references books(id),
  key_version int not null default 1 check (key_version >= 1),
  share_set_version int null check (share_set_version is null or share_set_version >= 1),
  blob bytea not null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz null,
  updated_at timestamptz not null default now(),
  constraint wrapped_keys_book_kind check ((kind = 'bk_for_user') = (book_id is not null)),
  constraint wrapped_keys_share_version check ((kind = 'guardian_share') = (share_set_version is not null))
);
create index wrapped_keys_user_idx on wrapped_keys (user_id, updated_at);
create index wrapped_keys_book_version_idx on wrapped_keys (book_id, key_version) where kind = 'bk_for_user';
create trigger wrapped_keys_touch before update on wrapped_keys for each row execute function rf.touch_updated_at();

-- Guardian-set HISTORY by share_set_version (ADR 2026-09-06 §2–§3): readers count k-of-n
-- revocation records against the set *at the version the record names*, so every version is kept.
create table guardian_sets (
  subject_user_id uuid not null references users(id),
  share_set_version int not null check (share_set_version >= 1),
  n int not null check (n between 2 and 5),
  k int not null check (k between 1 and n),
  created_at timestamptz not null default now(),
  superseded_at timestamptz null,
  source_record_id uuid null,
  updated_at timestamptz not null default now(),
  primary key (subject_user_id, share_set_version)
);
create trigger guardian_sets_touch before update on guardian_sets for each row execute function rf.touch_updated_at();

create table guardian_set_members (
  subject_user_id uuid not null,
  share_set_version int not null,
  guardian_user_id uuid not null references users(id),
  umk_pub_ed bytea not null check (octet_length(umk_pub_ed) = 32),  -- the guardian UMK as of that version
  wrapped_key_id uuid null references wrapped_keys(id),               -- their guardian_share row
  updated_at timestamptz not null default now(),
  primary key (subject_user_id, share_set_version, guardian_user_id),
  foreign key (subject_user_id, share_set_version) references guardian_sets(subject_user_id, share_set_version)
);
create index guardian_set_members_guardian_idx on guardian_set_members (guardian_user_id);
create trigger guardian_set_members_touch before update on guardian_set_members for each row execute function rf.touch_updated_at();

create table invites (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id),
  invitee_hmac bytea not null,                           -- NO plaintext number (ADR 2026-09-05c §4)
  roles jsonb not null default '[]'::jsonb,
  nonce bytea not null check (octet_length(nonce) = 32),
  status text not null default 'sent' check (status in ('sent','accepted','expired','revoked')),
  expires_at timestamptz not null,
  created_by uuid not null references users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index invites_tenant_idx on invites (tenant_id, updated_at);
create index invites_hmac_idx on invites (invitee_hmac);
create trigger invites_touch before update on invites for each row execute function rf.touch_updated_at();

create table verification_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id),
  subject_user uuid not null references users(id),
  verifier_user uuid not null references users(id),
  method text not null check (method in ('qr_in_person','code_remote','device_link')),
  result text not null check (result in ('verified','mismatch','cancelled')),
  at timestamptz not null default now(),
  source_record_id uuid null,                            -- signed record (ADR 2026-09-05d §7)
  updated_at timestamptz not null default now()
);
create index verification_events_tenant_idx on verification_events (tenant_id, updated_at);
create trigger verification_events_touch before update on verification_events for each row execute function rf.touch_updated_at();

create table recovery_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id),
  candidate_device uuid not null references devices(id),
  state text not null default 'pending' check (state in
    ('pending','waiting_24h','approved','cancelled','expired','completed')),  -- ADR 2026-09-05d §1
  approvals int not null default 0 check (approvals >= 0),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index recovery_requests_user_idx on recovery_requests (user_id, updated_at);
create trigger recovery_requests_touch before update on recovery_requests for each row execute function rf.touch_updated_at();

create table escrow_policies (
  id uuid primary key default gen_random_uuid(),
  member_user uuid not null references users(id),
  head_user uuid not null references users(id),
  book_id uuid not null references books(id),
  blob_ref uuid null references wrapped_keys(id),
  state text not null default 'active' check (state in
    ('active','release_requested','vetoed','released','revoked')),
  release_requested_at timestamptz null,                 -- veto window enforced from this row
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index escrow_policies_member_idx on escrow_policies (member_user, updated_at);
create index escrow_policies_head_idx on escrow_policies (head_user, updated_at);
create trigger escrow_policies_touch before update on escrow_policies for each row execute function rf.touch_updated_at();
