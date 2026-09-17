# ADR 2026-09-15 — The API terminates TLS on an origin we hold the key to; the pin stays SPKI and moves to the leaf

**Status: Accepted — owner-directed in session, 15 Sep 2026.** The owner chose the hosting shape, the
domain and the threat-model posture after each option was verified rather than recalled. **No numbered
spec is edited by this ADR**: `05 §1` is 🔒 and the exact edits are named in § Consequences for the owner
to apply on ratification.

Raised because `05 §1`'s own deferral came due. The line says *"⚠️ Pin at the intermediate-CA level for
hosted Supabase; **verify the exact chain** and write the rotation runbook at M4."* M7's transport lane
(`W1`) landed the client half and reported it could not finish the sentence. Verifying the chain — the
step the 🔒 line asked for and which had never been performed — showed the assumption underneath it is
false.

## The evidence ⟦tests: n/a — findings, not behaviour⟧

Every row below was run or fetched in session on 15 Sep 2026, not recalled (CLAUDE.md rule 11).

| Source | What it says | Consequence |
|---|---|---|
| [Supabase — Custom Domains](https://supabase.com/docs/guides/platform/custom-domains) | *"Supabase uses multiple Certificate Authorities (including Let's Encrypt, Google Trust Services and SSL.com) to ensure high availability"*; issuer *"chosen based on availability"* | **Hosted Supabase cannot be pinned.** The intermediate can change CA at any renewal, unannounced. |
| [Google Trust Services FAQ](https://pki.goog/faq/) | applications *"must never hardcode Intermediate or Root Certificate Authorities"* against a rotating provider | confirms the above as the general rule, not a Supabase quirk |
| `dart-sdk/lib/io/secure_socket.dart:226` | `SecureSocket.peerCertificate` yields **one** `X509Certificate` — the leaf | `dart:io` can never satisfy an intermediate pin |
| [flutter/flutter#89124](https://github.com/flutter/flutter/issues/89124) | native pinning config does not apply to Dart calls | Android `network-security-config` `<pin-set>` and iOS `NSPinnedDomains` never see our connections; declarative pinning requires leaving `dart:io` |
| `dart-sdk/lib/_http/http_impl.dart:2684-2701` | when `connectionFactory` is set the SDK uses that socket **instead of** its own `SecureSocket.startConnect` | the observe-then-request gap is closable in pure Dart |
| `dart-sdk/lib/io/secure_socket.dart:196` + `security_context.dart:96,123,147` | `SecureSocket.secureServer`, `usePrivateKeyBytes`, `useCertificateChainBytes`, `setTrustedCertificatesBytes` | a server presenting a **different key per connection** is buildable in a test; `W1`'s *"invisible to any test by construction"* is wrong |
| `openssl` against a live host, in session | whole-cert digest vs SPKI digest differ; serial and validity live inside the cert and change every ~90 days | certificate pinning breaks on renewal even when the key is unchanged |
| [certbot #7361](https://github.com/certbot/certbot/issues/7361) (closed; fix version not visible) | `--reuse-key` was once reported not to preserve the public key | key stability must be **verified empirically**, not assumed |
| `app/pubspec.yaml:30`, `app/lib/bootstrap.dart:100` | `crypto: ^3.0.7` present; `crypto.sha256` wired; no `UnsupportedError` remains | `W1`'s open item *"add a SHA-256 source"* is **already closed**; the ⚠️ SPEC comment at `bootstrap.dart:86` is stale |
| `09 §4` line 55 (owner-locked) | release lane carries `--obfuscate --split-debug-info` and never the pinning-off define | an **unimplemented** 🔒 requirement: neither flag appears in `scripts/` or `.github/workflows/` |

## Rulings

### 1. The API terminates TLS on an origin whose private key we hold ⟦tests: n/a — deployment topology; the pin behaviour it enables is ruled in §2⟧

`api.rukkafolio.com` resolves to a small origin **in the same region as the Supabase project**, which
terminates TLS with our own key pair and reverse-proxies to `<ref>.supabase.co`. Supabase's custom-domain
add-on is **not** used and is not needed.

- **Why not hosted Supabase (rejected).** A pin is only meaningful over a key whose rotation we control.
  Supabase rotates across three CAs by availability, so neither a leaf nor an intermediate pin is stable;
  combined with this line's own *"hard fail with no fallback and no override"*, pinning there is an
  outage generator, and pinning the union of three CAs' intermediates would be a weak pin besides.
- **Why not Cloudflare custom certificates (rejected).** It gives us the key, but only on the Business
  plan; the cost is not justified pre-pilot. Advanced Certificate Manager is available on every plan and
  lets the CA be chosen, but Cloudflare still holds the key, so it buys a fixed-CA intermediate pin, not
  a leaf pin.
- **Cost of what was chosen, stated honestly:** an origin we own — patching, uptime, renewal — and one
  more hop in the sync path, which is why the region must match. `05 §hot set` traffic is request/response
  only (no WebSocket, no Realtime: the client's whole surface is `sync-push`, `sync-pull`, `sync-meta`,
  `sync-meta/records`, `sync-meta/invites`, `sync-meta/invites/accept` — `http_transport.dart:52-67`), so a
  plain HTTP reverse proxy suffices.

### 2. The pinned object stays the **key**; the pinned **level** moves from intermediate to leaf ⟦tests: F1-05-42 @M7, F1-05-41 @M7⟧

- **Unchanged and still owner-locked:** `05 §1`'s *"the client pins the **SPKI hashes** … key, not certificate — with
  at least two pins (current + backup)"*. Certificate pinning is not merely worse here, it is **structurally
  incapable** of satisfying that sentence: a backup pin must be shipped for a key we have not yet rotated
  to, and a certificate for that key does not exist to be hashed. SPKI pinning ships the backup key's hash
  years early. ⟦tests: F1-05-41 @M7⟧
- **Changed:** the ⚠️ instruction *"pin at the intermediate-CA level"* was written for a host whose leaf key
  we do not hold. Under ruling 1 we hold it, so the pin is over **our own leaf's SPKI**, kept stable across
  renewals by `certbot --reuse-key`. Two pins ship from the first hosted build: the live key and an offline
  backup key pair generated at the same time. ⟦tests: F1-05-42 @M7⟧
- The two axes are independent and must not be conflated: *what* is hashed (certificate · **key** · CA) and
  *which* certificate in the chain (**leaf** · intermediate · root). This ADR changes only the second.

### 3. The pin is checked on the socket that carries the request ⟦tests: F1-05-35 @M7, F1-05-36 @M7⟧

`IoTlsChainSource` today opens its **own** probe handshake; the request then travels on `package:http`'s
connection. A host may present a pinned key to the probe and another to the request. The fix is
`HttpClient.connectionFactory` returning `SecureSocket.startConnect(...)`: the socket whose
`peerCertificate` we pin **is** the socket the request rides. Pure Dart, both platforms, no new dependency
in the security path. `SpkiPins`, `TlsChainSource` and every existing test keep their shape — only the
source of the chain changes.

Chain validation is not weakened: with `connectionFactory` set the SDK no longer passes its own
`badCertificateCallback`, so the factory performs ordinary CA validation itself. **Pinning is in addition
to chain validation, never instead of it.**

### 4. `rukkafolio.com` is primary; `rukkafolio.app` redirects to it ⟦tests: n/a — registrar and DNS configuration⟧

Brand, site, invite deep links, support and `api.` all live on `.com`; `.app` is held defensively and 301s
to `.com`. `.com` is the mental model of the audience this app is for — joint families and their businesses,
in Punjabi and Hindi as much as English — and an unfamiliar TLD in an invite link shared over WhatsApp costs
trust that a money app cannot spend. The one property `.app` has by construction, TLD-wide HSTS preload, is
obtainable for `.com` by submitting to `hstspreload.org`, which the runbook schedules.

### 5. Client hardening is targeted at the network attacker, not maximised ⟦tests: H-09-2 @M14⟧

Pinning defends an attacker with **no code execution on the phone** — hostile WiFi, a compromised or coerced
CA, a corporate MITM proxy. Bypassing a pin requires device control, and against that attacker no
client-side control is decisive. The scaling factor is architectural: this app is zero-knowledge (`03`
preamble (owner-locked), *"The server stores envelopes it cannot read"*), so a bypassed pin exposes session tokens and
sync metadata — **not the ledger**, which is encrypted under keys the server never holds.

- **Adopted:** SPKI pinning per rulings 2–3 · `--obfuscate --split-debug-info` on the release lane
  (already required by `09 §4` and not implemented — see § Consequences) · Certificate Transparency
  monitoring for `rukkafolio.com`, which defends precisely the CA-compromise case the pin addresses.
- **Declined — native pinning in place of Dart.** It buys nothing against the network attacker (there is no
  code execution to leverage) and costs native code on two platforms. It would also re-impose the
  intermediate-pin problem ruling 1 removes. The commonly cited Flutter bypass patches `libflutter.so`'s
  BoringSSL chain verifier; our check is an **application-level SPKI comparison** after reading the
  presented certificate (`http_transport.dart:389-396`), which that patch does not defeat, whereas native
  pinning hooks well-known system symbols for which canned scripts have existed for years.
- **Declined — RASP.** A commercial SDK with deep runtime access and vendor telemetry, inside an app whose
  rule 4 forbids financial data reaching analytics at all. A confidentiality regression bought against an
  attacker who already owns the device.
- **Deferred to M14 under MASVS L2+R**, which `PLAN.md` already schedules: runtime integrity checks and
  modified-device detection. `09 §4`'s existing ruling stands — the rooted device gets a **notice and the
  app keeps working**, never a block.

### 6. The pin is tested against a real handshake, a hostile server, and a renewal ⟦tests: F1-05-32 @M7, F1-05-33 @M7, F1-05-34 @M7, F1-05-35 @M7, F1-05-36 @M7, F1-05-37 @M7, F1-05-38 @M7, F1-05-39 @M7, F1-05-40 @M7, F1-05-41 @M7, F1-05-42 @M7, D-05-36 @M7, D-05-37 @M7⟧

Today every pin test injects its inputs: no test opens a socket, `secureSocketProbe` has none at all, and
the pin has never matched a real certificate. Fixtures are generated by `openssl` in `setUpAll` into a temp
directory — **no private key is committed**, keeping `09 §4`'s secret scan clean.

| id | asserts |
|---|---|
| `F1-05-32` | `secureSocketProbe` against a live TLS server returns the presented leaf; its SPKI digest equals a pin computed independently |
| `F1-05-33` | matching pin → request completes against a real handshake |
| `F1-05-34` | wrong pin → refused **and the server recorded zero requests** — refusing after sending is not refusing |
| `F1-05-35` | server presents key A to the first connection and B to the rest: refused, and no request reaches the B connection. **Red before ruling 3, green after** |
| `F1-05-36` | same server, pinned key on every connection → succeeds; proves `F1-05-35` is not "two connections always fail" |
| `F1-05-37` | probe throws → `null` → refused |
| `F1-05-38` | injected digest of wrong length → refused. A digest over nothing must never become a pin |
| `F1-05-39` | certificate truncated mid-SPKI → refused |
| `F1-05-40` | a failed probe is not cached — failure then success succeeds |
| `F1-05-41` | pins {A, B}, server presents **B** → accepted: the two-pin rotation property `05 §1` requires |
| `F1-05-42` | leaf A′ — same key, new serial and validity — yields an **identical** pin and passes: ruling 2 as behaviour, and what makes `--reuse-key` safe |
| `D-05-36` | the pin check fires on **every** route, not one |
| `D-05-37` | `localDevDisabled` is the only skip and is unreachable with a non-empty pin set |

**Out of reach of any Dart test, and recorded as such:** a real MITM proxy against a release build on a
device (`H-09-2`, M14, RC/release lane); Frida and binary-patch resistance (MASVS L2+R decompile pass); and
the production certificate itself, which cannot exist until the origin does — the runbook carries a manual
gate for it instead.

### 7. A pin failure surfaces as *Needs attention*, never as `Offline` ⟦tests: D-05-38, D-05-39⟧

`05 §9` lists five states and says *"No other states"*. That sentence is not disturbed: a pin failure is
**not** a sixth state. It becomes a new **reason** inside the existing *Needs attention* → Inbox state,
alongside rejections, quarantines and clock warnings — `pin_failed`.

- **Why not `Offline`, which is what ships today.** `Offline` instructs the user to wait for a network.
  A pin failure may be an attacker on the network right now, and waiting is the one thing that does not
  help. Telling a user their phone has no signal when the truth is that something is impersonating their
  server is a false statement from the app, not merely an unhelpful one.
- **Why not a sixth state.** It would amend an owner-locked sentence, and it is not needed: the Inbox
  exists precisely to carry reasons the five states cannot express.
- **Mechanism.** `TransportFailure` gains a `PinFailed` case (`transport.dart`); it is a new *failure
  cause*, not a new *status* — it maps into `NeedsAttention` with the `pin_failed` reason. `05 §9`'s
  reason list gains `pin_failed` in the same commit.
- The Inbox row must say what happened in the vocabulary of `01 §1.3` — that the app could not confirm it
  was talking to the real Rukka Folio server and has stopped rather than risk it — and must not offer a
  retry that bypasses anything, because there is nothing to bypass.

## Consequences

**For the owner to apply on ratification — `docs/05-sync-protocol.md` §1, line 13 (owner-locked):**
- replace *"⚠️ Pin at the intermediate-CA level for hosted Supabase; verify the exact chain and write the
  rotation runbook at M4."* with a statement that the API terminates on an origin we hold the key to and the
  pin is over **our leaf's SPKI**, with `docs/ops/tls-pinning-runbook.md` named as the runbook and this ADR
  cited. The rest of the line — SPKI not certificate, two pins minimum, hard fail with no override, local-dev
  the only exemption — is **unchanged**.
- the line's `⟦tests: …⟧` marker gains the ruling-6 ids.

**Code (M7):** `connectionFactory` replaces the probe socket in `IoTlsChainSource` (ruling 3); the stale
⚠️ SPEC comment at `bootstrap.dart:86` is deleted — `crypto` landed and `spkiPins()` no longer throws.

**CI:** `09 §4`'s release-lane clauses are implemented now, not at M14 — a `scripts/` assertion that the
release lane carries `--obfuscate --split-debug-info` and never the pinning-off define.

**Ops:** `docs/ops/tls-pinning-runbook.md` lands with this ADR.

## Open

- **The origin is not built.** Until it is, no hosted build can be configured — `spkiPins()` fails closed by
  construction, which is the intended state, not a gap.
- **`--reuse-key` is trusted but unverified** (certbot #7361). The runbook's first renewal is a gate: force
  a renewal, recompute the pin, refuse to ship if it moved.
- **Certificate Transparency monitoring** has no owner or tooling yet.
