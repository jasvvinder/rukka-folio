# Independent reference used to produce the B-04-73 known-answer vector
# (packages/core_crypto/test/shamir_test.dart). Deliberately a *second*
# implementation of GF(256) Shamir in this repo: table-free Russian-peasant
# multiply with the 0x11b reduction, brute-force inverse, direct Lagrange at
# x = 0 — written without consulting shamir.dart's loops. It is not a
# third-party audited vector; pasting one in from libgfshare or Vault before
# the external review (ADR 2026-09-06 §1) would still be worth doing.
#
# Run: python3 shamir_ref.py — prints the five shares and the secret, and
# self-checks every 3-subset. Synthetic bytes only; never a real key.

def gmul(a, b):
    p = 0
    for _ in range(8):
        if b & 1:
            p ^= a
        hi = a & 0x80
        a = (a << 1) & 0xFF
        if hi:
            a ^= 0x1B
        b >>= 1
    return p

def ginv(a):
    # brute force: the only 'independent' way
    for x in range(1, 256):
        if gmul(a, x) == 1:
            return x
    raise ValueError

def eval_poly(coeffs, x):  # coeffs[0] = secret byte
    y = 0
    for c in reversed(coeffs):
        y = gmul(y, x) ^ c
    return y

def combine(points):  # [(x, [y bytes])]
    m = len(points)
    L = len(points[0][1])
    out = []
    for b in range(L):
        acc = 0
        for i, (xi, yi) in enumerate(points):
            num, den = 1, 1
            for j, (xj, _) in enumerate(points):
                if i == j: continue
                num = gmul(num, xj)
                den = gmul(den, xi ^ xj)
            acc ^= gmul(yi[b], gmul(num, ginv(den)))
        out.append(acc)
    return bytes(out)

# FIPS-197 checks of the field itself
assert gmul(0x57, 0x83) == 0xC1 and gmul(0x57, 0x13) == 0xFE and gmul(0x53, 0xCA) == 0x01

# Fixed synthetic 16-byte secret and fixed coefficients (3-of-5): coefficient of
# x^1 and x^2 for byte j are fixed deterministic values so the vector is frozen.
secret = bytes([0x00, 0x01, 0x7f, 0x80, 0xff, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb])
k, n = 3, 5
coeffs = [[secret[j], (j * 29 + 7) & 0xff, (j * 113 + 91) & 0xff] for j in range(len(secret))]
shares = [(x, [eval_poly(coeffs[j], x) for j in range(len(secret))]) for x in range(1, n + 1)]
for x, ys in shares:
    print(f"share {x}: " + ", ".join(f"0x{y:02x}" for y in ys))
# self-check: every 3-subset reconstructs
import itertools
for sub in itertools.combinations(shares, k):
    assert combine(list(sub)) == secret
# a 2-subset does not
assert combine(shares[:2]) != secret
print("secret : " + ", ".join(f"0x{b:02x}" for b in secret))
print("OK")
