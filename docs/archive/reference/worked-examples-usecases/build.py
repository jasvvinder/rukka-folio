#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Rukka Folio — use-case worked examples, FY 2025-26 (01 Apr 2025 – 31 Mar 2026).

Generator for docs/reference/worked-examples/usecases/.  Python 3 standard library only.
Every amount is an integer number of paise; no float ever touches money.  The script is
deterministic: it reads no clock, no environment, uses no randomness, and resolves every
path relative to its own location, so re-running it regenerates every file byte-for-byte.

Outputs (beside this script):
  <slug>.md / <slug>.html / <slug>.pdf   one per use case — the PRINTED report, in the user's plain words
                                          (ADR 2026-10-12 §2): no engine class, verb id, rule reference,
                                          ⚠️ note or generator check appears in it; `plain_lint` refuses one that does
  <slug>.tech.md                          the technical companion: classes, kinds, refs, states, rules, ⚠️ SPEC, checks
  README.md / README.html / README.pdf    reading guide, class mapping, ⚠️ SPEC list, limits
  fixtures.json                           machine-readable books, accounts, vouchers, locks, counts

Usage:  python3 build.py [--no-pdf] [--chrome PATH]

Sources (precedence newest ADR > 02 > reference): docs/02-ledger-rules.md §1–§10;
docs/reference/financial-accounting-standards.md §1–§2, §7–§9; docs/archive/reference/accounting-audit-errata.md;
ADRs 2026-09-05e, 2026-09-09b, 2026-09-09c, 2026-09-09d, 2026-09-13 §4, 2026-09-14b, 2026-09-24b §9,
2026-10-07b, 2026-10-10b §4, 2026-10-10c, 2026-09-03 (gollak), 2026-10-08 (joint fund).
"""
import os
import sys
import json
import re
import hashlib
import subprocess
from datetime import date, timedelta
from collections import OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
FY_START = date(2025, 4, 1)
FY_END = date(2026, 3, 31)
NEXT_FY_START = date(2026, 4, 1)
FY_LABEL = "FY 2025-26"
NEXT_FY_LABEL = "FY 2026-27"
DEFAULT_CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
ADVANCE_WARN_DAYS = 15   # 02 §7 reminder default N (15/30)

MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


# ----------------------------------------------------------------------------------------------
# Money and date helpers — integer paise throughout
# ----------------------------------------------------------------------------------------------
def R(rupees, paise=0):
    """Rupees (+ optional paise) → integer paise."""
    assert isinstance(rupees, int) and isinstance(paise, int)
    return rupees * 100 + paise


def indian(n):
    s = str(n)
    if len(s) <= 3:
        return s
    last3, rest = s[-3:], s[:-3]
    parts = []
    while len(rest) > 2:
        parts.insert(0, rest[-2:])
        rest = rest[:-2]
    if rest:
        parts.insert(0, rest)
    return ",".join(parts) + "," + last3


def fmt(p):
    """Absolute amount, Indian grouping, paise only when non-zero."""
    p = abs(p)
    r, ps = divmod(p, 100)
    return indian(r) + (".%02d" % ps if ps else "")


def fmt_signed_side(p):
    """(amount text, side) for a signed balance: + = Dr, − = Cr, 0 = '—'."""
    if p == 0:
        return "0", "—"
    return fmt(p), ("Dr" if p > 0 else "Cr")


def rs(p):
    return "₹" + fmt(p)


def d(y, m, dd):
    return date(y, m, dd)


def fdate(dt):
    return "%02d %s %d" % (dt.day, MONTHS[dt.month - 1], dt.year)


def month_key(dt):
    return "%04d-%02d" % (dt.year, dt.month)


def month_label(key):
    y, m = key.split("-")
    return "%s %s" % (MONTHS[int(m) - 1], y)


def month_end(dt):
    nxt = date(dt.year + (dt.month == 12), (dt.month % 12) + 1, 1)
    return nxt - timedelta(days=1)


def fy_months():
    out = []
    y, m = 2025, 4
    for _ in range(12):
        out.append("%04d-%02d" % (y, m))
        m += 1
        if m == 13:
            y, m = y + 1, 1
    return out


def round_half_up(num, den):
    """num/den rounded half-up to an integer; both non-negative integers."""
    assert num >= 0 and den > 0
    return (2 * num + den) // (2 * den)


def split_by_ratio(total, weights):
    """02 §7.1 rounding rule: floor(total × w ÷ Σw) each; remainder to the largest weight,
    ties to the earliest-listed (earliest-created) partner.  Works for negative totals (loss)."""
    sw = sum(weights)
    sign = 1 if total >= 0 else -1
    t = abs(total)
    shares = [(t * w) // sw for w in weights]
    rem = t - sum(shares)
    idx = max(range(len(weights)), key=lambda i: (weights[i], -i))
    shares[idx] += rem
    return [sign * s for s in shares], rem, idx


# ----------------------------------------------------------------------------------------------
# Model
# ----------------------------------------------------------------------------------------------
CLASSES = ("money", "party", "advance", "partner", "category_income", "category_expense", "equity_system")
MONEY_SUBTYPES = ("cash", "cash_collection", "saving", "current", "OD", "CC", "loan")
EQ_ROLES = ("opening_balance", "adjustments", "suspense", "profit_distributed", "drawings", "link")
KINDS = ("money_in", "money_out", "gave_credit", "took_credit", "transfer", "adjustment")
KIND_LABEL = {"money_in": "Money in", "money_out": "Money out", "gave_credit": "Gave on credit",
              "took_credit": "Took on credit", "transfer": "Transfer", "adjustment": "Correction / adjustment"}
# plain words for the line tags of the appropriation entry (02 §7.1) — printed; the tag ids stay in fixtures.json
TAG_LABEL = {"interest": "interest on capital", "share": "profit share"}
BOOK_TYPE_LABEL = {"personal": "Personal book", "family": "Sub-family book", "joint": "Joint fund book",
                   "business": "Business book", "organization": "Trust book"}


class Account(object):
    def __init__(self, book, aid, name, cls, subtype=None, role=None, link_to=None, note="", opening=0):
        assert cls in CLASSES, cls
        if cls == "money":
            assert subtype in MONEY_SUBTYPES, (name, subtype)
        if cls == "equity_system":
            assert role in EQ_ROLES, (name, role)
        self.book = book
        self.id = aid
        self.name = name
        self.cls = cls
        self.subtype = subtype
        self.role = role
        self.link_to = link_to     # book id for role == link
        self.note = note
        self.opening = opening     # signed paise, + = Dr

    @property
    def key(self):
        return self.book.id + ":" + self.id

    def is_cash_like(self):
        return self.cls == "money" and self.subtype in ("cash", "cash_collection")

    def plain_type(self):
        """The account-type word a user sees on the printed report (ADR 2026-10-12 §2). Presentation only."""
        if self.cls == "money":
            return {"cash": "Cash", "cash_collection": "Collection box (gollak)", "saving": "Bank (savings)",
                    "current": "Bank (current)", "OD": "Bank overdraft", "CC": "Card", "loan": "Loan"}[self.subtype]
        if self.cls == "party":
            return "Person / shop"
        if self.cls == "advance":
            return "Advance with " + self.holder()
        if self.cls == "partner":
            return "Partner"
        if self.cls == "category_income":
            return "Income"
        if self.cls == "category_expense":
            return "Expense"
        return {"opening_balance": "Own money (capital)", "adjustments": "Adjustments",
                "suspense": "Unexplained money (suspense)", "profit_distributed": "Profit shared out to partners",
                "drawings": "Taken out by the owner (drawings)", "link": "Other book"}[self.role]

    def holder(self):
        """The member who holds an advance account — from its name, *Advance – {member} A/c*."""
        m = re.match(r"^Advance – (.+?) A/c$", self.name)
        return m.group(1) if m else self.name

    def plain_natural(self):
        """One plain sentence on which side the balance normally sits (printed under the ledger heading)."""
        if self.cls == "money":
            if self.subtype in ("CC", "loan", "OD"):
                return "The balance is normally Cr — what you owe the bank. A Dr balance would mean the bank holds your money."
            return "The balance is normally Dr — money you have."
        if self.cls == "party":
            return "Dr = you will get · Cr = you will give."
        if self.cls == "advance":
            return "Dr = money still with %s, not yet accounted for." % self.holder()
        if self.cls == "partner":
            return "Cr = the business owes the partner · Dr = the partner owes the business."
        if self.cls == "category_income":
            return "Cr = received or earned this year. Starts every year at zero."
        if self.cls == "category_expense":
            return "Dr = spent this year. Starts every year at zero."
        return {"opening_balance": "Cr = your own money in this book (opening balances and capital put in).",
                "adjustments": "Either side — cash-count differences and amounts written off.",
                "suspense": "Either side — money not yet explained; must be nil before a month is closed.",
                "profit_distributed": "Dr = profit already shared out to the partners.",
                "drawings": "Dr = what the owner has taken out of the business.",
                "link": "Dr = that book owes this one · Cr = this book owes that one."}[self.role]

    def std_type(self):
        """(standard type, traditional type) for the technical companion — the catalogue columns of ADR 2026-10-12 §6."""
        if self.cls == "money":
            if self.subtype in ("CC", "loan", "OD"):
                return ("liability (by sign)", "personal — the bank")
            return ("asset", "real")
        if self.cls == "party":
            return ("asset or liability, by sign", "personal")
        if self.cls == "advance":
            return ("asset", "personal — the holder")
        if self.cls == "partner":
            return ("capital (owed to the partner), by sign", "personal")
        if self.cls == "category_income":
            return ("income", "nominal")
        if self.cls == "category_expense":
            return ("expense", "nominal")
        return {"opening_balance": ("capital", "personal — the owner(s)"), "adjustments": ("capital (result adjustments)", "nominal"),
                "suspense": ("holding account — nil at every lock", "—"), "profit_distributed": ("capital (contra)", "personal"),
                "drawings": ("capital (contra)", "personal — the owner"), "link": ("asset or liability, by sign (due from / to the other book)", "personal — the other book")}[self.role]

    def label(self):
        """Bookkeeper label for the technical companion (presentation only; the class column is the truth)."""
        if self.cls == "money":
            return {"cash": "Money — cash", "cash_collection": "Money — collection box (cash_collection)",
                    "saving": "Money — bank (saving)", "current": "Money — bank (current)",
                    "OD": "Money — bank overdraft (OD)", "CC": "Money — credit card (CC)",
                    "loan": "Money — loan account (loan)"}[self.subtype]
        if self.cls == "party":
            return "Party" + (" — " + self.note if self.note else "")
        if self.cls == "advance":
            return "Advance (money held by a member)"
        if self.cls == "partner":
            return "Partner current account"
        if self.cls == "category_income":
            return "Income" + (" — " + self.note if self.note else "")
        if self.cls == "category_expense":
            return "Expense" + (" — " + self.note if self.note else "")
        return {"opening_balance": "Equity — opening balance / capital", "adjustments": "Equity — adjustments",
                "suspense": "Equity — suspense (import holding)", "profit_distributed": "Equity — profit distributed (contra)",
                "drawings": "Equity — drawings (contra)", "link": "Inter-book link (02 §6)"}[self.role]

    def natural(self):
        if self.cls == "money":
            if self.subtype in ("CC", "loan", "OD"):
                return "Cr (you owe the bank); a Dr balance means money with the bank"
            return "Dr"
        if self.cls == "party":
            return "by sign — Dr = you will get · Cr = you will give"
        if self.cls == "advance":
            return "Dr (money out with the holder)"
        if self.cls == "partner":
            return "by sign — Cr = business owes the partner · Dr = partner owes the business"
        if self.cls == "category_income":
            return "Cr"
        if self.cls == "category_expense":
            return "Dr"
        return {"opening_balance": "Cr", "adjustments": "either (differences and write-offs)",
                "suspense": "either; must be 0 at every lock", "profit_distributed": "Dr (contra-equity)",
                "drawings": "Dr (contra-equity)", "link": "by sign — Dr = that book owes this one · Cr = this book owes that one"}[self.role]

    def col_labels(self):
        """Contextual Dr/Cr column headers (standards §1.3) — the plain words first, the true side in brackets
        (ADR 2026-10-10b §4, ADR 2026-10-12 §2)."""
        if self.cls == "money":
            if self.subtype in ("CC", "loan", "OD"):
                return ("Paid to the bank (Dr)", "Taken or charged by the bank (Cr)")
            return ("Money in (Dr)", "Money out (Cr)")
        if self.cls == "party":
            return ("Given or billed to them (Dr)", "Received or taken from them (Cr)")
        if self.cls == "advance":
            return ("Handed out (Dr)", "Bills settled or returned (Cr)")
        if self.cls == "partner":
            return ("Taken out by them (Dr)", "Put in by them (Cr)")
        if self.cls == "category_expense":
            return ("Spent (Dr)", "Refund or correction (Cr)")
        if self.cls == "category_income":
            return ("Refund or correction (Dr)", "Received or earned (Cr)")
        return {"opening_balance": ("Withdrawn (Dr)", "Own money put in (Cr)"),
                "adjustments": ("Difference (Dr)", "Difference (Cr)"),
                "suspense": ("Unexplained money out (Dr)", "Unexplained money in (Cr)"),
                "profit_distributed": ("Shared out to the partners (Dr)", "Loss shared (Cr)"),
                "drawings": ("Taken out by the owner (Dr)", "Put back (Cr)"),
                "link": ("Sent to that book (Dr)", "Received from that book (Cr)")}[self.role]

    def carried(self):
        return self.cls != "category_income" and self.cls != "category_expense"


class Voucher(object):
    _seq = 0

    def __init__(self, book, dt, kind, narr, lines, by, t=5, authored=None, tag=None, refs=None,
                 review=None, pending=None, import_line=None, sheet=None, note=None):
        assert kind in KINDS, kind
        Voucher._seq += 1
        self.seq = Voucher._seq
        self.book = book
        self.date = dt
        self.kind = kind
        self.narr = narr
        self.lines = [(l[0], int(l[1])) for l in lines]
        self.ltags = [(l[2] if len(l) > 2 else None) for l in lines]
        self.by = by
        self.t = t
        self.authored = authored or dt
        self.tag = tag
        self.refs = dict(refs or {})
        self.review = review          # dict(approver, decided, decision, reason, limit)
        self.pending = pending        # dict(requested, approved_on, approver)
        self.import_line = import_line
        self.sheet = sheet            # dict(counted_by, witness, denoms) for cash_collection counts
        self.note = note
        self.amended_by = None
        self.reversed_by = None
        self.id = None                # assigned chronologically at finalize

    @property
    def amount(self):
        return sum(p for _, p in self.lines if p > 0)

    def debits(self):
        return [(a, p) for a, p in self.lines if p > 0]

    def credits(self):
        return [(a, -p) for a, p in self.lines if p < 0]

    def tagged_lines(self):
        return [(a, p, t) for (a, p), t in zip(self.lines, self.ltags)]

    def debits_t(self):
        return [(a, p, t) for a, p, t in self.tagged_lines() if p > 0]

    def credits_t(self):
        return [(a, -p, t) for a, p, t in self.tagged_lines() if p < 0]

    def is_head(self):
        return self.amended_by is None

    def counted(self, as_seen_on=None):
        if not self.is_head():
            return False
        if self.pending and as_seen_on is not None and as_seen_on < self.pending["approved_on"]:
            return False
        return True


class Book(object):
    def __init__(self, uc, bid, name, btype, prefix, ownership=None, members=None, start=FY_START, short=None):
        assert btype in ("personal", "family", "joint", "business", "organization")
        self.uc = uc
        self.id = bid
        self.name = name
        self.short = short or name
        self.type = btype
        self.prefix = prefix
        self.ownership = ownership      # business: "just_me" | "shared"
        self.members = members or []    # (name, role, limit_paise or None, designation)
        self.start = start
        self.accounts = OrderedDict()
        self.vouchers = []
        self.locks = OrderedDict()      # month key -> dict(date, by)
        self.counts = []                # dict(date, acct, counted, diff, denoms, by, witness, book_before)
        self.config = OrderedDict()
        self.notes = []                 # plain paragraphs printed under the book heading (presentation only)
        self.plain = []                 # plain one-line settings printed under the book heading (presentation only;
                                        # the technical `config` strings go to fixtures.json and the .tech.md companion)
        self.structural_approvals = []  # dict(date, what, approvals)
        self.year_close = None

    # ----- chart
    def acct(self, aid, name, cls, **kw):
        assert aid not in self.accounts, aid
        a = Account(self, aid, name, cls, **kw)
        self.accounts[aid] = a
        return a

    def member_names(self):
        return [m[0] for m in self.members]

    def member(self, name):
        for m in self.members:
            if m[0] == name:
                return m
        raise KeyError(name + " not in " + self.id)

    def admins(self):
        return [m[0] for m in self.members if m[1] in ("admin", "head")]

    def ob(self):
        obs = [a for a in self.accounts.values() if a.role == "opening_balance"]
        assert len(obs) == 1, (self.id, len(obs))
        return obs[0]

    def eq(self, role):
        for a in self.accounts.values():
            if a.role == role:
                return a
        raise KeyError(role)

    # ----- vouchers
    def v(self, dt, kind, narr, lines, by, **kw):
        for l in lines:
            assert l[0].book is self, ("account %s not in book %s" % (l[0].name, self.id))
        vo = Voucher(self, dt, kind, narr, lines, by, **kw)
        self.vouchers.append(vo)
        return vo

    def post_opening(self, by, dt=None):
        """02 §4 (and the engine's Verbs.openingBalance): one adjustment PER ACCOUNT — money, party, advance or
        partner — against Opening Balance / Capital, signed as the ledger sees it (a partner's contribution is
        `Dr Opening Balance / Capital · Cr Partner Current`); Opening Balance / Capital absorbs the difference
        (ADR 2026-09-09c §4)."""
        dt = dt or self.start
        ob = self.ob()
        out = []
        for a in self.accounts.values():
            if a.role == "opening_balance" or not a.opening:
                continue
            assert a.cls in ("money", "party", "advance", "partner"), (a.name, a.cls)
            amt, side = fmt_signed_side(a.opening)
            narr = "Opening balance of %s as on %s — %s %s (02 §4; counterpart %s)" % (a.name, fdate(dt), amt, side, ob.name)
            out.append(self.v(dt, "adjustment", narr, [(a, a.opening), (ob, -a.opening)], by, t=0, tag="opening"))
        ob.opening = -sum(a.opening for a in self.accounts.values() if a.role != "opening_balance")
        return out

    def amend(self, original, dt, lines, narr, by, authored=None):
        assert original.amended_by is None
        vo = self.v(dt, original.kind, narr, lines, by, authored=authored, refs={"amends": original}, tag=original.tag)
        original.amended_by = vo
        return vo

    def reverse(self, original, dt, by, reason, authored=None, tag="reversal"):
        lines = [(a, -p) for a, p in original.lines]
        narr = "Reversal of %s — %s" % ("{id:%d}" % original.seq, reason)
        vo = self.v(dt, "adjustment", narr, lines, by, authored=authored, refs={"reverses": original}, tag=tag)
        original.reversed_by = vo
        return vo

    def reject(self, original, approver, dt, reason):
        assert original.review and original.review["decision"] == "rejected"
        return self.reverse(original, dt, approver, "rejected by %s: %s" % (approver, reason), tag="rejection_reversal")

    def advance_request(self, req_date, appr_date, approver, holder, amount, purpose, money_acct, adv_acct):
        narr = "Advance to %s — %s (requested %s, approved %s by %s)" % (holder, purpose, fdate(req_date), fdate(appr_date), approver)
        return self.v(req_date, "money_out", narr, [(adv_acct, amount), (money_acct, -amount)], holder, t=1,
                      tag="advance_out", pending={"requested": req_date, "approved_on": appr_date, "approver": approver})

    def lock_all(self, by, day=5, march_day=5):
        for mk in fy_months():
            y, m = int(mk[:4]), int(mk[5:])
            ny, nm = (y + 1, 1) if m == 12 else (y, m + 1)
            dd = march_day if m == 3 else day
            self.locks[mk] = {"date": date(ny, nm, dd), "by": by}

    def count(self, dt, acct, by, diff=0, witness=None, sheet=False):
        assert acct.cls == "money" and acct.subtype == "cash"
        self.counts.append({"date": dt, "acct": acct, "by": by, "diff": diff, "witness": witness,
                            "sheet": sheet, "counted": None, "book_before": None, "denoms": None, "voucher": None})

    def monthly_counts(self, acct, by, diffs=None, sheet=False, witness=None):
        diffs = diffs or {}
        for mk in fy_months():
            y, m = int(mk[:4]), int(mk[5:])
            me = month_end(date(y, m, 1))
            self.count(me, acct, by, diff=diffs.get(mk, 0), sheet=sheet, witness=witness)

    def link_acct(self, other_book_id):
        for a in self.accounts.values():
            if a.role == "link" and a.link_to == other_book_id:
                return a
        raise KeyError("no link in %s to %s" % (self.id, other_book_id))

    # ----- derived
    def sorted_vouchers(self):
        return sorted(self.vouchers, key=lambda v: (v.date, v.t, v.seq))

    def balances(self, as_of=None, as_seen_on=None, exclude_tags=(), authored_before=None):
        bal = OrderedDict((a.id, 0) for a in self.accounts.values())
        for vo in self.vouchers:
            if as_of is not None and vo.date > as_of:
                continue
            if authored_before is not None and vo.authored >= authored_before:
                continue
            if not vo.counted(as_seen_on):
                continue
            if vo.tag in exclude_tags:
                continue
            for a, p in vo.lines:
                bal[a.id] += p
        return bal

    def balance(self, acct, **kw):
        return self.balances(**kw)[acct.id]

    def ledger_rows(self, acct):
        rows = []
        for vo in self.sorted_vouchers():
            if not vo.is_head():
                continue
            for a, p in vo.lines:
                if a is acct:
                    rows.append((vo, p))
        return rows

    def ledger_lines(self, acct):
        """(voucher, signed paise, line tag) for every head line on `acct`, in running order."""
        rows = []
        for vo in self.sorted_vouchers():
            if not vo.is_head():
                continue
            for a, p, t in vo.tagged_lines():
                if a is acct:
                    rows.append((vo, p, t))
        return rows

    def net_result(self, upto=FY_END):
        bal = self.balances(as_of=upto)
        inc = -sum(bal[a.id] for a in self.accounts.values() if a.cls == "category_income")
        exp = sum(bal[a.id] for a in self.accounts.values() if a.cls == "category_expense")
        return inc, exp, inc - exp

    def daily_balance_series(self, acct, exclude_tags=()):
        """End-of-day signed balance for every day 01 Apr 2025 … 31 Mar 2026."""
        by_day = {}
        for vo in self.vouchers:
            if not vo.counted() or vo.tag in exclude_tags:
                continue
            for a, p in vo.lines:
                if a is acct:
                    by_day[vo.date] = by_day.get(vo.date, 0) + p
        out = []
        bal = 0
        dt = FY_START
        while dt <= FY_END:
            bal += by_day.get(dt, 0)
            out.append((dt, bal))
            dt += timedelta(days=1)
        return out


class UseCase(object):
    def __init__(self, slug, title, entity, intro, people):
        self.slug = slug
        self.title = title
        self.entity = entity
        self.intro = intro
        self.people = people          # list of (name, role text)
        self.books = OrderedDict()
        self.groups = []              # inter-book transfer groups: dict(id, a, b)
        self.sections = []            # extra narrative blocks appended at the end (list of Doc blocks)
        self.spec_flags = []          # ⚠️ SPEC readings exercised here (text)
        self.coverage = []            # (rule, voucher refs text)
        self.tech_notes = []          # (heading, [paragraphs]) — developer notes that go to <slug>.tech.md, never to print

    def book(self, bid, name, btype, prefix, **kw):
        b = Book(self, bid, name, btype, prefix, **kw)
        self.books[bid] = b
        return b

    def link(self, dt, amount, from_book, from_lines, to_book, to_lines, narr_from, narr_to, by_from, by_to=None,
             kind_from="transfer", kind_to="transfer", t=5, review_to=None, authored=None):
        """Two envelopes sharing refs.transfer_group (02 §6)."""
        gid = "TG-%s-%s-%03d" % (from_book.prefix, to_book.prefix, len(self.groups) + 1)
        a = from_book.v(dt, kind_from, narr_from, from_lines, by_from, t=t, refs={"transfer_group": gid}, tag="interbook", authored=authored)
        b = to_book.v(dt, kind_to, narr_to, to_lines, by_to or by_from, t=t, refs={"transfer_group": gid}, tag="interbook", review=review_to, authored=authored)
        self.groups.append({"id": gid, "a": a, "b": b})
        return a, b

    def all_vouchers(self):
        for b in self.books.values():
            for vo in b.vouchers:
                yield vo


# ----------------------------------------------------------------------------------------------
# Finalisation: chronological ids, cash counts (differences → adjustments), denomination sheets
# ----------------------------------------------------------------------------------------------
def make_denoms(amount, seed):
    """A plausible denomination sheet summing exactly to `amount` (paise). Deterministic in (amount, seed)."""
    rupees, paise = divmod(amount, 100)
    sheet = OrderedDict()
    rem = rupees
    # keep some smaller notes so the sheet looks real: peel off a few of each smaller note first
    small = [(200, 3 + seed % 5), (100, 4 + seed % 7), (50, 1 + seed % 3), (20, 2 + seed % 4), (10, 3 + seed % 6)]
    keep = OrderedDict()
    for den, n in small:
        n = min(n, rem // den)
        keep[den] = n
        rem -= den * n
    sheet[500] = rem // 500
    rem -= 500 * sheet[500]
    for den in (200, 100, 50, 20, 10):
        n = rem // den
        sheet[den] = keep.get(den, 0) + n
        rem -= den * n
    coins = rem * 100 + paise
    sheet["coins"] = coins
    total = sum(den * n * 100 for den, n in sheet.items() if den != "coins") + coins
    assert total == amount, (total, amount)
    return sheet


def finalize(uc):
    # 1. cash counts in date order (count-difference adjustments depend on earlier ones)
    for b in uc.books.values():
        for c in sorted(b.counts, key=lambda c: (c["date"], c["acct"].id)):
            acct = c["acct"]
            book_bal = b.balance(acct, as_of=c["date"])
            c["book_before"] = book_bal
            c["counted"] = book_bal + c["diff"]
            if c["diff"] != 0:
                adj = b.eq("adjustments")
                if c["diff"] < 0:
                    word = "short"
                    lines = [(adj, -c["diff"]), (acct, c["diff"])]
                else:
                    word = "excess"
                    lines = [(acct, c["diff"]), (adj, -c["diff"])]
                narr = "Cash count of %s: counted %s against book %s — %s %s posted to %s (02 §8 step 1)" % (
                    acct.name, rs(c["counted"]), rs(book_bal), rs(c["diff"]), word, adj.name)
                vo = b.v(c["date"], "adjustment", narr, lines, c["by"], t=9, tag="count_diff")
                c["voucher"] = vo
            if c["sheet"]:
                c["denoms"] = make_denoms(c["counted"], c["date"].day + c["date"].month)
    # 2. gollak count sheets
    for b in uc.books.values():
        for vo in b.vouchers:
            if vo.sheet is not None and vo.sheet.get("denoms") is None:
                vo.sheet["denoms"] = make_denoms(vo.amount, vo.date.day + vo.date.month)
    # 3. chronological ids
    for b in uc.books.values():
        for i, vo in enumerate(b.sorted_vouchers(), 1):
            vo.id = "%s-%03d" % (b.prefix, i)
    # 4. narrations referring to other vouchers by {id:seq}
    seqmap = {}
    for vo in uc.all_vouchers():
        seqmap[vo.seq] = vo.id
    for vo in uc.all_vouchers():
        vo.narr = re.sub(r"\{id:(\d+)\}", lambda m: seqmap[int(m.group(1))], vo.narr)


# ----------------------------------------------------------------------------------------------
# Validators — every rule the brief names; a failure raises and stops the build
# ----------------------------------------------------------------------------------------------
class Violation(Exception):
    pass


def chk(cond, msg):
    if not cond:
        raise Violation(msg)


def shape_ok(vo):
    """02 §1.4 rule 7 class-shapes exactly as the engine's checkShape reads them
    (packages/core_ledger/lib/src/invariants.dart, ADR 2026-09-05e §6): `partner` is party-like; `advance` is admitted
    where a party would be on the debit side and beside money on the credit side (request and spend `money_out`,
    return `money_in`); a §6 link stands in for money on the far side — `transfer` for both money halves, and the
    payee half of a pocket expense `Dr Expense · Cr link` under `money_out`; `drawings` on money_out's debit side
    (ADR 2026-09-09b §3) and Opening Balance / Capital on money_in's credit side (ADR 2026-09-13 §4); an
    `adjustment` touches exactly one equity_system account; a `refs.reverses` mirror is exempt but is checked here
    to be the exact mirror of its target."""
    dr = [a for a, p in vo.lines if p > 0]
    cr = [a for a, p in vo.lines if p < 0]
    k = vo.kind

    def money(a):
        return a.cls == "money"

    def party(a):
        return a.cls in ("party", "partner")

    def advance(a):
        return a.cls == "advance"

    def income(a):
        return a.cls == "category_income"

    def expense(a):
        return a.cls == "category_expense"

    def link(a):
        return a.cls == "equity_system" and a.role == "link"

    def drawings(a):
        return a.cls == "equity_system" and a.role == "drawings"

    def capital(a):
        return a.cls == "equity_system" and a.role == "opening_balance"

    if "reverses" in vo.refs:
        tgt = vo.refs["reverses"]
        return sorted((a.key, -p) for a, p in tgt.lines) == sorted((a.key, p) for a, p in vo.lines)
    if k == "money_in":
        return all(money(a) for a in dr) and all(income(a) or party(a) or advance(a) or capital(a) for a in cr)
    if k == "money_out":
        return all(expense(a) or party(a) or advance(a) or drawings(a) for a in dr) and all(money(a) or advance(a) or link(a) for a in cr)
    if k == "gave_credit":
        return all(party(a) for a in dr) and all(money(a) or income(a) for a in cr)
    if k == "took_credit":
        return all(money(a) or expense(a) for a in dr) and all(party(a) for a in cr)
    if k == "transfer":
        return (all(money(a) or link(a) for a in dr) and all(money(a) or link(a) for a in cr)
                and not (any(link(a) for a in dr) and any(link(a) for a in cr)))
    if k == "adjustment":
        return len(set(a.key for a in dr + cr if a.cls == "equity_system")) == 1
    return False


def validate(uc):
    books = uc.books
    for b in books.values():
        obs = [a for a in b.accounts.values() if a.role == "opening_balance"]
        chk(len(obs) == 1, "%s: Opening Balance / Capital must appear exactly once" % b.id)
        names = [a.name for a in b.accounts.values()]
        chk(len(names) == len(set(names)), "%s: duplicate account names" % b.id)
        for a in b.accounts.values():
            if a.role == "drawings":
                chk(b.type == "business" and b.ownership == "just_me", "%s: Drawings only in a one-owner business book (ADR 2026-09-09b §2)" % b.id)
            if a.cls == "partner":
                chk(b.type == "business" and b.ownership == "shared", "%s: partner accounts only in a shared business" % b.id)
        if b.type == "business" and b.ownership == "shared":
            chk(not any(a.role == "drawings" for a in b.accounts.values()), "%s: shared business has no Drawings" % b.id)
        for vo in b.vouchers:
            vid = "%s/%s" % (b.id, vo.id)
            chk(sum(p for _, p in vo.lines) == 0, "%s: lines do not sum to zero" % vid)
            chk(len(vo.lines) >= 2 and all(p != 0 for _, p in vo.lines), "%s: fewer than two lines or a zero line" % vid)
            for a, p in vo.lines:
                chk(a.book is b, "%s: account %s not in book" % (vid, a.name))
            chk(vo.date >= b.start, "%s: dated before the book start" % vid)
            chk(vo.date <= FY_END or vo.tag == "next_fy", "%s: dated after the FY" % vid)
            chk(vo.authored >= vo.date, "%s: authored (%s) before its accounting date (%s)" % (vid, vo.authored, vo.date))
            chk(shape_ok(vo), "%s: class-shape violation for kind %s (%s)" % (vid, vo.kind, ", ".join("%s%s" % ("Dr " if p > 0 else "Cr ", a.name) for a, p in vo.lines)))
            # gollak: nothing leaves a cash_collection except a transfer into cash or bank
            for a, p in vo.credits():
                if a.cls == "money" and a.subtype == "cash_collection":
                    chk(vo.kind == "transfer" and all(x.cls == "money" and x.subtype in ("cash", "saving", "current") for x, _ in vo.debits()),
                        "%s: money left a collection box other than by Transfer to cash/bank (02 §8.2)" % vid)
            # a count never moves money; a cash_collection credit side only via transfer (above); expense never from gollak
            # period lock: nothing authored into a month after its lock
            mk = month_key(vo.date)
            if mk in b.locks:
                chk(vo.authored < b.locks[mk]["date"], "%s: authored %s after the lock of %s (%s)" % (vid, vo.authored, mk, b.locks[mk]["date"]))
            # membership
            chk(vo.by in b.member_names(), "%s: entered by %s who is not a member" % (vid, vo.by))
            # review flags
            name, role, limit, desig = b.member(vo.by)
            over = limit is not None and vo.amount > limit and len(b.members) > 1 and b.type != "personal"
            if vo.pending:
                chk(vo.review is None, "%s: advance requests are approved, never flagged" % vid)
                chk(vo.pending["approver"] != vo.by and vo.pending["approver"] in b.admins(), "%s: advance approver must be a different admin/head" % vid)
                chk(vo.pending["approved_on"] >= vo.pending["requested"] == vo.date, "%s: advance dates" % vid)
                if mk in b.locks:
                    chk(vo.pending["approved_on"] < b.locks[mk]["date"], "%s: advance still pending at lock" % vid)
            elif over:
                chk(vo.review is not None, "%s: %s over limit %s with no review flag (02 §3)" % (vid, rs(vo.amount), rs(limit)))
            else:
                chk(vo.review is None, "%s: review flag on an entry within limit" % vid)
            if vo.review:
                rv = vo.review
                chk(rv["approver"] != vo.by and rv["approver"] in b.admins(), "%s: reviewer must be a different admin/head (02 §7.2)" % vid)
                chk(rv["decided"] >= vo.authored, "%s: decided before authored" % vid)
                if mk in b.locks:
                    chk(rv["decided"] < b.locks[mk]["date"], "%s: flag still open at lock" % vid)
                if rv["decision"] == "rejected":
                    chk(vo.reversed_by is not None and vo.reversed_by.refs.get("reverses") is vo, "%s: rejected entry without its mirror reversal" % vid)
                    chk(vo.reversed_by.date == rv["decided"] and vo.reversed_by.by == rv["approver"], "%s: rejection reversal date/author" % vid)
            # capital introduced credits Opening Balance / Capital and never income (ADR 2026-09-13 §4)
            if vo.tag == "capital_in" or (vo.kind == "money_in" and any(a.cls == "equity_system" for a, _ in vo.lines)):
                chk(vo.kind == "money_in" and all(a.role == "opening_balance" for a, _ in vo.credits()) and all(a.cls == "money" for a, _ in vo.debits()),
                    "%s: capital introduced must post Dr money · Cr Opening Balance / Capital and never income (ADR 2026-09-13 §4)" % vid)
            # owner takeout debits Drawings and never an expense (ADR 2026-09-09b §3)
            if vo.tag == "drawings" or (b.type == "business" and b.ownership == "just_me" and vo.kind == "money_out" and "drawing" in vo.narr.lower()):
                chk(vo.kind == "money_out" and len(vo.debits()) == 1 and vo.debits()[0][0].role == "drawings" and all(a.cls == "money" for a, _ in vo.credits()),
                    "%s: owner takeout must post Dr Drawings · Cr money, never an expense (ADR 2026-09-09b §3)" % vid)
            # a collection box is filled only by a count (Dr gollak · Cr income); no Transfer flows into it (02 §8.2)
            for a, p in vo.debits():
                if a.cls == "money" and a.subtype == "cash_collection":
                    chk(vo.kind == "money_in" and vo.tag == "gollak_count" and all(x.cls == "category_income" for x, _ in vo.credits()),
                        "%s: money reached a collection box other than by a count (02 §8.2)" % vid)
            if vo.sheet:
                chk(vo.sheet["counted_by"] != vo.sheet["witness"], "%s: counted-by and witness must be two different people (02 §8.2)" % vid)
            # only admin/head amend or reverse (06 §1.0)
            if "amends" in vo.refs or "reverses" in vo.refs:
                chk(role in ("admin", "head"), "%s: %s (%s) may not amend or reverse — admin/head only (06 §1.0)" % (vid, vo.by, role))
            if "amends" in vo.refs:
                chk(vo.refs["amends"].amended_by is vo and vo.refs["amends"].kind == vo.kind, "%s: amend chain" % vid)
                omk = month_key(vo.refs["amends"].date)
                if omk in b.locks:
                    chk(vo.authored < b.locks[omk]["date"], "%s: amendment authored after the original's month lock (02 §5)" % vid)
            if "reverses" in vo.refs:
                tgt = vo.refs["reverses"]
                chk(tgt.book is b and tgt.reversed_by is vo, "%s: reversal target" % vid)
        # locks: every month, Suspense zero, no open flag / pending at each lock; cash counted
        chk(list(b.locks.keys()) == fy_months(), "%s: not every month locked" % b.id)
        cash_accts = [a for a in b.accounts.values() if a.cls == "money" and a.subtype == "cash"]
        for mk, lk in b.locks.items():
            y, m = int(mk[:4]), int(mk[5:])
            me = month_end(date(y, m, 1))
            bal = b.balances(as_of=me, authored_before=lk["date"])
            for a in b.accounts.values():
                if a.role == "suspense":
                    chk(bal[a.id] == 0, "%s: Suspense %s at lock of %s" % (b.id, rs(bal[a.id]), mk))
            for a in cash_accts:
                cs = [c for c in b.counts if c["acct"] is a and month_key(c["date"]) == mk]
                chk(len(cs) >= 1, "%s: %s not counted in %s" % (b.id, a.name, mk))
                for c in cs:
                    chk(c["date"] < lk["date"], "%s: count after lock" % b.id)
                    if b.type == "organization":
                        chk(c["denoms"] is not None, "%s: trust count without denomination sheet" % b.id)
            if b.type == "organization":
                for vo in b.vouchers:
                    if vo.tag == "gollak_count":
                        chk(vo.sheet and vo.sheet.get("counted_by") and vo.sheet.get("witness") and vo.sheet.get("denoms"), "%s: gollak count needs sheet + two names" % b.id)
        # no cash / collection / savings / current account negative after any posting (02 §9; audit item 2)
        for a in b.accounts.values():
            if a.cls == "money" and a.subtype in ("cash", "cash_collection", "saving", "current"):
                run = 0
                for vo in b.sorted_vouchers():
                    if not vo.is_head():
                        continue
                    for x, p in vo.lines:
                        if x is a:
                            run += p
                            chk(run >= 0, "%s: %s negative (%s) after %s on %s" % (b.id, a.name, rs(run), vo.id, vo.date))
        # profit appropriation (02 §7.1): ONE entry; interest half-up on credit days only (the setting in force);
        # the residual by ratio with the remainder to the largest weight, ties to the earliest-created account
        dists = [vo for vo in b.vouchers if vo.tag == "distribution"]
        chk(len(dists) <= 1 and (not dists or b.ownership == "shared"), "%s: a distribution belongs to a shared business, at most once this FY" % b.id)
        if dists:
            vo = dists[0]
            cfg = b.config["profit_distribution"]
            partners, weights, rate_bp = cfg["partners"], cfg["weights"], cfg["rate_bp"]
            inc, exp, net = b.net_result()
            drs = vo.debits()
            chk(len(drs) == 1 and drs[0][0].role == "profit_distributed" and drs[0][1] == net, "%s: the distribution must debit Profit Distributed with the FY net result in one entry" % b.id)
            chk(all(t in ("interest", "share") for a, p, t in vo.tagged_lines() if p < 0), "%s: every partner line of the distribution must be tagged interest or share" % b.id)
            den = 10000 * 365
            tot_int = 0
            for a in partners:
                s_cr = 0
                day = FY_START
                while day <= FY_END:
                    bal_d = b.balance(a, as_of=day, exclude_tags=("distribution",))
                    if bal_d < 0:
                        s_cr += -bal_d
                    day += timedelta(days=1)
                expect = (2 * s_cr * rate_bp + den) // (2 * den)
                got = sum(-p for x, p, t in vo.tagged_lines() if x is a and t == "interest")
                chk(got == expect, "%s: interest for %s is %s, expected %s (half-up to the paisa, credit days only, Actual/365)" % (b.id, a.name, rs(got), rs(expect)))
                tot_int += expect
            residual = net - tot_int
            sw = sum(weights)
            floors = [(abs(residual) * w) // sw for w in weights]
            rem = abs(residual) - sum(floors)
            idx = max(range(len(weights)), key=lambda i: (weights[i], -i))
            sign = 1 if residual >= 0 else -1
            for i, a in enumerate(partners):
                got = sum(-p for x, p, t in vo.tagged_lines() if x is a and t == "share")
                expect = sign * (floors[i] + (rem if i == idx else 0))
                chk(got == expect, "%s: share for %s is %s, expected %s (floor by weight; remainder %d paise to the largest weight, ties to the earliest-created account)" % (b.id, a.name, rs(got), rs(expect), rem))
        # trial balance
        bal = b.balances()
        chk(sum(bal.values()) == 0, "%s: trial balance does not balance" % b.id)
        # advances never negative
        for a in b.accounts.values():
            if a.cls == "advance":
                run = 0
                for vo in b.sorted_vouchers():
                    if not vo.is_head():
                        continue
                    for x, p in vo.lines:
                        if x is a:
                            run += p
                            chk(run >= 0, "%s: advance %s negative after %s" % (b.id, a.name, vo.id))
        # year-close preconditions
        for vo in b.vouchers:
            if vo.review:
                chk(vo.review["decided"] <= FY_END or vo.review["decided"] < b.locks["2026-03"]["date"], "%s: open flag at year close" % b.id)
    # inter-book pairs
    for g in uc.groups:
        a, bb = g["a"], g["b"]
        chk(a.date == bb.date and a.amount == bb.amount, "%s: halves differ" % g["id"])
        la = [x for x, _ in a.lines if x.role == "link"]
        lb = [x for x, _ in bb.lines if x.role == "link"]
        chk(len(la) == 1 and len(lb) == 1, "%s: each half needs exactly one link line" % g["id"])
        chk(la[0].link_to == bb.book.id and lb[0].link_to == a.book.id, "%s: link accounts do not point at each other" % g["id"])
        pa = [p for x, p in a.lines if x is la[0]][0]
        pb = [p for x, p in bb.lines if x is lb[0]][0]
        chk(pa + pb == 0, "%s: link lines do not mirror" % g["id"])
    for b in books.values():
        for a in b.accounts.values():
            if a.role == "link":
                other = books[a.link_to].link_acct(b.id)
                chk(b.balance(a) + books[a.link_to].balance(other) == 0, "pair %s/%s does not net to zero" % (a.name, other.name))
                for vo in b.vouchers:
                    if any(x is a for x, _ in vo.lines):
                        chk("transfer_group" in vo.refs, "%s: link account touched outside a transfer group" % vo.id)
    # year close vector sanity (computed later too)
    for b in books.values():
        bal = b.balances()
        carried = sum(bal[a.id] for a in b.accounts.values() if a.carried())
        inc, exp, net = b.net_result()
        chk(carried == net, "%s: carried balances %s != net result %s" % (b.id, carried, net))


# ----------------------------------------------------------------------------------------------
# Computations used by the reports
# ----------------------------------------------------------------------------------------------
def fifo_ageing(rows, as_on):
    """rows: chronological (date, signed amount). Credits settle the oldest open debits first; an
    unapplied credit is held and offsets the next debit. Returns (oldest_open_debit_date or None, open_debit_total)."""
    queue = []   # [date, remaining]
    pool = 0
    for dt, p in rows:
        if p > 0:
            use = min(pool, p)
            pool -= use
            p -= use
            if p:
                queue.append([dt, p])
        else:
            c = -p
            while c and queue:
                take = min(c, queue[0][1])
                queue[0][1] -= take
                c -= take
                if queue[0][1] == 0:
                    queue.pop(0)
            pool += c
    if not queue:
        return None, 0
    return queue[0][0], sum(q[1] for q in queue)


def trial_balance(b):
    bal = b.balances()
    rows = []
    for a in b.accounts.values():
        rows.append((a, bal[a.id]))
    tdr = sum(p for _, p in rows if p > 0)
    tcr = -sum(p for _, p in rows if p < 0)
    return rows, tdr, tcr


def closing_vector(b):
    bal = b.balances(as_of=FY_END)
    vec = [(a, bal[a.id]) for a in b.accounts.values() if a.carried()]
    inc, exp, net = b.net_result()
    return vec, net


# ----------------------------------------------------------------------------------------------
# Document model and renderers (Markdown + HTML from the same blocks)
# ----------------------------------------------------------------------------------------------
class Doc(object):
    def __init__(self, title):
        self.title = title
        self.blocks = []

    def h(self, level, text, anchor=None):
        self.blocks.append(("h", level, text))

    def p(self, text):
        self.blocks.append(("p", text))

    def ul(self, items):
        self.blocks.append(("ul", list(items)))

    def table(self, headers, rows, aligns=None, cls=None):
        self.blocks.append(("table", list(headers), [list(r) for r in rows], aligns or ["l"] * len(headers), cls))

    def hr(self):
        self.blocks.append(("hr",))

    def raw_html(self, html_text, md_text=""):
        self.blocks.append(("raw", html_text, md_text))


INLINE_RULES = [
    (re.compile(r"\*\*(.+?)\*\*"), r"<strong>\1</strong>"),
    (re.compile(r"~~(.+?)~~"), r"<s>\1</s>"),
    (re.compile(r"`(.+?)`"), r"<code>\1</code>"),
    (re.compile(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])"), r"<em>\1</em>"),
]


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def inline_html(s):
    parts = s.split("<br>")
    out = []
    for part in parts:
        t = esc(part)
        for rx, rep in INLINE_RULES:
            t = rx.sub(rep, t)
        out.append(t)
    return "<br>".join(out)


def md_cell(s):
    return s.replace("|", "／").replace("\n", " ")


def render_md(doc):
    out = []
    blocks = list(doc.blocks)
    if blocks and blocks[0][0] == "raw" and blocks[0][2].startswith("---"):
        out.append(blocks[0][2])
        out.append("")
        blocks = blocks[1:]
    out += ["# " + doc.title, ""]
    for blk in blocks:
        k = blk[0]
        if k == "h":
            out.append("#" * blk[1] + " " + blk[2])
            out.append("")
        elif k == "p":
            out.append(blk[1])
            out.append("")
        elif k == "ul":
            for it in blk[1]:
                out.append("- " + it)
            out.append("")
        elif k == "table":
            headers, rows, aligns = blk[1], blk[2], blk[3]
            out.append("| " + " | ".join(md_cell(h) for h in headers) + " |")
            out.append("|" + "|".join({"l": ":---", "r": "---:", "c": ":---:", "n": ":---"}[a] for a in aligns) + "|")
            for r in rows:
                out.append("| " + " | ".join(md_cell(str(c)) for c in r) + " |")
            out.append("")
        elif k == "hr":
            out.append("---")
            out.append("")
        elif k == "raw":
            if blk[2]:
                out.append(blk[2])
                out.append("")
    return "\n".join(out).rstrip() + "\n"


CSS = """
@page { size: A4; margin: 13mm 12mm 14mm 12mm; }
html { font-size: 10.5px; }
body { font-family: -apple-system, "Helvetica Neue", Helvetica, Arial, "Noto Sans", sans-serif; color: #111; margin: 0; padding: 0 2mm; line-height: 1.35; }
h1 { font-size: 2em; margin: 0 0 .4em 0; }
h2 { font-size: 1.45em; margin: 1.3em 0 .4em 0; border-bottom: 1.5px solid #333; padding-bottom: .15em; page-break-after: avoid; }
h3 { font-size: 1.18em; margin: 1.1em 0 .3em 0; page-break-after: avoid; }
h4 { font-size: 1.02em; margin: .9em 0 .25em 0; page-break-after: avoid; }
p { margin: .35em 0 .55em 0; }
ul { margin: .3em 0 .7em 1.2em; padding: 0; }
li { margin: .15em 0; }
table { border-collapse: collapse; width: 100%; margin: .35em 0 .9em 0; page-break-inside: auto; font-variant-numeric: tabular-nums; }
tr { page-break-inside: avoid; }
th, td { border: .5px solid #999; padding: 2.2px 4px; vertical-align: top; font-size: .95em; }
th { background: #eee; text-align: left; font-weight: 600; }
td.r, th.r { text-align: right; white-space: nowrap; }
td.c, th.c { text-align: center; }
td.n, th.n { text-align: left; white-space: nowrap; }
tr.total td { font-weight: 700; background: #f4f4f4; }
tr.khata td { background: #f9f9f9; font-style: italic; }
em { color: #444; }
s { color: #777; }
code { font-family: Menlo, Consolas, monospace; font-size: .92em; background: #f3f3f3; padding: 0 2px; }
hr { border: 0; border-top: 1px solid #bbb; margin: 1.2em 0; }
.meta { color: #333; font-size: .95em; }
.warn { background: #fff7e0; border-left: 3px solid #d08a00; padding: .3em .6em; }
thead { display: table-header-group; }
"""


def render_html(doc):
    out = ["<!doctype html>", "<html lang=\"en\"><head><meta charset=\"utf-8\">",
           "<title>%s</title>" % esc(doc.title), "<style>%s</style></head><body>" % CSS,
           "<h1>%s</h1>" % inline_html(doc.title)]
    for blk in doc.blocks:
        k = blk[0]
        if k == "h":
            out.append("<h%d>%s</h%d>" % (blk[1], inline_html(blk[2]), blk[1]))
        elif k == "p":
            cls = " class=\"warn\"" if blk[1].startswith("⚠️") else ""
            out.append("<p%s>%s</p>" % (cls, inline_html(blk[1])))
        elif k == "ul":
            out.append("<ul>" + "".join("<li>%s</li>" % inline_html(i) for i in blk[1]) + "</ul>")
        elif k == "table":
            headers, rows, aligns, cls = blk[1], blk[2], blk[3], blk[4]
            out.append("<table%s><thead><tr>" % ((" class=\"%s\"" % cls) if cls else ""))
            for h_, a in zip(headers, aligns):
                out.append("<th class=\"%s\">%s</th>" % (a, inline_html(h_)))
            out.append("</tr></thead><tbody>")
            for r in rows:
                rcls = ""
                cells = [str(c) for c in r]
                if cells and cells[0].startswith("@@"):
                    rcls = " class=\"%s\"" % cells[0][2:]
                    cells = cells[1:]
                out.append("<tr%s>" % rcls + "".join("<td class=\"%s\">%s</td>" % (a, inline_html(c)) for c, a in zip(cells, aligns)) + "</tr>")
            out.append("</tbody></table>")
        elif k == "hr":
            out.append("<hr>")
        elif k == "raw":
            out.append(blk[1])
    out.append("</body></html>")
    return "\n".join(out) + "\n"


def strip_row_class(rows):
    """Markdown has no row classes: drop the @@ marker cell but bold total rows."""
    out = []
    for r in rows:
        cells = [str(c) for c in r]
        if cells and cells[0].startswith("@@"):
            tag = cells[0][2:]
            cells = cells[1:]
            if tag == "total":
                cells = ["**%s**" % c if c and c != "—" and not c.startswith("**") else c for c in cells]
        out.append(cells)
    return out


class DualDoc(Doc):
    """Table rows may start with '@@total' / '@@khata' markers; md output strips them."""
    def table(self, headers, rows, aligns=None, cls=None):
        rows = [list(r) for r in rows]
        self.blocks.append(("table2", list(headers), rows, aligns or ["l"] * len(headers), cls))


def render_dual(doc):
    md_doc = Doc(doc.title)
    html_doc = Doc(doc.title)
    for blk in doc.blocks:
        if blk[0] == "table2":
            md_doc.blocks.append(("table", blk[1], strip_row_class(blk[2]), blk[3], blk[4]))
            html_doc.blocks.append(("table", blk[1], blk[2], blk[3], blk[4]))
        else:
            md_doc.blocks.append(blk)
            html_doc.blocks.append(blk)
    return render_md(md_doc), render_html(html_doc)


# ----------------------------------------------------------------------------------------------
# Plain language for print (ADR 2026-10-12 §2) — the data is untouched; only what is PRINTED changes
# ----------------------------------------------------------------------------------------------
# Every technical fragment a narration may carry, and what the printed report shows instead. The
# narration itself (fixtures.json, the tech companion) keeps the rule reference; the print drops it.
NARR_PLAIN = [
    (re.compile(r" \(02 §4; counterpart (.+?)\)"), r" (set against \1)"),
    (re.compile(r" \(02 §8 step 1\)"), ""),
    (re.compile(r" \(Money in · Cr Opening Balance / Capital, ADR 2026-09-13 §4\)"), ""),
    (re.compile(r" \(not a business expense, ADR 2026-09-09b §3\)"), " (not a business expense)"),
    (re.compile(r" \(02 §10: unexplained, never unrecorded\)"), " (unexplained, never unrecorded)"),
    (re.compile(r" \(Dr Partner Current · Cr bank, 02 §7\.1\)"), ""),
    (re.compile(r" \(02 §7\.1\)"), ""),
    (re.compile(r" \(one-sided pair, 02 §6; the payee half is a Money out whose credit is the link\)"), ""),
    (re.compile(r" \(Dr expense · Cr Advance, 02 §7\)"), ""),
    (re.compile(r" \(a 02 §6 pair — debt, not capital\)"), " (debt, not capital)"),
    (re.compile(r" \(02 §8\.2\)"), ""),
    (re.compile(r" \(ADR 2026-09-09b §3\)"), ""),
    (re.compile(r" \(02 §7: `Dr Adjustments · Cr Advance`, approver-only\)"), ""),
    (re.compile(r" \(not a farm expense, ADR 2026-09-09b §3\)"), " (not a farm expense)"),
    # fallback: any other bracket that cites a rule is dropped whole
    (re.compile(r" \([^()]*(?:§|ADR 20)[^()]*\)"), ""),
    # 01 §1.3 jargon inside a stored narration — printed in the plain word, stored as written
    (re.compile(r"society's bill \(fat-based\) accrued"), "society's bill (fat-based) raised"),
    (re.compile(r"society's fat-based bill accrued"), "society's fat-based bill raised"),
    (re.compile(r"\(one voucher, three lines\)"), "(one entry, three lines)"),
    (re.compile(r" appropriated in one entry: interest on capital at (\S+)% p\.a\., Actual/365, credited first"), r" shared out in one entry: interest on capital at \1% a year, counted day by day, credited first"),
]


def plain_narr(s):
    """The narration as the printed report shows it: the same words minus the rule citations."""
    for rx, rep in NARR_PLAIN:
        s = rx.sub(rep, s)
    return s.replace("`", "")


# What may never appear on a printed report (ADR 2026-10-12 §2; 01 §1.3 forbidden jargon). The build refuses to
# write a use-case .md that carries one of these — the same way it refuses an unbalanced voucher.
PLAIN_FORBIDDEN = [
    (r"§", "a rule reference"), (r"\bADR\b", "an ADR reference"), (r"`", "a code-style backtick"), (r"⚠", "a ⚠️ note"),
    (r"🔒", "a lock glyph"), (r"build\.py", "the generator's name"), (r"check_md", "the checker's name"), (r"\basserted\b", "a generator assertion"),
    (r"Cross-check", "a developer cross-check"), (r"PROVISIONAL", "developer status wording"), (r"\bSPEC\b", "a spec reading"), (r"\bREADME\b", "a README pointer"),
    (r"\b(money_in|money_out|gave_credit|took_credit)\b", "a verb id"),
    (r"\b(equity_system|category_income|category_expense|cash_collection)\b", "an engine class or subtype"),
    (r"\b(transfer_group|import_line)\b|refs\.", "a refs field"),
    (r"\b(structural_quorum|peer_reviewer|business_setting|book_config|auto_post_limit|bank_text)\b", "a config or engine field"),
    (r"\bEngine class\b|\bengine\b", "the word engine"), (r"\bvector\b", "the word vector"),
    (r"\b[Vv]ouchers?\b|\bVch\b", "the word voucher (01 §1.3)"), (r"\b[Nn]arration\b", "the word narration (01 §1.3)"),
    (r"\b[Jj]ournal\b", "the word journal (01 §1.3)"), (r"\b[Cc]ontra\b", "the word contra (01 §1.3)"),
    (r"\b[Aa]ccru", "the word accrual (01 §1.3)"), (r"\bFIFO\b", "an algorithm name"), (r"Full Position", "a screen-spec name"),
]


def plain_lint(text, where):
    """Refuse a printed report that still carries a technical token."""
    for pat, why in PLAIN_FORBIDDEN:
        m = re.search(pat, text)
        if m:
            i = m.start()
            line = text.count("\n", 0, i) + 1
            raise Violation("%s line %d: printed report carries %s: %r" % (where, line, why, text[max(0, i - 70):i + 70]))


def pair_text(vo):
    """`paired with {book} {id}` for an inter-book half — the plain reading of refs.transfer_group."""
    for g in vo.book.uc.groups:
        if g["a"] is vo or g["b"] is vo:
            other = g["b"] if g["a"] is vo else g["a"]
            return "paired with %s %s" % (other.book.short.split(" — ")[0], other.id)
    return "paired with another book"


# ----------------------------------------------------------------------------------------------
# Report builder — one document per use case
# ----------------------------------------------------------------------------------------------
def voucher_note(vo):
    """The plain *Notes* cell of the day book: approvals, corrections, pairs, statement lines, who counted."""
    bits = []
    if vo.pending:
        bits.append("advance request · asked %s, approved %s by %s" % (fdate(vo.pending["requested"]), fdate(vo.pending["approved_on"]), vo.pending["approver"]))
    if vo.review:
        rv = vo.review
        bits.append("over the %s limit → %s by %s on %s%s" % (rs(rv["limit"]), rv["decision"], rv["approver"], fdate(rv["decided"]),
                                                              (" — " + rv["reason"]) if rv.get("reason") else ""))
    if "amends" in vo.refs:
        bits.append("amends %s" % vo.refs["amends"].id)
    if "reverses" in vo.refs:
        bits.append("reverses %s" % vo.refs["reverses"].id)
    if "transfer_group" in vo.refs:
        bits.append(pair_text(vo))
    if vo.import_line:
        bits.append("bank statement line %s" % vo.import_line)
    if vo.amended_by:
        bits.append("amended by %s — not counted" % vo.amended_by.id)
    if vo.reversed_by:
        bits.append("reversed by %s" % vo.reversed_by.id)
    if vo.sheet:
        bits.append("counted by %s · witness %s" % (vo.sheet["counted_by"], vo.sheet["witness"]))
    if vo.authored != vo.date:
        bits.append("entered on %s" % fdate(vo.authored))
    if vo.tag == "distribution":
        bits.append("one entry — an interest line and a profit-share line for each partner")
    if vo.note:
        bits.append(vo.note)
    return " · ".join(bits)


def accts_cell(items):
    out = []
    for it in items:
        a, p = it[0], it[1]
        t = it[2] if len(it) > 2 and it[2] else None
        text = ("%s %s" % (a.name, fmt(p))) if len(items) > 1 else a.name
        if t:
            text += " (%s)" % TAG_LABEL.get(t, t)
        out.append(text)
    return "<br>".join(out)


def position_words(b):
    """*I* for a personal book, *we* for a family, a shared business or a trust, *the business* for a one-owner business."""
    if b.type == "personal":
        return ("What I have", "What I owe", "What I have and what I owe")
    if b.type == "business" and b.ownership == "just_me":
        return ("What the business has", "What it owes", "What the business has and what it owes")
    return ("What we have", "What we owe", "What we have and what we owe")


def section_chart(doc, b):
    rows = []
    tdr = tcr = 0
    for i, a in enumerate(b.accounts.values(), 1):
        if a.cls in ("category_income", "category_expense"):
            odr = ocr = "—"
        else:
            odr = fmt(a.opening) if a.opening > 0 else "—"
            ocr = fmt(-a.opening) if a.opening < 0 else "—"
            tdr += max(a.opening, 0)
            tcr += max(-a.opening, 0)
        what = a.note or ""
        if a.role == "link":
            what = "money owed between this book and " + b.uc.books[a.link_to].short.split(" — ")[0]
        rows.append([str(i), a.name, a.plain_type(), what, odr, ocr])
    assert tdr == tcr, (b.id, tdr, tcr)
    rows.append(["", "**Total of opening balances**", "", "", "**%s**" % fmt(tdr), "**%s**" % fmt(tcr)])
    doc.p("Every account in this book, in the order it was opened, with its balance on %s. Each opening balance is set against *%s*, so the Dr and Cr totals agree. Income and expense heads have no opening balance — they start every year at zero." % (fdate(b.start), b.ob().name))
    doc.table(["#", "Account", "Type", "What it is for", "Opening balance (Dr) ₹", "Opening balance (Cr) ₹"], rows, ["r", "l", "l", "l", "r", "r"])


def section_daybook(doc, b):
    rows = []
    for vo in b.sorted_vouchers():
        struck = (not vo.is_head()) or (vo.reversed_by is not None)
        narr = plain_narr(vo.narr)
        dr = accts_cell(vo.debits_t())
        cr = accts_cell(vo.credits_t())
        amt = fmt(vo.amount)
        if struck:
            narr, dr, cr, amt = ("~~%s~~" % x for x in (narr, dr, cr, amt))
        rows.append([fdate(vo.date), vo.id, KIND_LABEL[vo.kind], narr, dr, cr, amt, vo.by, voucher_note(vo)])
    doc.table(["Date", "Entry", "Type", "Details", "Where it went (Dr)", "Where it came from (Cr)", "Amount ₹", "Entered by", "Notes"],
              rows, ["n", "n", "l", "l", "l", "l", "r", "l", "l"])
    heads = sum(1 for v in b.vouchers if v.is_head())
    doc.p("*%d entries, of which %d count. An entry that was corrected or reversed is shown struck through and stays in the record. Every entry number appears in each account statement it touches.*" % (len(b.vouchers), heads))


def ledger_table(doc, b, a):
    dr_l, cr_l = a.col_labels()
    rows = []
    bal = 0
    tot_dr = tot_cr = 0
    is_cat = a.cls in ("category_income", "category_expense")
    if not is_cat:
        amt, side = fmt_signed_side(a.opening)
        # opening row (standards §2) — the b/f amount also sits in its own column so the Total row foots
        rows.append([fdate(FY_START), "", "Opening balance b/f", "—", "—", amt, side])
        bal = a.opening
        if a.opening > 0:
            tot_dr += a.opening
        elif a.opening < 0:
            tot_cr += -a.opening
    for vo, p, lt in b.ledger_lines(a):
        if vo.tag == "opening":
            continue
        counter = [x for x, q in vo.lines if x is not a]
        if p > 0:
            names = [x.name for x in counter if [q for y, q in vo.lines if y is x][0] < 0] or [x.name for x in counter]
            part = "To " + (names[0] if len(names) == 1 else "sundries (%s)" % ", ".join(names))
        else:
            names = [x.name for x in counter if [q for y, q in vo.lines if y is x][0] > 0] or [x.name for x in counter]
            part = "By " + (names[0] if len(names) == 1 else "sundries (%s)" % ", ".join(names))
        bal += p
        if p > 0:
            tot_dr += p
        else:
            tot_cr += -p
        amt, side = fmt_signed_side(bal)
        extra = ""
        if vo.reversed_by is not None:
            extra = " — reversed by %s" % vo.reversed_by.id
        if "reverses" in vo.refs:
            extra = " — reverses %s" % vo.refs["reverses"].id
        if vo.pending:
            extra = " — approved %s" % fdate(vo.pending["approved_on"])
        if lt:
            extra += " — %s line" % TAG_LABEL.get(lt, lt)
        rows.append([fdate(vo.date), vo.id, part + "<br><em>" + plain_narr(vo.narr) + extra + "</em>", fmt(p) if p > 0 else "—", fmt(-p) if p < 0 else "—", amt, side])
    if is_cat:
        amt, side = fmt_signed_side(bal)
        rows.append(["@@total", "", "", "Total for the year (%s)" % FY_LABEL, fmt(tot_dr) if tot_dr else "—", fmt(tot_cr) if tot_cr else "—", amt, side])
    else:
        cd_dr = fmt(-bal) if bal < 0 else "—"
        cd_cr = fmt(bal) if bal > 0 else "—"
        rows.append(["@@khata", fdate(FY_END), "", "Closing balance c/d", cd_dr, cd_cr, "—", "—"])
        tdr = tot_dr + (-bal if bal < 0 else 0)
        tcr = tot_cr + (bal if bal > 0 else 0)
        assert tdr == tcr, (a.name, tdr, tcr)
        rows.append(["@@total", "", "", "Total (incl. opening b/f)", fmt(tdr) if tdr else "—", fmt(tcr) if tcr else "—", "", ""])
        amt, side = fmt_signed_side(bal)
        rows.append(["@@khata", fdate(NEXT_FY_START), "", "Opening balance b/d (%s)" % NEXT_FY_LABEL,
                     fmt(bal) if bal > 0 else "—", fmt(-bal) if bal < 0 else "—", amt, side])
    doc.table(["Date", "Entry", "Particulars", dr_l, cr_l, "Balance ₹", "Side"], rows, ["n", "n", "l", "r", "r", "r", "c"])
    return bal


def ledger_check(b, a):
    """(opening, debits, credits, closing) in signed paise — the arithmetic behind each printed statement,
    reported in the technical companion (the printed report no longer carries a cross-check line)."""
    tot_dr = tot_cr = 0
    for vo, p, lt in b.ledger_lines(a):
        if vo.tag == "opening":
            continue
        if p > 0:
            tot_dr += p
        else:
            tot_cr += -p
    return a.opening, tot_dr, tot_cr, a.opening + tot_dr - tot_cr


def section_ledgers(doc, b):
    for a in b.accounts.values():
        rows = b.ledger_rows(a)
        doc.h(4, a.name)
        if not rows and not a.opening:
            doc.p("*%s. %s* No entries this year; balance nil." % (a.plain_type(), a.plain_natural()))
            continue
        doc.p("*%s. %s*" % (a.plain_type(), a.plain_natural()))
        ledger_table(doc, b, a)


def section_tb(doc, b):
    rows_, tdr, tcr = trial_balance(b)
    rows = []
    for a, p in rows_:
        rows.append([a.name, a.plain_type(), fmt(p) if p > 0 else "—", fmt(-p) if p < 0 else "—"])
    rows.append(["@@total", "Total", "", fmt(tdr), fmt(tcr)])
    doc.p("Every account's balance on %s, on the side it falls. The two totals agree — that is the check that the books balance." % fdate(FY_END))
    doc.table(["Account", "Type", "Closing balance (Dr) ₹", "Closing balance (Cr) ₹"], rows, ["l", "l", "r", "r"])
    doc.p("**Dr total %s = Cr total %s — the books balance.**" % (rs(tdr), rs(tcr)))
    return tdr


def section_periods(doc, b):
    rows = []
    for mk, lk in b.locks.items():
        y, m = int(mk[:4]), int(mk[5:])
        me = month_end(date(y, m, 1))
        counts = [c for c in b.counts if month_key(c["date"]) == mk]
        ctext = []
        for c in counts:
            if c["diff"] == 0:
                ctext.append("%s %s: book %s = counted %s ✓ verified" % (fdate(c["date"]), c["acct"].name, fmt(c["book_before"]), fmt(c["counted"])))
            else:
                ctext.append("%s %s: book %s, counted %s → %s %s, %s" % (fdate(c["date"]), c["acct"].name, fmt(c["book_before"]), fmt(c["counted"]),
                                                                         "short" if c["diff"] < 0 else "excess", fmt(c["diff"]), c["voucher"].id))
        bal = b.balances(as_of=me, authored_before=lk["date"])
        susp = [a for a in b.accounts.values() if a.role == "suspense"]
        stext = ("unexplained money: %s" % ("nil" if bal[susp[0].id] == 0 else fmt(bal[susp[0].id]))) if susp else None
        flags = [vo for vo in b.vouchers if vo.review and vo.date <= me and vo.review["decided"] >= lk["date"]]
        pend = [vo for vo in b.vouchers if vo.pending and vo.date <= me and vo.pending["approved_on"] >= lk["date"]]
        cleared = [vo for vo in b.vouchers if vo.review and vo.date <= me and me < vo.review["decided"] < lk["date"]]
        aged = []
        for a in b.accounts.values():
            if a.cls == "advance":
                rows_a = [(vo.date, p) for vo, p in b.ledger_rows(a) if vo.date <= me]
                oldest, open_amt = fifo_ageing(rows_a, me)
                if oldest and (me - oldest).days > ADVANCE_WARN_DAYS:
                    aged.append("%s %s, open %d days (a reminder, not a block)" % (a.name, fmt(open_amt), (me - oldest).days))
        tray = []
        if stext:
            tray.append(stext)
        tray.append("entries waiting for approval: %s" % ("none" if not flags else ", ".join("%s (decided %s)" % (v.id, fdate(v.review["decided"])) for v in flags)))
        if cleared:
            tray.append("approved between the month end and the closing: " + ", ".join("%s (decided %s)" % (v.id, fdate(v.review["decided"])) for v in cleared))
        tray.append("advance requests waiting: %s" % ("none" if not pend else ", ".join(v.id for v in pend)))
        if aged:
            tray.append("advances open more than %d days: " % ADVANCE_WARN_DAYS + "; ".join(aged))
        rows.append([month_label(mk), fdate(lk["date"]), lk["by"], "<br>".join(ctext) if ctext else "—", "<br>".join(tray)])
    doc.p("Cash is counted at the close of the month's last day and any difference is entered that day; the month is then closed a few days later. A month is closed only when nothing is waiting: no unexplained money, no entry waiting for approval, no advance request waiting.")
    doc.table(["Month", "Closed on", "Closed by", "Cash counts", "At the closing"], rows, ["l", "l", "l", "l", "l"])
    # denomination sheets for trusts
    if b.type == "organization":
        doc.h(4, "Note-count sheets — every cash count of the trust")
        rows = []
        for c in b.counts:
            den = c["denoms"]
            rows.append([fdate(c["date"]), c["acct"].name, fmt(c["counted"]), denoms_text(den), c["by"] + ((" · witness " + c["witness"]) if c["witness"] else "")])
        for vo in b.sorted_vouchers():
            if vo.tag == "gollak_count":
                rows.append([fdate(vo.date), "%s (count = income, %s)" % ([a for a, p in vo.lines if p > 0][0].name, vo.id), fmt(vo.amount), denoms_text(vo.sheet["denoms"]),
                             "counted by %s · witness %s" % (vo.sheet["counted_by"], vo.sheet["witness"])])
        rows.sort(key=lambda r: (r[0][7:], MONTHS.index(r[0][3:6]), int(r[0][:2])))
        doc.table(["Date", "Account", "Counted ₹", "Notes and coins", "Counted by"], rows, ["l", "l", "r", "l", "l"])


def denoms_text(den):
    parts = []
    for k, n in den.items():
        if k == "coins":
            if n:
                parts.append("coins %s" % fmt(n))
        elif n:
            parts.append("%d×%d" % (n, k))
    return ", ".join(parts)


def pl_titles(b):
    """Year-end statement names by book type (07 §14 *Profit/Loss*; a trust's is its Income & Expenditure Account),
    printed under one plain heading, *Income and expenses for the year*."""
    if b.type == "organization":
        return ("Income and expenses for the year — Income & Expenditure Account, %s" % FY_LABEL, "Spent (Dr) ₹", "Received (Cr) ₹",
                "Excess of income over spending (surplus) — added to the Corpus", "Excess of spending over income (deficit) — taken from the Corpus")
    if b.type == "business":
        return ("Income and expenses for the year — Profit & Loss Account, %s" % FY_LABEL, "Expenses (Dr) ₹", "Income (Cr) ₹",
                "Net profit for the year", "Net loss for the year")
    return ("Income and expenses for the year — %s" % FY_LABEL, "Spent (Dr) ₹", "Income (Cr) ₹",
            "Saved this year (income more than spending)", "Spent more than earned this year (deficit)")


def section_pl(doc, b):
    """Every income and expense head with its total for the year — the figure its ledger's *Total for FY* row shows."""
    title, dr_h, cr_h, surplus_l, deficit_l = pl_titles(b)
    bal = b.balances(as_of=FY_END)
    n_entries = {}
    for vo in b.vouchers:
        if vo.date <= FY_END and vo.counted():
            for a, p in vo.lines:
                if p:
                    n_entries[a.id] = n_entries.get(a.id, 0) + 1
    rows = []
    tdr = tcr = 0
    heads = [a for a in b.accounts.values() if a.cls == "category_expense"] + [a for a in b.accounts.values() if a.cls == "category_income"]
    for a in heads:
        p = bal[a.id]
        n = n_entries.get(a.id, 0)
        if p == 0 and n == 0:
            continue
        if p > 0:
            rows.append(["To %s" % a.name, str(n), fmt(p), "—"])
            tdr += p
        elif p < 0:
            rows.append(["By %s" % a.name, str(n), "—", fmt(-p)])
            tcr += -p
        else:
            rows.append(["%s (nets to nil)" % a.name, str(n), "—", "—"])
    inc, exp, net = b.net_result()
    assert tcr - tdr == net, (b.id, tcr, tdr, net)
    rows.append(["**Total of the heads for the year**", "", "**%s**" % fmt(tdr), "**%s**" % fmt(tcr)])
    if net > 0:
        rows.append(["To %s" % surplus_l, "", fmt(net), "—"])
    elif net < 0:
        rows.append(["By %s" % deficit_l, "", "—", fmt(-net)])
    grand = max(tdr, tcr)
    rows.append(["**Total**", "", "**%s**" % fmt(grand), "**%s**" % fmt(grand)])
    doc.p("%s: income %s · %s %s · **%s %s**. Each head shows its **total for the whole year** — the same figure as the *Total for the year* row of its statement above — and how many entries made it up. Income and expense heads are not carried forward; they start %s at zero." % (
        FY_LABEL, rs(inc), "spent" if b.type != "business" else "expenses", rs(exp),
        ("surplus" if b.type != "business" else "net profit") if net >= 0 else ("deficit" if b.type != "business" else "net loss"), rs(abs(net)), NEXT_FY_LABEL))
    doc.table(["Particulars", "Entries", dr_h, cr_h], rows, ["l", "r", "r", "r"])


def equity_label(b):
    """02 §1.2's name of the computed line — also the key of its figure in fixtures.json, so it never changes with the print."""
    if b.type == "organization":
        return "Corpus"
    if b.type == "personal":
        return "Net worth (accumulated surplus)"
    return "Accumulated surplus"


def equity_plain_label(b):
    """The same line in the words the printed report uses."""
    if b.type == "organization":
        return "Corpus — the trust's own funds"
    if b.type == "personal":
        return "Net worth — what is mine after what I owe"
    if b.type == "business" and b.ownership == "shared":
        return "Partners' funds in the business (accumulated surplus)"
    if b.type == "business":
        return "Owner's funds in the business (accumulated surplus)"
    return "Family's own funds (accumulated surplus)"


def equity_parts(b):
    """The computed equity line (02 §1.2, ADR 2026-09-05e §2): opening equity − adjustments + net result − drawings − distributions.
    Returns ([(label, signed paise, + = Dr)], computed equity as a Cr-positive figure)."""
    bal = b.balances(as_of=FY_END)
    inc, exp, net = b.net_result()
    parts = [(b.ob().name + " (opening own money and capital put in)", bal[b.ob().id])]
    for a in b.accounts.values():
        if a.role == "adjustments" and bal[a.id]:
            parts.append((a.name + " (cash-count differences, amounts written off)", bal[a.id]))
    word = ("profit" if net >= 0 else "loss") if b.type == "business" else ("surplus" if net >= 0 else "deficit")
    parts.append(("Net %s for %s (from the income and expenses above)" % (word, FY_LABEL), -net))
    for a in b.accounts.values():
        if a.role == "drawings" and bal[a.id]:
            parts.append((a.name + " (taken out by the owner)", bal[a.id]))
        if a.role == "profit_distributed" and bal[a.id]:
            parts.append((a.name + " (profit shares and interest credited to the partners)", bal[a.id]))
    computed = -sum(p for _, p in parts)
    return parts, computed


def section_position(doc, b):
    """07 §14 *Full Position* — balance-sheet layout by sign (02 §1.2): every carried account on the side its balance says."""
    bal = b.balances(as_of=FY_END)
    label = equity_plain_label(b)
    has_w, owe_w, both_w = position_words(b)
    parts, computed = equity_parts(b)
    rows = []
    has = owes = 0
    for a in b.accounts.values():
        if not a.carried() or a.role in ("opening_balance", "adjustments", "drawings", "profit_distributed", "suspense"):
            assert not (a.role == "suspense" and bal[a.id]), (b.id, "suspense at year end")
            continue
        p = bal[a.id]
        if p > 0:
            rows.append([a.name, a.plain_type(), fmt(p), "—"])
            has += p
        elif p < 0:
            rows.append([a.name, a.plain_type(), "—", fmt(-p)])
            owes += -p
        else:
            rows.append([a.name, a.plain_type(), "—", "—"])
    assert has - owes == computed, (b.id, has, owes, computed)
    if computed >= 0:
        rows.append(["**%s** — made up below" % label, "own money", "—", fmt(computed)])
    else:
        rows.append(["**%s — negative** — made up below" % label, "own money", fmt(-computed), "—"])
    grand = max(has, owes + computed) if computed >= 0 else has - computed
    rows.append(["**Total**", "", "**%s**" % fmt(grand), "**%s**" % fmt(grand)])
    doc.p("%s on %s: money in hand and in the bank, what others will pay, advances held (Dr), against what is still to be paid — people and shops, bank loans and cards, partners' balances (Cr). Each account sits on the side its balance falls. The difference is the **%s**, a figure worked out from the others and not an account of its own." % (both_w, fdate(FY_END), label))
    doc.table(["Account", "Type", "%s (Dr) ₹" % has_w, "%s (Cr) ₹" % owe_w], rows, ["l", "l", "r", "r"])
    rows = []
    for name, p in parts:
        amt, side = fmt_signed_side(p)
        rows.append([name, amt, side])
    ca, cs = fmt_signed_side(-computed)
    rows.append(["= **%s**" % label, "**%s**" % ca, cs])
    doc.h(4, "How the %s is made up" % label.split(" (")[0].split(" — ")[0])
    doc.table(["Particulars", "Amount ₹", "Side"], rows, ["l", "r", "c"])


def section_year_close(doc, b, close_date, closer):
    vec, net = closing_vector(b)
    rows = []
    for a, p in vec:
        amt, side = fmt_signed_side(p)
        rows.append([a.name, a.plain_type(), amt, side])
    namt, nside = fmt_signed_side(-net)   # a surplus sits on the Cr side of the vector
    word = ("profit" if net >= 0 else "loss") if b.type == "business" else ("surplus" if net >= 0 else "deficit")
    rows.append(["**Net %s for %s** — one line; income and expense heads are not carried" % (word, FY_LABEL), "this year's result", namt, nside])
    tot = sum(p for _, p in vec) - net
    assert tot == 0, (b.id, tot)
    vdr = sum(p for _, p in vec if p > 0) + (-net if net < 0 else 0)
    vcr = -sum(p for _, p in vec if p < 0) + (net if net > 0 else 0)
    assert vdr == vcr, (b.id, vdr, vcr)
    doc.p("The year was closed on %s by %s, after every month had been closed with nothing waiting — no unexplained money, no entry waiting for approval, no advance request waiting. These are the balances on %s that carry into %s; every member's phone works them out from the same entries and gets the same figures." % (fdate(close_date), closer, fdate(FY_END), NEXT_FY_LABEL))
    doc.table(["Account carried to %s (balance on %s)" % (NEXT_FY_LABEL, fdate(FY_END)), "Type", "Balance ₹", "Side"], rows, ["l", "l", "r", "c"])
    doc.p("The carried balances agree: Dr %s = Cr %s. No closing entry is posted — the balances simply carry forward." % (rs(vdr), rs(vcr)))
    parts, computed = equity_parts(b)
    rows = []
    for a, p in vec:
        amt, side = fmt_signed_side(p)
        rows.append([a.name, amt, side])
    doc.h(4, "%s opening balances (as on %s)" % (NEXT_FY_LABEL, fdate(NEXT_FY_START)))
    doc.table(["Account", "Opening balance ₹", "Side"], rows, ["l", "r", "c"])
    doc.p("Income and expense heads open %s at zero. Each account statement for %s starts from these figures." % (NEXT_FY_LABEL, NEXT_FY_LABEL))
    b.year_close = {"date": close_date, "by": closer, "net": net, "vector": [(a.id, p) for a, p in vec], "computed_equity": computed, "label": equity_label(b)}


def section_corrections(doc, b):
    items = []
    for vo in b.sorted_vouchers():
        if "amends" in vo.refs:
            o = vo.refs["amends"]
            items.append("**Corrected in an open month:** %s (%s, %s) was corrected by %s on %s (%s). Only the corrected entry counts; the original stays in the record, struck through." % (
                o.id, fdate(o.date), rs(o.amount), vo.id, fdate(vo.authored), rs(vo.amount)))
        if "reverses" in vo.refs:
            o = vo.refs["reverses"]
            if o.review and o.review["decision"] == "rejected":
                items.append("**Rejected:** %s (%s, %s, entered by %s over the %s limit) was rejected by %s on %s — reason: *%s*. The app entered the reversal %s on its own; both entries stay visible and together they come to nil." % (
                    o.id, fdate(o.date), rs(o.amount), o.by, rs(o.review["limit"]), o.review["approver"], fdate(o.review["decided"]), o.review["reason"], vo.id))
            else:
                lk = b.locks.get(month_key(o.date))
                items.append("**Correction of a closed month:** %s (%s) belongs to %s, which was closed on %s. A closed month is never changed, so the fix is the reversal %s dated %s in the open month, plus the corrected entry %s. The closed month's figures stay as they were; the fix shows in the month it was made." % (
                    o.id, fdate(o.date), month_label(month_key(o.date)), fdate(lk["date"]) if lk else "—", vo.id, fdate(vo.date),
                    (vo.refs.get("reentry").id if vo.refs.get("reentry") else "—")))
        if vo.review and vo.review["decision"] == "approved":
            items.append("**Approved after review:** %s (%s, %s) by %s was over the member's limit of %s. It was entered at once and marked for review, and %s approved it on %s. The approval changed no figure." % (
                vo.id, fdate(vo.date), rs(vo.amount), vo.by, rs(vo.review["limit"]), vo.review["approver"], fdate(vo.review["decided"])))
    if items:
        doc.ul(items)
    else:
        doc.p("No correction, reversal or approval was needed in this book this year.")


def section_advances(doc, b):
    advs = [a for a in b.accounts.values() if a.cls == "advance"]
    if not advs:
        return False
    for a in advs:
        doc.h(4, a.name)
        rows = []
        bal = 0
        for vo, p in b.ledger_rows(a):
            bal += p
            what = {"advance_out": "handed out (request approved)", "advance_spend": "bills submitted", "advance_return": "remainder returned", "write_off": "written off (approved, with the reason)"}.get(vo.tag, vo.tag or "")
            note = ""
            if vo.pending:
                note = "asked %s · approved %s by %s · not counted until approved" % (fdate(vo.pending["requested"]), fdate(vo.pending["approved_on"]), vo.pending["approver"])
            rows.append([fdate(vo.date), vo.id, what, fmt(p) if p > 0 else "—", fmt(-p) if p < 0 else "—", fmt(bal), note or plain_narr(vo.narr)])
        doc.table(["Date", "Entry", "What happened", "Handed out ₹", "Settled ₹", "Still held ₹", "Note"], rows, ["l", "l", "l", "r", "r", "r", "l"])
        # ageing at each month end
        age_rows = []
        for mk in fy_months():
            y, m = int(mk[:4]), int(mk[5:])
            me = month_end(date(y, m, 1))
            rows_a = [(vo.date, p) for vo, p in b.ledger_rows(a) if vo.date <= me]
            oldest, open_amt = fifo_ageing(rows_a, me)
            if oldest:
                days = (me - oldest).days
                age_rows.append([month_label(mk), fmt(open_amt), fdate(oldest), str(days), "reminder due — open more than %d days" % ADVANCE_WARN_DAYS if days > ADVANCE_WARN_DAYS else "—"])
        if age_rows:
            doc.table(["Month end", "Still held ₹", "Held since", "Days", "Reminder"], age_rows, ["l", "r", "l", "r", "l"])
        else:
            doc.p("Settled within every month — never overdue.")
    return True


def section_party_ageing(doc, b, parties, as_on=FY_END):
    rows = []
    for a in parties:
        rows_a = [(vo.date, p) for vo, p in b.ledger_rows(a)]
        if a.opening:
            rows_a.insert(0, (FY_START, 0))
        oldest, open_amt = fifo_ageing([(dt, p) for dt, p in rows_a if p], as_on)
        bal = b.balance(a)
        amt, side = fmt_signed_side(bal)
        if oldest:
            days = (as_on - oldest).days
            chip = "more than 90 days (red)" if days > 90 else ("more than 30 days (amber)" if days > 30 else "current")
            rows.append([a.name, "%s %s" % (amt, side), fmt(open_amt), fdate(oldest), str(days), chip])
        else:
            rows.append([a.name, "%s %s" % (amt, side), "—", "—", "—", "nothing to get"])
    doc.table(["Person / shop", "Balance", "You will get ₹", "Owed since", "Days", "How old"], rows, ["l", "r", "r", "l", "r", "l"])


def book_header(doc, b):
    doc.h(2, "Book: %s" % b.name)
    mem = "; ".join("%s — %s%s%s" % (m[0], m[1], (" (%s)" % m[3]) if len(m) > 3 and m[3] else "",
                                     (", entry limit %s" % rs(m[2])) if m[2] is not None else ", no limit") for m in b.members)
    own = ""
    if b.type == "business":
        own = " (" + ("just me" if b.ownership == "just_me" else "shared with others") + ")"
    doc.p("%s%s · started %s · members: %s." % (BOOK_TYPE_LABEL[b.type], own, fdate(b.start), mem))
    for n in b.notes:
        doc.p(n)
    for line in b.plain:
        doc.p(line)
    for sa in b.structural_approvals:
        doc.p("Decision recorded on %s — %s. Approved by: %s." % (fdate(sa["date"]), sa["what"], sa["approvals"]))


def build_report(uc, close_date, closer_by_book, extra_sections=None):
    doc = DualDoc(uc.title)
    doc.p("**About this book:** %s. %s" % (uc.entity, uc.intro))
    doc.p("**Period:** %s – %s (%s) · every month closed · year closed. Sample report — the figures are illustrative.")
    doc.blocks[-1] = ("p", doc.blocks[-1][1] % (fdate(FY_START), fdate(FY_END), FY_LABEL))
    doc.table(["Person", "Role in this example"], [[n, r] for n, r in uc.people], ["l", "l"])
    doc.p("How to read it: amounts are in ₹, with paise shown only when they are not zero. Every statement is written the way a ledger book is, with the plain meaning first and the true side in brackets — Money in (Dr), Money out (Cr), You will get (Dr), You will give (Cr). "
          "An account statement runs Date · Entry · Particulars (*To …* on the Dr side, *By …* on the Cr side) · Dr · Cr · Balance · Side; it opens with the balance brought forward and ends with the closing balance carried down, the totals and the opening balance for the new year. Income and expense heads have no opening balance and end with their total for the year.")
    tb_totals = OrderedDict()
    for b in uc.books.values():
        book_header(doc, b)
        start_blk = len(doc.blocks)
        doc.h(3, "1. Accounts and opening balances")
        section_chart(doc, b)
        doc.h(3, "2. Account statements (ledgers) — every account of the book")
        section_ledgers(doc, b)
        doc.h(3, "3. Day book — every entry in date order")
        section_daybook(doc, b)
        doc.h(3, "4. Corrections and approvals")
        section_corrections(doc, b)
        doc.h(3, "5. Months closed and cash counts")
        section_periods(doc, b)
        if any(a.cls == "advance" for a in b.accounts.values()):
            doc.h(3, "6. Advances — money held by a member")
            section_advances(doc, b)
        if extra_sections and b.id in extra_sections:
            for fn in extra_sections[b.id]:
                fn(doc, b)
        doc.h(3, "7. Closing balances (trial balance) as on %s" % fdate(FY_END))
        tb_totals[b.id] = section_tb(doc, b)
        doc.h(3, "8. " + pl_titles(b)[0])
        section_pl(doc, b)
        doc.h(3, "9. %s (position) as on %s" % (position_words(b)[2], fdate(FY_END)))
        section_position(doc, b)
        doc.h(3, "10. Year end — balances carried to %s" % NEXT_FY_LABEL)
        section_year_close(doc, b, close_date, closer_by_book.get(b.id, b.admins()[0]))
        # number this book's sections in the order they were written (optional and book-specific ones vary)
        n = 0
        for i in range(start_blk, len(doc.blocks)):
            blk = doc.blocks[i]
            if blk[0] == "h" and blk[1] == 3:
                n += 1
                doc.blocks[i] = ("h", 3, re.sub(r"^\d+\. ", "%d. " % n, blk[2]))
    for blk in uc.sections:
        blk(doc)
    return doc, tb_totals


# ----------------------------------------------------------------------------------------------
# Partner computations (02 §7.1) — interest on capital, residual split, position, settlement
# ----------------------------------------------------------------------------------------------
def partner_interest(b, partners, rate_bp):
    """Σ end-of-day Cr balances over the FY × rate ÷ 365, half-up to the paisa, per partner.
    Debit days earn nothing and are not charged (02 §7.1 ⚠️, ADR 2026-09-05e Open 2 — see README ⚠️ SPEC)."""
    out = []
    for a in partners:
        series = b.daily_balance_series(a, exclude_tags=("distribution",))
        s = sum(-bal for _, bal in series if bal < 0)   # Cr balances are negative signed
        cr_days = sum(1 for _, bal in series if bal < 0)
        num = s * rate_bp
        den = 10000 * 365
        interest = round_half_up(num, den)
        # exact value to 4 decimals of a paisa for the report
        q, r = divmod(num, den)
        frac = (r * 10000) // den
        rup, ps = divmod(q, 100)
        out.append({"acct": a, "sum_cr_bal": s, "cr_days": cr_days, "interest": interest, "exact": "%s.%02d%04d" % (indian(rup), ps, frac)})
    return out


def distribute(b, dt, by, partners, weights, rate_bp, approvals_text):
    """ONE multi-line entry (02 §7.1; the engine's Verbs.profitDistribution): Dr Profit Distributed (net profit) ·
    Cr each partner's interest line (tagged `interest`) · Cr each partner's share line (tagged `share`). Moves no cash."""
    inc, exp, net = b.net_result()
    pd = b.eq("profit_distributed")
    ints = partner_interest(b, partners, rate_bp)
    tot_int = sum(i["interest"] for i in ints)
    residual = net - tot_int
    shares, rem, idx = split_by_ratio(residual, weights)
    lines = [(pd, net)] + [(i["acct"], -i["interest"], "interest") for i in ints if i["interest"]] + [(a, -sh, "share") for a, sh in zip(partners, shares) if sh]
    rate_txt = str(rate_bp // 100) if rate_bp % 100 == 0 else "%d.%02d" % divmod(rate_bp, 100)
    narr = ("Profit for %s %s appropriated in one entry (02 §7.1): interest on capital at %s%% p.a., Actual/365, credited first — %s; the remaining %s shared %s — %s%s" % (
        FY_LABEL, rs(net), rate_txt,
        " · ".join("%s %s" % (i["acct"].name.split(" — ")[0], rs(i["interest"])) for i in ints),
        rs(residual), ":".join(str(w) for w in weights),
        " · ".join("%s %s" % (a.name.split(" — ")[0], rs(sh)) for a, sh in zip(partners, shares)),
        (" (remainder %d paise to %s, the largest ratio)" % (rem, partners[idx].name.split(" — ")[0])) if rem else ""))
    v = b.v(dt, "adjustment", narr, lines, by, t=9, tag="distribution")
    b.config["profit_distribution"] = OrderedDict([("date", dt), ("net", net), ("interest", ints), ("tot_int", tot_int), ("residual", residual),
                                                   ("shares", shares), ("rem", rem), ("rem_to", partners[idx]), ("weights", weights),
                                                   ("rate_bp", rate_bp), ("v", v), ("approvals", approvals_text), ("partners", partners)])
    return v


def section_partners(doc, b, partners, weights, drift_margin, settlement_note):
    cfg = b.config.get("profit_distribution")
    bal = b.balances()
    doc.h(3, "8. Partners — what each put in, took out and is owed")
    rows = []
    for a, w in zip(partners, weights):
        put = sum(-p for vo, p in b.ledger_rows(a) if p < 0 and vo.tag in ("opening", "own_pocket"))
        took = sum(p for vo, p in b.ledger_rows(a) if p > 0 and vo.tag == "takeout")
        intr = sum(-p for vo, p, t in b.ledger_lines(a) if p < 0 and t == "interest")
        shr = sum(-p for vo, p, t in b.ledger_lines(a) if p < 0 and t == "share")
        amt, side = fmt_signed_side(bal[a.id])
        rows.append([a.name, str(w), fmt(put), fmt(took) if took else "—", fmt(intr) if intr else "—", fmt(shr) if shr else "—", "**%s %s**" % (amt, side),
                     "the business owes them" if bal[a.id] < 0 else ("they owe the business" if bal[a.id] > 0 else "nil")])
    doc.table(["Partner", "Share", "Put in (opening + own pocket) ₹", "Took out ₹", "Interest ₹", "Profit share ₹", "Balance", "Meaning"], rows, ["l", "r", "r", "r", "r", "r", "r", "l"])
    if cfg:
        doc.h(4, "Interest on capital — worked out to the paisa")
        doc.p("The setting agreed by every partner and in force all year: %s%% a year, counted day by day over the %d days of %s, on credit balances only — a partner's debit days earn nothing and are charged nothing. Interest = the sum of each day's closing credit balance × rate ÷ 365, rounded half-up to the paisa for each partner. The interest and the profit shares are entered together as one entry at the year end." % (
            cfg["rate_bp"] // 100, 365, FY_LABEL))
        rows = []
        for i in cfg["interest"]:
            rows.append([i["acct"].name, fmt(i["sum_cr_bal"]), str(i["cr_days"]), i["exact"], "**%s**" % fmt(i["interest"])])
        rows.append(["@@total", "Total interest credited by entry %s" % cfg["v"].id, "", "", "", fmt(cfg["tot_int"])])
        doc.table(["Partner", "Sum of daily Cr balances ₹", "Days in credit", "× %d%% ÷ 365 (exact)" % (cfg["rate_bp"] // 100), "Rounded to the paisa ₹"], rows, ["l", "r", "r", "r", "r"])
        doc.h(4, "Profit shared by the agreed ratio")
        inc, exp, net = b.net_result()
        doc.p("Net profit for %s = income %s − expenses %s = **%s**. Less the interest %s leaves **%s** (%s paise) to share %s. Each partner's share is worked out in whole paise and rounded down; the %d paise left over go to %s, the partner with the largest share." % (
            FY_LABEL, rs(inc), rs(exp), rs(net), rs(cfg["tot_int"]), rs(cfg["residual"]), indian(cfg["residual"]), " : ".join(str(w) for w in weights), cfg["rem"], cfg["rem_to"].name.split(" — ")[0]))
        sw = sum(weights)
        rows = []
        for a, w, s in zip(partners, weights, cfg["shares"]):
            fl = (abs(cfg["residual"]) * w) // sw
            rows.append([a.name, "%d/%d" % (w, sw), indian(fl) + " paise", ("+%d" % (s - fl)) if s - fl else "—", "**%s**" % fmt(s)])
        rows.append(["@@total", "Total profit shared by entry %s" % cfg["v"].id, "", "", "", fmt(cfg["residual"])])
        doc.table(["Partner", "Ratio", "Share before rounding", "Paise left over", "Share ₹"], rows, ["l", "r", "r", "r", "r"])
        doc.p("Check: the total shared out, %s, is within what the business had to share (this year's profit %s plus the own money it started with, %s)." % (
            rs(cfg["tot_int"] + cfg["residual"]), rs(net), rs(-bal[b.ob().id])))
        b.uc.tech_notes.append(("Partner appropriation — %s" % b.id, [
            "Setting in force all year: %s%% p.a., Actual/365, **credit balances only** — chosen deliberately: 02 §7.1's default charges a debit balance at the same rate *unless the setting says otherwise* (⚠️ open there; ADR 2026-09-05e Open 2); recorded as a dated `business_setting` with every partner's approval (%s). Interest = Σ(end-of-day credit balance) × rate ÷ 365, rounded half-up to the paisa per partner, independently (02 §7.1 — not a ratio split, so no remainder rule). Interest and the residual shares are posted together as one multi-line `adjustment` (02 §7.1; the engine's `Verbs.profitDistribution`), the partner lines tagged `interest` and `share`." % (cfg["rate_bp"] // 100, cfg["approvals"]),
            "Residual split: net profit %s (no distribution earlier in the FY, ADR 2026-09-05e §8) less interest %s = %s paise, split %s by `floor(amount × weight ÷ Σweights)` in integer paise; remainder %d paise → %s (largest ratio; ties go to the earliest-created partner account). Ceiling check: cumulative distributions %s ≤ accumulated surplus before distribution (net result %s + opening equity %s) ✓." % (
                rs(net), rs(cfg["tot_int"]), indian(cfg["residual"]), ":".join(str(w) for w in weights), cfg["rem"], cfg["rem_to"].name, rs(cfg["tot_int"] + cfg["residual"]), rs(net), rs(-bal[b.ob().id])),
        ]))
    # settlement capacity
    money = sum(bal[a.id] for a in b.accounts.values() if a.cls == "money")
    cr_total = sum(-bal[a.id] for a in partners if bal[a.id] < 0)
    if money >= cr_total:
        sent = "**The business could pay every partner out today** — cash and bank %s, partners' credit balances %s." % (rs(money), rs(cr_total))
    else:
        sent = "**Short by %s to pay every partner out today** — cash and bank %s against partners' credit balances %s." % (rs(cr_total - money), rs(money), rs(cr_total))
    doc.h(4, "Could the business pay the partners out today?")
    doc.p(sent)
    n = len(partners)
    avg = sum(-bal[a.id] for a in partners) // n
    cards = []
    for a in partners:
        v = -bal[a.id]
        if v - avg > drift_margin:
            cards.append("A note the app shows (when a partner is more than %s above the others' average): *\"%s has %s more with the business than the group average\"* — information, never a demand." % (rs(drift_margin), a.name.split(" — ")[0], rs(v - avg)))
    if cards:
        for c in cards:
            doc.p(c)
    else:
        doc.p("No partner is more than %s above the others' average, so the app shows no note." % rs(drift_margin))
    doc.ul(["Pay a partner out from the business bank account — offered; needs the cash.",
            "Settle between partners outside the business — offered; not taken.",
            "**Carry the balances forward (chosen):** every partner's balance closes at the year end and re-opens as a dated opening balance for the new year — never a remembered number. See the year-end section."])
    b.uc.tech_notes.append(("Partner settlement routes — %s" % b.id, [
        "Route 1 — business pays out a partner's balance (`Dr Partner Current · Cr bank`): offered; needs cash. Route 2 — partner-to-partner settlement outside the business (`Dr over-funded partner · Cr under-funded partner`): offered; not taken. Route 3 — carry forward (preselected, taken): every partner balance closes and re-opens under the year-close ceremony as a certified, dated opening balance (02 §7.1, 02 §8.1). Drift card margin %s (07 §7 partner card, informational)." % rs(drift_margin)]))
    if settlement_note:
        doc.p(settlement_note)


# ----------------------------------------------------------------------------------------------
# Fixtures
# ----------------------------------------------------------------------------------------------
def fixtures_for(ucs):
    out = OrderedDict()
    out["schema"] = "rukka-folio.worked-examples-usecases/1"
    out["status"] = "PROVISIONAL — pending bookkeeper sign-off (ADR 2026-10-11)"
    out["fy"] = OrderedDict([("start", FY_START.isoformat()), ("end", FY_END.isoformat())])
    out["conventions"] = OrderedDict([("amounts", "integer paise; lines signed, + = Dr, − = Cr"),
                                      ("order", "running balances sort by (accounting_date, t, seq) — t and seq stand in for the HLC"),
                                      ("kind_by_shape", "advance, partner and inter-book one-sided postings carry the kind nearest their 02 §1.4 rule-7 shape; see README ⚠️ SPEC")])
    cases = []
    for uc in ucs:
        c = OrderedDict([("slug", uc.slug), ("title", uc.title), ("entity", uc.entity)])
        books = []
        for b in uc.books.values():
            bo = OrderedDict([("id", b.id), ("name", b.name), ("type", b.type), ("ownership", b.ownership), ("start_date", b.start.isoformat()),
                              ("members", [OrderedDict([("name", m[0]), ("role", m[1]), ("auto_post_limit_paise", m[2]), ("designation", m[3] if len(m) > 3 else None)]) for m in b.members])])
            cfg = OrderedDict()
            for k, v in b.config.items():
                if k == "profit_distribution":
                    cfg[k] = OrderedDict([("date", v["date"].isoformat()), ("net_paise", v["net"]), ("rate_bp", v["rate_bp"]), ("weights", v["weights"]),
                                          ("interest_paise", [i["interest"] for i in v["interest"]]), ("residual_paise", v["residual"]), ("shares_paise", v["shares"]),
                                          ("remainder_paise", v["rem"]), ("remainder_to", v["rem_to"].id), ("voucher", v["v"].id),
                                          ("partners", [a.id for a in v["partners"]])])
                else:
                    cfg[k] = v
            bo["config"] = cfg
            bo["accounts"] = [OrderedDict([("id", a.id), ("name", a.name), ("class", a.cls), ("subtype", a.subtype), ("role", a.role),
                                           ("link_to", a.link_to), ("opening_paise", a.opening)]) for a in b.accounts.values()]
            vs = []
            for vo in b.sorted_vouchers():
                r = OrderedDict([("id", vo.id), ("accounting_date", vo.date.isoformat()), ("authored", vo.authored.isoformat()), ("kind", vo.kind),
                                 ("status", "pending→posted" if vo.pending else "posted"), ("narration", vo.narr),
                                 ("lines", [OrderedDict([("account", a.id), ("amount_paise", p)] + ([("tag", t)] if t else [])) for a, p, t in vo.tagged_lines()]),
                                 ("created_by", vo.by), ("tag", vo.tag)])
                refs = OrderedDict()
                for k in ("amends", "reverses"):
                    if k in vo.refs:
                        refs[k] = vo.refs[k].id
                if "transfer_group" in vo.refs:
                    refs["transfer_group"] = vo.refs["transfer_group"]
                if vo.import_line:
                    refs["import_line"] = vo.import_line
                if refs:
                    r["refs"] = refs
                lim = b.member(vo.by)[2]
                r["review_required"] = bool(vo.review)
                r["review_limit_paise"] = lim
                if vo.review:
                    r["review"] = OrderedDict([("approver", vo.review["approver"]), ("decided", vo.review["decided"].isoformat()), ("decision", vo.review["decision"]), ("reason", vo.review.get("reason"))])
                if vo.pending:
                    r["advance_request"] = OrderedDict([("requested", vo.pending["requested"].isoformat()), ("approved_on", vo.pending["approved_on"].isoformat()), ("approver", vo.pending["approver"])])
                if vo.sheet:
                    r["count_sheet"] = OrderedDict([("counted_by", vo.sheet["counted_by"]), ("witness", vo.sheet["witness"]), ("denominations", OrderedDict((str(k), n) for k, n in vo.sheet["denoms"].items()))])
                if vo.amended_by:
                    r["amended_by"] = vo.amended_by.id
                if vo.reversed_by:
                    r["reversed_by"] = vo.reversed_by.id
                vs.append(r)
            bo["vouchers"] = vs
            bo["period_locks"] = [OrderedDict([("month", mk), ("locked_on", lk["date"].isoformat()), ("by", lk["by"])]) for mk, lk in b.locks.items()]
            bo["cash_counts"] = [OrderedDict([("date", c["date"].isoformat()), ("account", c["acct"].id), ("book_paise", c["book_before"]), ("counted_paise", c["counted"]),
                                              ("difference_paise", c["diff"]), ("adjustment", c["voucher"].id if c["voucher"] else None), ("by", c["by"]), ("witness", c["witness"]),
                                              ("denominations", OrderedDict((str(k), n) for k, n in c["denoms"].items()) if c["denoms"] else None)]) for c in sorted(b.counts, key=lambda c: (c["date"], c["acct"].id))]
            rows, tdr, tcr = trial_balance(b)
            bo["expected"] = OrderedDict([("closing_balances_paise", OrderedDict((a.id, p) for a, p in rows)), ("tb_total_paise", tdr),
                                          ("net_result_paise", b.net_result()[2]),
                                          ("year_close", OrderedDict([("date", b.year_close["date"].isoformat()), ("by", b.year_close["by"]),
                                                                      ("vector_paise", OrderedDict(b.year_close["vector"])), ("net_line_paise", b.year_close["net"]),
                                                                      (b.year_close["label"].lower().replace(" ", "_") + "_paise", b.year_close["computed_equity"])]))])
            books.append(bo)
        c["books"] = books
        c["interbook_groups"] = [OrderedDict([("id", g["id"]), ("a", g["a"].book.id + "/" + g["a"].id), ("b", g["b"].book.id + "/" + g["b"].id)]) for g in uc.groups]
        cases.append(c)
    out["use_cases"] = cases
    return out


# ----------------------------------------------------------------------------------------------
# PDF via headless Chrome; dates inside the PDF are pinned so the file is reproducible
# ----------------------------------------------------------------------------------------------
def to_pdf(chrome, html_path, pdf_path):
    cmd = [chrome, "--headless=new", "--disable-gpu", "--no-pdf-header-footer", "--print-to-pdf=%s" % os.path.abspath(pdf_path), "file://%s" % os.path.abspath(html_path)]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with open(pdf_path, "rb") as f:
        data = f.read()
    fixed = re.sub(rb"/(CreationDate|ModDate) \(D:\d{14}([+-]\d{2}'\d{2}')?\)",
                   lambda m: b"/" + m.group(1) + b" (D:20261011000000" + (m.group(2) or b"") + b")", data)
    with open(pdf_path, "wb") as f:
        f.write(fixed)


# ----------------------------------------------------------------------------------------------
# Scenario 1 — Individual + own business: Jasvinder Singh
# ----------------------------------------------------------------------------------------------
def build_uc1():
    uc = UseCase("individual-jasvinder-singh",
                 "Individual + own business — Jasvinder Singh and Jasvinder Technologies",
                 "Individual with a one-owner business (two books linked by one owner loan)",
                 "Jasvinder Singh keeps a personal book (savings bank, cash, a credit card as a money account, a friend's hand-loan, a grocer's khata) "
                 "and runs **Jasvinder Technologies**, a one-owner IT services business with its own book (current account, business cash, clients as parties — one of them crossing zero both ways — "
                 "a hosting supplier on credit, Drawings, capital introduced). The two books touch only through one owner loan, entered in both books as a matching pair and repaid in part.",
                 [("Jasvinder Singh", "owner of both books; the only member (admin) of each — nothing needs a second person's approval in a one-member book"),
                  ("Gurpreet Sandhu", "friend who borrows ₹25,000 (party in the personal book)"),
                  ("Sharma General Store", "grocer with a monthly khata (party in the personal book)"),
                  ("Medtech Solutions · Kaur Exports · Punjab Agro Board", "clients (parties in the business book)"),
                  ("Cloudnine Hosting", "supplier on monthly credit (party in the business book)"),
                  ("Rohit Verma", "developer on salary — paid, not a member and not a party")])
    J = "Jasvinder Singh"
    # ---------------- personal book
    js = uc.book("JS", "Jasvinder Singh — Personal Book", "personal", "JS", members=[(J, "admin", None, "")])
    cash = js.acct("cash", "Cash in Hand", "money", subtype="cash", opening=R(12000))
    sav = js.acct("sav", "HDFC Savings A/c", "money", subtype="saving", opening=R(460000))
    cc = js.acct("cc", "HDFC Credit Card A/c", "money", subtype="CC", opening=-R(8400))
    gur = js.acct("gur", "Gurpreet Sandhu A/c", "party", note="friend — hand loan")
    sgs = js.acct("sgs", "Sharma General Store A/c", "party", note="grocer — monthly khata", opening=-R(3200))
    jt_link = js.acct("jt", "Jasvinder Technologies (own business book)", "equity_system", role="link", link_to="JT")
    hh = js.acct("hh", "Household Expense A/c", "category_expense")
    util = js.acct("util", "Utility Expense A/c", "category_expense")
    fuel = js.acct("fuel", "Fuel & Travel Expense A/c", "category_expense")
    med = js.acct("med", "Medical Expense A/c", "category_expense")
    ins = js.acct("ins", "Insurance Expense A/c", "category_expense")
    fest = js.acct("fest", "Festival Expense A/c", "category_expense")
    intinc = js.acct("intinc", "Savings Interest Income A/c", "category_income")
    js.acct("ob", "Opening Balance / Capital A/c", "equity_system", role="opening_balance")
    js_adj = js.acct("adj", "Adjustments A/c", "equity_system", role="adjustments")
    js.post_opening(J)

    # ---------------- business book
    jt = uc.book("JT", "Jasvinder Technologies — Business Book", "business", "JT", ownership="just_me", members=[(J, "admin", None, "")])
    icici = jt.acct("icici", "ICICI Current A/c", "money", subtype="current", opening=R(110000))
    bcash = jt.acct("bcash", "Business Cash A/c", "money", subtype="cash", opening=R(6500))
    medt = jt.acct("medt", "Medtech Solutions A/c", "party", note="client", opening=R(85000))
    kaur = jt.acct("kaur", "Kaur Exports A/c", "party", note="client — crosses zero both ways")
    agro = jt.acct("agro", "Punjab Agro Board A/c", "party", note="client — one project")
    cloud = jt.acct("cloud", "Cloudnine Hosting A/c", "party", note="supplier — monthly invoices on credit")
    js_link = jt.acct("js", "Jasvinder Singh (personal book)", "equity_system", role="link", link_to="JS")
    draw = jt.acct("draw", "Drawings A/c", "equity_system", role="drawings")
    jt.acct("ob", "Opening Balance / Capital A/c", "equity_system", role="opening_balance")
    jt_adj = jt.acct("adj", "Adjustments A/c", "equity_system", role="adjustments")
    svc = jt.acct("svc", "Service Income A/c", "category_income")
    sal = jt.acct("sal", "Staff Salary Expense A/c", "category_expense")
    rent = jt.acct("rent", "Office Rent Expense A/c", "category_expense")
    host = jt.acct("host", "Software & Hosting Expense A/c", "category_expense")
    net = jt.acct("net", "Internet & Phone Expense A/c", "category_expense")
    trav = jt.acct("trav", "Travel Expense A/c", "category_expense")
    off = jt.acct("off", "Office Expense A/c", "category_expense")
    prof = jt.acct("prof", "Professional Fees Expense A/c", "category_expense")
    bank = jt.acct("bank", "Bank Charges Expense A/c", "category_expense")
    jt.post_opening(J)

    # ---------------- the owner loan (02 §6 pair)
    uc.link(d(2025, 4, 10), R(200000), js, [(jt_link, R(200000)), (sav, -R(200000))], jt, [(icici, R(200000)), (js_link, -R(200000))],
            "Owner loan to Jasvinder Technologies by NEFT — the business owes Jasvinder", "Owner loan received from Jasvinder Singh by NEFT — the business owes Jasvinder", J, t=1)
    uc.link(d(2025, 12, 20), R(80000), jt, [(js_link, R(80000)), (icici, -R(80000))], js, [(sav, R(80000)), (jt_link, -R(80000))],
            "Part repayment of the owner loan to Jasvinder Singh by NEFT", "Part repayment of the owner loan received from Jasvinder Technologies", J, t=1)

    # ---------------- personal book — the year
    khata = {4: 5400, 5: 5650, 6: 5300, 7: 5800, 8: 5500, 9: 5900, 10: 6200, 11: 6400, 12: 5700, 1: 5600, 2: 5450, 3: 5800}
    fuel_cc = {4: 2900, 5: 3100, 6: 2850, 7: 3250, 8: 3000, 9: 3150, 10: 3400, 11: 2950, 12: 3100, 1: 3050, 2: 2900, 3: 3200}
    util_b = {4: 1650, 5: 2100, 6: 2400, 7: 2550, 8: 2450, 9: 2200, 10: 1900, 11: 1700, 12: 1800, 1: 1950, 2: 1750, 3: 1700}
    hh_cash = {4: 4800, 5: 5100, 6: 4600, 7: 5300, 8: 4900, 9: 5200, 10: 5600, 11: 5000, 12: 4700, 1: 5100, 2: 4800, 3: 5200}
    cc_due = R(8400)   # bill to pay in the first month
    prev_khata = R(3200)
    for mk in fy_months():
        y, m = int(mk[:4]), int(mk[5:])
        js.v(d(y, m, 2), "transfer", "ATM withdrawal for the month's household cash", [(cash, R(8000)), (sav, -R(8000))], J, t=1)
        js.v(d(y, m, 6), "money_out", "Electricity and water bills paid by net banking", [(util, R(util_b[m])), (sav, -R(util_b[m]))], J)
        js.v(d(y, m, 12), "money_out", "Groceries and vegetables paid in cash through the month", [(hh, R(hh_cash[m])), (cash, -R(hh_cash[m]))], J)
        js.v(d(y, m, 18), "money_out", "Petrol on the HDFC credit card", [(fuel, R(fuel_cc[m])), (cc, -R(fuel_cc[m]))], J)
        js.v(d(y, m, 25), "took_credit", "Sharma General Store — month's provisions on khata (bill received)", [(hh, R(khata[m])), (sgs, -R(khata[m]))], J)
        js.v(d(y, m, 8), "money_out", "Paid Sharma General Store last month's khata by UPI", [(sgs, prev_khata), (sav, -prev_khata)], J, t=3)
        prev_khata = R(khata[m])
        js.v(d(y, m, 15), "transfer", "HDFC credit card statement paid in full from savings", [(cc, cc_due), (sav, -cc_due)], J, t=3)
        cc_due = R(fuel_cc[m])
    js.v(d(2025, 6, 13), "transfer", "Cash withdrawn at the branch for the hand loan to Gurpreet", [(cash, R(25000)), (sav, -R(25000))], J, t=1)
    js.v(d(2025, 6, 14), "gave_credit", "Hand loan given to Gurpreet Sandhu in cash", [(gur, R(25000)), (cash, -R(25000))], J)
    js.v(d(2025, 9, 10), "money_in", "Gurpreet Sandhu returned part of the hand loan by UPI", [(sav, R(15000)), (gur, -R(15000))], J)
    js.v(d(2025, 8, 22), "money_out", "Doctor's consultation and medicines for Indu's mother, paid by card", [(med, R(6800)), (cc, -R(6800))], J, note="card bill of 15 Sep carries this too")
    js.v(d(2025, 7, 20), "money_out", "Annual term-insurance premium by net banking", [(ins, R(14600)), (sav, -R(14600))], J)
    js.v(d(2025, 10, 19), "money_out", "Diwali sweets, gifts and crackers in cash", [(fest, R(9000)), (cash, -R(9000))], J)
    for dt, amt in ((d(2025, 6, 30), R(1812, 47)), (d(2025, 9, 30), R(1106, 20)), (d(2025, 12, 31), R(934, 85)), (d(2026, 3, 31), R(801, 33))):
        js.v(dt, "money_in", "Quarterly savings interest credited by HDFC", [(sav, amt), (intinc, -amt)], J, t=2)
    # the Sep card bill includes the medical charge of 22 Aug: patch that month's card payment amount
    for vo in js.vouchers:
        if vo.date == d(2025, 9, 15) and vo.kind == "transfer" and vo.lines[0][0] is cc:
            vo.lines = [(cc, R(fuel_cc[8]) + R(6800)), (sav, -(R(fuel_cc[8]) + R(6800)))]
            vo.narr = "HDFC credit card statement (petrol + medical) paid in full from savings"
    js.lock_all(J, day=4)
    js.monthly_counts(cash, J, diffs={"2025-11": R(500)})

    # ---------------- business book — the year
    invoices = {4: 95000, 5: 110000, 6: 88000, 7: 120000, 8: 105000, 9: 98000, 10: 115000, 11: 102000, 12: 90000, 1: 125000, 2: 108000, 3: 112000}
    prev_inv = R(85000)   # opening receivable from Medtech
    host_due = 0
    for mk in fy_months():
        y, m = int(mk[:4]), int(mk[5:])
        jt.v(d(y, m, 1), "money_out", "Office rent for the month paid by NEFT", [(rent, R(12000)), (icici, -R(12000))], J, t=2)
        jt.v(d(y, m, 5), "took_credit", "Cloudnine Hosting — monthly server and licence invoice on credit", [(host, R(3540)), (cloud, -R(3540))], J)
        host_due += R(3540)
        if m in (6, 9, 12, 3):
            jt.v(d(y, m, 20), "money_out", "Paid Cloudnine Hosting the quarter's invoices by NEFT", [(cloud, host_due), (icici, -host_due)], J)
            host_due = 0
        jt.v(d(y, m, 7), "money_out", "Internet and phone bills by net banking", [(net, R(2360)), (icici, -R(2360))], J)
        jt.v(d(y, m, 10), "money_in", "Medtech Solutions paid last month's invoice by NEFT", [(icici, prev_inv), (medt, -prev_inv)], J, t=3)
        jt.v(d(y, m, 28), "gave_credit", "Invoice to Medtech Solutions for the month's support retainer", [(medt, R(invoices[m])), (svc, -R(invoices[m]))], J)
        prev_inv = R(invoices[m])
        jt.v(d(y, m, 30 if m != 2 else 28), "money_out", "Salary to Rohit Verma (developer) by NEFT", [(sal, R(45000)), (icici, -R(45000))], J, t=6)
        jt.v(d(y, m, 3), "transfer", "Cash drawn from ICICI for office petty expenses", [(bcash, R(4000)), (icici, -R(4000))], J, t=1)
        jt.v(d(y, m, 16), "money_out", "Tea, courier and stationery paid in cash", [(off, R(2650) if m % 2 else R(3100)), (bcash, -(R(2650) if m % 2 else R(3100)))], J)
        jt.v(d(y, m, 30 if m != 2 else 28), "money_out", "Bank charges debited by ICICI", [(bank, R(177)), (icici, -R(177))], J, t=7)
    # Kaur Exports — crosses zero both ways
    jt.v(d(2025, 5, 15), "money_in", "Kaur Exports paid an advance before work began (party goes Cr — you will give)", [(icici, R(50000)), (kaur, -R(50000))], J)
    jt.v(d(2025, 6, 30), "gave_credit", "Invoice to Kaur Exports — export documentation portal, phase 1", [(kaur, R(120000)), (svc, -R(120000))], J)
    jt.v(d(2025, 7, 20), "money_in", "Kaur Exports settled phase 1 by NEFT", [(icici, R(70000)), (kaur, -R(70000))], J)
    jt.v(d(2026, 1, 12), "gave_credit", "Invoice to Kaur Exports — portal phase 2", [(kaur, R(60000)), (svc, -R(60000))], J)
    jt.v(d(2026, 2, 9), "money_in", "Kaur Exports paid phase 2 by NEFT", [(icici, R(60000)), (kaur, -R(60000))], J)
    jt.v(d(2026, 3, 18), "money_in", "Kaur Exports paid an advance for phase 3 (party Cr again at year end)", [(icici, R(20000)), (kaur, -R(20000))], J)
    # Punjab Agro Board — one project
    jt.v(d(2025, 10, 15), "gave_credit", "Invoice to Punjab Agro Board — mandi price dashboard", [(agro, R(300000)), (svc, -R(300000))], J)
    jt.v(d(2025, 11, 25), "money_in", "Punjab Agro Board paid 60% of the dashboard invoice by RTGS", [(icici, R(180000)), (agro, -R(180000))], J)
    jt.v(d(2026, 1, 20), "money_in", "Punjab Agro Board paid the balance of the dashboard invoice by RTGS", [(icici, R(120000)), (agro, -R(120000))], J)
    # capital introduced (ADR 2026-09-13 §4) — FD proceeds never on the personal book
    jt.v(d(2025, 9, 5), "money_in", "Capital introduced — matured fixed deposit proceeds paid straight into the business account (Money in · Cr Opening Balance / Capital, ADR 2026-09-13 §4)",
         [(icici, R(150000)), (jt.ob(), -R(150000))], J, tag="capital_in")
    # drawings (ADR 2026-09-09b §3)
    jt.v(d(2025, 6, 25), "money_out", "Owner's drawing — child's school fees paid from the business account (not a business expense)", [(draw, R(40000)), (icici, -R(40000))], J, tag="drawings")
    jt.v(d(2025, 10, 20), "money_out", "Owner's drawing — Diwali household spending transferred to the owner", [(draw, R(60000)), (icici, -R(60000))], J, tag="drawings")
    jt.v(d(2026, 2, 15), "money_out", "Owner's drawing — family travel paid from the business account", [(draw, R(50000)), (icici, -R(50000))], J, tag="drawings")
    # CA fee, travel
    jt.v(d(2025, 8, 12), "money_out", "Client visit to Chandigarh — taxi and meals by net banking", [(trav, R(8200)), (icici, -R(8200))], J)
    jt.v(d(2026, 3, 25), "money_out", "Professional fees — CA for annual accounts, by NEFT", [(prof, R(15000)), (icici, -R(15000))], J)
    # a locked-month correction: a June payment booked to Travel was Office Expense (laptop bag + chairs)
    wrong = jt.v(d(2025, 6, 18), "money_out", "Office chairs and bag paid by net banking", [(trav, R(9400)), (icici, -R(9400))], J)
    rev = jt.reverse(wrong, d(2025, 7, 12), J, "booked to Travel Expense in June; June is locked, so reversed and re-entered under Office Expense", tag="locked_fix")
    re_v = jt.v(d(2025, 7, 12), "money_out", "Office chairs and bag (re-entry of the June payment under the right category)", [(off, R(9400)), (icici, -R(9400))], J, t=6, note="corrects %s" % "{id:%d}" % wrong.seq)
    rev.refs["reentry"] = re_v
    jt.lock_all(J, day=5)
    jt.monthly_counts(bcash, J, diffs={"2025-08": -R(200)})
    uc.spec_flags = ["kind by shape for the owner loan halves (`transfer`, 02 §6 pair)", "one multi-line opening adjustment per book"]
    return uc, d(2026, 4, 10), {"JS": J, "JT": J}, {}


# ----------------------------------------------------------------------------------------------
# Scenario 2 — Shop / trader: Sukhwinder Sales Co. (pipes & sanitary)
# ----------------------------------------------------------------------------------------------
def build_uc2():
    uc = UseCase("shop-sukhwinder-sales-co",
                 "Shop / trader — Sukhwinder Sales Co. (pipes & sanitary)",
                 "One-owner trading business with staff",
                 "Sukhwinder Bal runs a pipes-and-sanitary shop. Cash sales over the counter, credit sales to builders and plumbers, suppliers on khata, one salesman on salary who also posts entries "
                 "(with an entry limit), shop rent, owner Drawings, a bank-statement import that leaves one unexplained line in Suspense until it is cleared before the month lock, and a cash-count difference at a month end.",
                 [("Sukhwinder Bal", "proprietor · admin, no entry limit · approves the salesman's entries that go over his limit"),
                  ("Manpreet Kaur", "salesman · role operator, entry limit ₹10,000 · posts freight, utilities, small purchases"),
                  ("Guru Nanak Builders", "customer on monthly credit (party)"), ("Dhillon Plumbing Works", "customer who pays an advance, then buys — crosses zero both ways (party)"),
                  ("Supreme Pipes Ltd · Jaquar Sanitary Agency", "suppliers on credit (parties)")])
    S, M = "Sukhwinder Bal", "Manpreet Kaur"
    b = uc.book("SS", "Sukhwinder Sales Co. — Business Book", "business", "SS", ownership="just_me",
                members=[(S, "admin", None, "proprietor"), (M, "operator", R(10000), "salesman")])
    galla = b.acct("galla", "Galla Cash A/c", "money", subtype="cash", opening=R(18500))
    pnb = b.acct("pnb", "PNB Current A/c", "money", subtype="current", opening=R(240000))
    gnb = b.acct("gnb", "Guru Nanak Builders A/c", "party", note="customer on credit", opening=R(64000))
    dhil = b.acct("dhil", "Dhillon Plumbing Works A/c", "party", note="customer — advance then purchases")
    sup = b.acct("sup", "Supreme Pipes Ltd A/c", "party", note="supplier", opening=-R(185000))
    jaq = b.acct("jaq", "Jaquar Sanitary Agency A/c", "party", note="supplier")
    sales = b.acct("sales", "Sales A/c", "category_income")
    purch = b.acct("purch", "Purchases A/c", "category_expense")
    rent = b.acct("rent", "Shop Rent Expense A/c", "category_expense")
    staff = b.acct("staff", "Staff Salary Expense A/c", "category_expense")
    frt = b.acct("frt", "Freight Expense A/c", "category_expense")
    util = b.acct("util", "Shop Utility Expense A/c", "category_expense")
    misc = b.acct("misc", "Packing & Misc. Expense A/c", "category_expense")
    bankch = b.acct("bankch", "Bank Charges Expense A/c", "category_expense")
    draw = b.acct("draw", "Drawings A/c", "equity_system", role="drawings")
    b.acct("ob", "Opening Balance / Capital A/c", "equity_system", role="opening_balance")
    adj = b.acct("adj", "Adjustments A/c", "equity_system", role="adjustments")
    susp = b.acct("susp", "Suspense A/c", "equity_system", role="suspense")
    b.post_opening(S)
    b.config["peer_reviewer"] = "Sukhwinder Bal (book_config, 02 §7.2 item 1)"
    b.config["auto_post_limit"] = "Manpreet Kaur ₹10,000 (06 §1.1); Sukhwinder Bal none"
    b.plain.append("Entries over a member's limit are approved by Sukhwinder Bal. Entry limits: Manpreet Kaur ₹10,000; Sukhwinder Bal none.")

    cash_sales = {4: (62000, 71000), 5: (68000, 74500), 6: (59000, 66000), 7: (64000, 69500), 8: (70000, 78000), 9: (73000, 81000),
                  10: (88000, 96000), 11: (76000, 72500), 12: (65000, 69000), 1: (61000, 64500), 2: (63500, 70000), 3: (79000, 92000)}
    credit_sales = {4: 58000, 5: 64000, 6: 52000, 7: 71000, 8: 66000, 9: 69000, 10: 84000, 11: 73000, 12: 61000, 1: 57000, 2: 62000, 3: 88000}
    purchases = {4: 118000, 5: 126000, 6: 109000, 7: 121000, 8: 134000, 9: 141000, 10: 162000, 11: 128000, 12: 115000, 1: 108000, 2: 119000, 3: 155000}
    utils = {4: 2600, 5: 3400, 6: 4100, 7: 4300, 8: 4200, 9: 3900, 10: 3100, 11: 2500, 12: 2700, 1: 2900, 2: 2600, 3: 2800}
    freight = {4: 2800, 5: 3100, 6: 2600, 7: 2900, 8: 3300, 9: 3500, 10: 3800, 11: 3000, 12: 2700, 1: 2500, 2: 2800, 3: 3600}
    miscx = {4: 1200, 5: 1450, 6: 1300, 7: 1600, 8: 1500, 9: 1700, 10: 1900, 11: 1400, 12: 1250, 1: 1350, 2: 1300, 3: 1800}
    prev_credit = R(64000)
    prev_purch = R(185000)
    for mk in fy_months():
        y, m = int(mk[:4]), int(mk[5:])
        last = month_end(date(y, m, 1)).day
        b.v(d(y, m, 1), "money_out", "Salary to Manpreet Kaur for last month by NEFT", [(staff, R(14000)), (pnb, -R(14000))], S, t=2)
        b.v(d(y, m, 2), "money_out", "Shop rent for the month paid by NEFT", [(rent, R(15000)), (pnb, -R(15000))], S, t=2)
        b.v(d(y, m, 3), "money_out", "Owner's drawing for household expenses transferred to Sukhwinder (not a business expense, ADR 2026-09-09b §3)", [(draw, R(25000)), (pnb, -R(25000))], S, tag="drawings")
        b.v(d(y, m, 4), "took_credit", "Supreme Pipes Ltd — stock purchase on credit (invoice received)", [(purch, R(purchases[m])), (sup, -R(purchases[m]))], S)
        b.v(d(y, m, 5), "money_out", "Freight on incoming stock paid in cash to the transporter", [(frt, R(freight[m])), (galla, -R(freight[m]))], M)
        b.v(d(y, m, 9), "money_out", "Shop electricity bill paid by net banking", [(util, R(utils[m])), (pnb, -R(utils[m]))], M)
        b.v(d(y, m, 10), "gave_credit", "Credit sale to Guru Nanak Builders — pipes and fittings for their site", [(gnb, R(credit_sales[m])), (sales, -R(credit_sales[m]))], S)
        a1, a2 = cash_sales[m]
        b.v(d(y, m, 14), "money_in", "Counter sales in cash, 1st to 14th", [(galla, R(a1)), (sales, -R(a1))], S, t=1)
        b.v(d(y, m, 15), "transfer", "Cash deposited into PNB Current A/c", [(pnb, R(a1 - 6000)), (galla, -R(a1 - 6000))], S, t=2)
        b.v(d(y, m, 19), "money_out", "Packing material and sundries paid in cash", [(misc, R(miscx[m])), (galla, -R(miscx[m]))], M)
        b.v(d(y, m, 20), "money_in", "Guru Nanak Builders paid last month's bill by NEFT", [(pnb, prev_credit), (gnb, -prev_credit)], S)
        prev_credit = R(credit_sales[m])
        b.v(d(y, m, 22), "money_out", "Paid Supreme Pipes Ltd last month's invoice by RTGS", [(sup, prev_purch), (pnb, -prev_purch)], S)
        prev_purch = R(purchases[m])
        b.v(d(y, m, last), "money_in", "Counter sales in cash, 15th to month end", [(galla, R(a2)), (sales, -R(a2))], S, t=1)
        b.v(d(y, m, last), "transfer", "Cash deposited into PNB Current A/c", [(pnb, R(a2 - 5000)), (galla, -R(a2 - 5000))], S, t=2)
        if m != 8:
            b.v(d(y, m, last), "money_out", "Bank charges debited by PNB", [(bankch, R(236)), (pnb, -R(236))], S, t=7)
    # Jaquar — quarterly on credit, paid 30 days later
    for (y, m) in ((2025, 6), (2025, 9), (2025, 12), (2026, 3)):
        b.v(d(y, m, 7), "took_credit", "Jaquar Sanitary Agency — sanitaryware purchase on credit", [(purch, R(60000)), (jaq, -R(60000))], S)
        if m != 3:
            ny, nm = (y + (m == 12), (m % 12) + 1)
            b.v(d(ny, nm, 6), "money_out", "Paid Jaquar Sanitary Agency by NEFT", [(jaq, R(60000)), (pnb, -R(60000))], S)
    # Dhillon Plumbing — crosses zero both ways
    b.v(d(2025, 6, 5), "money_in", "Dhillon Plumbing Works paid an advance against a bulk order (party Cr — you will give)", [(pnb, R(30000)), (dhil, -R(30000))], S)
    b.v(d(2025, 6, 18), "gave_credit", "Supplied CPVC pipes and fittings to Dhillon Plumbing Works on credit", [(dhil, R(72000)), (sales, -R(72000))], S)
    b.v(d(2025, 7, 10), "money_in", "Dhillon Plumbing Works settled the balance by UPI", [(pnb, R(42000)), (dhil, -R(42000))], S)
    b.v(d(2025, 12, 8), "gave_credit", "Supplied bathroom fittings to Dhillon Plumbing Works on credit", [(dhil, R(38000)), (sales, -R(38000))], S)
    b.v(d(2026, 1, 15), "money_in", "Dhillon Plumbing Works paid the December bill by NEFT", [(pnb, R(38000)), (dhil, -R(38000))], S)
    b.v(d(2026, 2, 20), "gave_credit", "Supplied pipes to Dhillon Plumbing Works on credit (open at year end)", [(dhil, R(26500)), (sales, -R(26500))], S)
    # over-limit entry by the salesman, approved by the proprietor
    b.v(d(2025, 7, 12), "money_out", "Urgent cash purchase of brass fittings from a local dealer", [(purch, R(14500)), (galla, -R(14500))], M,
        review={"approver": S, "decided": d(2025, 7, 13), "decision": "approved", "reason": "", "limit": R(10000)})
    # amend in an open period (by the admin — operators cannot amend, 06 §1.0)
    orig = b.v(d(2025, 10, 15), "money_out", "Freight on the Diwali stock paid in cash", [(frt, R(3200)), (galla, -R(3200))], M)
    b.amend(orig, d(2025, 10, 15), [(frt, R(2300)), (galla, -R(2300))], "Freight on the Diwali stock paid in cash (bill re-read: ₹2,300, not ₹3,200)", S, authored=d(2025, 10, 17))
    # statement import for August (02 §10): matches, one new line, one Suspense line cleared before the lock
    n = 0
    for vo in b.sorted_vouchers():
        if vo.date.month == 8 and vo.date.year == 2025 and any(a is pnb for a, _ in vo.lines) and vo.kind != "adjustment":
            n += 1
            vo.import_line = "PNB-AUG25-%02d" % n
    n += 1
    b.v(d(2025, 8, 31), "money_out", "Bank charges debited by PNB (confirmed as new from the imported statement line)", [(bankch, R(236)), (pnb, -R(236))], S, t=7,
        authored=d(2025, 9, 3), import_line="PNB-AUG25-%02d" % n)
    n += 1
    sus = b.v(d(2025, 8, 28), "adjustment", "Imported NEFT credit with unknown counterpart — held in Suspense (02 §10: unexplained, never unrecorded)",
              [(pnb, R(18000)), (susp, -R(18000))], S, t=4, authored=d(2025, 9, 3), import_line="PNB-AUG25-%02d" % n, tag="suspense_in")
    b.v(d(2025, 8, 28), "adjustment", "Suspense cleared: the NEFT of 28 Aug was Guru Nanak Builders paying ahead on their khata (identified 05 Sep, before the August lock)",
        [(susp, R(18000)), (gnb, -R(18000))], S, t=5, authored=d(2025, 9, 5), import_line="PNB-AUG25-%02d" % n, tag="suspense_clear", note="clears %s" % "{id:%d}" % sus.seq)
    b.config["import_batch"] = "PNB statement 01–31 Aug 2025, uploaded 03 Sep 2025 by Sukhwinder Bal: %d lines — %d matched to existing entries (no posting, `refs.import_line` set), 1 confirmed as new (bank charges), 1 to Suspense, cleared 05 Sep" % (n, n - 2)
    b.lock_all(S, day=6)
    b.monthly_counts(galla, S, diffs={"2025-11": -R(200)})
    uc.spec_flags = ["Suspense clearing posted as an adjustment Dr Suspense · Cr counterpart (02 §10 is silent)"]

    uc.tech_notes.append(("Statement import — SS, August 2025 (02 §10)", [
        b.config["import_batch"] + ". The bank's words are `bank_text`, immutable; the one question per line is the counterpart. Matched lines post nothing (`refs.import_line` set on the existing entry). The unknown NEFT credit was posted to Suspense the day the statement was read and cleared two days later when the customer confirmed the payment — Suspense is 0 at the lock, as 02 §8 step 3 requires.",
        "⚠️ SPEC: 02 §10 names the Suspense posting (`Dr/Cr Bank · Cr/Dr Suspense`) but not the clearing posting. This set clears it with one guided adjustment `Dr Suspense · Cr {counterpart}` carrying the same `refs.import_line` — exactly one `equity_system` counter-account, so it passes rule 7. The alternative (a `refs.reverses` mirror plus a fresh money-in with the counterpart) is also shape-legal; the owner should choose.",
    ]))

    def imp_section(doc, bk):
        doc.h(3, "8. Bank statement matched — August 2025")
        n_lines = sum(1 for vo in bk.sorted_vouchers() if vo.import_line)
        doc.p("The PNB statement for 01–31 Aug 2025 was uploaded on 03 Sep 2025 by Sukhwinder Bal: %d lines — %d matched entries already in the book (nothing new entered), 1 confirmed as a new entry (bank charges), 1 held as unexplained money and cleared on 05 Sep. "
              "For every line the one question is: where did it come from, or where did it go? The unknown NEFT credit was held as unexplained money the day the statement was read and cleared two days later when the customer confirmed the payment — so nothing was unexplained when August was closed." % (n_lines, n_lines - 2))
        rows = []
        for vo in bk.sorted_vouchers():
            if vo.import_line:
                kind = "matched an entry already in the book" if vo.tag not in ("suspense_in", "suspense_clear") and vo.authored == vo.date else (
                    "confirmed as new" if vo.tag is None else ("not known yet → held as unexplained money" if vo.tag == "suspense_in" else "explained and cleared"))
                rows.append([vo.import_line, fdate(vo.date), vo.id, kind, fmt(vo.amount), plain_narr(vo.narr)])
        doc.table(["Statement line", "Bank date", "Entry", "What was done", "₹", "Details"], rows, ["l", "l", "l", "l", "r", "l"])

    return uc, d(2026, 4, 10), {"SS": S}, {"SS": [imp_section]}


# ----------------------------------------------------------------------------------------------
# Scenario 3 — Partnership: Bal Fabricators
# ----------------------------------------------------------------------------------------------
def build_uc3():
    uc = UseCase("partnership-bal-fabricators",
                 "Partnership — Bal Fabricators",
                 "Jointly-owned business (shared ownership, unequal weights, interest on capital ON)",
                 "Bal Fabricators is a steel-fabrication workshop owned by Sukhwinder Bal, Pradeep Bal and Harjeet Singh with weights **2 : 2 : 1** agreed at creation. Opening contributions are credited to each Partner Current A/c "
                 "and Opening Balance / Capital holds only the difference. Partners pay costs from their own pockets, take money out monthly, one ends the year owing the business (Dr), "
                 "and the year's profit is shared to the paisa: interest on capital first, then the rest by the agreed ratio.",
                 [("Sukhwinder Bal", "partner, share 2 · admin · approves Harjeet's entries that go over his limit"), ("Pradeep Bal", "partner, share 2 · admin"),
                  ("Harjeet Singh", "partner, share 1 (outside the family) · member, entry limit ₹25,000 · ends the year owing the business (Dr)"),
                  ("Verka Dairy Plant · Punjab Steel Sheds · Gill Farms", "customers (parties)"), ("Jindal Steel Traders", "steel supplier on credit (party)")])
    S, P, H = "Sukhwinder Bal", "Pradeep Bal", "Harjeet Singh"
    b = uc.book("BF", "Bal Fabricators — Business Book (shared)", "business", "BF", ownership="shared",
                members=[(S, "admin", None, "partner"), (P, "admin", None, "partner"), (H, "member", R(25000), "partner")])
    sbi = b.acct("sbi", "SBI Current A/c", "money", subtype="current", opening=R(600000))
    wcash = b.acct("wcash", "Workshop Cash A/c", "money", subtype="cash", opening=R(15000))
    verka = b.acct("verka", "Verka Dairy Plant A/c", "party", note="customer", opening=R(48000))
    pss = b.acct("pss", "Punjab Steel Sheds A/c", "party", note="customer")
    gillf = b.acct("gillf", "Gill Farms A/c", "party", note="customer")
    jindal = b.acct("jindal", "Jindal Steel Traders A/c", "party", note="supplier")
    pc_s = b.acct("pc_s", "Sukhwinder Bal — Partner Current A/c", "partner", opening=-R(240000))
    pc_p = b.acct("pc_p", "Pradeep Bal — Partner Current A/c", "partner", opening=-R(240000))
    pc_h = b.acct("pc_h", "Harjeet Singh — Partner Current A/c", "partner", opening=-R(120000))
    pd = b.acct("pd", "Profit Distributed A/c", "equity_system", role="profit_distributed")
    b.acct("ob", "Opening Balance / Capital A/c", "equity_system", role="opening_balance")
    adj = b.acct("adj", "Adjustments A/c", "equity_system", role="adjustments")
    fab = b.acct("fab", "Fabrication Income A/c", "category_income")
    mat = b.acct("mat", "Steel & Material Expense A/c", "category_expense")
    lab = b.acct("lab", "Labour Expense A/c", "category_expense")
    elec = b.acct("elec", "Electricity Expense A/c", "category_expense")
    wrent = b.acct("wrent", "Workshop Rent Expense A/c", "category_expense")
    dsl = b.acct("dsl", "Diesel & Machinery Expense A/c", "category_expense")
    cons = b.acct("cons", "Consumables & Welding Expense A/c", "category_expense")
    bankch = b.acct("bankch", "Bank Charges Expense A/c", "category_expense")
    b.post_opening(S)
    partners = [pc_s, pc_p, pc_h]
    weights = [2, 2, 1]
    b.config["partner_shares"] = "{pc_s: 2, pc_p: 2, pc_h: 1} — whole-number weights keyed by Partner Current A/c id, recorded once in `book_config` at creation (ADR 2026-09-13 §3, ADR 2026-09-14b §2, §4)"
    b.config["structural_quorum"] = "`all_owners` — chosen explicitly at creation (02 §7.2.1)"
    b.config["interest_on_capital"] = "ON at 6% p.a., Actual/365, credit balances only — `business_setting` dated 01 Apr 2025"
    b.structural_approvals.append({"date": d(2025, 4, 1), "what": "interest on capital at 6% a year (every partner's approval needed)", "approvals": "Sukhwinder Bal ✓ · Pradeep Bal ✓ · Harjeet Singh ✓ (3 of 3, all owners)"})
    b.plain.append("Partners' shares: Sukhwinder Bal 2 · Pradeep Bal 2 · Harjeet Singh 1, agreed when the book was created. Decisions that change the partnership — sharing out the profit, interest on capital, a change of shares — need every partner's approval. Interest on capital: 6% a year, counted day by day, on credit balances only.")
    b.notes.append("Opening contributions — Sukhwinder ₹2,40,000, Pradeep ₹2,40,000, Harjeet ₹1,20,000 — are **asked of each partner, never worked out from the ratio**. The firm also started with ₹15,000 workshop cash and ₹48,000 owed by Verka Dairy Plant for work billed before 1 Apr; those ₹63,000 belong to no one partner, so Opening Balance / Capital shows ₹63,000 Cr — the difference, shown openly.")

    jobs_pss = {4: 110000, 5: 160000, 6: 138000, 7: 184000, 8: 155000, 9: 172000, 10: 201000, 11: 167000, 12: 150000, 1: 178000, 2: 144000, 3: 207000}
    jobs_verka = {5: 200000, 7: 170000, 9: 185000, 11: 210000, 1: 160000, 3: 230000}
    jobs_gill = {6: 85000, 10: 120000, 2: 95000}
    steel = {4: 90000, 5: 135000, 6: 110000, 7: 125000, 8: 105000, 9: 130000, 10: 150000, 11: 140000, 12: 95000, 1: 120000, 2: 100000, 3: 160000}
    wages = {4: 52000, 5: 58000, 6: 54000, 7: 60000, 8: 32000, 9: 59000, 10: 62000, 11: 57000, 12: 50000, 1: 55000, 2: 51000, 3: 61000}
    power = {4: 12800, 5: 16400, 6: 18900, 7: 19200, 8: 17600, 9: 16100, 10: 14500, 11: 12900, 12: 11800, 1: 12200, 2: 11900, 3: 13400}
    consum = {4: 6200, 5: 7800, 6: 7100, 7: 8400, 8: 6900, 9: 7600, 10: 9100, 11: 7300, 12: 6500, 1: 7000, 2: 6400, 3: 8800}
    prev_pss = 0
    prev_steel = 0
    for mk in fy_months():
        y, m = int(mk[:4]), int(mk[5:])
        last = month_end(date(y, m, 1)).day
        b.v(d(y, m, 3), "money_out", "Workshop rent for the month paid by NEFT", [(wrent, R(18000)), (sbi, -R(18000))], S, t=2)
        b.v(d(y, m, 6), "took_credit", "Jindal Steel Traders — MS sections and sheets on credit", [(mat, R(steel[m])), (jindal, -R(steel[m]))], P)
        b.v(d(y, m, 10), "money_out", "Sukhwinder Bal took money out of the business for household use (Dr Partner Current · Cr bank, 02 §7.1)", [(pc_s, R(20000)), (sbi, -R(20000))], S, tag="takeout")
        b.v(d(y, m, 10), "money_out", "Pradeep Bal took money out of the business for household use", [(pc_p, R(20000)), (sbi, -R(20000))], P, tag="takeout", t=6)
        b.v(d(y, m, 11), "money_out", "Harjeet Singh took money out of the business for household use", [(pc_h, R(28000)), (sbi, -R(28000))], S, tag="takeout", note="entered by Sukhwinder on Harjeet's request")
        b.v(d(y, m, 12), "money_out", "Workshop electricity bill paid by net banking", [(elec, R(power[m])), (sbi, -R(power[m]))], P)
        b.v(d(y, m, 15), "money_out", "Welding rods, discs and gas paid in cash", [(cons, R(consum[m])), (wcash, -R(consum[m]))], H)
        b.v(d(y, m, 20), "gave_credit", "Bill to Punjab Steel Sheds for the month's shed fabrication", [(pss, R(jobs_pss[m])), (fab, -R(jobs_pss[m]))], S)
        if prev_pss:
            b.v(d(y, m, 8), "money_in", "Punjab Steel Sheds paid last month's bill by RTGS", [(sbi, prev_pss), (pss, -prev_pss)], S)
        prev_pss = R(jobs_pss[m])
        if m in jobs_verka:
            b.v(d(y, m, 24), "gave_credit", "Bill to Verka Dairy Plant — SS tanks and platforms", [(verka, R(jobs_verka[m])), (fab, -R(jobs_verka[m]))], S)
        if m in (4, 6, 8, 10, 12, 2):
            owed = b.balance(verka, as_of=d(y, m, 1))
            if owed > 0:
                b.v(d(y, m, 8), "money_in", "Verka Dairy Plant settled their outstanding bills by RTGS", [(sbi, owed), (verka, -owed)], S, t=1)
        if m in jobs_gill:
            b.v(d(y, m, 22), "gave_credit", "Bill to Gill Farms — cattle-shed structure and gates", [(gillf, R(jobs_gill[m])), (fab, -R(jobs_gill[m]))], P)
            ny, nm = (y + (m == 12), (m % 12) + 1)
            b.v(d(ny, nm, 9), "money_in", "Gill Farms paid their bill by NEFT", [(sbi, R(jobs_gill[m])), (gillf, -R(jobs_gill[m]))], P)
        if prev_steel:
            b.v(d(y, m, 26), "money_out", "Paid Jindal Steel Traders last month's invoice by RTGS", [(jindal, prev_steel), (sbi, -prev_steel)], S)
        prev_steel = R(steel[m])
        b.v(d(y, m, 28), "transfer", "Cash drawn from SBI for the month's wages", [(wcash, R(wages[m]) + R(12000)), (sbi, -(R(wages[m]) + R(12000)))], P, t=1)
        if m == 8:
            b.v(d(y, m, last), "money_out", "Month's wages paid to the fabrication crew in cash (Pradeep away; entered by Harjeet)", [(lab, R(wages[m])), (wcash, -R(wages[m]))], H, t=4,
                review={"approver": S, "decided": d(2025, 9, 1), "decision": "approved", "reason": "", "limit": R(25000)})
        else:
            b.v(d(y, m, last), "money_out", "Month's wages paid to the fabrication crew in cash", [(lab, R(wages[m])), (wcash, -R(wages[m]))], P, t=4)
        b.v(d(y, m, last), "money_out", "Bank charges debited by SBI", [(bankch, R(295)), (sbi, -R(295))], S, t=7)
    # own-pocket payments (02 §7.1: Dr Expense · Cr Partner Current)
    b.v(d(2025, 5, 9), "took_credit", "Harjeet Singh paid generator diesel from his own pocket — the business owes him (02 §7.1)", [(dsl, R(12500)), (pc_h, -R(12500))], H, tag="own_pocket")
    b.v(d(2025, 8, 22), "took_credit", "Pradeep Bal paid the welding-machine repair from his own pocket", [(dsl, R(18000)), (pc_p, -R(18000))], P, tag="own_pocket")
    b.v(d(2025, 11, 14), "took_credit", "Harjeet Singh paid generator diesel from his own pocket", [(dsl, R(9800)), (pc_h, -R(9800))], H, tag="own_pocket")
    b.lock_all(S, day=5)
    b.monthly_counts(wcash, P, diffs={"2025-09": R(150)})
    # profit appropriation at year end — computed from the ledger, never typed
    distribute(b, d(2026, 3, 31), S, partners, weights, 600, "business_setting of 01 Apr 2025: Sukhwinder Bal · Pradeep Bal · Harjeet Singh")
    b.structural_approvals.append({"date": d(2026, 3, 31), "what": "share out the profit for FY 2025-26 (every partner's approval needed)", "approvals": "Sukhwinder Bal ✓ · Pradeep Bal ✓ · Harjeet Singh ✓ (3 of 3)"})
    uc.spec_flags = ["kind by shape for partner postings", "interest on credit-balance days only (the setting)"]
    note = ("Harjeet Singh's balance is a **Dr** balance at the year end: he took out more than he put in plus his interest and profit share, so *he owes the business* — shown as plainly as the credit cases. "
            "Because the partners chose to carry the balances forward, his Dr balance re-opens in %s as a dated opening balance; it is settled by future profit shares or a repayment, never by a remembered number." % NEXT_FY_LABEL)
    return uc, d(2026, 4, 12), {"BF": S}, {"BF": [lambda doc, bk: section_partners(doc, bk, partners, weights, R(100000), note)]}


# ----------------------------------------------------------------------------------------------
# Scenario 4 — Joint family + its businesses: the Randhawa family (seven books)
# ----------------------------------------------------------------------------------------------
def build_uc4():
    uc = UseCase("joint-family-randhawa",
                 "Joint family and its businesses — the Randhawa family (seven books)",
                 "Joint family: one joint fund, three sub-family books, three family businesses",
                 "Three brothers — Amarjeet, Lakhbeer and Lakhwinder Randhawa — run a joint household. The common money lives in the **Randhawa Family Fund** (the joint fund); each brother's household has its own sub-family book; "
                 "the family owns **Randhawa Agriculture** and **Randhawa Real Estate** outright and shares **Randhawa Brick Field** 3 : 2 with an outside partner, Nirmaljeet Gill, who is not on the app. "
                 "Each book stands on its own: every movement between two books is entered in both, as a matching pair, and the Family Reconciliation table at the end shows each pair agreeing. "
                 "Assumptions stated, not given: Indu is Amarjeet's wife; Aman is Lakhbeer's son and runs the farm day to day.",
                 [("Amarjeet Randhawa", "eldest brother · admin of the fund, Agriculture and Brick Field · head of his sub-family book"),
                  ("Lakhbeer Randhawa", "brother · admin of the fund and Brick Field · head of his sub-family book · approves members' over-limit entries in the fund"),
                  ("Lakhwinder Randhawa", "brother · admin of the fund and Real Estate · head role in Agriculture · head of his sub-family book"),
                  ("Indu Randhawa", "Amarjeet's wife · member of the fund (limit ₹5,000) and of Amarjeet's Family (limit ₹3,000)"),
                  ("Aman Randhawa", "Lakhbeer's son · member of the fund (₹5,000), of Lakhbeer's Family (₹3,000) and of Agriculture (₹20,000) — holds the monthly farm-labour advance"),
                  ("Harjeet Randhawa", "Lakhwinder's wife · member of the fund (₹5,000), of Lakhwinder's Family (₹5,000) and of Real Estate (₹5,000)"),
                  ("Supreet Randhawa", "Lakhwinder's daughter · member of Lakhwinder's Family (limit ₹2,000)"),
                  ("Nirmaljeet Gill", "outside partner in the Brick Field (weight 2 of 5) — **not on the app**; his takeouts are entered by Lakhbeer on his instruction")])
    A, L, W = "Amarjeet Randhawa", "Lakhbeer Randhawa", "Lakhwinder Randhawa"
    I, AM, HR, SU = "Indu Randhawa", "Aman Randhawa", "Harjeet Randhawa", "Supreet Randhawa"

    # ---------------- books
    rf = uc.book("RF", "Randhawa Family Fund — Joint Fund Book", "joint", "RF",
                 members=[(A, "admin", None, "karta"), (L, "admin", None, ""), (W, "admin", None, ""), (I, "member", R(5000), ""), (AM, "member", R(5000), ""), (HR, "member", R(5000), "")])
    af = uc.book("AF", "Amarjeet's Family — Sub-family Book", "family", "AF", members=[(A, "admin", None, ""), (I, "member", R(3000), "")])
    lf = uc.book("LF", "Lakhbeer's Family — Sub-family Book", "family", "LF", members=[(L, "admin", None, ""), (AM, "member", R(3000), "")])
    lw = uc.book("LW", "Lakhwinder's Family — Sub-family Book", "family", "LW", members=[(W, "admin", None, ""), (HR, "member", R(5000), ""), (SU, "member", R(2000), "")])
    ra = uc.book("RA", "Randhawa Agriculture — Family Business Book", "business", "RA", ownership="just_me",
                 members=[(A, "admin", None, ""), (L, "admin", None, ""), (W, "head", None, ""), (AM, "member", R(20000), "farm manager")])
    rr = uc.book("RR", "Randhawa Real Estate — Family Business Book", "business", "RR", ownership="just_me", members=[(W, "admin", None, ""), (HR, "member", R(5000), "")])
    rb = uc.book("RB", "Randhawa Brick Field — Shared Business Book", "business", "RB", ownership="shared", members=[(L, "admin", None, ""), (A, "admin", None, "")])
    rf.config["peer_reviewer"] = "Lakhbeer Randhawa for members' flags; Lakhwinder Randhawa for Amarjeet's and Lakhbeer's own entries (none arose — admins carry no limit)"
    rf.plain.append("Members' entries over their limit are approved by Lakhbeer Randhawa; Amarjeet's and Lakhbeer's own entries would go to Lakhwinder Randhawa (none arose — admins have no limit).")
    ra.notes.append("Ownership answer at creation: **Just me** — the farm is owned by the joint family as a whole, so it has no partner accounts; its surplus goes to the Family Fund as an ordinary transfer between the two books, never as a drawing. Drawings A/c is created for every *Just me* business and stays unused here.")
    rr.notes.append("Ownership: **Just me** (family-owned). Each tenant has one account: a security deposit held is a **credit** on it (you will give it back), the month's rent is entered as a debit on the 1st, and each receipt credits it. See section 8 for how old the arrears are and for the deposit adjusted when a tenant leaves.")
    rb.notes.append("Ownership: **Shared with others** — Randhawa family (share 3) and Nirmaljeet Gill (share 2). The kiln and its land are not on the books (a thing owned is not yet an account — a known limit); the partners' opening balances are the working money each put in when the book was created, and Opening Balance / Capital holds the ₹2,000 difference between the ₹4,52,000 net opening position on the books and the ₹4,50,000 put in.")
    rb.config["partner_shares"] = "{pc_fam: 3, pc_gill: 2} — recorded once in `book_config` at creation"
    rb.config["structural_quorum"] = "`all_owners`, chosen explicitly at creation. ⚠️ With an owner who is not on the app no structural action (profit distribution, interest on capital, ratio change) can reach quorum in-app — so FY 2025-26's surplus stays undistributed and is carried as the computed Accumulated surplus (see *Year close* and the README)"
    rb.plain.append("Partners' shares: Randhawa family 3 · Nirmaljeet Gill 2, agreed when the book was created. Decisions that change the partnership need every owner's approval; Nirmaljeet Gill is not on the app, so no such decision — sharing out the profit, interest on capital, a change of shares — could be completed this year. The surplus stays in the business and is carried forward (see the position and the year end).")

    # ---------------- Family Fund accounts
    jcash = rf.acct("jcash", "Joint Cash A/c", "money", subtype="cash", opening=R(9500))
    jsav = rf.acct("jsav", "Joint Savings A/c (SBI)", "money", subtype="saving", opening=R(215000))
    rf_af = rf.acct("l_af", "Amarjeet's Family (sub-family book)", "equity_system", role="link", link_to="AF")
    rf_lf = rf.acct("l_lf", "Lakhbeer's Family (sub-family book)", "equity_system", role="link", link_to="LF")
    rf_lw = rf.acct("l_lw", "Lakhwinder's Family (sub-family book)", "equity_system", role="link", link_to="LW")
    rf_ra = rf.acct("l_ra", "Randhawa Agriculture (family business book)", "equity_system", role="link", link_to="RA")
    rf_rr = rf.acct("l_rr", "Randhawa Real Estate (family business book)", "equity_system", role="link", link_to="RR")
    rf_rb = rf.acct("l_rb", "Randhawa Brick Field (shared business book)", "equity_system", role="link", link_to="RB")
    f_elec = rf.acct("elec", "Electricity Expense A/c (common house)", "category_expense")
    f_kit = rf.acct("kit", "Common Kitchen Expense A/c", "category_expense")
    f_rep = rf.acct("rep", "House Repair Expense A/c", "category_expense")
    f_fun = rf.acct("fun", "Function & Ceremony Expense A/c", "category_expense")
    f_fest = rf.acct("fest", "Festival Expense A/c", "category_expense")
    f_med = rf.acct("med", "Medical Expense A/c (elders)", "category_expense")
    f_tax = rf.acct("tax", "Property Tax Expense A/c", "category_expense")
    f_int = rf.acct("int", "Savings Interest Income A/c", "category_income")
    rf.acct("ob", "Opening Balance / Capital A/c", "equity_system", role="opening_balance")
    f_adj = rf.acct("adj", "Adjustments A/c", "equity_system", role="adjustments")
    rf.post_opening(A)

    # ---------------- sub-family books
    def subfam(bk, head, cash_open, sav_open, sav_name, extra_cats):
        c = bk.acct("cash", "Cash in Hand", "money", subtype="cash", opening=cash_open)
        s = bk.acct("sav", sav_name, "money", subtype="saving", opening=sav_open)
        lk = bk.acct("l_rf", "Randhawa Family Fund (joint family book)", "equity_system", role="link", link_to="RF")
        cats = OrderedDict()
        for aid, nm in [("groc", "Groceries & Kitchen Expense A/c"), ("fuel", "Fuel & Travel Expense A/c"), ("mob", "Mobile & Internet Expense A/c"), ("med", "Medical Expense A/c")] + extra_cats:
            cats[aid] = bk.acct(aid, nm, "category_expense")
        bk.acct("ob", "Opening Balance / Capital A/c", "equity_system", role="opening_balance")
        bk.acct("adj", "Adjustments A/c", "equity_system", role="adjustments")
        bk.post_opening(head)
        return c, s, lk, cats
    af_cash, af_sav, af_rf, af_c = subfam(af, A, R(4200), R(38000), "Amarjeet — Canara Savings A/c", [("fees", "School Fees Expense A/c"), ("cloth", "Clothing Expense A/c"), ("rep", "House Repair Expense A/c")])
    lf_cash, lf_sav, lf_rf, lf_c = subfam(lf, L, R(3800), R(52000), "Lakhbeer — PNB Savings A/c", [("fees", "College Fees Expense A/c"), ("fest", "Festival Expense A/c")])
    lw_cash, lw_sav, lw_rf, lw_c = subfam(lw, W, R(5600), R(71000), "Lakhwinder — SBI Savings A/c", [("fees", "College Fees Expense A/c"), ("books", "Books & Stationery Expense A/c"), ("cloth", "Clothing Expense A/c"), ("fun", "Function & Ceremony Expense A/c")])

    # ---------------- Agriculture accounts
    fcash = ra.acct("fcash", "Farm Cash A/c", "money", subtype="cash", opening=R(14000))
    fsbi = ra.acct("fsbi", "SBI Savings A/c (farm)", "money", subtype="saving", opening=R(390000))
    kcc = ra.acct("kcc", "PNB Kisan Credit Card A/c", "money", subtype="loan", opening=-R(320000), note="Kisan Credit Card — a loan from the bank")
    sodhi = ra.acct("sodhi", "Sodhi & Sons (arhtiya) A/c", "party", note="commission agent — owes, then is owed, then nil")
    verka = ra.acct("verka", "Verka Milk Society A/c", "party", note="dairy society — the month's milk is billed, then paid", opening=R(24600))
    khad = ra.acct("khad", "Kisan Khad Store A/c", "party", note="fertiliser dealer — khata", opening=-R(36000))
    adv_am = ra.acct("adv_am", "Advance – Aman Randhawa A/c", "advance")
    ra_rf = ra.acct("l_rf", "Randhawa Family Fund (joint family book)", "equity_system", role="link", link_to="RF")
    ra.acct("draw", "Drawings A/c", "equity_system", role="drawings")
    ra.acct("ob", "Opening Balance / Capital A/c", "equity_system", role="opening_balance")
    ra_adj = ra.acct("adj", "Adjustments A/c", "equity_system", role="adjustments")
    crop = ra.acct("crop", "Crop Sale Income A/c", "category_income")
    milk = ra.acct("milk", "Milk Sale Income A/c", "category_income")
    fert = ra.acct("fert", "Seed & Fertiliser Expense A/c", "category_expense")
    dsl = ra.acct("dsl", "Diesel & Machinery Expense A/c", "category_expense")
    lab = ra.acct("lab", "Labour Expense A/c", "category_expense")
    rep = ra.acct("rep", "Machinery Repair Expense A/c", "category_expense")
    feed = ra.acct("feed", "Cattle Feed Expense A/c", "category_expense")
    kint = ra.acct("kint", "Interest on KCC Expense A/c", "category_expense")
    achg = ra.acct("achg", "Arhtiya Charges Expense A/c", "category_expense")
    twell = ra.acct("twell", "Tube-well Electricity Expense A/c", "category_expense")
    ra.post_opening(A)

    # ---------------- Real Estate accounts
    rcash = rr.acct("rcash", "RR Cash A/c", "money", subtype="cash", opening=R(6000))
    rhdfc = rr.acct("rhdfc", "HDFC Current A/c (RR)", "money", subtype="current", opening=R(85000))
    kaur = rr.acct("kaur", "Dr Kaur's Clinic (tenant) A/c", "party", note="shop tenant — ₹36,000 deposit held", opening=-R(36000))
    shar = rr.acct("shar", "Sharma Family (tenant) A/c", "party", note="house tenant — no deposit, pays irregularly")
    mehta = rr.acct("mehta", "Mehta Mobile Shop (tenant) A/c", "party", note="shop tenant — ₹24,000 deposit, leaves 31 Jan", opening=-R(24000))
    sidhu = rr.acct("sidhu", "Sidhu Pharmacy (tenant) A/c", "party", note="new shop tenant from 01 Mar 2026 — ₹30,000 deposit")
    rr_rf = rr.acct("l_rf", "Randhawa Family Fund (joint family book)", "equity_system", role="link", link_to="RF")
    rr.acct("draw", "Drawings A/c", "equity_system", role="drawings")
    rr.acct("ob", "Opening Balance / Capital A/c", "equity_system", role="opening_balance")
    rr.acct("adj", "Adjustments A/c", "equity_system", role="adjustments")
    rinc = rr.acct("rinc", "Rent Income A/c", "category_income")
    rrep = rr.acct("rrep", "Property Repair & Maintenance Expense A/c", "category_expense")
    rtax = rr.acct("rtax", "Property Tax Expense A/c", "category_expense")
    rwat = rr.acct("rwat", "Water & Common Electricity Expense A/c", "category_expense")
    rbank = rr.acct("rbank", "Bank Charges Expense A/c", "category_expense")
    rr.post_opening(W)

    # ---------------- Brick Field accounts
    bcash = rb.acct("bcash", "Brick Field Cash A/c", "money", subtype="cash", opening=R(22000))
    canara = rb.acct("canara", "Canara Bank Current A/c", "money", subtype="current", opening=R(520000))
    dhal = rb.acct("dhal", "Dhaliwal Builders A/c", "party", note="customer", opening=R(120000))
    kang = rb.acct("kang", "Kang Constructions A/c", "party", note="customer")
    coal = rb.acct("coal", "Punjab Coal Depot A/c", "party", note="coal supplier on credit", opening=-R(210000))
    pc_fam = rb.acct("pc_fam", "Randhawa Family — Partner Current A/c", "partner", opening=-R(270000))
    pc_gill = rb.acct("pc_gill", "Nirmaljeet Gill — Partner Current A/c", "partner", opening=-R(180000))
    rb.acct("pd", "Profit Distributed A/c", "equity_system", role="profit_distributed")
    rb_rf = rb.acct("l_rf", "Randhawa Family Fund (joint family book)", "equity_system", role="link", link_to="RF")
    rb.acct("ob", "Opening Balance / Capital A/c", "equity_system", role="opening_balance")
    rb.acct("adj", "Adjustments A/c", "equity_system", role="adjustments")
    bsales = rb.acct("bsales", "Brick Sales A/c", "category_income")
    bcoal = rb.acct("bcoal", "Coal & Fuel Expense A/c", "category_expense")
    blab = rb.acct("blab", "Labour Expense A/c (moulders and firemen)", "category_expense")
    bclay = rb.acct("bclay", "Clay & Soil Expense A/c", "category_expense")
    btr = rb.acct("btr", "Transport Expense A/c", "category_expense")
    brep = rb.acct("brep", "Kiln Repair Expense A/c", "category_expense")
    belec = rb.acct("belec", "Electricity Expense A/c", "category_expense")
    bbank = rb.acct("bbank", "Bank Charges Expense A/c", "category_expense")
    rb.post_opening(L)

    # ---------------- the year: allowances and sub-family spending
    allowance = {"AF": (af, af_sav, af_rf, rf_af, R(18000), A), "LF": (lf, lf_sav, lf_rf, rf_lf, R(18000), L), "LW": (lw, lw_sav, lw_rf, rf_lw, R(22000), W)}
    for mk in fy_months():
        y, m = int(mk[:4]), int(mk[5:])
        for key, (bk, sav, lk, rflk, amt, head) in allowance.items():
            uc.link(d(y, m, 1), amt, rf, [(rflk, amt), (jsav, -amt)], bk, [(sav, amt), (lk, -amt)],
                    "Monthly household allowance to %s by NEFT" % bk.name.split(" — ")[0], "Monthly household allowance received from the Family Fund", A, by_to=head, t=1)
        # fund
        rf.v(d(y, m, 2), "transfer", "Cash drawn from Joint Savings for the common kitchen", [(jcash, R(15000)), (jsav, -R(15000))], A, t=1)
        rf.v(d(y, m, 8), "money_out", "Common house electricity bill paid by net banking", [(f_elec, R({4: 3100, 5: 4200, 6: 4800, 7: 4700, 8: 4300, 9: 4000, 10: 3500, 11: 3000, 12: 3200, 1: 3400, 2: 3100, 3: 3000}[m])),
                                                                                             (jsav, -R({4: 3100, 5: 4200, 6: 4800, 7: 4700, 8: 4300, 9: 4000, 10: 3500, 11: 3000, 12: 3200, 1: 3400, 2: 3100, 3: 3000}[m]))], A)
        rf.v(d(y, m, 20), "money_out", "Common kitchen — atta, dal, oil and milk for the month, paid in cash", [(f_kit, R(12000)), (jcash, -R(12000))], A)
        # Amarjeet's family
        af_w = R(12000) + (R(8000) if m in (7, 10) else 0)
        af.v(d(y, m, 3), "transfer", "Cash withdrawn for the month", [(af_cash, af_w), (af_sav, -af_w)], A, t=1)
        g = {4: 6200, 5: 6600, 6: 6100, 7: 6900, 8: 6400, 9: 6700, 10: 7100, 11: 6500, 12: 6300, 1: 6600, 2: 6200, 3: 6800}[m]
        af.v(d(y, m, 12), "money_out", "Groceries and vegetables for the month in cash", [(af_c["groc"], R(g)), (af_cash, -R(g))], A)
        af.v(d(y, m, 5), "money_out", "Mobile and broadband recharge in cash", [(af_c["mob"], R(1200)), (af_cash, -R(1200))], I)
        af.v(d(y, m, 15), "money_out", "Scooter petrol in cash", [(af_c["fuel"], R(2000)), (af_cash, -R(2000))], A)
        # Lakhbeer's family
        lf_w = R(11000) + (R(7000) if m == 10 else 0)
        lf.v(d(y, m, 3), "transfer", "Cash withdrawn for the month", [(lf_cash, lf_w), (lf_sav, -lf_w)], L, t=1)
        g = {4: 6100, 5: 6400, 6: 6000, 7: 6700, 8: 6300, 9: 6500, 10: 7200, 11: 6400, 12: 6100, 1: 6500, 2: 6000, 3: 6600}[m]
        lf.v(d(y, m, 12), "money_out", "Groceries and vegetables for the month in cash", [(lf_c["groc"], R(g)), (lf_cash, -R(g))], L)
        lf.v(d(y, m, 6), "money_out", "Motorcycle petrol in cash", [(lf_c["fuel"], R(2500)), (lf_cash, -R(2500))], AM)
        lf.v(d(y, m, 4), "money_out", "Mobile recharge in cash", [(lf_c["mob"], R(999)), (lf_cash, -R(999))], AM)
        # Lakhwinder's family
        lw.v(d(y, m, 3), "transfer", "Cash withdrawn for the month", [(lw_cash, R(14000) + (R(9000) if m == 10 else 0)), (lw_sav, -(R(14000) + (R(9000) if m == 10 else 0)))], W, t=1)
        g = {4: 6900, 5: 7300, 6: 6800, 7: 7600, 8: 7100, 9: 7400, 10: 7900, 11: 7200, 12: 6900, 1: 7300, 2: 6800, 3: 7500}[m]
        lw.v(d(y, m, 12), "money_out", "Groceries and vegetables for the month in cash", [(lw_c["groc"], R(g)), (lw_cash, -R(g))], W)
        lw.v(d(y, m, 7), "money_out", "Car fuel in cash", [(lw_c["fuel"], R(2800)), (lw_cash, -R(2800))], W)
        lw.v(d(y, m, 4), "money_out", "Mobile and broadband recharge in cash", [(lw_c["mob"], R(1499)), (lw_cash, -R(1499))], HR)
        bk_amt = {4: 900, 5: 600, 6: 1100, 7: 1900, 8: 2650, 9: 800, 10: 700, 11: 1300, 12: 650, 1: 1800, 2: 900, 3: 1200}[m]
        lw.v(d(y, m, 18), "money_out", "Books and stationery for college in cash", [(lw_c["books"], R(bk_amt)), (lw_cash, -R(bk_amt))], SU,
             review={"approver": W, "decided": d(y, m, 19), "decision": "approved", "reason": "", "limit": R(2000)} if bk_amt > 2000 else None)
    # fund: one-offs
    rf.v(d(2025, 6, 22), "money_out", "Roof waterproofing of the common house, paid by NEFT", [(f_rep, R(36000)), (jsav, -R(36000))], A)
    rf.v(d(2025, 10, 19), "money_out", "Diwali — sweets, lights and gifts for the whole household, cash", [(f_fest, R(22000)), (jcash, -R(22000))], A)
    rf.v(d(2025, 12, 3), "money_out", "Bibi ji's cataract operation, paid by NEFT", [(f_med, R(15600)), (jsav, -R(15600))], A)
    rf.v(d(2026, 1, 13), "money_out", "Lohri function — tent, dhol and dinner for the village, by NEFT", [(f_fun, R(48000)), (jsav, -R(48000))], A)
    rf.v(d(2025, 9, 12), "money_out", "House property tax paid in cash at the municipal office", [(f_tax, R(6200)), (jcash, -R(6200))], AM,
         review={"approver": L, "decided": d(2025, 9, 13), "decision": "approved", "reason": "", "limit": R(5000)})
    rejected = rf.v(d(2025, 7, 14), "money_out", "Kitchen tap and pipe repair paid in cash", [(f_rep, R(7500)), (jcash, -R(7500))], I,
                    review={"approver": L, "decided": d(2025, 7, 16), "decision": "rejected", "reason": "paid from Amarjeet's household cash, not from the fund — belongs in Amarjeet's Family book", "limit": R(5000)})
    rf.reject(rejected, L, d(2025, 7, 16), "paid from Amarjeet's household cash, not from the fund")
    af.v(d(2025, 7, 16), "money_out", "Kitchen tap and pipe repair paid in cash (re-recorded here after the fund entry was rejected)", [(af_c["rep"], R(7500)), (af_cash, -R(7500))], A)
    for dt, amt in ((d(2025, 6, 30), R(1245, 60)), (d(2025, 9, 30), R(1038, 15)), (d(2025, 12, 31), R(1412, 90)), (d(2026, 3, 31), R(1190, 45))):
        rf.v(dt, "money_in", "Quarterly savings interest credited by SBI", [(jsav, amt), (f_int, -amt)], A, t=2)
    # one-sided own-pocket payment: Amarjeet pays the fund's electricity from his household cash (02 §6)
    uc.link(d(2025, 8, 6), R(4300), af, [(af_rf, R(4300)), (af_cash, -R(4300))], rf, [(f_elec, R(4300)), (rf_af, -R(4300))],
            "Paid the common house's electricity bill from household cash — the fund owes Amarjeet's family", "Common house electricity bill paid by Amarjeet from his household cash (one-sided pair, 02 §6; the payee half is a Money out whose credit is the link)", A, t=3, kind_to="money_out")
    # sub-family one-offs
    af.v(d(2025, 4, 10), "money_out", "School fees for the children, first term, by NEFT", [(af_c["fees"], R(24000)), (af_sav, -R(24000))], A)
    af.v(d(2025, 10, 10), "money_out", "School fees for the children, second term, by NEFT", [(af_c["fees"], R(24000)), (af_sav, -R(24000))], A)
    af.v(d(2025, 8, 22), "money_out", "Doctor and medicines, cash", [(af_c["med"], R(3400)), (af_cash, -R(3400))], A)
    af.v(d(2025, 10, 11), "money_out", "Diwali clothes for the children, cash", [(af_c["cloth"], R(4800)), (af_cash, -R(4800))], I,
         review={"approver": A, "decided": d(2025, 10, 12), "decision": "approved", "reason": "", "limit": R(3000)})
    lf.v(d(2025, 7, 15), "money_out", "Aman's college fee, first semester, by NEFT", [(lf_c["fees"], R(36000)), (lf_sav, -R(36000))], L)
    lf.v(d(2026, 1, 15), "money_out", "Aman's college fee, second semester, by NEFT", [(lf_c["fees"], R(36000)), (lf_sav, -R(36000))], L)
    lf.v(d(2025, 10, 18), "money_out", "Diwali sweets and gifts, cash", [(lf_c["fest"], R(6500)), (lf_cash, -R(6500))], L)
    lf.v(d(2026, 2, 9), "money_out", "Doctor and medicines, cash", [(lf_c["med"], R(2800)), (lf_cash, -R(2800))], L)
    lw.v(d(2025, 7, 20), "money_out", "Supreet's college fee, first semester, by NEFT", [(lw_c["fees"], R(45000)), (lw_sav, -R(45000))], W)
    lw.v(d(2026, 1, 20), "money_out", "Supreet's college fee, second semester, by NEFT", [(lw_c["fees"], R(45000)), (lw_sav, -R(45000))], W)
    lw.v(d(2025, 10, 16), "money_out", "Diwali clothes for the family, cash", [(lw_c["cloth"], R(8400)), (lw_cash, -R(8400))], W)
    lw.v(d(2025, 12, 14), "money_out", "Supreet's birthday dinner for relatives, by NEFT", [(lw_c["fun"], R(15000)), (lw_sav, -R(15000))], W)
    lw.v(d(2025, 9, 9), "money_out", "Doctor and medicines, cash", [(lw_c["med"], R(1800)), (lw_cash, -R(1800))], HR)

    # ---------------- Agriculture — the year
    ra.v(d(2025, 4, 22), "money_in", "Wheat 320 qtl procured at MSP ₹2,425 — payment credited direct to the farm's SBI account by the procurement agency", [(fsbi, R(776000)), (crop, -R(776000))], A)
    ra.v(d(2025, 5, 5), "transfer", "KCC repaid in full after the wheat payment (Dr loan account · Cr savings)", [(kcc, R(320000)), (fsbi, -R(320000))], A, t=1)
    ra.v(d(2025, 5, 5), "money_out", "Paid Kisan Khad Store the rabi fertiliser dues by UPI", [(khad, R(36000)), (fsbi, -R(36000))], A, t=2)
    ra.v(d(2025, 6, 20), "took_credit", "Kisan Khad Store — urea and DAP for paddy on khata", [(fert, R(68000)), (khad, -R(68000))], A)
    ra.v(d(2025, 7, 25), "took_credit", "Kisan Khad Store — zinc and pesticide on khata", [(fert, R(42000)), (khad, -R(42000))], A)
    ra.v(d(2025, 7, 8), "transfer", "KCC drawn for paddy transplanting costs (Dr savings · Cr loan account)", [(fsbi, R(250000)), (kcc, -R(250000))], A, t=1)
    ra.v(d(2025, 11, 25), "money_out", "Paid Kisan Khad Store the kharif khata by NEFT", [(khad, R(110000)), (fsbi, -R(110000))], A)
    ra.v(d(2025, 11, 10), "took_credit", "Kisan Khad Store — wheat seed and DAP on khata", [(fert, R(74000)), (khad, -R(74000))], A)
    ra.v(d(2026, 1, 20), "money_out", "Part payment to Kisan Khad Store by UPI", [(khad, R(30000)), (fsbi, -R(30000))], A)
    # KCC interest debited by the bank (money out from the loan account)
    for dt, amt in ((d(2025, 6, 30), R(2453, 70)), (d(2025, 9, 30), R(4027, 40)), (d(2025, 12, 31), R(4411, 64)), (d(2026, 3, 31), R(2256, 85))):
        ra.v(dt, "money_out", "Interest debited by PNB on the Kisan Credit Card account", [(kint, amt), (kcc, -amt)], A, t=6)
    ra.v(d(2025, 12, 15), "transfer", "KCC repaid after the basmati payment", [(kcc, R(250000)), (fsbi, -R(250000))], A, t=1)
    ra.v(d(2026, 3, 12), "transfer", "KCC drawn for the wheat harvest season", [(fsbi, R(150000)), (kcc, -R(150000))], A, t=1)
    # arhtiya: Dr → Cr → zero
    ra.v(d(2025, 11, 12), "gave_credit", "Basmati 180 qtl sold through Sodhi & Sons at ₹4,200 — gross sale on the arhtiya's khata", [(sodhi, R(756000)), (crop, -R(756000))], A)
    ra.v(d(2025, 11, 14), "took_credit", "Sodhi & Sons — commission and mandi charges deducted (2.5% of the basmati sale)", [(achg, R(18900)), (sodhi, -R(18900))], A)
    ra.v(d(2025, 11, 20), "money_in", "Sodhi & Sons paid the basmati proceeds by RTGS plus ₹60,000 advanced against the next crop — the farm now owes the arhtiya (Cr)", [(fsbi, R(797100)), (sodhi, -R(797100))], A)
    ra.v(d(2026, 3, 10), "gave_credit", "Mustard 13 qtl sold through Sodhi & Sons — gross sale on the khata", [(sodhi, R(61600)), (crop, -R(61600))], A)
    ra.v(d(2026, 3, 11), "took_credit", "Sodhi & Sons — commission, palledari and mandi charges on the mustard", [(achg, R(1600)), (sodhi, -R(1600))], A, note="the khata closes at exactly zero: the ₹60,000 advance is settled by the net proceeds")
    # milk society — monthly accrual, paid on the 10th of the next month
    milk_amt = {4: R(28412, 50), 5: R(27180, 0), 6: R(25915, 75), 7: R(26340, 25), 8: R(27705, 0), 9: R(28120, 50), 10: R(29610, 0), 11: R(30265, 25), 12: R(31140, 75), 1: R(30880, 0), 2: R(27955, 50), 3: R(29725, 25)}
    prev_milk = R(24600)
    for mk in fy_months():
        y, m = int(mk[:4]), int(mk[5:])
        me = month_end(date(y, m, 1))
        ra.v(d(y, m, 10), "money_in", "Verka Milk Society paid last month's milk bill by NEFT", [(fsbi, prev_milk), (verka, -prev_milk)], A, t=2)
        ra.v(me, "gave_credit", "Milk supplied to Verka Milk Society this month — society's bill (fat-based) accrued", [(verka, milk_amt[m]), (milk, -milk_amt[m])], A, t=5)
        prev_milk = milk_amt[m]
        # cash and running costs
        ra.v(d(y, m, 1), "transfer", "Cash drawn from SBI for the month's farm expenses", [(fcash, R(45000)), (fsbi, -R(45000))], A, t=0)
        ra.v(d(y, m, 9), "money_out", "Diesel for tractor and tube-well, cash", [(dsl, R({4: 14500, 5: 9800, 6: 16200, 7: 18900, 8: 12400, 9: 11800, 10: 15600, 11: 17200, 12: 10900, 1: 9600, 2: 10400, 3: 16800}[m])),
                                                                                (fcash, -R({4: 14500, 5: 9800, 6: 16200, 7: 18900, 8: 12400, 9: 11800, 10: 15600, 11: 17200, 12: 10900, 1: 9600, 2: 10400, 3: 16800}[m]))], AM)
        ra.v(d(y, m, 14), "money_out", "Cattle feed (khal and chokar) for the month, cash", [(feed, R(8200)), (fcash, -R(8200))], AM)
        ra.v(d(y, m, 16), "money_out", "Tube-well electricity bill by net banking", [(twell, R({4: 2100, 5: 2900, 6: 3600, 7: 3900, 8: 3500, 9: 3100, 10: 2600, 11: 2200, 12: 2000, 1: 2100, 2: 2000, 3: 2400}[m])),
                                                                                       (fsbi, -R({4: 2100, 5: 2900, 6: 3600, 7: 3900, 8: 3500, 9: 3100, 10: 2600, 11: 2200, 12: 2000, 1: 2100, 2: 2000, 3: 2400}[m]))], A)
        # the monthly labour advance to Aman (02 §7)
        req = d(y, m, 10) if m == 6 else d(y, m, 2)
        appr = d(y, m, 12) if m == 6 else d(y, m, 2)
        ra.advance_request(req, appr, A, AM, R(15000), "farm labour payments for the month", fcash, adv_am)
        spent = {4: 12800, 5: 14200, 6: 15000, 7: 13600, 8: 9500, 9: 14900, 10: 13200, 11: 15000, 12: 11400, 1: 12600, 2: 13900, 3: 14700}[m]
        ra.v(d(y, m, 20), "money_out", "Aman submitted the month's labour payment slips against his advance (Dr expense · Cr Advance, 02 §7)", [(lab, R(spent)), (adv_am, -R(spent))], AM, tag="advance_spend")
        if spent < 15000:
            ret_date = d(2025, 9, 22) if m == 8 else d(y, m, 25)
            ra.v(ret_date, "money_in", "Aman returned the unspent remainder of the month's advance to Farm Cash", [(fcash, R(15000 - spent)), (adv_am, -R(15000 - spent))], AM, tag="advance_return")
    ra.v(d(2025, 8, 18), "money_out", "Combine harvester repair — workshop bill paid by NEFT", [(rep, R(28500)), (fsbi, -R(28500))], A)
    ra.v(d(2026, 2, 24), "money_out", "Tractor clutch plate and service, cash", [(rep, R(16400)), (fcash, -R(16400))], AM)
    # surplus to the fund (02 §7.1: an inter-book transfer, not a drawing)
    for dt, amt, why in ((d(2025, 5, 20), R(350000), "after the wheat payment"), (d(2025, 8, 20), R(150000), "from milk income and the KCC drawdown headroom"), (d(2025, 11, 28), R(350000), "after the basmati payment"), (d(2026, 2, 16), R(100000), "from milk income")):
        uc.link(dt, amt, ra, [(ra_rf, amt), (fsbi, -amt)], rf, [(jsav, amt), (rf_ra, -amt)],
                "Farm surplus remitted to the Randhawa Family Fund by NEFT (%s)" % why, "Surplus received from Randhawa Agriculture by NEFT (%s)" % why, A, t=4)

    # ---------------- Real Estate — the year
    rents = [(kaur, R(18000), range(1, 13)), (shar, R(9000), range(1, 13)), (mehta, R(12000), (4, 5, 6, 7, 8, 9, 10, 11, 12, 1)), (sidhu, R(14000), (3,))]
    sharma_pay = {4: (20, R(9000)), 5: (25, R(9000)), 6: (28, R(9000)), 8: (30, R(18000)), 9: (22, R(9000)), 10: (29, R(9000)), 12: (30, R(18000)), 1: (25, R(9000))}
    for mk in fy_months():
        y, m = int(mk[:4]), int(mk[5:])
        for tenant, amt, months in rents:
            if m in months:
                rr.v(d(y, m, 1), "gave_credit", "Rent for the month due from %s" % tenant.name.replace(" (tenant) A/c", ""), [(tenant, amt), (rinc, -amt)], W, t=1)
        rr.v(d(y, m, 5), "money_in", "Dr Kaur's Clinic paid the month's rent by NEFT", [(rhdfc, R(18000)), (kaur, -R(18000))], W)
        if m in (4, 5, 6, 7, 8, 9, 10, 11, 12):
            rr.v(d(y, m, 7), "money_in", "Mehta Mobile Shop paid the month's rent in cash", [(rcash, R(12000)), (mehta, -R(12000))], W)
            rr.v(d(y, m, 8), "transfer", "Cash rent deposited into HDFC", [(rhdfc, R(12000)), (rcash, -R(12000))], W)
        if m in sharma_pay:
            dd, amt = sharma_pay[m]
            rr.v(d(y, m, dd), "money_in", "Sharma Family paid rent by UPI%s" % (" (two months)" if amt > R(9000) else ""), [(rhdfc, amt), (shar, -amt)], W)
        if m == 3:
            rr.v(d(y, m, 5), "money_in", "Sidhu Pharmacy paid March rent by NEFT", [(rhdfc, R(14000)), (sidhu, -R(14000))], W, t=6)
        w = {4: 1100, 5: 1400, 6: 1600, 7: 1550, 8: 1500, 9: 1350, 10: 1200, 11: 1100, 12: 1150, 1: 1200, 2: 1100, 3: 1150}[m]
        rr.v(d(y, m, 15), "money_out", "Water and common-passage electricity for the shops, paid by UPI", [(rwat, R(w)), (rhdfc, -R(w))], HR)
        rr.v(month_end(date(y, m, 1)), "money_out", "Bank charges debited by HDFC", [(rbank, R(118)), (rhdfc, -R(118))], W, t=7)
    rr.v(d(2025, 7, 22), "money_out", "Shop-front plaster and painting, paid by NEFT", [(rrep, R(18500)), (rhdfc, -R(18500))], W)
    rr.v(d(2025, 12, 9), "money_out", "Plumbing repair in the rented house, paid by UPI", [(rrep, R(9200)), (rhdfc, -R(9200))], W)
    rr.v(d(2025, 9, 18), "money_out", "Property tax on the shops and the rented house, paid online", [(rtax, R(14300)), (rhdfc, -R(14300))], W)
    rr.v(d(2026, 2, 2), "money_out", "Refund of Mehta Mobile Shop's deposit after adjusting January's rent — tenant left 31 Jan", [(mehta, R(12000)), (rhdfc, -R(12000))], W, note="deposit ₹24,000 − January rent ₹12,000 = ₹12,000 refunded; the account closes at zero")
    rr.v(d(2026, 2, 25), "money_in", "Security deposit received from Sidhu Pharmacy, the new shop tenant (party Cr — held across the FY boundary)", [(rhdfc, R(30000)), (sidhu, -R(30000))], W)
    for dt in (d(2025, 6, 30), d(2025, 9, 30), d(2025, 12, 31), d(2026, 3, 31)):
        uc.link(dt, R(60000), rr, [(rr_rf, R(60000)), (rhdfc, -R(60000))], rf, [(jsav, R(60000)), (rf_rr, -R(60000))],
                "Quarter's rent surplus remitted to the Randhawa Family Fund by NEFT", "Rent surplus received from Randhawa Real Estate by NEFT", W, t=4)

    # ---------------- Brick Field — the year (kiln runs Oct–Jun; closed in the monsoon)
    season = {4: 1, 5: 1, 6: 1, 7: 0, 8: 0, 9: 0, 10: 1, 11: 1, 12: 1, 1: 1, 2: 1, 3: 1}
    cash_br = {4: 140000, 5: 155000, 6: 120000, 10: 135000, 11: 160000, 12: 170000, 1: 150000, 2: 165000, 3: 180000}
    cred_br = {4: (dhal, 95000), 5: (kang, 110000), 6: (dhal, 80000), 10: (kang, 120000), 11: (dhal, 140000), 12: (kang, 125000), 1: (dhal, 115000), 2: (kang, 130000), 3: (dhal, 150000)}
    coal_m = {4: 85000, 5: 90000, 6: 70000, 10: 95000, 11: 105000, 12: 110000, 1: 100000, 2: 105000, 3: 115000}
    lab_m = {4: 95000, 5: 105000, 6: 80000, 10: 90000, 11: 110000, 12: 120000, 1: 105000, 2: 110000, 3: 125000}
    prev_cred = None
    prev_coal = R(210000)
    for mk in fy_months():
        y, m = int(mk[:4]), int(mk[5:])
        last = month_end(date(y, m, 1)).day
        rb.v(d(y, m, 15), "money_out", "Nirmaljeet Gill took money out of the business for his household (entered by Lakhbeer on his instruction; Dr Partner Current · Cr bank)", [(pc_gill, R(25000)), (canara, -R(25000))], L, tag="takeout")
        rb.v(d(y, m, last), "money_out", "Bank charges debited by Canara Bank", [(bbank, R(265)), (canara, -R(265))], L, t=7)
        rb.v(d(y, m, 12), "money_out", "Electricity bill for the kiln office and pumps, by net banking", [(belec, R(3400) if season[m] else R(1200)), (canara, -(R(3400) if season[m] else R(1200)))], L)
        if prev_coal:
            rb.v(d(y, m, 11), "money_out", "Paid Punjab Coal Depot the previous coal invoice by RTGS", [(coal, prev_coal), (canara, -prev_coal)], L)
            prev_coal = 0
        if prev_cred:
            t_acct, t_amt = prev_cred
            rb.v(d(y, m, 9), "money_in", "%s paid last month's brick bill by NEFT" % t_acct.name.replace(" A/c", ""), [(canara, R(t_amt)), (t_acct, -R(t_amt))], L)
            prev_cred = None
        if season[m]:
            rb.v(d(y, m, 4), "took_credit", "Punjab Coal Depot — coal for the month's firing, on credit", [(bcoal, R(coal_m[m])), (coal, -R(coal_m[m]))], L)
            prev_coal = R(coal_m[m])
            rb.v(d(y, m, 3), "transfer", "Cash drawn from Canara for moulders' and firemen's wages", [(bcash, R(lab_m[m]) + R(28000)), (canara, -(R(lab_m[m]) + R(28000)))], L, t=1)
            rb.v(d(y, m, 14), "money_in", "Cash brick sales at the kiln, 1st to 14th", [(bcash, R(cash_br[m] // 2)), (bsales, -R(cash_br[m] // 2))], A, t=1)
            rb.v(d(y, m, last), "money_in", "Cash brick sales at the kiln, 15th to month end", [(bcash, R(cash_br[m] - cash_br[m] // 2)), (bsales, -R(cash_br[m] - cash_br[m] // 2))], A, t=1)
            rb.v(d(y, m, 16), "transfer", "Cash sales deposited into Canara", [(canara, R(cash_br[m] // 2)), (bcash, -R(cash_br[m] // 2))], L, t=2)
            rb.v(d(y, m, last), "transfer", "Cash sales deposited into Canara", [(canara, R(cash_br[m] - cash_br[m] // 2)), (bcash, -R(cash_br[m] - cash_br[m] // 2))], L, t=2)
            t_acct, t_amt = cred_br[m]
            rb.v(d(y, m, 20), "gave_credit", "Bricks supplied to %s on credit" % t_acct.name.replace(" A/c", ""), [(t_acct, R(t_amt)), (bsales, -R(t_amt))], L)
            prev_cred = (t_acct, t_amt)
            rb.v(d(y, m, last), "money_out", "Month's wages to moulders, loaders and firemen, cash", [(blab, R(lab_m[m])), (bcash, -R(lab_m[m]))], L, t=4)
            rb.v(d(y, m, 10), "money_out", "Clay and soil carted to the kiln, cash", [(bclay, R(9500)), (bcash, -R(9500))], A)
            rb.v(d(y, m, 22), "money_out", "Tractor-trolley hire for deliveries, cash", [(btr, R(14000)), (bcash, -R(14000))], A)
    rb.v(d(2025, 4, 2), "money_in", "Dhaliwal Builders paid the opening dues by NEFT", [(canara, R(120000)), (dhal, -R(120000))], L, t=1)
    rb.v(d(2025, 8, 12), "money_out", "Kiln chimney and flue relining in the off season, contractor paid by RTGS", [(brep, R(120000)), (canara, -R(120000))], L)
    rb.v(d(2025, 8, 20), "took_credit", "Nirmaljeet Gill paid the relining labour from his own pocket — the business owes him (02 §7.1)", [(brep, R(25000)), (pc_gill, -R(25000))], L, tag="own_pocket")
    uc.link(d(2025, 10, 1), R(150000), rf, [(rf_rb, R(150000)), (jsav, -R(150000))], rb, [(canara, R(150000)), (rb_rf, -R(150000))],
            "Loan to Randhawa Brick Field for the season restart — coal and wages until sales resume, by NEFT", "Loan received from the Randhawa Family Fund for the season restart (a 02 §6 pair — debt, not capital)", L, t=0)
    uc.link(d(2026, 2, 27), R(60000), rb, [(rb_rf, R(60000)), (canara, -R(60000))], rf, [(jsav, R(60000)), (rf_rb, -R(60000))],
            "Part repayment of the Family Fund's loan by NEFT", "Part repayment received from Randhawa Brick Field by NEFT", L, t=3)

    # ---------------- locks and counts
    rf.lock_all(A, day=7)
    rf.monthly_counts(jcash, A, diffs={"2026-01": -R(300)})
    af.lock_all(A, day=6)
    af.monthly_counts(af_cash, A)
    lf.lock_all(L, day=6)
    lf.monthly_counts(lf_cash, L)
    lw.lock_all(W, day=6)
    lw.monthly_counts(lw_cash, W)
    ra.lock_all(A, day=7)
    ra.monthly_counts(fcash, AM, diffs={"2025-10": -R(250)})
    for vo in ra.vouchers:
        if vo.tag == "advance_return" and vo.date == d(2025, 9, 22):
            aug_lock = ra.locks["2025-08"]["date"]
            vo.note = "returned late — the 02 Aug advance was still open %d days later when August was closed (%s); a reminder, not a block" % ((aug_lock - d(2025, 8, 2)).days, fdate(aug_lock))
    rr.lock_all(W, day=6)
    rr.monthly_counts(rcash, W)
    rb.lock_all(L, day=7)
    rb.monthly_counts(bcash, L, diffs={"2026-03": -R(500)})
    uc.spec_flags = ["accounting date of an approved advance request = the request date", "Brick Field quorum unreachable in-app"]

    uc.tech_notes.append(("Tenants — RR, ageing reading (⚠️ SPEC S6)", [
        "Each tenant is one party account (02 §1.2: one party, one account). A security deposit is a credit; monthly rent is a debit on the 1st; a receipt credits it. Ageing reading (⚠️ SPEC S6): receipts settle the oldest open debits first (FIFO); an unapplied credit — a deposit — offsets the next debit, so a tenant's arrears only *show* as a Dr once they exceed the deposit held. "
        "This is a modelling consequence of one-party-one-account that the owner should see: Dr Kaur's Clinic could be three months behind and still read Cr. Sharma Family hold no deposit, so their arrears are visible and age plainly. The 07 §7 chip turns amber after 30 days and red after 90."]))
    uc.tech_notes.append(("Brick Field — RB, off-app owner (⚠️ SPEC S8)", [
        "No profit distribution and no interest on capital this year: both are structural actions (02 §7.2.1) needing a quorum of owners' signed approvals, and Nirmaljeet Gill is not on the app, so no approval envelope can exist for him. The year's surplus is carried undistributed in the computed *Accumulated surplus* line; the owner should rule how an off-app owner approves (README ⚠️ SPEC S8). "
        "The Randhawa family took nothing out this year (the receiving-book side of a partner takeout is unruled — README §6); Gill's takeouts are ordinary partner postings (`Dr Partner Current · Cr money`, kind `money_out`, S2)."]))
    uc.tech_notes.append(("Family Reconciliation — 02 §6", [
        "For every pair, balance(A→B) + balance(B→A) = 0 — the only cross-book integrity check that exists or is needed (standards §5.4). The link accounts are `equity_system · link` (S12: named in plain words). 02 §6/§7.1 route business surplus through these pairs rather than through an income account, so the fund's own P&L shows only its common spending. The one-sided own-pocket case (RF-037 ↔ AF-028) is S3."]))

    def rr_section(doc, bk):
        doc.h(3, "8. Tenants — deposits, rent owed and a tenant leaving")
        doc.p("Each tenant has one account. The security deposit is a **credit** (you will give it back); the month's rent is a **debit** on the 1st; each receipt credits it. "
              "**How the age of arrears is counted:** each receipt clears the oldest unpaid rent first, and a deposit held counts against the next rent due — so a tenant's arrears show as a Dr balance only once they are more than the deposit held. "
              "Dr Kaur's Clinic could be three months behind and still show a Cr balance; Sharma Family hold no deposit, so their arrears show plainly.")
        section_party_ageing(doc, bk, [kaur, shar, mehta, sidhu])
        doc.p("Mehta Mobile Shop left on 31 Jan 2026: January's rent (%s) was entered as due, no money was received, and the ₹24,000 deposit was adjusted against it; the remaining ₹12,000 was refunded on 02 Feb 2026 (%s), closing the account at nil. "
              "Dr Kaur's Clinic's ₹36,000 deposit and Sidhu Pharmacy's ₹30,000 deposit carry into the new year as Cr balances (see the year end)." % (
                  [v.id for v in bk.sorted_vouchers() if v.date == d(2026, 1, 1) and any(a is mehta for a, _ in v.lines)][0],
                  [v.id for v in bk.sorted_vouchers() if v.date == d(2026, 2, 2)][0]))

    def rb_section(doc, bk):
        section_partners(doc, bk, [pc_fam, pc_gill], [3, 2], R(100000),
                         "No profit was shared out and no interest on capital was credited this year: both need every owner's approval, and Nirmaljeet Gill is not on the app, so his approval could not be recorded. "
                         "The year's surplus is therefore carried forward in the *Partners' funds in the business* line (see the position and the year end). "
                         "The Randhawa family took nothing out this year; Gill's takeouts are ordinary partner entries.")

    def family_recon(doc):
        doc.h(2, "Family Reconciliation — every pair of books agrees, as on %s" % fdate(FY_END))
        doc.p("Every movement between two books is entered in both. For every pair of books, what one says it is owed is exactly what the other says it owes, so the two balances add up to nil. The side is shown as the ledger shows it, with the plain words in brackets.")
        rows = []
        for b1 in uc.books.values():
            for a in b1.accounts.values():
                if a.role == "link" and b1.id == "RF":
                    b2 = uc.books[a.link_to]
                    other = b2.link_acct("RF")
                    p1, p2 = b1.balance(a), b2.balance(other)
                    s1, side1 = fmt_signed_side(p1)
                    s2, side2 = fmt_signed_side(p2)
                    w1 = "that book owes the fund" if p1 > 0 else ("the fund owes that book" if p1 < 0 else "nil")
                    w2 = "the fund owes this book" if p2 > 0 else ("this book owes the fund" if p2 < 0 else "nil")
                    groups = [g for g in uc.groups if g["a"].book in (b1, b2) and g["b"].book in (b1, b2)]
                    rows.append(["%s ↔ %s" % (b1.short.split(" — ")[0], b2.short.split(" — ")[0]), "%s: %s %s (%s)" % (a.name, s1, side1, w1), "%s: %s %s (%s)" % (other.name, s2, side2, w2),
                                 "%d" % len(groups), "**%s** ✓" % fmt(p1 + p2)])
        doc.table(["Pair", "Fund's book says", "Other book says", "Entries in the pair", "Together"], rows, ["l", "l", "l", "r", "c"])
        doc.p("Reading these balances: a Dr balance in the fund means that book owes the fund (the allowances the fund paid out; the Brick Field loan); a Cr balance in the fund means the fund owes that book (the surplus the businesses sent). "
              "Business surplus reaches the fund through these pairs, not as income of the fund, so the fund's own income and expenses show only its common spending.")
        doc.h(2, "Open advances across the family, as on %s" % fdate(FY_END))
        rows = []
        for b in uc.books.values():
            for a in b.accounts.values():
                if a.cls == "advance":
                    bal = b.balance(a)
                    rows_a = [(vo.date, p) for vo, p in b.ledger_rows(a)]
                    oldest, open_amt = fifo_ageing(rows_a, FY_END)
                    rows.append([b.short.split(" — ")[0], a.name, fmt(bal), fdate(oldest) if oldest else "—", str((FY_END - oldest).days) if oldest else "—"])
        doc.table(["Book", "Advance account", "Still held ₹", "Held since", "Days"], rows, ["l", "l", "r", "l", "r"])

    uc.sections.append(family_recon)
    return uc, d(2026, 4, 14), {"RF": A, "AF": A, "LF": L, "LW": W, "RA": A, "RR": W, "RB": L}, {"RR": [rr_section], "RB": [rb_section]}


# ----------------------------------------------------------------------------------------------
# Scenario 5 — Trust: Radha Soami Satsang Sabha
# ----------------------------------------------------------------------------------------------
def build_uc5():
    uc = UseCase("trust-radha-soami-satsang-sabha",
                 "Trust — Radha Soami Satsang Sabha",
                 "Organization (trust) book — gollak, langar, dairy, construction, two labourers on monthly wages",
                 "A satsang sabha with a monthly gollak count, sponsor donations, a langar, a small dairy run on donations, a new langar hall under construction, two labourers paid monthly wages in cash — each with his own expense head — and daily-wage labour at the big diwans, "
                 "and a sewadar who takes langar advances. The gollak is a collection box: a count is income, with a note-count sheet, a counter and a witness; it is emptied **only** by Transfer into the Cash A/c or the bank; nothing is ever paid from it. "
                 "Every trust cash count — gollak or cash — has a note-count sheet.",
                 [("Ranjeet Singh", "Secretary · admin, no entry limit · witness at every gollak count · approves the sewadar's advances and over-limit entries"),
                  ("Amritpal Singh", "Sewadar · member, entry limit ₹5,000 · counts the gollak and the cash · holds langar advances"),
                  ("Manni · Ravinder", "labourers on monthly wages, paid in cash at each month end — each has his own **expense head** (*Manni Labour A/c*, *Ravinder Labour A/c*), so the year's total paid to each shows in his statement and in the income and expenses for the year. Nothing is owed to them at any month end, so no person account is needed"),
                  ("Daily-wage labourers", "casual labour hired for the big diwans and repairs — booked to the general *Labour A/c*")])
    RS, AS = "Ranjeet Singh", "Amritpal Singh"
    b = uc.book("TR", "Radha Soami Satsang Sabha — Trust Book", "organization", "TR", members=[(RS, "admin", None, "Secretary"), (AS, "member", R(5000), "Sewadar")])
    cash = b.acct("cash", "Cash A/c", "money", subtype="cash", opening=R(22000))
    gollak = b.acct("gollak", "Gollak Cash A/c", "money", subtype="cash_collection")
    sbi = b.acct("sbi", "SBI Current A/c", "money", subtype="current", opening=R(485000))
    adv = b.acct("adv", "Advance – Amritpal Singh A/c", "advance")
    b.acct("ob", "Opening Balance / Capital A/c", "equity_system", role="opening_balance")
    adj = b.acct("adj", "Adjustments A/c", "equity_system", role="adjustments")
    don = b.acct("don", "Donation A/c", "category_income")
    ddon = b.acct("ddon", "Dairy Donation A/c", "category_income")
    cons = b.acct("cons", "Construction A/c", "category_expense", note="the langar hall building — booked as an expense")
    gen = b.acct("gen", "General Expense A/c", "category_expense")
    dexp = b.acct("dexp", "Dairy Expense A/c", "category_expense")
    fuel = b.acct("fuel", "Trust Fuel A/c", "category_expense")
    manni = b.acct("manni", "Manni Labour A/c", "category_expense", note="Manni's monthly wages")
    ravi = b.acct("ravi", "Ravinder Labour A/c", "category_expense", note="Ravinder's monthly wages")
    labour = b.acct("lab", "Labour A/c", "category_expense", note="daily-wage labour")
    langar = b.acct("langar", "Langar A/c", "category_expense")
    b.post_opening(RS)
    b.notes.append("**Construction A/c is an expense:** the langar hall's cost reduces the year's result and the Corpus instead of appearing as a thing owned — a known limit.")
    b.notes.append("The gollak: each count is entered as donation income for the full counted amount, with the note-count sheet, *counted by* and *witness*; the box is then emptied by Transfer — part into the Cash A/c the same day, the rest into the bank two days later — so the Gollak balance is always exactly what is still in the box and is nil before the next count. No expense and no advance is ever paid from it.")
    uc.tech_notes.append(("Trust — TR (02 §8.2, ⚠️ SPEC S9, S10)", [
        "⚠️ Construction A/c is an expense (02 §1.2 has no fixed-asset class; ADR 2026-10-12 §6 rules an `asset` class for a later slice): the langar hall's ₹5,50,000 reduces the year's result and the computed Corpus rather than appearing as an asset (S9).",
        "Gollak rule (02 §8.2, ADR 2026-09-03): each count posts `Dr Gollak Cash · Cr Donation` (kind `money_in`, tag `gollak_count`) for the full counted amount with the denomination sheet, *counted by* and *witness* (two different people, asserted); the box is emptied only by `transfer` into cash or bank (tag `gollak_deposit`); the generator refuses any other credit on a `cash_collection` account and any debit on it other than a count. Counts are recorded by the Secretary because the sewadar's ₹5,000 limit would flag every count (S10).",
    ]))

    sundays = [d(2025, 4, 6), d(2025, 5, 4), d(2025, 6, 1), d(2025, 7, 6), d(2025, 8, 3), d(2025, 9, 7), d(2025, 10, 5), d(2025, 11, 2), d(2025, 12, 7), d(2026, 1, 4), d(2026, 2, 1), d(2026, 3, 1)]
    counts = [R(48260), R(52410), R(44870), R(61330), R(55920), R(49780), R(72640), R(68150), R(51470), R(58930), R(47320), R(53860)]
    to_cash = [R(40000), R(42000), R(40000), R(44000), R(42000), R(40000), R(46000), R(45000), R(42000), R(44000), R(40000), R(43000)]
    lang_cash = {4: 12000, 5: 11500, 6: 12500, 7: 13000, 8: 12000, 9: 12500, 10: 16000, 11: 15000, 12: 12500, 1: 12000, 2: 11500, 3: 12500}
    lang_bank = {4: 14000, 5: 13500, 6: 14000, 7: 15000, 8: 14500, 9: 14000, 10: 19000, 11: 17500, 12: 14500, 1: 14000, 2: 13500, 3: 14500}
    for i, mk in enumerate(fy_months()):
        y, m = int(mk[:4]), int(mk[5:])
        sun = sundays[i]
        assert sun.weekday() == 6
        b.v(sun, "money_in", "Gollak opened and counted after the Sunday diwan — count recognises income for the full amount (02 §8.2); recorded by the Secretary, counted by the sewadar, witnessed", [(gollak, counts[i]), (don, -counts[i])], RS, t=1,
            tag="gollak_count", sheet={"counted_by": AS, "witness": RS, "denoms": None})
        b.v(sun, "transfer", "Part of the counted gollak cash moved into the Cash A/c for the week's langar purchases", [(cash, to_cash[i]), (gollak, -to_cash[i])], RS, t=2, tag="gollak_deposit")
        rest = counts[i] - to_cash[i]
        b.v(sun + timedelta(days=2), "transfer", "Rest of the counted gollak cash deposited into SBI — the box is now empty", [(sbi, rest), (gollak, -rest)], RS, t=1, tag="gollak_deposit")
        # wages: each labourer is paid his month's wages in cash on the month's last day — Dr {name} Labour (expense) · Cr Cash
        me = month_end(date(y, m, 1))
        mon = me.strftime("%B %Y")
        b.v(me, "money_out", "Manni's wages for %s, paid in cash" % mon, [(manni, R(9000)), (cash, -R(9000))], RS, t=3)
        b.v(me, "money_out", "Ravinder's wages for %s, paid in cash" % mon, [(ravi, R(8500)), (cash, -R(8500))], RS, t=3)
        # langar — the standards §8 split voucher: one purchase, two money accounts
        b.v(d(y, m, 10), "money_out", "Langar provisions for the month — atta, dal, ghee and vegetables: part paid in cash, part by bank transfer to the wholesaler (one voucher, three lines)",
            [(langar, R(lang_cash[m]) + R(lang_bank[m])), (cash, -R(lang_cash[m])), (sbi, -R(lang_bank[m]))], RS, tag="split")
        b.v(d(y, m, 18), "money_out", "LPG cylinders for the langar kitchen, by bank", [(langar, R(4200)), (sbi, -R(4200))], RS)
        b.v(d(y, m, 8), "money_out", "Cattle feed for the dairy, cash", [(dexp, R(4800)), (cash, -R(4800))], AS)
        b.v(d(y, m, 12), "money_out", "Diesel for the generator and the sabha's vehicle, cash", [(fuel, R(3600)), (cash, -R(3600))], AS)
        b.v(d(y, m, 15), "money_out", "Electricity bill for the sabha premises, by bank", [(gen, R(7800)), (sbi, -R(7800))], RS)
        b.v(d(y, m, 22), "money_out", "Stationery, printing and sundries, cash", [(gen, R(900)), (cash, -R(900))], AS)
    for dt, amt, who in ((d(2025, 4, 18), R(25000), "a sangat family"), (d(2025, 7, 12), R(51000), "an NRI devotee"), (d(2025, 10, 20), R(100000), "a family's bhent towards the langar hall"),
                         (d(2025, 12, 15), R(21000), "a devotee on a wedding"), (d(2026, 2, 10), R(75000), "the Sunday sangat's collective bhent for the hall")):
        b.v(dt, "money_in", "Donation received by bank transfer from %s" % who, [(sbi, amt), (don, -amt)], RS)
    b.v(d(2025, 5, 10), "money_in", "Donation for the dairy (cow feed) received in cash", [(cash, R(4100)), (ddon, -R(4100))], AS)
    b.v(d(2025, 8, 24), "money_in", "Donation for the dairy received by bank", [(sbi, R(11000)), (ddon, -R(11000))], RS)
    b.v(d(2025, 11, 30), "money_in", "Donation for the dairy received in cash", [(cash, R(4500)), (ddon, -R(4500))], AS, t=3)
    b.v(d(2026, 1, 26), "money_in", "Donation for the dairy received by bank", [(sbi, R(15000)), (ddon, -R(15000))], RS)
    b.v(d(2025, 6, 14), "money_out", "Veterinary visit and medicines for the cows, cash", [(dexp, R(2400)), (cash, -R(2400))], AS)
    # daily-wage labour at the big diwans and after the monsoon — the general Labour A/c
    for dt, amt, what in ((d(2025, 4, 12), R(4500), "cleaning and tent work for the Vaisakhi diwan"), (d(2025, 7, 20), R(3200), "clearing the drain and the roof after the monsoon rain"),
                          (d(2025, 11, 1), R(4800), "tent and cleaning work for the Gurpurab diwan"), (d(2026, 2, 8), R(3600), "setting up for the annual bhandara")):
        b.v(dt, "money_out", "Daily-wage labourers — %s, paid in cash" % what, [(labour, amt), (cash, -amt)], AS)
    for dt, amt, what in ((d(2025, 5, 20), R(180000), "foundation and plinth"), (d(2025, 7, 15), R(150000), "columns and roof slab"), (d(2025, 9, 10), R(100000), "brickwork"),
                          (d(2025, 12, 5), R(70000), "plaster and flooring"), (d(2026, 2, 20), R(50000), "doors, windows and paint")):
        b.v(dt, "money_out", "Langar hall construction — contractor's bill for %s, paid by RTGS" % what, [(cons, amt), (sbi, -amt)], RS)
    # advances to the sewadar — from the Cash A/c, never from the gollak
    b.advance_request(d(2025, 4, 8), d(2025, 4, 9), RS, AS, R(10000), "vegetables and milk for the Vaisakhi diwan langar", cash, adv)
    b.v(d(2025, 4, 14), "money_out", "Amritpal submitted the Vaisakhi langar bills against his advance", [(langar, R(9650)), (adv, -R(9650))], AS, tag="advance_spend",
        review={"approver": RS, "decided": d(2025, 4, 15), "decision": "approved", "reason": "", "limit": R(5000)})
    b.v(d(2025, 4, 15), "money_in", "Amritpal returned the unspent remainder to the Cash A/c", [(cash, R(350)), (adv, -R(350))], AS, tag="advance_return")
    b.advance_request(d(2025, 11, 3), d(2025, 11, 3), RS, AS, R(12000), "Gurpurab langar purchases", cash, adv)
    b.v(d(2025, 11, 6), "money_out", "Amritpal submitted the Gurpurab langar bills against his advance", [(langar, R(11200)), (adv, -R(11200))], AS, tag="advance_spend",
        review={"approver": RS, "decided": d(2025, 11, 7), "decision": "approved", "reason": "", "limit": R(5000)})
    b.v(d(2025, 11, 7), "money_in", "Amritpal returned the unspent remainder to the Cash A/c", [(cash, R(800)), (adv, -R(800))], AS, tag="advance_return")
    b.advance_request(d(2026, 2, 10), d(2026, 2, 11), RS, AS, R(8000), "sweets and fruit for the annual bhandara", cash, adv)
    b.v(d(2026, 2, 14), "money_out", "Amritpal submitted the bhandara bills — the whole advance accounted for", [(langar, R(8000)), (adv, -R(8000))], AS, tag="advance_spend",
        review={"approver": RS, "decided": d(2026, 2, 15), "decision": "approved", "reason": "", "limit": R(5000)})
    b.v(d(2025, 10, 22), "money_out", "Extra cattle feed bought in cash before the Gurpurab", [(dexp, R(6400)), (cash, -R(6400))], AS,
        review={"approver": RS, "decided": d(2025, 10, 23), "decision": "approved", "reason": "", "limit": R(5000)})
    b.lock_all(RS, day=6)
    b.monthly_counts(cash, AS, diffs={"2025-12": -R(100)}, sheet=True, witness=RS)
    uc.spec_flags = ["Construction expensed"]

    def gollak_section(doc, bk):
        doc.h(3, "8. Gollak and cash — counted, then emptied")
        rows = []
        for vo in bk.sorted_vouchers():
            if vo.tag == "gollak_count":
                deps = [v for v in bk.sorted_vouchers() if v.tag == "gollak_deposit" and vo.date <= v.date <= vo.date + timedelta(days=2)]
                rows.append([fdate(vo.date), vo.id, fmt(vo.amount), "<br>".join("%s %s → %s" % (v.id, fmt(v.amount), [a.name for a, p in v.lines if p > 0][0]) for v in deps),
                             fmt(bk.balance(gollak, as_of=vo.date + timedelta(days=2)))])
        doc.table(["Count (Sunday)", "Entry", "Counted = income ₹", "Emptied by Transfer", "Still in the box after"], rows, ["l", "l", "r", "l", "r"])
        doc.p("Twelve counts, twenty-four transfers, nothing paid out of the gollak. Advances to the sewadar (*Advances*) and every expense come from the Cash A/c or the bank.")

    return uc, d(2026, 4, 11), {"TR": RS}, {"TR": [gollak_section]}


# ----------------------------------------------------------------------------------------------
# Scenario 6 — Contractor / job-work: Bal Aluminium & PVC Works
# ----------------------------------------------------------------------------------------------
def build_uc6():
    uc = UseCase("contractor-bal-aluminium-pvc-works",
                 "Contractor / job-work — Bal Aluminium & PVC Works",
                 "One-owner contracting business with a site supervisor",
                 "Pradeep Bal fabricates and fits aluminium and uPVC windows and partitions. One builder pays a mobilisation advance, is billed in running bills, holds 5% retention that stays Dr and ages until it is released; "
                 "material is bought on credit, one supplier is paid in advance (so the supplier owes the business until the invoice arrives), and the site supervisor runs labour floats as advances — one float ends with ₹1,200 of lost slips written off.",
                 [("Pradeep Bal", "owner · admin, no entry limit · approves the supervisor's advances and over-limit entries"),
                  ("Jagtar Singh", "site supervisor · member, entry limit ₹5,000 · holds the labour floats as advances in his own advance account"),
                  ("Sandhu Builders", "customer: advance → running bills → retention (party)"), ("Mann Residency", "customer: one small job (party)"),
                  ("Gill Residency", "customer: one job in January (party)"), ("Alu-Tech Profiles", "supplier on credit (party)"), ("Glass Mart", "supplier paid in advance, then invoiced (party)")])
    P, J = "Pradeep Bal", "Jagtar Singh"
    b = uc.book("BA", "Bal Aluminium & PVC Works — Business Book", "business", "BA", ownership="just_me", members=[(P, "admin", None, "owner"), (J, "member", R(5000), "site supervisor")])
    scash = b.acct("scash", "Site Cash A/c", "money", subtype="cash", opening=R(8000))
    axis = b.acct("axis", "Axis Current A/c", "money", subtype="current", opening=R(270000))
    sandhu = b.acct("sandhu", "Sandhu Builders A/c", "party", note="customer — advance, running bills, retention")
    mann = b.acct("mann", "Mann Residency A/c", "party", note="customer")
    gillr = b.acct("gillr", "Gill Residency A/c", "party", note="customer")
    alu = b.acct("alu", "Alu-Tech Profiles A/c", "party", note="supplier on credit", opening=-R(42000))
    glass = b.acct("glass", "Glass Mart A/c", "party", note="supplier — advance paid, then invoiced")
    adv_j = b.acct("adv_j", "Advance – Jagtar Singh A/c", "advance")
    draw = b.acct("draw", "Drawings A/c", "equity_system", role="drawings")
    b.acct("ob", "Opening Balance / Capital A/c", "equity_system", role="opening_balance")
    adj = b.acct("adj", "Adjustments A/c", "equity_system", role="adjustments")
    cinc = b.acct("cinc", "Contract Income A/c", "category_income")
    mat = b.acct("mat", "Material Expense A/c", "category_expense")
    lab = b.acct("lab", "Labour Expense A/c", "category_expense")
    trn = b.acct("trn", "Transport Expense A/c", "category_expense")
    wrent = b.acct("wrent", "Workshop Rent Expense A/c", "category_expense")
    tools = b.acct("tools", "Tools & Consumables Expense A/c", "category_expense")
    bankch = b.acct("bankch", "Bank Charges Expense A/c", "category_expense")
    b.post_opening(P)
    b.config["peer_reviewer"] = "Pradeep Bal"
    b.plain.append("Entries over a member's limit, and advance requests, are approved by Pradeep Bal.")
    uc.tech_notes.append(("Contractor — BA (02 §7 advances, 06 §1.0, ⚠️ SPEC S1, S6)", [
        "Jagtar Singh holds role `member` (06 §1.0 — an advance holder must be a book member; `Advance – Jagtar Singh` is auto-created for him). Labour floats follow the 02 §7 flow: request `money_out` (pending until approved, S1), spends `money_out` against the advance, remainder `money_in`, write-off `adjustment` (`Dr Adjustments · Cr Advance`, approver-only).",
        "Sandhu Builders ageing reading (⚠️ SPEC S6, FIFO): each receipt settles the oldest open debits first, so by October the open ₹62,500 is the tail of the final bill (30 Sep), not three separate retentions; the 07 §7 chip turns amber after 30 days and red after 90. Glass Mart is a party driven Dr by a Money out (advance paid), then invoiced.",
    ]))

    # Sandhu Builders: advance → running bills → retention → release
    b.v(d(2025, 4, 10), "money_in", "Mobilisation advance received from Sandhu Builders by RTGS before work began (party Cr — you will give)", [(axis, R(200000)), (sandhu, -R(200000))], P)
    b.v(d(2025, 5, 31), "gave_credit", "Running bill 1 to Sandhu Builders — windows for blocks A and B", [(sandhu, R(420000)), (cinc, -R(420000))], P, t=6)
    b.v(d(2025, 6, 15), "money_in", "Sandhu Builders paid running bill 1 by RTGS: ₹4,20,000 less the ₹2,00,000 advance adjusted and 5% retention ₹21,000 held", [(axis, R(199000)), (sandhu, -R(199000))], P)
    b.v(d(2025, 7, 31), "gave_credit", "Running bill 2 to Sandhu Builders — partitions and doors, blocks C and D", [(sandhu, R(500000)), (cinc, -R(500000))], P, t=6)
    b.v(d(2025, 8, 20), "money_in", "Sandhu Builders paid running bill 2 by RTGS less 5% retention ₹25,000", [(axis, R(475000)), (sandhu, -R(475000))], P)
    b.v(d(2025, 9, 30), "gave_credit", "Final bill to Sandhu Builders — balcony glazing and snag list", [(sandhu, R(330000)), (cinc, -R(330000))], P, t=6)
    b.v(d(2025, 10, 25), "money_in", "Sandhu Builders paid the final bill by RTGS less 5% retention ₹16,500", [(axis, R(313500)), (sandhu, -R(313500))], P)
    b.v(d(2026, 3, 20), "money_in", "Sandhu Builders released the full retention ₹62,500 after the defect-liability period", [(axis, R(62500)), (sandhu, -R(62500))], P)
    # Mann Residency
    b.v(d(2025, 11, 12), "gave_credit", "Bill to Mann Residency — uPVC windows for a farmhouse", [(mann, R(85000)), (cinc, -R(85000))], P)
    b.v(d(2025, 12, 5), "money_in", "Mann Residency paid their bill by NEFT", [(axis, R(85000)), (mann, -R(85000))], P)
    b.v(d(2026, 1, 10), "gave_credit", "Bill to Gill Residency — aluminium partitions and a glass railing", [(gillr, R(120000)), (cinc, -R(120000))], P)
    b.v(d(2026, 2, 5), "money_in", "Gill Residency paid their bill by NEFT", [(axis, R(120000)), (gillr, -R(120000))], P)
    # suppliers
    b.v(d(2025, 4, 20), "money_out", "Paid Alu-Tech Profiles the opening dues by NEFT", [(alu, R(42000)), (axis, -R(42000))], P)
    for inv_dt, inv_amt, pay_dt in ((d(2025, 4, 14), R(145000), d(2025, 6, 20)), (d(2025, 6, 9), R(160000), d(2025, 8, 25)), (d(2025, 8, 5), R(95000), d(2025, 9, 10)),
                                    (d(2025, 10, 7), R(60000), d(2025, 11, 12)), (d(2026, 1, 12), R(70000), d(2026, 2, 16)), (d(2026, 3, 4), R(48000), None)):
        b.v(inv_dt, "took_credit", "Alu-Tech Profiles — aluminium sections and hardware on credit", [(mat, inv_amt), (alu, -inv_amt)], P)
        if pay_dt:
            b.v(pay_dt, "money_out", "Paid Alu-Tech Profiles' invoice by NEFT", [(alu, inv_amt), (axis, -inv_amt)], P)
    b.v(d(2025, 5, 5), "money_out", "Advance paid to Glass Mart for toughened glass before delivery (party Dr by Money out — you will get)", [(glass, R(60000)), (axis, -R(60000))], P)
    b.v(d(2025, 5, 20), "took_credit", "Glass Mart — toughened glass delivered and invoiced", [(mat, R(94000)), (glass, -R(94000))], P)
    b.v(d(2025, 5, 30), "money_out", "Paid Glass Mart the balance of their invoice by NEFT — account back to zero", [(glass, R(34000)), (axis, -R(34000))], P)
    b.v(d(2025, 11, 18), "took_credit", "Glass Mart — glass for the Mann Residency job, on credit", [(mat, R(52000)), (glass, -R(52000))], P)
    b.v(d(2025, 12, 15), "money_out", "Paid Glass Mart by NEFT", [(glass, R(52000)), (axis, -R(52000))], P)
    # labour floats (02 §7)
    floats = [(d(2025, 5, 2), d(2025, 5, 4), R(40000), "fabrication labour at the Sandhu site, weeks 1–3", [(d(2025, 5, 9), R(14000)), (d(2025, 5, 16), R(13500)), (d(2025, 5, 23), R(11200))], d(2025, 5, 26)),
              (d(2025, 7, 1), d(2025, 7, 1), R(45000), "fitting labour at the Sandhu site, July", [(d(2025, 7, 8), R(15000)), (d(2025, 7, 15), R(16000)), (d(2025, 7, 22), R(13800))], d(2025, 7, 25)),
              (d(2025, 12, 1), d(2025, 12, 2), R(30000), "labour at the Mann Residency farmhouse", [(d(2025, 12, 6), R(12000)), (d(2025, 12, 13), R(11500)), (d(2025, 12, 20), R(5300))], None)]
    for req, appr, amt, purpose, spends, ret in floats:
        b.advance_request(req, appr, P, J, amt, purpose, scash, adv_j)
        for sdt, samt in spends:
            b.v(sdt, "money_out", "Jagtar submitted the week's labour payment slips against his float (Dr Labour · Cr Advance; over his limit, so flagged and approved)", [(lab, samt), (adv_j, -samt)], J, tag="advance_spend",
                review={"approver": P, "decided": sdt + timedelta(days=1), "decision": "approved", "reason": "", "limit": R(5000)})
        if ret:
            left = amt - sum(s for _, s in spends)
            b.v(ret, "money_in", "Jagtar returned the unspent remainder of the float to Site Cash", [(scash, left), (adv_j, -left)], J, tag="advance_return")
    b.v(d(2026, 3, 31), "adjustment", "Write-off of ₹1,200 of the December float never accounted for — approver Pradeep Bal, reason: payment slips lost on site (02 §7: `Dr Adjustments · Cr Advance`, approver-only)",
        [(adj, R(1200)), (adv_j, -R(1200))], P, t=8, tag="write_off")
    # running costs
    labour_direct = {4: 18000, 6: 22000, 8: 20000, 9: 24000, 10: 19000, 11: 16000, 1: 15000, 2: 17000, 3: 21000}
    for mk in fy_months():
        y, m = int(mk[:4]), int(mk[5:])
        last = month_end(date(y, m, 1)).day
        b.v(d(y, m, 1), "transfer", "Cash drawn from Axis for site expenses", [(scash, R(68000) if m in (5, 7, 12) else R(32000)), (axis, -(R(68000) if m in (5, 7, 12) else R(32000)))], P, t=0)
        b.v(d(y, m, 2), "money_out", "Workshop rent for the month by NEFT", [(wrent, R(9000)), (axis, -R(9000))], P)
        b.v(d(y, m, 3), "money_out", "Owner's drawing for household expenses, transferred to Pradeep (ADR 2026-09-09b §3)", [(draw, R(15000)), (axis, -R(15000))], P, tag="drawings")
        tr = {4: 3200, 5: 4100, 6: 7800, 7: 4400, 8: 3900, 9: 4200, 10: 3600, 11: 4500, 12: 3300, 1: 2900, 2: 3100, 3: 3800}[m]
        b.v(d(y, m, 18), "money_out", "Tempo hire for material and crew to site, cash", [(trn, R(tr)), (scash, -R(tr))], J,
            review={"approver": P, "decided": d(2025, 6, 19), "decision": "approved", "reason": "", "limit": R(5000)} if tr > 5000 else None)
        if m in labour_direct:
            b.v(d(y, m, 24), "money_out", "Workshop labour for the month paid in cash", [(lab, R(labour_direct[m])), (scash, -R(labour_direct[m]))], P)
        if m in (4, 7, 10, 1):
            b.v(d(y, m, 12), "money_out", "Drill bits, blades, silicone and screws, by UPI", [(tools, R(6500)), (axis, -R(6500))], P)
        b.v(d(y, m, last), "money_out", "Bank charges debited by Axis", [(bankch, R(212)), (axis, -R(212))], P, t=7)
    b.lock_all(P, day=6)
    b.monthly_counts(scash, P, diffs={"2025-09": R(100)})
    uc.spec_flags = ["retention ageing under FIFO"]

    def retention_section(doc, bk):
        doc.h(3, "8. Sandhu Builders — advance, running bills, retention and how old it is")
        doc.p("Mobilisation advance ₹2,00,000 (Cr) → bill 1 ₹4,20,000 → paid less the advance and 5% retention → bills 2 and 3 likewise → the retention sits as a Dr balance until it is released on 20 Mar 2026. "
              "**How the age is counted:** each receipt clears the oldest unpaid bill first, so by October the open ₹62,500 is the tail of the final bill (30 Sep), not three separate retentions; the app marks it amber after 30 days and red after 90.")
        rows = []
        for mk in fy_months():
            y, m = int(mk[:4]), int(mk[5:])
            me = month_end(date(y, m, 1))
            rows_a = [(vo.date, p) for vo, p in bk.ledger_rows(sandhu) if vo.date <= me]
            oldest, open_amt = fifo_ageing(rows_a, me)
            bal = bk.balance(sandhu, as_of=me)
            amt, side = fmt_signed_side(bal)
            if oldest:
                days = (me - oldest).days
                chip = "> 90 days (red)" if days > 90 else ("> 30 days (amber)" if days > 30 else "current")
                rows.append([month_label(mk), "%s %s" % (amt, side), fmt(open_amt), fdate(oldest), str(days), chip])
            else:
                rows.append([month_label(mk), "%s %s" % (amt, side), "—", "—", "—", "nothing to get" if bal <= 0 else "—"])
        doc.table(["Month end", "Balance", "You will get ₹", "Owed since", "Days", "How old"], rows, ["l", "r", "r", "l", "r", "l"])
        doc.h(4, "Glass Mart — a supplier paid in advance, and the other people and shops")
        section_party_ageing(doc, bk, [glass, alu, mann, gillr])

    return uc, d(2026, 4, 10), {"BA": P}, {"BA": [retention_section]}


# ----------------------------------------------------------------------------------------------
# Scenario 7 — Farmer: Bal Agriculture
# ----------------------------------------------------------------------------------------------
def build_uc7():
    uc = UseCase("farmer-bal-agriculture",
                 "Farmer — Bal Agriculture (Amar Bal)",
                 "One-owner farm book — KCC loan account, fertiliser khata, MSP wheat, basmati through an arhtiya, milk on a ten-day cycle",
                 "Amar Bal farms wheat, basmati and a few buffaloes. The Kisan Credit Card is a **loan account** (it opens with money owed to the bank): drawdowns and repayments are Transfers, the bank's interest debits are Money out from the loan account. "
                 "Fertiliser goes on the dealer's khata, wheat is procured at MSP and paid straight into the bank, basmati is sold through an arhtiya who deducts his charges, milk goes to the dairy society on a ten-day cycle and is paid monthly, "
                 "PM-Kisan instalments arrive by DBT, and one month-end cash count comes up short.",
                 [("Amar Bal", "farmer · the only member (admin) — nothing needs a second person's approval"), ("Bhatti Khad Store", "fertiliser dealer — khata (party)"),
                  ("Garg & Co.", "arhtiya (commission agent) — gross sale on his khata, charges deducted, net paid (party)"), ("Verka Milk Society", "dairy society — a bill every ten days, paid on the 7th of the next month (party)")])
    AB = "Amar Bal"
    b = uc.book("AG", "Bal Agriculture — Farm Book", "business", "AG", ownership="just_me", members=[(AB, "admin", None, "")])
    fcash = b.acct("fcash", "Farm Cash A/c", "money", subtype="cash", opening=R(9000))
    sbi = b.acct("sbi", "SBI Savings A/c", "money", subtype="saving", opening=R(260000))
    kcc = b.acct("kcc", "SBI Kisan Credit Card A/c", "money", subtype="loan", opening=-R(240000), note="loan account")
    bhatti = b.acct("bhatti", "Bhatti Khad Store A/c", "party", note="fertiliser dealer — khata", opening=-R(18000))
    garg = b.acct("garg", "Garg & Co. (arhtiya) A/c", "party", note="commission agent")
    verka = b.acct("verka", "Verka Milk Society A/c", "party", note="dairy society", opening=R(5950))
    draw = b.acct("draw", "Drawings A/c", "equity_system", role="drawings")
    b.acct("ob", "Opening Balance / Capital A/c", "equity_system", role="opening_balance")
    adj = b.acct("adj", "Adjustments A/c", "equity_system", role="adjustments")
    crop = b.acct("crop", "Crop Sale Income A/c", "category_income")
    milk = b.acct("milk", "Milk Sale Income A/c", "category_income")
    govt = b.acct("govt", "Government Support Income A/c (PM-Kisan)", "category_income")
    fert = b.acct("fert", "Seed & Fertiliser Expense A/c", "category_expense")
    dsl = b.acct("dsl", "Diesel & Machinery Expense A/c", "category_expense")
    lab = b.acct("lab", "Labour Expense A/c", "category_expense")
    rep = b.acct("rep", "Machinery Repair Expense A/c", "category_expense")
    feed = b.acct("feed", "Cattle Feed Expense A/c", "category_expense")
    kint = b.acct("kint", "Interest on KCC Expense A/c", "category_expense")
    achg = b.acct("achg", "Arhtiya Charges Expense A/c", "category_expense")
    twell = b.acct("twell", "Tube-well Electricity Expense A/c", "category_expense")
    b.post_opening(AB)

    b.v(d(2025, 4, 25), "money_in", "Wheat 160 qtl procured at MSP ₹2,425 — payment credited direct to the SBI account by the procurement agency", [(sbi, R(388000)), (crop, -R(388000))], AB)
    b.v(d(2025, 5, 5), "transfer", "KCC repaid in full after the wheat payment (Transfer: Dr loan account · Cr savings)", [(kcc, R(240000)), (sbi, -R(240000))], AB, t=1)
    b.v(d(2025, 5, 8), "money_out", "Paid Bhatti Khad Store the rabi khata by UPI", [(bhatti, R(18000)), (sbi, -R(18000))], AB)
    b.v(d(2025, 6, 15), "took_credit", "Bhatti Khad Store — urea and DAP for basmati nursery and transplanting, on khata", [(fert, R(38000)), (bhatti, -R(38000))], AB)
    b.v(d(2025, 7, 10), "transfer", "KCC drawn for transplanting and inputs (Transfer: Dr savings · Cr loan account)", [(sbi, R(180000)), (kcc, -R(180000))], AB, t=1)
    b.v(d(2025, 7, 20), "took_credit", "Bhatti Khad Store — zinc, pesticide and weedicide on khata", [(fert, R(22000)), (bhatti, -R(22000))], AB)
    b.v(d(2025, 11, 5), "took_credit", "Bhatti Khad Store — wheat seed and DAP on khata", [(fert, R(41000)), (bhatti, -R(41000))], AB)
    b.v(d(2025, 11, 28), "money_out", "Paid Bhatti Khad Store the kharif khata by NEFT", [(bhatti, R(60000)), (sbi, -R(60000))], AB)
    b.v(d(2026, 2, 18), "money_out", "Part payment to Bhatti Khad Store by UPI", [(bhatti, R(20000)), (sbi, -R(20000))], AB)
    for dt, amt in ((d(2025, 6, 30), R(1604, 38)), (d(2025, 9, 30), R(2853, 70)), (d(2025, 12, 31), R(3172, 60)), (d(2026, 3, 31), R(912, 33))):
        b.v(dt, "money_out", "Interest debited by SBI on the Kisan Credit Card account (Money out from the loan account)", [(kint, amt), (kcc, -amt)], AB, t=6)
    b.v(d(2025, 11, 10), "gave_credit", "Basmati 155 qtl sold through Garg & Co. at ₹4,000 — gross sale on the arhtiya's khata", [(garg, R(620000)), (crop, -R(620000))], AB)
    b.v(d(2025, 11, 12), "took_credit", "Garg & Co. — commission and mandi charges deducted (2.5%)", [(achg, R(15500)), (garg, -R(15500))], AB)
    b.v(d(2025, 11, 18), "money_in", "Garg & Co. paid the net basmati proceeds by RTGS — khata settled", [(sbi, R(604500)), (garg, -R(604500))], AB)
    b.v(d(2025, 12, 15), "transfer", "KCC repaid after the basmati payment", [(kcc, R(180000)), (sbi, -R(180000))], AB, t=1)
    b.v(d(2026, 3, 5), "transfer", "KCC drawn for the wheat harvest — combine hire and labour", [(sbi, R(120000)), (kcc, -R(120000))], AB, t=1)
    for dt in (d(2025, 8, 2), d(2025, 11, 19), d(2026, 2, 24)):
        b.v(dt, "money_in", "PM-Kisan instalment ₹2,000 credited by DBT", [(sbi, R(2000)), (govt, -R(2000))], AB)
    # milk on a ten-day cycle, paid monthly on the 7th
    base = {4: 5600, 5: 5300, 6: 5100, 7: 5400, 8: 5800, 9: 6100, 10: 6400, 11: 6600, 12: 6900, 1: 6700, 2: 6200, 3: 5900}
    prev_month_total = R(5950)
    idx = 0
    for mk in fy_months():
        y, m = int(mk[:4]), int(mk[5:])
        b.v(d(y, m, 7), "money_in", "Verka Milk Society paid last month's three milk cycles by NEFT", [(sbi, prev_month_total), (verka, -prev_month_total)], AB, t=2)
        tot = 0
        for cyc_end, label in ((d(y, m, 10), "1st–10th"), (d(y, m, 20), "11th–20th"), (month_end(date(y, m, 1)), "21st to month end")):
            idx += 1
            amt = R(base[m] + (idx * 137) % 900, (idx % 4) * 25)
            tot += amt
            b.v(cyc_end, "gave_credit", "Milk supplied to Verka Milk Society, %s — society's fat-based bill accrued" % label, [(verka, amt), (milk, -amt)], AB, t=5)
        prev_month_total = tot
        # cash and running costs
        wd = R({4: 42000, 5: 28000, 6: 52000, 7: 48000, 8: 30000, 9: 30000, 10: 45000, 11: 42000, 12: 29000, 1: 28000, 2: 35000, 3: 36000}[m])
        b.v(d(y, m, 2), "transfer", "Cash drawn from SBI for the month", [(fcash, wd), (sbi, -wd)], AB, t=0)
        b.v(d(y, m, 4), "money_out", "Household drawing for the month in cash (not a farm expense, ADR 2026-09-09b §3)", [(draw, R(12000)), (fcash, -R(12000))], AB, tag="drawings")
        dz = {4: 9800, 5: 6200, 6: 11500, 7: 12400, 8: 8100, 9: 7600, 10: 10900, 11: 11800, 12: 7200, 1: 6400, 2: 6900, 3: 10200}[m]
        b.v(d(y, m, 9), "money_out", "Diesel for tractor and tube-well, cash", [(dsl, R(dz)), (fcash, -R(dz))], AB)
        lb = {4: 14000, 5: 4000, 6: 22000, 7: 18000, 8: 4000, 9: 4000, 10: 16000, 11: 12000, 12: 4000, 1: 4000, 2: 4000, 3: 8000}[m]
        b.v(d(y, m, 16), "money_out", "Farm labour for the month paid in cash", [(lab, R(lb)), (fcash, -R(lb))], AB)
        b.v(d(y, m, 14), "money_out", "Cattle feed (khal and chokar), cash", [(feed, R(5400)), (fcash, -R(5400))], AB)
        tw = {4: 1900, 5: 2400, 6: 2900, 7: 2800, 8: 2600, 9: 2300, 10: 1800, 11: 1500, 12: 1400, 1: 1500, 2: 1400, 3: 1700}[m]
        b.v(d(y, m, 19), "money_out", "Tube-well electricity bill by net banking", [(twell, R(tw)), (sbi, -R(tw))], AB)
    b.v(d(2025, 9, 23), "money_out", "Tractor hydraulic pump repair, workshop paid by NEFT", [(rep, R(9800)), (sbi, -R(9800))], AB)
    b.v(d(2026, 2, 11), "money_out", "Tube-well motor rewinding, cash", [(rep, R(6200)), (fcash, -R(6200))], AB)
    b.lock_all(AB, day=5)
    b.monthly_counts(fcash, AB, diffs={"2025-07": -R(300)})
    uc.spec_flags = []

    uc.tech_notes.append(("Farm — AG, the KCC as a loan account", [
        "The KCC is `money`, subtype `loan` (02 §1.2): a Cr balance is what the farm owes the bank; placement is by sign. Drawdowns and repayments are `transfer` between two money accounts (02 §2 verb 5); the bank's interest debits are `money_out` from the loan account into *Interest on KCC Expense*. No EMI splitting arises — the bank debits interest separately. Sood (interest an arhtiya charges on an advance) is not posted anywhere in this set — open roadmap row (docs/10-roadmap.md, *Interest on hand loans*).",
    ]))

    def kcc_section(doc, bk):
        doc.h(3, "8. The Kisan Credit Card as a loan account")
        doc.p("The KCC is a loan account: a Cr balance is what the farm owes the bank. Money drawn and money repaid are Transfers between the loan account and the savings account; the interest the bank charges is Money out from the loan account to *Interest on KCC Expense*. The bank charges interest separately, which is how a KCC works.")
        rows = []
        for vo, p in bk.ledger_rows(kcc):
            if vo.tag == "opening":
                continue
            rows.append([fdate(vo.date), vo.id, KIND_LABEL[vo.kind], plain_narr(vo.narr), fmt(p) if p > 0 else "—", fmt(-p) if p < 0 else "—"])
        doc.table(["Date", "Entry", "Type", "What happened", "Repaid to the bank (Dr) ₹", "Drawn or charged by the bank (Cr) ₹"], rows, ["l", "l", "l", "l", "r", "r"])
        doc.h(4, "The milk society, the arhtiya and the khad store")
        section_party_ageing(doc, bk, [verka, garg, bhatti])
        doc.p("Sood (interest an arhtiya may charge on an advance) is **not entered** anywhere in this book; Garg & Co. advanced nothing here, so the question does not arise.")

    return uc, d(2026, 4, 9), {"AG": AB}, {"AG": [kcc_section]}


# ----------------------------------------------------------------------------------------------
# README — reading guide, class mapping, coverage, ⚠️ SPEC readings, limits, defects in the old set
# ----------------------------------------------------------------------------------------------
def ids(uc, pred, cap=8):
    out = [vo.id for b in uc.books.values() for vo in b.sorted_vouchers() if pred(vo)]
    if len(out) > cap:
        return ", ".join(out[:cap]) + " … (+%d more)" % (len(out) - cap)
    return ", ".join(out) if out else "—"


def count(uc, pred):
    return sum(1 for b in uc.books.values() for vo in b.vouchers if pred(vo))


def has_acct(uc, pred):
    return any(pred(a) for b in uc.books.values() for a in b.accounts.values())


def kinds_row(uc):
    return " · ".join("%s %d" % (k, count(uc, lambda v, k=k: v.kind == k)) for k in KINDS)


def aged_advances(uc):
    """Advance accounts open longer than ADVANCE_WARN_DAYS at a month end (warn-only at the lock, 02 §7)."""
    out = []
    for b in uc.books.values():
        for a in b.accounts.values():
            if a.cls != "advance":
                continue
            for mk in fy_months():
                y, m = int(mk[:4]), int(mk[5:])
                me = month_end(date(y, m, 1))
                oldest, open_amt = fifo_ageing([(vo.date, p) for vo, p in b.ledger_rows(a) if vo.date <= me], me)
                if oldest and (me - oldest).days > ADVANCE_WARN_DAYS:
                    out.append("%s %s at %s (%d days, %s open)" % (b.id, a.name, month_label(mk), (me - oldest).days, rs(open_amt)))
    return "; ".join(out) if out else "—"


def zero_crossing_parties(uc):
    """Parties whose running balance (opening included) sits Dr at one time and Cr at another (standards §7)."""
    out = []
    for b in uc.books.values():
        for a in b.accounts.values():
            if a.cls != "party":
                continue
            run = 0
            seen_dr = seen_cr = False
            for vo, p in b.ledger_rows(a):
                run += p
                seen_dr = seen_dr or run > 0
                seen_cr = seen_cr or run < 0
            if seen_dr and seen_cr:
                out.append("%s (%s)" % (a.name, b.id))
    return ", ".join(out) if out else "—"


def pairs_text(uc):
    if not uc.groups:
        return "—"
    one_sided = ids(uc, lambda v: v.tag == "interbook" and v.kind != "transfer")
    return "%d pairs" % len(uc.groups) + (("; one-sided (payee half `money_out`): " + one_sided) if one_sided != "—" else "")


# Which rule each scenario exercises — (rule, where in the set, fn(uc) → voucher ids or "—"). One table, used by
# the README (every use case) and by each technical companion (that use case only).
RULES = [
    ("02 §2 — all six verbs (`kind`) present", "every file", kinds_row),
    ("02 §3 — over-limit entry posts instantly with a review flag, approved by a *different* member (02 §7.2 item 1)", "shop, partnership, family, trust, contractor",
     lambda uc: ids(uc, lambda v: v.review and v.review["decision"] == "approved", cap=4)),
    ("02 §3 — rejection with the auto-posted mirror reversal (`refs.reverses`), reason recorded, both entries kept", "family fund",
     lambda uc: "—" if not count(uc, lambda v: v.review and v.review["decision"] == "rejected") else
     ids(uc, lambda v: v.review and v.review["decision"] == "rejected") + " → " + ids(uc, lambda v: v.tag == "rejection_reversal")),
    ("02 §4 / ADR 2026-09-09d §4 — one opening adjustment per account against Opening Balance / Capital, dated at the start; Opening Balance / Capital absorbs the difference", "every book",
     lambda uc: "%d openings, e.g. %s" % (count(uc, lambda v: v.tag == "opening"), ids(uc, lambda v: v.tag == "opening", cap=3))),
    ("ADR 2026-09-09c §4 — each partner's opening contribution credited to their Partner Current A/c (`Dr Opening Balance / Capital · Cr Partner Current`), OB / Capital only the difference", "partnership, brick field",
     lambda uc: ids(uc, lambda v: v.tag == "opening" and any(a.cls == "partner" for a, _ in v.lines))),
    ("02 §5 — amend in an open period (`refs.amends`, original struck through, head counts)", "shop",
     lambda uc: "—" if not count(uc, lambda v: "amends" in v.refs) else ids(uc, lambda v: "amends" in v.refs) + " amends " + ids(uc, lambda v: v.amended_by is not None)),
    ("02 §5 — locked-month correction: mirror reversal dated in the open period + corrected re-entry", "business (Jasvinder Technologies)",
     lambda uc: "—" if not count(uc, lambda v: v.tag == "locked_fix") else ids(uc, lambda v: v.tag == "locked_fix") + " reverses " +
     ids(uc, lambda v: v.reversed_by is not None and not v.review) + "; re-entry " + ids(uc, lambda v: bool(v.note) and v.note.startswith("corrects"))),
    ("02 §6 — inter-book pairs (`refs.transfer_group`), incl. the one-sided own-pocket case (payer half `transfer`, payee half `money_out` with the link as its credit) and a loan between books; Family Reconciliation nets every pair to 0",
     "individual (owner loan), family (47 pairs)", pairs_text),
    ("02 §7 — advance request `pending` → approved (excluded from balances until approval), spends, remainder returned", "family (Agriculture), trust, contractor",
     lambda uc: ids(uc, lambda v: v.pending is not None, cap=3)),
    ("02 §7 — ageing = days since the oldest unsettled debit; warn-only at the lock", "Agriculture (Aug advance returned 22 Sep), contractor (Dec float)", aged_advances),
    ("02 §7 — write-off `Dr Adjustments · Cr Advance`, approver-only, reason", "contractor", lambda uc: ids(uc, lambda v: v.tag == "write_off")),
    ("02 §7.1 — own-pocket payment (`Dr Expense · Cr Partner Current`), takeouts, one appropriation entry with `interest`-tagged lines (Actual/365, half-up to the paisa) and `share`-tagged lines (paise remainder rule), a partner in Dr, settlement-capacity sentence, drift card, three routes",
     "partnership, brick field",
     lambda uc: "—" if not has_acct(uc, lambda a: a.cls == "partner") else "own pocket %s; takeouts %s; appropriation %s" % (
         ids(uc, lambda v: v.tag == "own_pocket"), ids(uc, lambda v: v.tag == "takeout", cap=3), ids(uc, lambda v: v.tag == "distribution"))),
    ("02 §7.2.1 — structural records (interest setting, distribution) with every owner's approval; `structural_quorum` chosen at creation; an off-app owner",
     "partnership (recorded), brick field (quorum unreachable — flagged)",
     lambda uc: ", ".join("%s book header (%d record%s)" % (b.id, len(b.structural_approvals), "" if len(b.structural_approvals) == 1 else "s")
                          for b in uc.books.values() if b.structural_approvals or "structural_quorum" in b.config) or "—"),
    ("02 §8 — month locks with cash counts; differences posted to Adjustments", "every book; differences:", lambda uc: ids(uc, lambda v: v.tag == "count_diff", cap=10)),
    ("02 §8.1 — year close: certified vector, net result as one line, computed surplus/Corpus, next-FY b/f", "every book", lambda uc: "every book (%d) — the *Year end* section" % len(uc.books)),
    ("02 §8.2 — gollak count = income with denomination sheet, counter and witness; emptied only by Transfer to cash/bank; nothing paid from it; denomination sheet on every trust cash count", "trust",
     lambda uc: "—" if not count(uc, lambda v: v.tag == "gollak_count") else "counts %s; deposits %d transfers" % (ids(uc, lambda v: v.tag == "gollak_count", cap=4), count(uc, lambda v: v.tag == "gollak_deposit"))),
    ("02 §9 — a `pending` request contributes nothing until approved; no cash, collection, savings or current account negative after any posting (asserted)", "Agriculture (June request 10→12 Jun); every book",
     lambda uc: ids(uc, lambda v: v.pending and v.pending["requested"] != v.pending["approved_on"])),
    ("02 §10 — statement import: matched lines (no posting), one confirmed-new line, one Suspense line cleared before the lock", "shop",
     lambda uc: "—" if not count(uc, lambda v: v.tag == "suspense_in") else ids(uc, lambda v: v.tag == "suspense_in") + " → " + ids(uc, lambda v: v.tag == "suspense_clear")),
    ("ADR 2026-09-13 §4 — capital introduced is Money in · Cr Opening Balance / Capital", "business (Jasvinder Technologies)", lambda uc: ids(uc, lambda v: v.tag == "capital_in")),
    ("ADR 2026-09-09b §3 — owner takeout is `Dr Drawings · Cr money`, never an expense", "every one-owner business",
     lambda uc: ("%d takeouts: " % count(uc, lambda v: v.tag == "drawings")) + ids(uc, lambda v: v.tag == "drawings", cap=3) if count(uc, lambda v: v.tag == "drawings") else "—"),
    ("standards §7 — zero-crossing parties (placement by sign, both directions)", "Kaur Exports (JT), Dhillon Plumbing (SS), Sandhu Builders and Glass Mart (BA), Sodhi & Sons (RA), Mehta Mobile Shop (RR)", zero_crossing_parties),
    ("standards §8 — multi-line split voucher (one purchase, two money accounts)", "trust", lambda uc: ids(uc, lambda v: v.tag == "split", cap=3)),
    ("money subtypes — CC bill paid as a Transfer; KCC `loan` with drawdown/repayment as Transfers and bank-debited interest as Money out from the loan account", "individual (CC), Agriculture and farmer (KCC)",
     lambda uc: ids(uc, lambda v: any(a.subtype in ("CC", "loan") for a, _ in v.lines) and v.tag != "opening", cap=4)),
]


# ⚠️ SPEC — readings taken where 02 and the ADRs are silent. One list: the README prints all twelve, each technical
# companion prints the ones its scenario exercises (`spec_applies`).
SPEC_READINGS = [
    ("S1", "**S1 · kind of the advance postings.** 02 §7 prescribes the postings (`Dr Advance · Cr money`; `Dr expense · Cr Advance`; `Dr money · Cr Advance`; write-off `Dr Adjustments · Cr Advance`) and ADR 2026-09-05e §6 calls the advance shape already reader-checked, but neither names the `kind` (02 §1.3 lists six). This set labels by nearest shape — request and spend `money_out`, return `money_in`, write-off `adjustment` — which is also how the engine's `checkShape` admits them."),
    ("S2", "**S2 · kind of the partner postings.** 02 §7.1's three events name postings, not kinds: own-pocket `Dr Expense · Cr Partner Current` is `took_credit`, takeout `Dr Partner Current · Cr money` is `money_out` (the engine treats `partner` as party-like), and the appropriation `Dr Profit Distributed · Cr each Partner Current` is one `adjustment` (exactly one `equity_system` counter-account, rule 7)."),
    ("S3", "**S3 · kinds of the one-sided inter-book case.** 02 §6 calls *a member pays a family expense from his own pocket* the same mechanism as a transfer and ADR 2026-09-05e §6 admits *the §6 pair shapes*. The payer half `Dr link · Cr Cash` is a `transfer`; the payee half `Dr Expense · Cr link` is read as a **`money_out`** whose credit is the link — the engine's `money_out` arm admits a Due credit and its `transfer` arm admits only money and Due. Both halves share one `transfer_group`."),
    ("S4", "**S4 · Suspense clearing.** 02 §10 names the Suspense posting but not the clearing. This set clears with one guided adjustment `Dr Suspense · Cr {counterpart}` carrying the same `refs.import_line` (shape-legal under rule 7). The alternative — a `refs.reverses` mirror plus a fresh Money in — is also legal; owner to choose."),
    ("S5", "**S5 · accounting date of an approved advance request.** 02 §7 posts the request *on approval* and 02 §1.4 rule 4 makes entries immutable; this set keeps the request date as the accounting date (RA June: requested 10 Jun, approved 12 Jun, excluded from every balance in between, counted from 10 Jun once approved). If the owner prefers the approval date, only the ledger row's date moves."),
    ("S6", "**S6 · ageing method.** 02 §7 defines advance ageing as *days since the oldest unsettled debit*; 07 §7 gives party chips (> 30 amber, > 90 red) without a matching rule. This set reads both as **FIFO**: credits settle the oldest open debits first and an unapplied credit (deposit, prepayment) offsets the next debit. Consequence shown in Real Estate: a tenant's arrears only *show* as Dr once they exceed the deposit held."),
    ("S7", "**S7 · the interest-on-capital setting.** 02 §7.1 leaves the charging of a debit balance ⚠️ — *charged at the same rate unless the setting says otherwise* (ADR 2026-09-05e Open 2). The Bal Fabricators setting says **credit balances only**, chosen deliberately so that Harjeet's debit days neither earn nor are charged; the generator recomputes every interest figure from the daily balances under that setting and refuses any other. A different setting is a different, equally legal, example."),
    ("S8", "**S8 · an owner who is not on the app.** The Brick Field's `structural_quorum` is `all_owners` (chosen at creation, 02 §7.2.1); Nirmaljeet Gill holds no device, so no signed approval can exist for him and no structural action — profit distribution, interest, ratio change — can complete in-app. This set leaves the surplus undistributed and carried; the owner must rule how an off-app owner approves (a paper mandate recorded by an admin? a required invite?)."),
    ("S9", "**S9 · construction is expensed.** 02 §1.2 has no fixed-asset class, so the langar hall's ₹5,50,000 reduces the year's result and the computed Corpus. Flagged, not solved (ADR 2026-10-12 §6 rules an `asset` class for a later build slice)."),
    ("S10", "**S10 · entry limits apply to every entry, counts included.** 02 §3 flags any entry over the author's limit and 02 §7 says advance spends are *approved per limits*; a gollak count recorded by the sewadar (limit ₹5,000) would be flagged every month, so the Secretary records counts (the sheet still names the counter and the witness) and the sewadar's over-limit spends are flagged and approved the next day."),
    ("S11", "**S11 · count timing.** Cash is counted at close of business on the month's last day, any difference is dated that day, and the lock follows a few days later — so the certified month ends on counted cash (02 §8 step 1). A count performed on the lock day itself would date the adjustment in the next month; both are consistent with 02 §8."),
    ("S12", "**S12 · link account naming.** 02 §6 names the engine's accounts *Due to/from {Book}*; the owner ruled plain labels for this set. The class is unchanged (`equity_system`, role link) and the name carries the other book and its type, e.g. *Randhawa Family Fund (joint family book)*."),
]


def spec_applies(uc):
    """The ⚠️ SPEC readings a use case exercises — derived from its data (S6, S9, S10 from the scenario shape)."""
    out = []
    if has_acct(uc, lambda a: a.cls == "advance"):
        out.append("S1")
    if has_acct(uc, lambda a: a.cls == "partner"):
        out.append("S2")
    if any(g["a"].kind != g["b"].kind for g in uc.groups):
        out.append("S3")
    if count(uc, lambda v: v.tag == "suspense_clear"):
        out.append("S4")
    if count(uc, lambda v: v.pending and v.pending["requested"] != v.pending["approved_on"]):
        out.append("S5")
    if has_acct(uc, lambda a: a.cls == "advance") or uc.slug in ("joint-family-randhawa", "contractor-bal-aluminium-pvc-works", "farmer-bal-agriculture"):
        out.append("S6")   # an advance or a party ageing table is printed
    if any("interest_on_capital" in b.config for b in uc.books.values()):
        out.append("S7")
    if any("not on the app" in str(b.config.get("structural_quorum", "")) for b in uc.books.values()):
        out.append("S8")
    if any(b.type == "organization" for b in uc.books.values()):
        out += ["S9", "S10"]
    out.append("S11")
    if has_acct(uc, lambda a: a.role == "link"):
        out.append("S12")
    return out


ASSERTS_TEXT = ("every voucher sums to zero with ≥ 2 non-zero lines; every account belongs to its book; the class-shape of every `kind` (02 §1.4 rule 7 as the engine's `checkShape` reads it, incl. the advance, partner and §6 shapes); every trial balance balances; every inter-book pair has two halves of the same date and amount whose link lines mirror, and every pair nets to 0; Opening Balance / Capital exactly once per book; Drawings only in a one-owner business book and partner accounts only in a shared one; capital introduced is `Dr money · Cr Opening Balance / Capital` and never income (ADR 2026-09-13 §4); an owner takeout is `Dr Drawings · Cr money` and never an expense (ADR 2026-09-09b §3); nothing leaves a collection box except a Transfer to cash or bank and nothing enters it except a count, whose *counted by* and *witness* are two different people (02 §8.2); nothing is dated before the start and nothing is authored into a locked month or before its own accounting date; an entry over its author's limit carries a review flag decided by a different admin/head before the lock, a rejected one has its mirror reversal, and only an admin or head amends or reverses (06 §1.0); an advance request is approved by a different admin/head before the lock and no advance account goes negative; Suspense is 0, no flag is open and no advance is pending as of every lock date; every cash account is counted in every month before its lock (trust: with a denomination sheet that sums to the count); the appropriation is one entry whose `interest` lines equal an independent recomputation (half-up to the paisa, credit days only, Actual/365) and whose `share` lines equal the floor-by-weight split with the remainder on the largest weight (ties to the earliest-created account); the closing vector carries only balance-sheet classes and sums to zero with the net line; no cash, collection, savings or current account is negative after any posting; and the printed report carries no engine class, verb id, rule or ADR reference, ⚠️ note, backtick or generator check (`plain_lint`, ADR 2026-10-12 §2).")

MUTATION_TEXT = ("`python3 build.py --self-test` rebuilds the set in memory, changes one guarded posting at a time (the remainder moved to the wrong partner; an interest line a paisa short; an interest figure not from credit-day balances; capital introduced credited to income; an owner takeout debited to an expense; a gollak count whose witness is the counter; a Transfer into the gollak; an operator amending; an entry authored before its date; the pocket-expense half labelled `transfer`; a Suspense line left uncleared; cash driven negative) and reports whether the validator refused each one. All refusals are expected; a *not refused* line is a defect in the generator.")


def voucher_tech_cell(vo):
    bits = []
    if vo.pending:
        bits.append("status pending→posted: requested %s · approved %s by %s" % (vo.pending["requested"].isoformat(), vo.pending["approved_on"].isoformat(), vo.pending["approver"]))
    if vo.review:
        rv = vo.review
        bits.append("review: %s by %s on %s (limit %s)%s" % (rv["decision"], rv["approver"], rv["decided"].isoformat(), rs(rv["limit"]), (" — " + rv["reason"]) if rv.get("reason") else ""))
    for k in ("amends", "reverses"):
        if k in vo.refs:
            bits.append("refs.%s = %s" % (k, vo.refs[k].id))
    if "transfer_group" in vo.refs:
        bits.append("refs.transfer_group = %s" % vo.refs["transfer_group"])
    if vo.import_line:
        bits.append("refs.import_line = %s" % vo.import_line)
    if vo.sheet:
        bits.append("count sheet: counted by %s · witness %s" % (vo.sheet["counted_by"], vo.sheet["witness"]))
    if vo.amended_by:
        bits.append("amended_by %s (not a head)" % vo.amended_by.id)
    if vo.reversed_by:
        bits.append("reversed_by %s" % vo.reversed_by.id)
    if vo.note:
        bits.append("note: " + vo.note)
    return " · ".join(bits) if bits else "—"


def render_tech(uc, tb_totals, n_checks):
    """The technical companion <slug>.tech.md — everything ADR 2026-10-12 §2 keeps off the printed report."""
    doc = Doc("%s — technical companion (%s)" % (uc.title, FY_LABEL))
    doc.p("**Status: ⚠️ PROVISIONAL — pending bookkeeper sign-off.** Generated by `build.py` beside the printed report `%s.md` (`.html`, `.pdf`); never edited by hand. "
          "The printed report carries the user's plain words with the true side in brackets (ADR 2026-10-12 §2, ADR 2026-10-10b §4); this file carries the engine view of the **same entries and the same figures**: "
          "classes, kinds, refs, review and advance states, the rules the scenario exercises, the ⚠️ SPEC readings that apply, and the checks. `fixtures.json` is the machine copy; `README.md` is the reading guide." % uc.slug)
    doc.p("Entity: %s. Books: %s." % (uc.entity, "; ".join("`%s` %s (%d vouchers, TB %s)" % (b.id, b.name, len(b.vouchers), rs(tb_totals[b.id])) for b in uc.books.values())))
    # 1. books
    doc.h(2, "1. Books, members and settings")
    rows = []
    for b in uc.books.values():
        mem = "<br>".join("%s — %s%s · %s" % (m[0], m[1], (" (%s)" % m[3]) if len(m) > 3 and m[3] else "", ("limit " + rs(m[2])) if m[2] is not None else "no limit") for m in b.members)
        cfg = "<br>".join("`%s`: %s" % (k, v) for k, v in b.config.items() if isinstance(v, str)) or "—"
        sa = "<br>".join("%s — %s · %s" % (fdate(s["date"]), s["what"], s["approvals"]) for s in b.structural_approvals) or "—"
        yc = "%s by %s" % (fdate(b.year_close["date"]), b.year_close["by"]) if b.year_close else "—"
        rows.append(["`%s`" % b.id, b.name, "`%s`%s" % (b.type, (" · `%s`" % b.ownership) if b.ownership else ""), fdate(b.start), mem, cfg, sa, yc])
    doc.table(["Book", "Name", "Type · ownership", "Start", "Members (role · limit)", "`config`", "Structural records (02 §7.2.1)", "Year closed"], rows, ["l", "l", "l", "l", "l", "l", "l", "l"])
    # 2. accounts
    doc.h(2, "2. Accounts — engine class, subtype, role and standard type (02 §1.2; ADR 2026-10-12 §6 catalogue columns)")
    for b in uc.books.values():
        doc.h(3, "%s — %s" % (b.id, b.name))
        rows = []
        for i, a in enumerate(b.accounts.values(), 1):
            sub = a.subtype or (("role " + a.role) if a.role else "—")
            link = b.uc.books[a.link_to].name if a.role == "link" else "—"
            st, tt = a.std_type()
            rows.append([str(i), "`%s`" % a.id, a.name, "`%s`" % a.cls, "`%s`" % sub, link, st, tt, a.natural(), str(a.opening), a.plain_type(), a.label()])
        doc.table(["#", "Id", "Account", "Engine class", "Subtype / role", "Link to", "Standard type", "Traditional type", "Natural balance", "Opening paise (+ = Dr)", "Printed type word", "Bookkeeper label"], rows,
                  ["r", "l", "l", "l", "l", "l", "l", "l", "l", "r", "l", "l"])
    # 3. vouchers
    doc.h(2, "3. Vouchers — `kind`, lines, refs and states (02 §1.3, §1.4 rule 7)")
    doc.p("Lines are signed paise, + = Dr, − = Cr, on the account id of §2; a tag in brackets is the appropriation line tag (`interest` / `share`). *Authored* is shown only when it differs from the accounting date. The printed day book shows the same entries as *Money in / Money out / Gave on credit / Took on credit / Transfer / Correction / adjustment* and prints the narration without its rule citation.")
    for b in uc.books.values():
        doc.h(3, "%s — %s (%d vouchers)" % (b.id, b.name, len(b.vouchers)))
        rows = []
        for vo in b.sorted_vouchers():
            lines = " · ".join("%s%s %s%s" % ("+" if p > 0 else "−", a.id, indian(abs(p)), (" (%s)" % t) if t else "") for a, p, t in vo.tagged_lines())
            rows.append([vo.id, fdate(vo.date), fdate(vo.authored) if vo.authored != vo.date else "—", "`%s`" % vo.kind, ("`%s`" % vo.tag) if vo.tag else "—", lines, voucher_tech_cell(vo), vo.narr])
        doc.table(["Id", "Date", "Authored", "`kind`", "Tag", "Lines (paise)", "Refs · states", "Narration (as stored)"], rows, ["n", "n", "n", "l", "l", "l", "l", "l"])
    # 4. rules
    doc.h(2, "4. Which rule this scenario exercises (voucher ids)")
    rows = [[rule, text] for rule, where, fn in RULES for text in [fn(uc)] if text != "—"]
    doc.table(["Rule", "Voucher ids in this use case"], rows, ["l", "l"])
    # 5. spec readings
    applies = spec_applies(uc)
    doc.h(2, "5. ⚠️ SPEC readings that apply here (README §5 has all twelve)")
    doc.ul([text for sid, text in SPEC_READINGS if sid in applies])
    if uc.spec_flags:
        doc.p("Readings this scenario was built to exercise: " + "; ".join(uc.spec_flags) + ".")
    # 6. developer notes
    doc.h(2, "6. Developer notes kept off the printed report")
    doc.ul(["**Conventions.** Amounts in ₹ with paise shown only when non-zero; the engine holds integer paise. Ledgers follow the standards §2 layout — Date · Particulars (To … on the debit side, By … on the credit side) · contextual Dr · contextual Cr · Balance · Side on every row — and, being printed ledgers, end *Closing balance c/d · Total · Opening balance b/d* with no separate c/f row (ADR 2026-09-24b §9). Income and expense ledgers carry no b/f row and are not carried forward (ADR 2026-09-05e §2). The printed column headers are the plain words with the true side in brackets (ADR 2026-10-10b §4); the engine's posting logic never bends to the display language (02 §10).",
            "**Openings.** One adjustment per account against Opening Balance / Capital (02 §4; the engine's `Verbs.openingBalance`), dated at the book start (ADR 2026-09-09d §4); the narration's citation *(02 §4; counterpart …)* prints as *(set against …)*.",
            "**Year close** (02 §8.1, ADR 2026-09-05e §2): the certified closing vector carries money, party, advance, partner and equity_system accounts as on %s; category accounts are not carried; the net result is one line; *%s* is a computed line (02 §1.2), printed as *%s*; there is no closing journal entry; every member's device recomputes the same vector (02 §8 step 4). Preconditions asserted: all 12 months locked · Suspense 0 · no open review flag · no pending advance request (the sync-layer checks of ADR 2026-09-05e §4 are outside this reference's scope)." % (
                fdate(FY_END), " / ".join(sorted(set(equity_label(b) for b in uc.books.values()))), " / ".join(sorted(set(equity_plain_label(b) for b in uc.books.values())))),
            "**Position** = 07 §14 *Full Position*, by sign (02 §1.2): every carried account on the side its balance says; the printed heading is *What I/we have and what I/we owe (position)*.",
            "**Periods** (02 §8): step 1 cash counts at close of business on the month's last day, differences `Dr/Cr Cash · Cr/Dr Adjustments` (kind `adjustment`, tag `count_diff`); step 3 tray at the lock — Suspense, open flags, pending advances; aged advances warn only (reminder default %d days)." % ADVANCE_WARN_DAYS])
    for heading, paras in uc.tech_notes:
        doc.h(3, heading)
        for p in paras:
            doc.p(p)
    # 7. checks
    doc.h(2, "7. Checks")
    doc.ul(["**What `build.py` asserts on every run, and refuses to write otherwise:** " + ASSERTS_TEXT,
            "**Mutation check** — " + MUTATION_TEXT,
            "**Independent re-derivation** — `check_md.py` parses the printed markdown as a reader would (daybook → ledgers → trial balance → income and expense statement → position → year-close vector, plus the section order and the plain-language lint); this build passed **%d checks with 0 differences** across the seven printed reports." % n_checks])
    for b in uc.books.values():
        doc.h(3, "Ledger arithmetic — %s (the cross-check lines formerly printed under every ledger)" % b.id)
        rows_tb, tdr, tcr = trial_balance(b)
        tb = dict((a.id, p) for a, p in rows_tb)
        rows = []
        for a in b.accounts.values():
            op, dr, cr, close = ledger_check(b, a)
            o_amt, o_side = fmt_signed_side(op)
            c_amt, c_side = fmt_signed_side(close)
            rows.append([a.name, "%s %s" % (o_amt, o_side) if op else "—", fmt(dr) if dr else "—", fmt(cr) if cr else "—", "%s %s" % (c_amt, c_side), "✓" if tb[a.id] == close else "✗"])
        doc.table(["Account", "Opening", "Debits", "Credits", "Closing (opening + Dr − Cr)", "= TB"], rows, ["l", "r", "r", "r", "r", "c"])
        vec, net = closing_vector(b)
        parts, computed = equity_parts(b)
        doc.p("Trial balance Dr %s = Cr %s ✓ · Σ(vector) + net line = %d ✓ · net result %s · computed %s %s (fixtures key `%s_paise`)." % (
            rs(tdr), rs(tcr), sum(p for _, p in vec) - net, rs(net), equity_label(b), rs(computed), equity_label(b).lower().replace(" ", "_")))
    return doc


def build_readme(ucs, summaries, md_hash, n_checks):
    doc = DualDoc("Use-case worked examples — reading guide, class mapping and open readings (%s)" % FY_LABEL)
    doc.raw_html("", "---\napproved_by:      # bookkeeper name — empty = PROVISIONAL (ADR 2026-09-05i §3, ADR 2026-10-11)\napproved_on:      # YYYY-MM-DD\ncontent_hash:     # BLAKE2b-256 over the seven use-case .md files; build.py prints it (currently %s…)\n---" % md_hash[:16])
    total_v = sum(len(b.vouchers) for uc in ucs for b in uc.books.values())
    total_b = sum(len(uc.books) for uc in ucs)
    doc.p("**Status: ⚠️ PROVISIONAL — pending bookkeeper sign-off.** Seven use cases, %d books, %d vouchers, one full financial year (%s – %s), every month locked and every book closed with a certified vector. "
          "Everything here is generated by `build.py` from the voucher data in that one script and asserted to balance; the markdown, HTML, PDF, the technical companions and `fixtures.json` are outputs, never edited by hand. "
          "This set is written **from the financial architecture specification and the ledger rules only** (`docs/reference/financial-accounting-standards.md`, `docs/02-ledger-rules.md`, the ADRs named below) — not from the app's code and not from any demo data. "
          "It sits in `docs/reference/worked-examples/usecases/`, inside the one folder that holds every worked example (ADR 2026-10-12 §9); the original five files at that folder's root are untouched and remain the golden set until the owner rules otherwise (ADR 2026-10-11)." % (total_b, total_v, fdate(FY_START), fdate(FY_END)))
    doc.p("**Two files per use case (ADR 2026-10-12 §2).** `<slug>.md` (and its `.html` / `.pdf`) is the **printed report** — the real layout of the reports and statements a user prints or shares from the app, in the plain words a household or a shopkeeper writes in a diary or ledger book, with the true side in a small bracket after the plain label (*Money in (Dr)*, *You will get (Dr)*; ADR 2026-10-10b §4). "
          "Engine class names, verb ids, rule or ADR references, ⚠️ notes and generator checks never appear on it — `build.py` refuses to write a report that carries one (`plain_lint`), and `check_md.py` checks the same independently. "
          "`<slug>.tech.md` is the **technical companion**: per account the engine class, subtype, role and the standard and traditional types; per voucher the `kind`, refs, review and advance states; the rules the scenario exercises; the ⚠️ SPEC readings that apply; the checks; and the developer notes that used to sit in the report. The figures in the two files are the same figures.")
    doc.p("Real names given by the owner are used here on purpose and are committed (ADR 2026-10-11 §2 reverses, for this folder only, the 4 Oct 2026 *real names never committed* note at `.gitignore:41`). Names only — no phone numbers, and every figure is illustrative.")
    doc.h(2, "1. The set")
    rows = []
    for uc, tb in summaries:
        for i, b in enumerate(uc.books.values()):
            rows.append(["`%s.md` / `.html` / `.pdf`<br>`%s.tech.md`" % (uc.slug, uc.slug) if i == 0 else "", uc.entity if i == 0 else "", b.name, str(len(b.vouchers)), fmt(tb[b.id])])
    doc.table(["Files (printed report · technical companion)", "Entity", "Book", "Vouchers", "TB total ₹"], rows, ["l", "l", "l", "r", "r"])
    doc.p("Every printed book reads the way a ledger book is read, in the same order (owner ruling, 12 Oct 2026), under plain headings: **(1) Accounts and opening balances** — every account with its type word and its opening balance, Dr and Cr totals agreeing; **(2) Account statements (ledgers)** — every account, one after the other; an account with no entries still appears; then the supporting registers — **(3) Day book** with every entry's plain type (*Money in*, *Money out*, *Gave on credit*, *Took on credit*, *Transfer*, *Correction / adjustment*) and *entered by*, **(4) Corrections and approvals**, **(5) Months closed and cash counts**, **(6) Advances**, and the use-case section (bank statement, partners, tenants, gollak, retention, KCC); and **at the end the closing statements**: **(7) Closing balances (trial balance)**, **(8) Income and expenses for the year** — the Income & Expenditure Account (trust) / Profit & Loss Account (business) / income and expenses (personal and family) with every head's total for the whole year, **(9) What I have and what I owe (position)** (07 §14 *Full Position*, by sign) with how the Corpus or the owner's funds are made up, and **(10) Year end — balances carried to next year**. The family file ends with the Family Reconciliation and the open advances across the family.")
    doc.h(2, "2. Period, openings, locks, close and layout")
    doc.ul(["**Period** %s – %s (%s); every book's start date is 01 Apr 2025 and its openings are dated there (ADR 2026-09-09d §4). Nothing is dated before the start; nothing is authored into a month after its lock (02 §8)." % (fdate(FY_START), fdate(FY_END), FY_LABEL),
            "**Openings**: one adjustment **per account** — money, party, advance or partner — against Opening Balance / Capital, signed as the ledger sees it (02 §4; the engine's `Verbs.openingBalance`); a partner's contribution is `Dr Opening Balance / Capital · Cr Partner Current`; Opening Balance / Capital absorbs the difference and the chart shows it (ADR 2026-09-09c §4).",
            "**Locks**: all twelve months, each lock dated in the following month; cash counted at close of business on the month's last day (02 §8 step 1), differences posted `Dr/Cr Cash · Cr/Dr Adjustments`; Suspense 0, no open flag and no pending advance as of every lock date (02 §8 step 3); aged advances warn only.",
            "**Year close** (02 §8.1, ADR 2026-09-05e §2): the certified closing vector carries money, party, advance, partner and equity_system accounts as on 31 Mar 2026; category accounts are not carried; the year's surplus/deficit is one line; *Accumulated surplus* (business, family, personal) / *Corpus* (trust) is a computed line (02 §1.2); there is **no closing journal entry**; the vector becomes the %s b/f. The printed report calls the line *Owner's funds / Partners' funds / Family's own funds in the business (accumulated surplus)*, *Net worth* or *Corpus — the trust's own funds*; `fixtures.json` keeps the 02 §1.2 name as its key." % NEXT_FY_LABEL,
            "**Ledger layout** (standards §2): Date · Entry · Particulars (*To …* on the debit side, *By …* on the credit side) · contextual Dr · contextual Cr · Balance · **Side as its own column** on every row; no minus signs. The opening row is drawn exactly as standards §2 draws it — *Opening balance b/f · — · — · amount · side* — and, being printed ledgers, they end *Closing balance c/d · Total (incl. opening b/f) · Opening balance b/d* with no separate c/f row (ADR 2026-09-24b §9: the opening row of an export is unchanged). Income and expense ledgers have no b/f row and end with *Total for the year* (ADR 2026-09-05e §2).",
            "**Vocabulary** (ADR 2026-10-12 §2, ADR 2026-10-10b §4, 02 §10): the printed reports speak the user's language — *Money in / Money out*, *You will get / You will give*, *Spent / Received*, *Cash in hand*, *Opening balance / Closing balance*, *Total for the year*, *What I have / What I owe* — and every column header carries its true side in brackets, *(Dr)* or *(Cr)*; the Side column and the trial balance show Dr/Cr plainly. The engine's posting logic never bends to the display language. Words 01 §1.3 forbids in the UI (*voucher*, *narration*, *journal*, *contra*, *accrual*) do not appear on a printed report — the day book says *Entry* and *Details*. Technical terms live in the technical companion and in this README. Amounts show paise only when non-zero; the engine holds integer paise throughout."])
    doc.h(2, "3. Plain labels ⇄ engine classes (02 §1.2)")
    doc.p("The printed reports carry a plain **type word** per account; the engine knows seven classes and none of the words. A fixture compares on the **class** column, never on the label. The technical companion's §2 lists every account with both.")
    doc.table(["Type word printed", "Engine class", "Note"], [
        ["Cash · Bank (savings) · Bank (current) · Bank overdraft · Card · Loan · Collection box (gollak)", "`money` + subtype", "placement by sign: a CC, OD or loan account normally sits Cr (you owe the bank); a KCC is `money · loan`; a gollak is `money · cash_collection`"],
        ["Person / shop — customer, supplier, tenant, friend, arhtiya, dairy society", "`party`", "one person, one account, both roles; **never** a static debtor/creditor type — several parties here cross zero in both directions"],
        ["Advance with {member}", "`advance`", "money held by a book member (06 §1.0); the 02 §7 flow"],
        ["Partner — *{Owner} — Partner Current A/c*", "`partner`", "shared businesses only; by sign (Cr = business owes them, Dr = they owe the business)"],
        ["Income — *… Income A/c*", "`category_income`", "P&L; opens each FY at zero; not carried"],
        ["Expense — *… Expense A/c*", "`category_expense`", "P&L; opens each FY at zero; not carried"],
        ["Own money (capital) — *Opening Balance / Capital A/c*", "`equity_system · opening_balance`", "exactly one per book; counterpart of the openings and of capital introduced (ADR 2026-09-09b §1, 2026-09-13 §4)"],
        ["Taken out by the owner (drawings) — *Drawings A/c*", "`equity_system · drawings`", "one-owner business books only; **natural balance Dr** (contra-equity); owner takeout is Money out (ADR 2026-09-09b)"],
        ["Profit shared out to partners — *Profit Distributed A/c*", "`equity_system · profit_distributed`", "shared businesses; **natural balance Dr** (contra-equity); records what has been handed to partners"],
        ["Adjustments — *Adjustments A/c*", "`equity_system · adjustments`", "cash-count differences, write-offs; sign either way"],
        ["Unexplained money (suspense) — *Suspense A/c*", "`equity_system · suspense`", "import holding account; must be 0 at every lock (02 §10); 01 §2 calls it *Unexplained*"],
        ["Other book — *{Other book} ({type} book)*, e.g. *Randhawa Agriculture (family business book)*, *Randhawa Family Fund (joint family book)*, *Amarjeet's Family (sub-family book)*", "`equity_system · link`", "the 02 §6 inter-book pair, named in plain words (owner ruling 11 Oct 2026 — the words *Due to/from* do not appear in account names); placed by sign: Dr = that book owes this one, Cr = this one owes that book; every pair nets to zero"],
    ], ["l", "l", "l"])
    doc.h(2, "4. Which rule each scenario exercises (voucher ids)")
    rows = []
    for rule, where, fn in RULES:
        cells = []
        for uc in ucs:
            t = fn(uc)
            if t != "—":
                cells.append("%s: %s" % (uc.slug, t))
        rows.append([rule, where, "<br>".join(cells) if cells else "—"])
    doc.table(["Rule", "Where", "Voucher ids"], rows, ["l", "l", "l"])
    doc.h(2, "5. ⚠️ SPEC — readings taken where 02 and the ADRs are silent")
    doc.p("Each is the most conservative reading available, flagged for the owner; none changes a locked line. Where a reading is overruled, `build.py` is changed and every file regenerated — the markdown is never patched. The kinds in S1–S3 coincide with the engine's own ⚠️ SPEC reading in `packages/core_ledger/lib/src/invariants.dart` (checked 11 Oct 2026); the generator's class-shape check mirrors that arm. Each technical companion repeats the readings its scenario exercises; the printed reports carry none of them.")
    doc.ul([text for sid, text in SPEC_READINGS])
    doc.p("**Ruled by the owner (12 Oct 2026), no longer a reading:** *Manni Labour A/c* and *Ravinder Labour A/c* are **expense heads**, not party accounts. Each labourer is paid his month's wages in cash on the month's last day (`Dr Manni Labour · Cr Cash`, a Money out), so nothing is owed at any month end and no party is needed; the year's total paid to each — ₹1,08,000 and ₹1,02,000 — is the *Total for the year* row of his ledger and his line in the trust's Income & Expenditure Account. *Labour A/c* stays for daily-wage labour at the big diwans. (Had wages been left unpaid at a month end, 02 §1.2 would need the person as a party to show what is owed.)")
    doc.h(2, "6. Known limits (avoided on purpose)")
    doc.ul([
        "**Receiving-book side of an owner's or partner's takeout.** ADR 2026-09-09b fixes only the business side (`Dr Drawings · Cr money`); 02 §7.1 only the business side of a partner takeout. No book in this set records the receiving side: Jasvinder's household items are paid straight from the business account as Drawings and never enter his personal book (its P&L is therefore a deficit funded from savings — by construction); the Randhawa family takes nothing out of the Brick Field this year. Unruled; the owner should rule before a personal book is expected to show business takeouts as income.",
        "**Capital introduced from an asset never on the books.** Jasvinder's ₹1,50,000 comes from a fixed deposit that matured straight into the business account; the FD predates 1 Apr 2025 and was never on the personal book (ADR 2026-09-09d §4 — the books begin at the start date), so no personal-side posting is needed.",
        "**Sood** (interest an arhtiya charges on an advance) is not posted — open roadmap row (10, *Interest on hand loans*). Sodhi & Sons' ₹60,000 advance is settled by the next sale without interest.",
        "No EMI with principal and interest in one bank line (the KCC bank debits interest separately); no party-to-party posting; no credit to an expense category outside adjustment/reversal; no write-off to P&L (write-offs go to Adjustments; ADR 2026-10-12 §8 rules a *Written off* head for a later slice); no fixed assets (kilns, land, cattle, the langar hall are not on the books; ADR 2026-10-12 §6 rules an `asset` class for a later slice); no GST or TDS (every rent is below ₹2,40,000 a year; no TDS on contract bills modelled); no late arrival, no re-opened month or year, no loss sharing, no route-1/route-2 partner settlement posting; INR only.",
        "**The joint fund's P&L is a deficit by construction**: business surplus reaches it through 02 §6 pairs, never through an income account (02 §7.1 last paragraph), so its own P&L shows only the common spending while the links show what each business has remitted.",
        "Two-member books flag only the limited member's entries; admins carry no limit, so the admin-held-to-a-lower-threshold option (02 §7.2 item 2, default ⚠️) is not exercised.",
    ])
    doc.h(2, "7. Defects found in the existing set `docs/reference/worked-examples/` (not fixed there — owner decision)")
    doc.p("An independent audit of the current golden set surfaced the following. Nothing in that folder was changed; the owner decides whether it is corrected, re-hashed, or replaced. This set was built so that none of them recurs, and each is asserted by `build.py` where an assertion is possible.")
    doc.table(["#", "Finding", "Where in the existing set", "In this set"], [
        ["1", "Trust pays advances and expenses straight from Gollak Cash and has no plain Cash A/c; counts conflate counting with depositing", "`trust-singh-sabha-gurudwara.md` T-003, T-011, T-022 (advances from Gollak), T-018, T-027 (ration from Gollak); narration of T-001 *counted and deposited in cash box* against a count posting; chart rows 1–2 have no Cash A/c", "Cash A/c + Gollak Cash; every gollak credit is a Transfer to cash/bank (asserted); counts and deposits are separate vouchers"],
        ["2", "Two cash accounts end negative — 02 §9 calls negative physical cash a missing entry", "`joint-family-sharma.md`: Agri Cash A/c closes **39,900 Cr**, Sub-family Cash A/c closes **41,900 Cr**", "no cash, collection, savings or current account is negative after any posting (asserted); only CC and loan accounts sit Cr"],
        ["3", "Partnership opening not credited to the partners", "`joint-business-partnership.md` chart row 12: Opening Balance / Capital 50,000 Cr; rows 2–4 partners open at —", "BF-001 and RB-001 credit each Partner Current; Opening Balance / Capital carries only the difference (ADR 2026-09-09c §4)"],
        ["4", "Splits stated in rupees; interest in rupees", "`joint-business-partnership.md` §5 line *equal share = 1,11,668 / 1,11,666 / 1,11,666*; §4 interest illustration (errata F-6/F-7)", "every split and interest computed in integer paise, shown to the paisa (BF-178, BF-179; remainder 2 paise to the largest ratio)"],
        ["5", "Natural-balance labels wrong for contra-equity; link accounts given a fixed side", "`business-sharma-textile.md`:249 Drawings *Natural balance: Cr*; `joint-business-partnership.md`:163 Profit Distributed *Natural balance: Cr*", "Drawings and Profit Distributed are stated natural **Dr** (contra-equity); links, parties and partners are *by sign*"],
        ["6", "Family Reconciliation shows consumer wording only", "`joint-family-sharma.md` §6: *you will give / you will get* with no Dr/Cr", "plain words with the true side in brackets on every printed surface (ADR 2026-10-10b §4, ADR 2026-10-12 §2); the Side column shows Dr/Cr plainly"],
        ["7", "Income and expense ledgers carry an *Opening balance b/f* row", "every category ledger, e.g. `individual-rahul-sharma.md` Household Expense A/c first row", "no b/f on category ledgers; they end with the year's total and are not carried (ADR 2026-09-05e §2)"],
        ["8", "Layout: Balance and Side merged in one column; ledgers end with a c/f row and no c/d · Total · b/d block", "every ledger of the existing set (`| 1,09,400 Dr |`, *Closing balance c/f*)", "standards §2 columns with Side separate; printed ledgers end c/d · Total · b/d (ADR 2026-09-24b §9)"],
        ["9", "Generator not reproducible: absolute machine paths, no PDF step, one file hand-edited after generation", "`build.py:235`, `joint.py:162`, `partnership.py:40` write to `/home/claude/gen/out/…`; `joint-business-partnership.md` (05 Sep) is newer than its `.pdf` (30 Aug)", "`build.py` is deterministic, path-relative, renders md/html/pdf, the technical companions and `fixtures.json`; two runs from a clean folder are byte-identical (PDF dates pinned)"],
        ["10", "The voucher register carries no `kind`, so the class-shape of each posting cannot be checked", "every daybook table of the existing set (columns Date · Particulars · Dr · Cr · Amount)", "every voucher carries its verb (printed as the plain entry type; the `kind` id in the technical companion and `fixtures.json`); the generator checks 02 §1.4 rule 7 (and the §6/§7/§7.1 shapes, S1–S3) for every voucher"],
        ["11", "Narrations that do not match the posting", "e.g. `trust-singh-sabha-gurudwara.md` T-001 *Gollak counted and deposited in cash box* posts `Dr Gollak Cash · Cr Donation` (no deposit)", "narrations are templated from the accounts and events they post"],
        ["12", "Printed reports carry engine classes, verb ids, rule references and generator notes", "every file of the existing set (chart *Engine class* column, `kind` column, `(02 §…)` in narrations and headings)", "plain words only on the printed report (ADR 2026-10-12 §2), refused otherwise by `plain_lint`; the technical companion carries the rest"],
    ], ["r", "l", "l", "l"])
    doc.h(2, "8. Regenerating, checking, fixtures, and what would make this set golden")
    doc.ul([
        "`python3 build.py` in this folder regenerates every file — the seven printed reports (`.md`, `.html`, `.pdf`), the seven technical companions (`.tech.md`), this README and `fixtures.json`. `--no-pdf` skips Chrome; `--chrome PATH` points at another Chrome; `--self-test` runs the mutation checks below. The script uses the standard library only, integer paise everywhere, no clock, no randomness, relative paths; Chrome's `/CreationDate` and `/ModDate` are pinned so the PDFs are byte-stable.",
        "**What `build.py` asserts on every run, and refuses to write otherwise:** " + ASSERTS_TEXT,
        "**Mutation check** — " + MUTATION_TEXT,
        "**Independent re-derivation** — `check_md.py` (committed beside the generator, standard library only, no code shared with `build.py`) parses the **printed markdown** as a reader would: it sums every day book, rebuilds every trial balance, re-runs every account statement's running balance and khata block, re-adds every year-end carried vector, checks that every book runs accounts → statements → closing balances → income and expenses → position → year end, that the accounts table lists exactly the accounts of the statements and the trial balance with openings that total Dr = Cr and match each statement's b/f row, that every head's year total in the income and expense statement equals its statement and the statement balances, that the position's *has − owes* equals the computed Corpus / owner's funds and its make-up, and that no technical token (§, ADR, backtick, ⚠️, engine class, verb id, *voucher*) appears in print. `build.py` runs it after writing the seven printed reports and stops on any difference; this build passed **%d checks with 0 differences**. Run it by hand with `python3 -I check_md.py` in this folder." % n_checks,
        "`fixtures.json` holds every book (type, ownership, members with limits), every account (class, subtype, role, link, opening paise), every voucher (kind, accounting date, authored date, the narration as stored — with its rule citation — signed lines in paise with the `interest`/`share` line tags, refs, review and advance states, count sheets), the locks, the cash counts with denominations, and the expected closing balances, TB totals and year-close vectors — so an engine golden test can consume this set without parsing markdown. The plain-language rework of 12 Oct 2026 changed no figure and no field of it except `content_hash_md`.",
        "To become golden (ADR 2026-10-11 §5, ADR 2026-10-12 §3): bookkeeper sign-off in the front matter; the owner's ruling on each ⚠️ SPEC item above; a new suite-A engine test (A-ref-8/9) that replays `fixtures.json` and reproduces every ledger, TB and vector; and the `content_hash` over the seven printed `.md` files written into the front matter (currently `%s`)." % md_hash,
    ])
    return doc


# ----------------------------------------------------------------------------------------------
# Self-test — mutate one guarded posting per assertion and expect the validator to refuse it
# ----------------------------------------------------------------------------------------------
def self_test():
    results = []

    def expect_refusal(name, builder, mutate):
        uc = builder()[0]
        finalize(uc)
        mutate(uc)
        try:
            validate(uc)
        except Violation as e:
            results.append((name, True, str(e)))
            return
        results.append((name, False, "validator accepted the mutated set"))

    def dist(uc):
        return [v for v in uc.books["BF"].vouchers if v.tag == "distribution"][0]

    def move(vo, src, dst, paise):
        """Move `paise` of credit from the line matching src to the line matching dst (sum stays zero)."""
        li = list(vo.lines)
        i = next(k for k, (a, p) in enumerate(li) if src(a, vo.ltags[k]))
        j = next(k for k, (a, p) in enumerate(li) if dst(a, vo.ltags[k]))
        li[i] = (li[i][0], li[i][1] + paise)
        li[j] = (li[j][0], li[j][1] - paise)
        vo.lines = li

    expect_refusal("remainder paise moved to the wrong partner", build_uc3,
                   lambda uc: move(dist(uc), lambda a, t: a.id == "pc_s" and t == "share", lambda a, t: a.id == "pc_p" and t == "share", 2))
    expect_refusal("an interest line a paisa short (rounded down)", build_uc3,
                   lambda uc: move(dist(uc), lambda a, t: a.id == "pc_s" and t == "interest", lambda a, t: a.id == "pc_s" and t == "share", 1))
    expect_refusal("interest not from credit-day balances (debit days charged)", build_uc3,
                   lambda uc: move(dist(uc), lambda a, t: a.id == "pc_h" and t == "share", lambda a, t: a.id == "pc_h" and t == "interest", 5000))

    def capital_to_income(uc):
        b = uc.books["JT"]
        vo = [v for v in b.vouchers if v.tag == "capital_in"][0]
        vo.lines = [(b.accounts["icici"], vo.amount), (b.accounts["svc"], -vo.amount)]
    expect_refusal("capital introduced credited to Service Income", build_uc1, capital_to_income)

    def drawings_to_expense(uc):
        b = uc.books["SS"]
        vo = [v for v in b.vouchers if v.tag == "drawings"][0]
        vo.lines = [(b.accounts["rent"], vo.amount), (b.accounts["pnb"], -vo.amount)]
    expect_refusal("owner takeout debited to Shop Rent Expense", build_uc2, drawings_to_expense)

    def witness_is_counter(uc):
        vo = [v for v in uc.books["TR"].vouchers if v.tag == "gollak_count"][0]
        vo.sheet["witness"] = vo.sheet["counted_by"]
    expect_refusal("gollak count whose witness is the counter", build_uc5, witness_is_counter)

    def transfer_into_gollak(uc):
        b = uc.books["TR"]
        b.v(d(2025, 4, 20), "transfer", "cash put back into the gollak", [(b.accounts["gollak"], R(1000)), (b.accounts["cash"], -R(1000))], "Ranjeet Singh")
    expect_refusal("a Transfer into the gollak", build_uc5, transfer_into_gollak)

    def operator_amends(uc):
        vo = [v for v in uc.books["SS"].vouchers if "amends" in v.refs][0]
        vo.by = "Manpreet Kaur"
    expect_refusal("an operator amending an entry", build_uc2, operator_amends)

    def authored_before_dated(uc):
        vo = uc.books["JS"].sorted_vouchers()[5]
        vo.authored = vo.date - timedelta(days=1)
    expect_refusal("an entry authored before its accounting date", build_uc1, authored_before_dated)

    def pocket_half_as_transfer(uc):
        vo = [v for v in uc.books["RF"].vouchers if v.tag == "interbook" and v.date == d(2025, 8, 6)][0]
        vo.kind = "transfer"
    expect_refusal("the pocket-expense half labelled transfer", build_uc4, pocket_half_as_transfer)

    def suspense_uncleared(uc):
        b = uc.books["SS"]
        vo = [v for v in b.vouchers if v.tag == "suspense_clear"][0]
        b.vouchers.remove(vo)
    expect_refusal("a Suspense line left uncleared at the lock", build_uc2, suspense_uncleared)

    def cash_negative(uc):
        b = uc.books["JS"]
        b.v(d(2025, 4, 3), "money_out", "impossible cash payment", [(b.accounts["hh"], R(500000)), (b.accounts["cash"], -R(500000))], "Jasvinder Singh")
    expect_refusal("cash driven negative", build_uc1, cash_negative)

    bad = 0
    for name, refused, msg in results:
        print("%-58s %s  %s" % (name, "refused ✓" if refused else "NOT REFUSED ✗", msg[:100]))
        bad += 0 if refused else 1
    print("self-test: %d mutations, %d refused, %d not refused" % (len(results), len(results) - bad, bad))
    return 1 if bad else 0


# ----------------------------------------------------------------------------------------------
# main    return doc


# ----------------------------------------------------------------------------------------------
# main
# ----------------------------------------------------------------------------------------------
def write(path, text):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main(argv):
    if "--self-test" in argv:
        return self_test()
    no_pdf = "--no-pdf" in argv
    chrome = DEFAULT_CHROME
    if "--chrome" in argv:
        chrome = argv[argv.index("--chrome") + 1]
    builders = [build_uc1, build_uc2, build_uc3, build_uc4, build_uc5, build_uc6, build_uc7]
    ucs = []
    summaries = []
    for bld in builders:
        uc, close_date, closers, extra = bld()
        finalize(uc)
        validate(uc)
        doc, tb = build_report(uc, close_date, closers, extra)
        md, html = render_dual(doc)
        plain_lint(md, uc.slug + ".md")          # ADR 2026-10-12 §2: nothing technical on a printed report
        write(os.path.join(HERE, uc.slug + ".md"), md)
        write(os.path.join(HERE, uc.slug + ".html"), html)
        ucs.append(uc)
        summaries.append((uc, tb))
    h = hashlib.blake2b(digest_size=32)
    for uc in ucs:
        with open(os.path.join(HERE, uc.slug + ".md"), "rb") as f:
            h.update(f.read())
    md_hash = h.hexdigest()
    # independent re-derivation of the printed markdown — stop here on any difference
    res = subprocess.run([sys.executable, "-I", os.path.join(HERE, "check_md.py"), HERE], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    last = res.stdout.strip().splitlines()[-1] if res.stdout.strip() else ""
    m = re.match(r"checks: (\d+)\s+problems: (\d+)", last)
    if res.returncode != 0 or not m or int(m.group(2)) != 0:
        sys.stderr.write(res.stdout)
        raise SystemExit("check_md.py found a difference between the printed markdown and the register")
    n_checks = int(m.group(1))
    fx = fixtures_for(ucs)
    fx["content_hash_md"] = md_hash
    write(os.path.join(HERE, "fixtures.json"), json.dumps(fx, indent=1, ensure_ascii=False) + "\n")
    # the technical companions — one per use case, markdown only
    for uc, tb in summaries:
        tmd = render_md(render_tech(uc, tb, n_checks))
        chk("🔒" not in tmd, "%s.tech.md carries a lock glyph" % uc.slug)
        write(os.path.join(HERE, uc.slug + ".tech.md"), tmd)
    readme = build_readme(ucs, summaries, md_hash, n_checks)
    md, html = render_dual(readme)
    write(os.path.join(HERE, "README.md"), md)
    write(os.path.join(HERE, "README.html"), html)
    if not no_pdf:
        for uc in ucs:
            to_pdf(chrome, os.path.join(HERE, uc.slug + ".html"), os.path.join(HERE, uc.slug + ".pdf"))
        to_pdf(chrome, os.path.join(HERE, "README.html"), os.path.join(HERE, "README.pdf"))
    for uc, tb in summaries:
        for b in uc.books.values():
            print("%-34s %-44s vouchers %4d  TB %s" % (uc.slug, b.name[:44], len(b.vouchers), rs(tb[b.id])))
    print("check_md.py: %d checks, 0 problems" % n_checks)
    print("plain_lint: 7 printed reports clean; technical companions written: %d" % len(ucs))
    print("content_hash (BLAKE2b-256 over the seven use-case .md files): %s" % md_hash)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
