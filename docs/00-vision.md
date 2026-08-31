# 00 — Vision: Rukka Folio

**Tagline (11 §2):** *Every rupee. Accounted for.*

**What:** One app where a person, a family, or a joint family with n businesses records what they actually have — banks, cash, udhaar given and taken, advances — and sees one live position screen. Real double-entry underneath; a paper rokad-vahi on top.

**Who:** Indian households and small/medium business families who today keep a daybook, cashbook, and ledger on paper — starting with our own joint family as pilot users. English + ਪੰਜਾਬੀ + हिन्दी at launch.

**The bets (each one is load-bearing):**
1. **Books, not modes** — individual, family, joint family, business, trust are all the same Book object; the flow never changes, only the count (requirements doc §1).
2. **Zero-knowledge** — the server can mathematically never read the money. Recovery works through the family itself (guardians), not passwords (04, 06).
3. **Six verbs, no jargon** — the user can never build a wrong posting (02 §2).
4. **The 8-second entry** — faster than paper, every day, or nothing else matters (07 §1).
5. **Self-auditing family** — every device recomputes and verifies every close; trust is arithmetic, not hierarchy (02 §8).

**Non-goals (permanent for this product):** invoicing, GST, taxation, statutory filings, inventory, payroll. Registered businesses use Tally et al. for those; we export cleanly and never compete there.

**Success at pilot:** our family runs one full month — entries, approvals, one advance cycle, statement import, month close — with zero paper fallback and zero WhatsApp "what's the balance?" messages.
