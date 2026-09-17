# TLS pinning runbook — `api.rukkafolio.com`

Procedure for the pin `05 §1` requires. Decisions and their evidence live in
**ADR 2026-09-15**; this file is how the decisions are carried out. Not a spec —
when this file and `05 §1` disagree, `05 §1` wins.

**The rule everything here serves:** a pin is only safe over a key whose rotation we control.
We hold the key. `05 §1` makes a pin failure a hard fail with no fallback and no override, so
every step below is written to fail closed — a step that cannot be completed must stop the
release, never relax the pin.

---

## 0. Before you start

| | |
|---|---|
| Domain | `rukkafolio.com` (primary) · `rukkafolio.app` → 301 |
| API host | `api.rukkafolio.com` |
| TLS terminates on | **our origin**, reverse-proxying to `<ref>.supabase.co` |
| Origin region | **must match the Supabase project's region** — check it first, or every sync pays a double hop |
| Pinned object | SHA-256 of the **leaf's SubjectPublicKeyInfo** — the key, not the certificate |
| Pins shipped | **two**: live key + an offline backup key pair |

---

## 1. The key pair — generate once, never regenerate

This key *is* the pin. It outlives certificates. Back it up before anything else touches it.

```bash
# Live key
openssl ecparam -genkey -name prime256v1 -out api-live.key

# Backup key — generated NOW, kept offline, never installed until a rotation
openssl ecparam -genkey -name prime256v1 -out api-backup.key
```

Store both outside the repo. `api-backup.key` never goes on the origin until § 6.

---

## 2. Certificate issuance, with the key held fixed

Caddy on the origin gives auto-TLS, auto-renewal and the HTTP→HTTPS redirect with near-zero config.
Whatever issues the certificate, **the key must be reused at every renewal** or the pin moves and every
installed app hard-fails.

With certbot:

```bash
certbot certonly --key-type ecdsa --reuse-key -d api.rukkafolio.com
# renewals:
certbot renew --reuse-key
```

> ⚠️ `--reuse-key` is the documented mechanism but has a defect history (certbot #7361, closed, fix
> version not recorded). It is **verified in § 5, not trusted.**

If Caddy manages certificates instead, confirm its key-reuse behaviour the same way — by measurement,
in § 5.

---

## 3. Computing a pin

Use this. **Do not use `csplit … '{*}'`** — that is a GNU extension, macOS rejects it, and the pipeline
then emits the SHA-256 of *empty input* (`47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=`), which looks
exactly like a valid pin. The length guard below exists for that reason.

### From a key you hold (the normal case)

```bash
openssl pkey -in api-live.key -pubout -outform der \
  | openssl dgst -sha256 -binary | base64
```

### From a live host (verification, and reading someone else's chain)

```bash
#!/bin/bash
set -euo pipefail
HOST=api.rukkafolio.com

openssl s_client -connect "$HOST:443" -servername "$HOST" -showcerts \
    </dev/null 2>/dev/null > chain.pem
[ "$(grep -c 'BEGIN CERTIFICATE' chain.pem)" -ge 1 ] || { echo "no chain captured"; exit 1; }

rm -f cert-*.pem
awk '/-----BEGIN CERTIFICATE-----/{n++} n>0{print > ("cert-" n ".pem")}' chain.pem

for f in cert-*.pem; do
  echo "=== $f"
  openssl x509 -in "$f" -noout -subject -issuer
  der=$(openssl x509 -in "$f" -pubkey -noout | openssl pkey -pubin -outform der | wc -c | tr -d ' ')
  [ "$der" -gt 0 ] || { echo "EMPTY SPKI — refusing to emit a pin"; exit 1; }
  openssl x509 -in "$f" -pubkey -noout | openssl pkey -pubin -outform der \
    | openssl dgst -sha256 -binary | base64
done
```

`cert-1.pem` is the leaf — subject `api.rukkafolio.com`. **That is the one we pin.**

---

## 4. Shipping the pins

```
--dart-define=RF_API_BASE=https://api.rukkafolio.com/functions/v1/
--dart-define=RF_SPKI_PINS=<live pin>,<backup pin>
```

An empty `RF_SPKI_PINS` selects `SpkiPins.localDev()` — the only build permitted to run unpinned, and
the only one that may talk to `127.0.0.1`. The release lane asserts it never ships empty, and never
ships without `--obfuscate --split-debug-info` (`09 §4`).

---

## 5. Gates — run these before any hosted build ships

1. **The key survived a renewal.** The whole design rests on this and on nothing else.
   ```bash
   # pin before
   openssl pkey -in api-live.key -pubout -outform der | openssl dgst -sha256 -binary | base64
   certbot renew --force-renewal --reuse-key
   # pin after — must be byte-identical
   openssl pkey -in api-live.key -pubout -outform der | openssl dgst -sha256 -binary | base64
   ```
   **If it moved, stop.** `--reuse-key` is not working on this version and no pinned build may ship
   until it does.

2. **The live host presents the pinned key.** § 3's host script against `api.rukkafolio.com`; the
   `cert-1.pem` pin must equal the live pin in `RF_SPKI_PINS`.

3. **The backup pin is for a key that exists** and is stored offline, separately from the live key.

4. **A wrong pin is actually refused.** Build with a deliberately corrupted pin and confirm sync fails
   closed rather than falling back.

---

## 6. Rotation — without an outage

Possible only because two pins ship. Never skip a step; the order is what prevents the outage.

1. Confirm the **backup** pin is already in `RF_SPKI_PINS` of every build in the field. If it is not,
   rotation will lock users out — ship the backup pin first and wait for adoption.
2. Install `api-backup.key` on the origin and issue a certificate for it (`--reuse-key` on the new key).
3. Verify the live host now presents the backup key (§ 3), and that clients keep syncing — they match
   the second pin.
4. Promote: `api-backup.key` becomes the live key.
5. Generate a **new** backup key pair (§ 1), compute its pin, and ship it in the next release.
6. Only once that release has adoption may the retired key's pin be dropped.

**Emergency key compromise.** There is no override — that is the design. Rotate to the backup key
(steps 2–4), which every installed build already trusts. If both keys are compromised, a new build is
the only path and users on old builds cannot sync until they update.

---

## 7. Domain and DNS

- `api.rukkafolio.com` → our origin. If Cloudflare fronts the zone, this record must be
  **DNS-only (grey cloud)** — a proxied record means Cloudflare terminates TLS with *its* key and the
  pin no longer describes what the phone talks to.
- `rukkafolio.app` → 301 to `rukkafolio.com`. Cloudflare redirect rules require the hostname be
  proxied, so a placeholder proxied record is needed for the redirect to fire.
- **HSTS preload** for `rukkafolio.com` once the site is live: `max-age` ≥ `31536000`, plus
  `includeSubDomains` and `preload`, HTTP→HTTPS on the same host, then submit at `hstspreload.org`.
  Note before enabling: it binds **every** subdomain including internal ones, `www` must serve HTTPS
  if a `www` record exists at all, and removal takes months.

---

## 8. Certificate Transparency monitoring

Pinning stops a bad certificate from being *used* against our app; CT monitoring tells us one was
*issued*. Register `rukkafolio.com` for CT notifications so unexpected issuance surfaces as an alert.
Owner unassigned — see ADR 2026-09-15 § Open.

---

## 9. What this runbook does not cover

- A real MITM proxy against a release build on a device — `H-09-2`, M14, RC/release lane.
- Resistance to Frida or binary patching — MASVS L2+R decompile pass, M14.
- The automated pin tests (`F1-05-32…42`, `D-05-36/37`) — they live in the suite, not here.
