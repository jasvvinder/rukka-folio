#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build.py — the five reference books: compact worked-example ledger books for FY 2025-26 (ADR 2026-10-20 §2).

    individual-jasvinder-singh            personal book + Jasvinder Technologies (two books); a vehicle bought on a loan, a driver's advance, a FASTag wallet
    joint-family-randhawa                 joint family, three sub-families, Agriculture, Real Estate, Brick Field (seven books)
    shop-sukhwinder-sales-co              pipes & sanitary shop
    partnership-bal-fabricators           2:2:1 partnership; a contract job with retention money, a mobilisation advance, supplier advances
    trust-radha-soami-satsang-sabha       trust: gollak, langar, dairy, construction, a Langar Hall Fund for a purpose; R&P, I&E, Balance Sheet, fund statement

Five practice books were merged into these five on 20 Oct 2026 (truck, farmer, landlord, contractor, committee); their finished
outputs are archived at docs/archive/reference/practice-books-merged/ and COVERAGE.md says where each mechanic now sits.

These books are the TARGET OUTPUT of the ledger app (ADR 2026-10-12 §10–§12, reworked by ADR 2026-10-20 §2 and the rulings of 20 Oct 2026 in
docs/archive/reference/accounting-research/OPEN.md): written the way a competent Indian bookkeeper keeps such books from real transactions, not from the app's
current rules. They follow the rulings: no tax, GST, TDS, invoicing, stock or payroll; the khata basis (no depreciation, no accruals, no
closing stock); things owned stay at cost; every report head carries the book, the date or period, the basis, Year closed and Made on; the
year close is POSTED by the book itself (income and expense heads to the result, the result and drawings to own money, a partnership
through a P&L Appropriation Account); plain words with the true side in brackets; no registers or entry tags; about 40-60 entries per
book (25-40 for each joint-family book) and 10-12 A4 pages; the build FAILS when a book prints on more than 14 pages.

Standard library only; integer paise everywhere (no float touches money); no clock, no randomness; paths
relative to this file; two runs produce byte-identical md / html / tech.md (Chrome's PDF dates are pinned too).

Usage:  python3 -I build.py [--no-pdf] [--chrome PATH] [--skip-check]
"""
import datetime as dt
import hashlib
import html as html_mod
import os
import re
import shutil
import subprocess
import sys
import tempfile
from decimal import Decimal, ROUND_HALF_UP

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
FY_START = dt.date(2025, 4, 1)
FY_END = dt.date(2026, 3, 31)
MID_YEAR = dt.date(2025, 9, 30)
STATEMENT_MONTH = (2025, 10)          # the one month whose account summary every book shows
MAX_PAGES = 14                        # ADR 2026-10-12 §11 (kept by ADR 2026-10-20 §2): a book over 14 A4 pages fails the build

# ---------------------------------------------------------------------------------------------
# Fixed lines every report carries (OPEN.md rulings O-01-1, O-09-1, O-10-1, O-20-1, O-20-2) — no clock: the date is pinned.
# ---------------------------------------------------------------------------------------------
BASIS_LINE = "Kept on money paid and received, and what people owe; no year-end adjustments."
MADE_ON = "02 Apr 2026, 10:00"
COST_LINE = "Things owned are shown at what they cost; no depreciation is charged."
STAKE_LINE = "The business is shown at the money put into it, not at its worth."          # 04 §4.3: a position that shows money put into a business
STAKES_LINE = "The businesses are shown at the money put into them, not at their worth."  # the same note, when more than one business is shown
STOCK_LINE = "No stock is counted. Everything bought for sale is treated as sold or used in the year it was bought."
BUILD_LINE = "The cost of %s, ₹%s to date, is charged to expenditure and is not shown as a thing owned."   # 04 §4.3, 02 §5.8: a trust that charges a building to expenditure

# ---------------------------------------------------------------------------------------------
# money and date helpers — integer paise only
# ---------------------------------------------------------------------------------------------

def R(rupees, paise=0):
    """Rupees (+ paise) → integer paise."""
    assert isinstance(rupees, int) and isinstance(paise, int)
    return rupees * 100 + paise


def fmt(p, dash=True, show_zero=False):
    """Integer paise → Indian-grouped rupees, paise only when non-zero; 0 prints as '—'."""
    if p == 0:
        return "0" if show_zero else ("—" if dash else "0")
    neg = p < 0
    p = -p if neg else p
    r, ps = divmod(p, 100)
    s = str(r)
    if len(s) > 3:
        head, tail = s[:-3], s[-3:]
        parts = []
        while len(head) > 2:
            parts.insert(0, head[-2:])
            head = head[:-2]
        parts.insert(0, head)
        s = ",".join(parts) + "," + tail
    if ps:
        s += ".%02d" % ps
    return ("\u2212" if neg else "") + s


def D(y, m, d):
    return dt.date(y, m, d)


def fdate(d):
    return d.strftime("%d %b %Y")


def month_name(y, m):
    return dt.date(y, m, 1).strftime("%B %Y")


def month_end(y, m):
    if m == 12:
        return dt.date(y, 12, 31)
    return dt.date(y, m + 1, 1) - dt.timedelta(days=1)


def fy_months():
    out = []
    y, m = 2025, 4
    for _ in range(12):
        out.append((y, m))
        m += 1
        if m == 13:
            y, m = y + 1, 1
    return out


def half_up(numer, denom):
    """Integer division rounded half-up (non-negative operands)."""
    assert numer >= 0 and denom > 0
    return (2 * numer + denom) // (2 * denom)


# ---------------------------------------------------------------------------------------------
# accounts, vouchers, books
# ---------------------------------------------------------------------------------------------

# kind → (standard type, traditional class, natural balance, (plain Dr column, plain Cr column), plain type word)
KIND = {
    "cash":     ("Asset", "Real", "Dr", ("Money in (Dr)", "Money out (Cr)"), "Cash"),
    "gollak":   ("Asset", "Real", "Dr", ("Counted in (Dr)", "Emptied (Cr)"), "Gollak"),
    "bank":     ("Asset", "Personal", "Dr", ("Money in (Dr)", "Money out (Cr)"), "Bank"),
    "wallet":   ("Asset", "Personal", "Dr", ("Money in (Dr)", "Money out (Cr)"), "Wallet"),
    "card":     ("Liability (by balance)", "Personal", "Cr", ("Paid in (Dr)", "Spent on the card (Cr)"), "Credit card"),
    "cc":       ("Liability (by balance)", "Personal", "Cr", ("Paid in (Dr)", "Drawn / charged (Cr)"), "KCC loan"),
    "party":    ("Asset / Liability (by balance)", "Personal", "by sign", ("You will get (Dr)", "You will give (Cr)"), "Person / shop"),
    "link":     ("Asset / Liability (by balance)", "Personal", "by sign", ("Given (Dr)", "Received (Cr)"), "Other book"),
    "stake":    ("Asset", "Personal", "Dr", ("Put in (Dr)", "Taken out (Cr)"), "Money in a business"),
    "advance":  ("Asset", "Personal", "Dr", ("Given as advance (Dr)", "Settled / returned (Cr)"), "Advance"),
    "loanto":   ("Asset", "Personal", "Dr", ("Lent (Dr)", "Paid back / written off (Cr)"), "Loan given"),
    "retention": ("Asset", "Personal", "Dr", ("Held back (Dr)", "Released (Cr)"), "Retention held"),
    "fixed":    ("Asset", "Real", "Dr", ("Bought / received (Dr)", "Sold / gone (Cr)"), "Thing owned"),
    "deppaid":  ("Asset", "Personal", "Dr", ("Paid (Dr)", "Got back / set off (Cr)"), "Deposit paid"),
    "invest":   ("Asset", "Personal", "Dr", ("Kept aside / interest added (Dr)", "Taken back (Cr)"), "Deposit"),
    "loan":     ("Liability", "Personal", "Cr", ("Paid back (Dr)", "Taken (Cr)"), "Loan"),
    "deposit":  ("Liability", "Personal", "Cr", ("Returned / set off (Dr)", "Received (Cr)"), "Deposit held"),
    "fund":     ("Capital (fund for a purpose)", "Personal", "Cr", ("Spent from it (Dr)", "Added to it (Cr)"), "Fund"),
    "capital":  ("Capital", "Personal", "Cr", ("Taken out (Dr)", "Put in / added (Cr)"), "Own money"),
    "drawings": ("Capital (contra)", "Personal", "Dr", ("Taken out (Dr)", "Put back / closed to own money (Cr)"), "Drawings"),
    "shareout": ("Capital (contra)", "Personal", "Dr", ("Shared out (Dr)", "Put back / closed to own money (Cr)"), "Share-out"),
    "partner":  ("Capital", "Personal", "Cr", ("Taken out (Dr)", "Put in / added (Cr)"), "Partner"),
    "pcapital": ("Capital", "Personal", "Cr", ("Taken out (Dr)", "Put in / added (Cr)"), "Partner's capital"),
    "pcurrent": ("Capital", "Personal", "by sign", ("Taken out (Dr)", "Put in / added (Cr)"), "Partner's current"),
    "income":   ("Income", "Nominal", "Cr", ("Returned / closed (Dr)", "Income (Cr)"), "Income"),
    "expense":  ("Expense", "Nominal", "Dr", ("Spent (Dr)", "Got back / closed (Cr)"), "Expense"),
}
MONEY_KINDS = ("cash", "gollak", "bank", "wallet", "card", "cc")
NONNEG_MONEY = ("cash", "gollak", "bank", "wallet")
EQUITY_KINDS = ("capital", "drawings", "shareout", "partner", "pcapital", "pcurrent")
HAVE_KINDS = ("cash", "gollak", "bank", "wallet", "card", "cc", "advance", "fixed", "invest", "stake", "deppaid", "loanto", "retention")

# formal voucher type → printed type word (the technical companion maps each to the 02 §2 verb it needs)
PLAIN_VTYPE = {
    "Receipt": "Money in", "Payment": "Money out", "Contra": "Transfer",
    "Journal (credit given)": "Gave on credit", "Journal (credit taken)": "Took on credit",
    "Journal (advance settled)": "Advance settled", "Journal (paid by partner)": "Paid by a partner",
    "Journal (correction)": "Correction", "Journal (paid by family)": "Paid by the joint family",
    "Journal (settled)": "Settled at year end", "Journal": "Fix / Adjust",
    "Payment (from a fund)": "Paid from a fund", "Journal (interest added)": "Interest added to a deposit",
    "Journal (written off)": "Written off", "Journal (set off)": "Deposit set off", "Journal (deposit forfeited)": "Deposit forfeited",
    "Journal (retention released)": "Retention released",
}
APP_VERB = {
    "Receipt": "money_in", "Payment": "money_out", "Contra": "transfer", "Journal (credit given)": "gave_credit",
    "Journal (credit taken)": "took_credit", "Journal (advance settled)": "advance spend (02 §7) — non-member advance, see GAPS A10",
    "Journal (paid by partner)": "partner pays from own pocket (02 §1.2 partner) — see GAPS",
    "Journal (correction)": "amend / re-classify (02 §5) — see GAPS", "Journal (paid by family)": "02 §6 one-sided case (a book pays another's cost) — see GAPS A11",
    "Journal (settled)": "year-end settlement of a sub-family account (owner's option) — see GAPS A11", "Journal": "adjustment, or a non-money journal 02 §2 lacks — see GAPS",
    "Payment (from a fund)": "one action, two postings (O-17-1): Dr expense · Cr money, and Dr fund · Cr transfer from the fund — see GAPS E2",
    "Journal (interest added)": "interest the bank adds to a deposit (O-09-5, O-17-2): Dr deposit · Cr fund or income — see GAPS A3",
    "Journal (written off)": "write-off to an expense head (O-06-5, O-12-1, O-18-5): Dr Written off · Cr the account — see GAPS A5",
    "Journal (set off)": "deposit held set off against what the same person owes (O-09-8, O-12-2): Dr deposit held · Cr the person — see GAPS A5",
    "Journal (deposit forfeited)": "deposit held kept as income (O-09-8, O-18-3): Dr deposit held · Cr Deposit forfeited — see GAPS A5",
    "Journal (retention released)": "retention money released by transfer to the party's khata (O-06-4): Dr the person · Cr retention held — see GAPS D2",
}
VTYPES = tuple(PLAIN_VTYPE)
CONTRA_KINDS = ("cash", "gollak", "bank", "cc")   # 02 §1.3: a contra is cash ↔ bank only


def formal_vtype(b, v):
    """The formal voucher type the technical companion prints. A transfer that is not cash ↔ bank (a card bill, a wallet load, a deposit made or
    matured) is a payment from, or a receipt into, the cash or bank side; the app verb stays *transfer*."""
    if v.vtype != "Contra" or all(b.accounts[n].kind in CONTRA_KINDS for n, _ in v.lines):
        return v.vtype
    if any(b.accounts[n].kind in CONTRA_KINDS and a < 0 for n, a in v.lines):
        return "Payment"
    if any(b.accounts[n].kind in CONTRA_KINDS and a > 0 for n, a in v.lines):
        return "Receipt"
    return "Journal"


class Account(object):
    def __init__(self, name, kind, label, opening=0, group=None, cols=None):
        assert kind in KIND, kind
        self.name = name
        self.kind = kind
        self.label = label
        self.opening = opening          # signed paise, + = Dr
        self.type, self.trad, self.natural, self.cols, self.group = KIND[kind]
        if group:
            self.group = group
        if cols:
            self.cols = cols
        self.is_bs = kind not in ("income", "expense")
        self.is_money = kind in MONEY_KINDS
        self.is_equity = kind in EQUITY_KINDS
        self.rows = []
        self.closing = None


class Voucher(object):
    def __init__(self, date, vtype, narration, lines, stmt=None):
        self.date = date
        self.vtype = vtype
        self.narration = narration
        self.lines = lines              # [(account name, signed paise)]
        self.stmt = stmt                # bank-statement wording (for the extract)
        self.vid = None
        self.seq = None
        self.ref = None                 # an earlier entry this one names ({ref} in the note)

    @property
    def amount(self):
        return sum(a for _, a in self.lines if a > 0)

    def dr_lines(self):
        return [(n, a) for n, a in self.lines if a > 0]

    def cr_lines(self):
        return [(n, -a) for n, a in self.lines if a < 0]


class Book(object):
    """One ledger book. `style` sets the year-end words: business | property | household | npo."""

    def __init__(self, name, kindword, prefix, style):
        assert style in ("business", "property", "household", "npo")
        self.name = name
        self.kindword = kindword
        self.prefix = prefix
        self.style = style
        self.accounts = {}
        self.order = []
        self.vouchers = []
        self.about = ""                 # one paragraph under the book heading
        self.custom = None              # (account, start, end, why)
        self.bank_extract = None        # (bank account, (y, m))
        self.partners = []              # [{name, capital, current, share, ioc_bp}]
        self.own_word = "Own money"     # what the equity is called on the page
        self.pl_title = {"business": "Profit & Loss Account", "property": "Profit & Loss Account",
                         "household": "Income & Expenses", "npo": "Income & Expenditure Account"}[style]
        self.assets_note = ""
        self.journal_word = "an adjustment where no money moved"   # what a plain Journal is in this book (the tech companion's basis line)
        self.construction = None        # (expense head, the building) — a trust that charges a building to expenditure (02 §5.8, 03 §5.7)
        self.chart_note = ""
        self.put_note = ""              # e.g. " (by the sub-families, or settled)" on the own-money make-up
        self.taken_note = ""            # replaces the default sentence on how the openings balance
        self.sources = []
        self.gaps = []                  # (voucher id or chart row, note) — technical companion only
        self.counts = {}
        self.stock_line = False         # the shop's statement prints STOCK_LINE (O-10-1)
        self.pl_note = ""               # an extra sentence under the year's statement
        self._close = None

    # --- building ---------------------------------------------------------------------
    def add(self, acct):
        assert acct.name not in self.accounts, acct.name
        self.accounts[acct.name] = acct
        self.order.append(acct.name)
        return acct.name

    def balance_opening_into(self, name):
        """The own-money opening is the balancing figure of every other opening (practice)."""
        total = sum(a.opening for n, a in self.accounts.items() if n != name)
        self.accounts[name].opening = -total

    def v(self, date, vtype, narration, lines, stmt=None):
        assert FY_START <= date <= FY_END, (date, narration)
        vch = Voucher(date, vtype, narration, [(n, int(a)) for n, a in lines], stmt=stmt)
        vch.seq = len(self.vouchers)
        self.vouchers.append(vch)
        return vch

    # shorthands — every one is a real double entry
    def pay(self, date, dr, money, amt, narr, stmt=None):
        return self.v(date, "Payment", narr, [(dr, amt), (money, -amt)], stmt)

    def rec(self, date, money, cr, amt, narr, stmt=None):
        return self.v(date, "Receipt", narr, [(money, amt), (cr, -amt)], stmt)

    def move(self, date, to, frm, amt, narr, stmt=None):
        return self.v(date, "Contra", narr, [(to, amt), (frm, -amt)], stmt)

    def gave(self, date, party, inc, amt, narr):
        return self.v(date, "Journal (credit given)", narr, [(party, amt), (inc, -amt)])

    def took(self, date, exp, party, amt, narr):
        return self.v(date, "Journal (credit taken)", narr, [(exp, amt), (party, -amt)])

    def fix(self, date, dr, cr, amt, narr, vtype="Journal", ref=None):
        vch = self.v(date, vtype, narr, [(dr, amt), (cr, -amt)])
        vch.ref = ref
        return vch

    # --- posting ------------------------------------------------------------------------
    def finalize(self):
        self.vouchers.sort(key=lambda x: (x.date, x.seq))
        for i, vch in enumerate(self.vouchers, 1):
            vch.vid = "%s-%03d" % (self.prefix, i)
        for vch in self.vouchers:
            if vch.ref is not None:
                vch.narration = vch.narration.replace("{ref}", "%s of %s" % (vch.ref.vid, fdate(vch.ref.date)))   # O-11-5: names the entry it fixes, number and date
        self.validate_vouchers()
        self.post()
        self.validate_balances()

    def validate_vouchers(self):
        for vch in self.vouchers:
            assert len(vch.lines) >= 2, (vch.vid, vch.narration)
            assert sum(a for _, a in vch.lines) == 0, ("double entry broken", vch.vid, vch.lines)
            names = [n for n, _ in vch.lines]
            assert len(names) == len(set(names)), ("account repeated in one entry", vch.vid)
            for n, a in vch.lines:
                assert n in self.accounts, ("unknown account", n, vch.vid)
                assert a != 0, ("zero line", vch.vid)
            assert vch.vtype in VTYPES, vch.vtype
            money = [n for n, _ in vch.lines if self.accounts[n].is_money]
            if vch.vtype == "Contra":
                own = [n for n, _ in vch.lines if self.accounts[n].is_money or self.accounts[n].kind == "invest"]
                assert len(own) == len(vch.lines) == 2 and money, ("a transfer joins two own money/deposit accounts", vch.vid)
            elif vch.vtype == "Payment (from a fund)":
                # O-17-1: one action — the cost is charged to the year (Dr expense · Cr money) and the same amount is
                # transferred from the fund (Dr fund · Cr transfer from the fund): two postings, one entry
                kd = [self.accounts[n].kind for n, a in vch.lines if a > 0]
                kc = [self.accounts[n].kind for n, a in vch.lines if a < 0]
                assert kd.count("fund") == 1 and kc.count("income") == 1 and money and len(vch.lines) == 4, ("fund spending shape", vch.vid)
                assert all(k in ("fund", "expense", "fixed") for k in kd) and all(self.accounts[n].is_money or self.accounts[n].kind == "income" for n, a in vch.lines if a < 0), vch.vid
                fa = [a for n, a in vch.lines if a > 0 and self.accounts[n].kind == "fund"][0]
                ia = [-a for n, a in vch.lines if a < 0 and self.accounts[n].kind == "income"][0]
                assert fa == ia == sum(-a for n, a in vch.lines if a < 0 and self.accounts[n].is_money), ("fund transfer equals the spending", vch.vid)
            elif vch.vtype in ("Receipt", "Payment"):
                assert money, ("money in/out without a money account", vch.vid)
                if vch.vtype == "Receipt":
                    assert all(self.accounts[n].is_money for n, a in vch.lines if a > 0), vch.vid
                else:
                    # Money out; a Cr line that is not money may only be an advance recovered (O-07-5) or the lender's part of a purchase (O-09-6)
                    assert all(self.accounts[n].is_money or self.accounts[n].kind in ("advance", "loan") for n, a in vch.lines if a < 0), vch.vid
                    assert all(not self.accounts[n].is_money for n, a in vch.lines if a > 0), vch.vid
            else:
                assert not money, ("a no-money entry must not touch cash/bank", vch.vid)
            # the gollak is only ever counted in (income) and emptied into the cash box or the bank
            for n, a in vch.lines:
                if self.accounts[n].kind == "gollak":
                    if a < 0:
                        assert vch.vtype == "Contra" and all(self.accounts[m].kind in ("cash", "bank") for m, x in vch.lines if x > 0), ("gollak emptied only into cash or bank", vch.vid)
                    else:
                        assert vch.vtype == "Receipt" and all(self.accounts[m].kind == "income" for m, x in vch.lines if x < 0), ("gollak filled only by a count", vch.vid)

    def post(self):
        for name in self.order:
            acct = self.accounts[name]
            acct.rows = []
            acct.bal = acct.opening
        for vch in self.vouchers:
            for n, a in vch.lines:
                acct = self.accounts[n]
                others = [(m, b) for m, b in vch.lines if (b > 0) != (a > 0)]
                if vch.vtype == "Payment (from a fund)":
                    # two postings in one action: the cost against the money paid, the fund against its transfer
                    k = acct.kind
                    pick = {"fund": "income", "income": "fund"}.get(k)
                    others = [(m, b) for m, b in others if self.accounts[m].kind == pick] if pick else [(m, b) for m, b in others if self.accounts[m].is_money] if k in ("expense", "fixed") else [(m, b) for m, b in vch.lines if b > 0 and self.accounts[m].kind in ("expense", "fixed")]
                if len(others) <= 3:
                    part = " / ".join(m for m, _ in others)
                else:
                    part = "several accounts (%d)" % len(others)
                acct.bal += a
                acct.rows.append({"date": vch.date, "vid": vch.vid, "vch": vch, "part": ("To " if a > 0 else "By ") + part,
                                  "dr": a if a > 0 else 0, "cr": -a if a < 0 else 0, "bal": acct.bal})
        for name in self.order:
            self.accounts[name].closing = self.accounts[name].bal

    def validate_balances(self):
        dr = sum(a.closing for a in self.accounts.values() if a.closing > 0)
        cr = sum(-a.closing for a in self.accounts.values() if a.closing < 0)
        assert dr == cr, ("trial balance", dr, cr)
        assert sum(a.opening for a in self.accounts.values()) == 0, "openings do not balance"
        for a in self.accounts.values():
            if a.kind in NONNEG_MONEY:
                assert a.opening >= 0, (a.name, "negative opening")
                for row in a.rows:
                    if row["bal"] < 0:
                        for r in a.rows:
                            print(r["vid"], fdate(r["date"]), fmt(r["dr"]), fmt(r["cr"]), fmt(r["bal"]), r["vch"].narration[:50], file=sys.stderr)
                    assert row["bal"] >= 0, ("cash/bank negative", self.name, a.name, row["vid"], row["bal"])
            if a.kind == "card":
                for row in a.rows:   # a card bill only brings what is owed down (02 §1.7): a card never stands on the Dr side
                    assert row["bal"] <= 0, ("card overpaid", self.name, a.name, row["vid"])
            if a.kind in ("advance", "fixed", "invest", "gollak", "deppaid", "loanto", "retention"):
                for row in a.rows:
                    assert row["bal"] >= 0, ("over-settled", self.name, a.name, row["vid"])
            if a.kind == "pcapital":
                assert not a.rows, ("fixed capital moves only by a decision of the partners", a.name)
        for k in ("cash", "bank"):
            assert any(a.kind == k for a in self.accounts.values()) or k == "bank", (self.name, "no cash account")
        n = len(self.vouchers)
        assert self.counts.get("min", 40) <= n <= self.counts.get("max", 60), ("entry count", self.name, n)

    # --- queries ------------------------------------------------------------------------
    def balance_at(self, name, date):
        acct = self.accounts[name]
        return acct.opening + sum(r["dr"] - r["cr"] for r in acct.rows if r["date"] <= date)

    def movement(self, name, start, end):
        acct = self.accounts[name]
        return (sum(r["dr"] for r in acct.rows if start <= r["date"] <= end),
                sum(r["cr"] for r in acct.rows if start <= r["date"] <= end))

    def result_to(self, date):
        inc = sum(-self.balance_at(n, date) for n in self.order if self.accounts[n].kind == "income")
        exp = sum(self.balance_at(n, date) for n in self.order if self.accounts[n].kind == "expense")
        return inc, exp

    def equity_parts(self, date):
        """(own money at the start, put in so far, taken out so far) over every own-money account."""
        eq = [n for n in self.order if self.accounts[n].is_equity]
        start = -sum(self.accounts[n].opening for n in eq)
        put = sum(self.movement(n, FY_START, date)[1] for n in eq)
        taken = sum(self.movement(n, FY_START, date)[0] for n in eq)
        return start, put, taken

    def appropriation(self, result):
        """P&L Appropriation (posted at the year close, O-14-1): interest on fixed capital where agreed and only out of profit (O-14-3), then the agreed shares.
        Returns [(partner, interest, share)]; leftover paise of the share go to the largest ratio, ties to the earliest partner (02 §7.1)."""
        if not self.partners:
            return []
        rows = []
        tot_int = 0
        for p in self.partners:
            cap = -self.accounts[p["capital"]].closing if p.get("capital") else 0
            i = half_up(cap * p.get("ioc_bp", 0), 10000) if cap > 0 else 0
            rows.append([p, i])
            tot_int += i
        rest = result - tot_int
        assert rest > 0, ("interest on capital is paid only out of profit", self.name, result, tot_int)
        weights = sum(p["share"] for p in self.partners)
        shares = [rest * p["share"] // weights for p in self.partners]
        left = rest - sum(shares)
        # 02 §7.1 🔒: the remainder goes to the partner with the largest ratio, ties to the earliest-created partner account (the list is in that order)
        shares[max(range(len(self.partners)), key=lambda k: (self.partners[k]["share"], -k))] += left
        return [(p, i, s) for (p, i), s in zip(rows, shares)]


    # --- the year close, posted by the book itself (O-19-1, O-13-1, O-14-1, O-17) ---------------
    def result_name(self):
        return {"business": "Profit & Loss A/c", "property": "Profit & Loss A/c", "household": "Income & Expenses A/c", "npo": "Income & Expenditure A/c"}[self.style]

    def owner_account(self):
        """The own-money account the result is closed to: the capital account, or (a business owned by another book) the owner's account."""
        for n in self.order:
            if self.accounts[n].kind == "capital":
                return n
        for n in self.order:
            if self.accounts[n].group == "Owner":
                return n
        return None

    def close_entries(self):
        """The entries the book makes itself on 31 Mar 2026: [(id, note, [(account, signed paise)])]. The user never types them."""
        if self._close is not None:
            return self._close
        res = self.result_name()
        inc = [(n, -self.accounts[n].closing) for n in self.order if self.accounts[n].kind == "income" and self.accounts[n].closing != 0]
        exp = [(n, self.accounts[n].closing) for n in self.order if self.accounts[n].kind == "expense" and self.accounts[n].closing != 0]
        ti, te = sum(x for _, x in inc), sum(x for _, x in exp)
        result = ti - te
        out = []

        def add(note, lines):
            lines = [(n, int(a)) for n, a in lines if a != 0]
            if lines:
                assert sum(a for _, a in lines) == 0, (self.name, note)
                out.append(("%s-Y%d" % (self.prefix, len(out) + 1), note, lines))
        add("Income heads closed to %s" % res[:-4], [(n, x) for n, x in inc] + [(res, -ti)])
        add("Expense heads closed to %s" % res[:-4], [(res, te)] + [(n, -x) for n, x in exp])
        if self.partners:
            assert result > 0, ("a partnership's appropriation is shown for a profit", self.name)
            ap = self.appropriation(result)
            appr = "P&L Appropriation A/c"
            add("Net profit to the P&L Appropriation Account", [(res, result), (appr, -result)])
            add("Interest on capital, as the partners agreed, to the partners' accounts (out of profit only)",
                [(appr, sum(i for _, i, _ in ap))] + [(p["current"], -i) for p, i, _ in ap])
            add("Share of profit to the partners' accounts (%s)" % " : ".join(str(p["share"]) for p in self.partners),
                [(appr, sum(x for _, _, x in ap))] + [(p["current"], -x) for p, _, x in ap])
        else:
            own = self.owner_account()
            assert own, self.name
            word = {"business": ("Net profit added to own money", "Net loss taken from own money"), "property": ("Net profit added to own money", "Net loss taken from own money"),
                    "household": ("Saving for the year added to own money", "Spent more than came in — taken from own money"),
                    "npo": ("Surplus added to the General Fund", "Deficit taken from the General Fund")}[self.style]
            add(word[0] if result >= 0 else word[1], [(res, result), (own, -result)])
            for kind, note in (("drawings", "Drawings closed to own money"), ("shareout", "Business income shared out, closed to own money (not a cost)")):
                dr = [(n, self.accounts[n].closing) for n in self.order if self.accounts[n].kind == kind and self.accounts[n].closing != 0]
                add(note, [(own, sum(x for _, x in dr))] + [(n, -x) for n, x in dr])
        self._close = out
        return out

    def close_posts(self, name):
        """The close entries' lines on one account: [(entry id, note, signed amount, the other accounts)]."""
        rows = []
        for vid, note, lines in self.close_entries():
            for n, a in lines:
                if n == name:
                    others = [m for m, b in lines if (b > 0) != (a > 0)]
                    rows.append((vid, note, a, others))
        return rows

    def post_close_balances(self):
        """Every account's balance after the year close; income, expense, drawings and the result account stand at nil."""
        bal = {n: self.accounts[n].closing for n in self.order}
        pseudo = {}
        for _, _, lines in self.close_entries():
            for n, a in lines:
                if n in bal:
                    bal[n] += a
                else:
                    pseudo[n] = pseudo.get(n, 0) + a
        assert all(v == 0 for v in pseudo.values()), ("the result account is not closed", self.name, pseudo)
        for n in self.order:
            if self.accounts[n].kind in ("income", "expense", "drawings", "shareout"):
                assert bal[n] == 0, ("not closed", self.name, n, bal[n])
        return bal


class Case(object):
    """One printed file: one book, or several books of one person or family."""

    def __init__(self, slug, title, real_names=True):
        self.slug = slug
        self.title = title
        self.real_names = real_names
        self.intro = []
        self.people = []
        self.books = []
        self.summary_note = ""          # the line under the family summary (computed result not in the other book)
        self.demonstrates = []          # README bullets (technical)


# ---------------------------------------------------------------------------------------------
# markdown helpers
# ---------------------------------------------------------------------------------------------

def table(headers, aligns, rows):
    sep = {"l": ":---", "r": "---:", "c": ":---:"}
    out = ["| " + " | ".join(headers) + " |", "|" + "|".join(sep[a] for a in aligns) + "|"]
    for r in rows:
        out.append("| " + " | ".join(str(c) for c in r) + " |")
    return out


def bold(s):
    return "**%s**" % s


def side_of(bal):
    return "Dr" if bal > 0 else ("Cr" if bal < 0 else "—")


def amt_side(bal):
    return fmt(abs(bal), show_zero=True) + ((" " + side_of(bal)) if bal else "")


# ---------------------------------------------------------------------------------------------
# report sections (every book of a file prints all five)
# ---------------------------------------------------------------------------------------------

def head_line(name, period):
    """The head every report carries (O-20-1, O-20-2): the book, the date or period, the basis, Year closed, Made on (a pinned date)."""
    return "*%s · %s · %s · Year closed · Made on %s*" % (name, period, BASIS_LINE, MADE_ON)


def side_cell(lines):
    """A Day-Book style cell: the account alone when it is the only one on its side, else each account with its amount."""
    return lines[0][0] if len(lines) == 1 else "<br>".join("%s ₹%s" % (n, fmt(a)) for n, a in lines)


def sec_chart(b):
    out = ["### 1. Accounts and opening balances", "", head_line(b.name, "opening balances on %s" % fdate(FY_START)), ""]
    out.append("Every account used in FY 2025-26, with its balance on 01 Apr 2025 brought forward from last year. %s Income and expense accounts start the year at zero." % (
        b.chart_note or "The %s opening is the balancing figure, so the Dr and Cr totals agree." % b.own_word.lower()))
    out.append("")
    rows = []
    tdr = tcr = 0
    for i, n in enumerate(b.order, 1):
        a = b.accounts[n]
        odr = a.opening if a.opening > 0 else 0
        ocr = -a.opening if a.opening < 0 else 0
        tdr += odr
        tcr += ocr
        rows.append([i, n, a.group, a.label, fmt(odr), fmt(ocr)])
    rows.append(["", bold("Total of opening balances"), "", "", bold(fmt(tdr, show_zero=True)), bold(fmt(tcr, show_zero=True))])
    assert tdr == tcr
    out += table(["#", "Account", "Type", "What it is", "Opening balance (Dr) ₹", "Opening balance (Cr) ₹"], ["r", "l", "l", "l", "r", "r"], rows)
    out.append("")
    out += foot_notes(b, things=shows_things_owned(b, FY_START - dt.timedelta(days=1)))
    return out


def close_row(b, acct, cp, bal):
    """One ledger row for a year-close entry (31 Mar 2026): returns (row text, new balance, dr, cr)."""
    vid, note, a, others = cp
    part = ("To " if a > 0 else "By ") + " / ".join(others)
    nb = bal + a
    return ("| %s | %s | %s<br><em>%s</em> | %s | %s | %s | %s |" % (fdate(FY_END), vid, part, note, fmt(a if a > 0 else 0), fmt(-a if a < 0 else 0),
                                                                   fmt(abs(nb), show_zero=True), side_of(nb)), nb, a if a > 0 else 0, -a if a < 0 else 0)


def ledger_table(b, acct, rows, start, end, bf_label, cd_label, bd_label, show_bd=True, total_label="Total for the year", narr=False, close=False):
    dr_l, cr_l = acct.cols
    out = table(["Date", "No.", "Particulars", dr_l, cr_l, "Balance ₹", "Side"], ["l", "l", "l", "r", "r", "r", "c"], [])
    opening = b.balance_at(acct.name, start - dt.timedelta(days=1)) if acct.is_bs else 0
    tdr = tcr = 0
    if acct.is_bs:
        # 04 §5.2, ADR 2026-09-24b §9: the opening balance stands in the amount column of its side, so each column adds up to the Total
        out.append("| %s |  | %s | %s | %s | %s | %s |" % (fdate(start), bf_label, fmt(opening if opening > 0 else 0), fmt(-opening if opening < 0 else 0),
                                                         fmt(abs(opening), show_zero=True), side_of(opening)))
    bal = opening
    for r in rows:
        bal += r["dr"] - r["cr"]
        tdr += r["dr"]
        tcr += r["cr"]
        part = r["part"] + ("<br><em>%s</em>" % r["vch"].narration if narr else "")
        out.append("| %s | %s | %s | %s | %s | %s | %s |" % (fdate(r["date"]), r["vid"], part, fmt(r["dr"]), fmt(r["cr"]),
                                                           fmt(abs(bal), show_zero=True), side_of(bal)))
    if close and acct.is_bs:
        for cp in b.close_posts(acct.name):
            line, bal, cd, cc = close_row(b, acct, cp, bal)
            out.append(line)
            tdr += cd
            tcr += cc
    closing = bal
    if acct.is_bs:
        cd_dr = -closing if closing < 0 else 0
        cd_cr = closing if closing > 0 else 0
        out.append("| %s |  | %s | %s | %s | — | — |" % (fdate(end), cd_label, fmt(cd_dr), fmt(cd_cr)))
        total = tdr + (opening if opening > 0 else 0) + cd_dr
        total2 = tcr + (-opening if opening < 0 else 0) + cd_cr
        assert total == total2, (acct.name, total, total2)
        out.append("|  |  | %s | %s | %s |  |  |" % (bold("Total"), bold(fmt(total, show_zero=True)), bold(fmt(total2, show_zero=True))))
        if show_bd:
            out.append("| %s |  | %s | %s | %s | %s | %s |" % (fdate(end + dt.timedelta(days=1)), bd_label,
                                                              fmt(closing if closing > 0 else 0), fmt(-closing if closing < 0 else 0),
                                                              fmt(abs(closing), show_zero=True), side_of(closing)))
    else:
        out.append("|  |  | %s | %s | %s | %s | %s |" % (bold(total_label), bold(fmt(tdr)), bold(fmt(tcr)),
                                                        bold(fmt(abs(closing), show_zero=True)), bold(side_of(closing))))
        if close:
            for cp in b.close_posts(acct.name):
                vid, note, a, others = cp
                out.append("| %s | %s | %s<br><em>%s</em> | %s | %s | %s | %s |" % (fdate(FY_END), vid, ("To " if a > 0 else "By ") + " / ".join(others), note,
                                                                                   fmt(a if a > 0 else 0), fmt(-a if a < 0 else 0), fmt(0, show_zero=True), "—"))
    return out, opening, tdr, tcr, closing


def statement_table(b, acct, rows, start, end):
    """04 §5.6: the opening balance with its side, every entry with its running balance, the totals of the period's entries only
    (the opening balance is not part of them), then the closing balance with its side — for a person, You will get / You will give."""
    dr_l, cr_l = acct.cols
    out = table(["Date", "No.", "Particulars", dr_l, cr_l, "Balance ₹", "Side"], ["l", "l", "l", "r", "r", "r", "c"], [])
    opening = b.balance_at(acct.name, start - dt.timedelta(days=1)) if acct.is_bs else 0
    out.append("| %s |  | Opening balance on %s | — | — | %s | %s |" % (fdate(start), fdate(start), fmt(abs(opening), show_zero=True), side_of(opening)))
    bal = opening
    tdr = tcr = 0
    for r in rows:
        bal += r["dr"] - r["cr"]
        tdr += r["dr"]
        tcr += r["cr"]
        out.append("| %s | %s | %s<br><em>%s</em> | %s | %s | %s | %s |" % (fdate(r["date"]), r["vid"], r["part"], r["vch"].narration, fmt(r["dr"]), fmt(r["cr"]),
                                                                          fmt(abs(bal), show_zero=True), side_of(bal)))
    assert bal == opening + tdr - tcr
    out.append("|  |  | %s | %s | %s |  |  |" % (bold("Total for the period"), bold(fmt(tdr, show_zero=True)), bold(fmt(tcr, show_zero=True))))
    if acct.kind == "party" and bal:
        label = "Closing balance on %s — %s" % (fdate(end), "You will get" if bal > 0 else "You will give")
    else:
        label = "Closing balance on %s" % fdate(end)
    out.append("| %s |  | %s |  |  | %s | %s |" % (fdate(end), bold(label), bold(fmt(abs(bal), show_zero=True)), bold(side_of(bal))))
    return out


def natural_line(a):
    if a.kind == "party":
        return "on the Dr side when they owe you, on the Cr side when you owe them"
    if a.kind == "link":
        return "on the Dr side when that book owes this one, on the Cr side when this book owes that one"
    if a.kind == "pcurrent":
        return "on the Cr side when the firm owes the partner, on the Dr side when the partner has taken more"
    if a.kind in ("card", "cc"):
        return "on the Cr side — what is owed to the bank"
    return "usually on the %s side" % a.natural


def sec_ledgers(b):
    out = ["### 2. Every account (ledger)", "", head_line(b.name, "%s to %s" % (fdate(FY_START), fdate(FY_END))), ""]
    out.append("One account after another: date, entry number, the other account (*To …* on the Dr side, *By …* on the Cr side) with the entry's note in small type, the amount on its side, "
               "the running balance and its side. "
               "Accounts that carry a balance open with *Opening balance b/f* and end *Closing balance c/d · Total · Opening balance b/d*, the opening and closing balances standing in the amount column of their side so that each column adds up to the Total; "
               "income and expense accounts end with their total for the year. The last rows of the heads%s and the own-money accounts are the year-close entries "
               "(numbers ending Y1, Y2 …) that the book makes itself on %s — they are listed in section 4." % (", the drawings" if has_drawings(b) else "", fdate(FY_END)))
    out.append("")
    for n in b.order:
        a = b.accounts[n]
        out.append("#### %s" % n)
        out.append("")
        if not a.rows and a.opening == 0:
            out.append("*No entries in FY 2025-26 and no opening balance.*")
            out.append("")
            continue
        rows, _, _, _, _ = ledger_table(b, a, a.rows, FY_START, FY_END, "Opening balance b/f", "Closing balance c/d", "Opening balance b/d (FY 2026-27)", narr=True, close=True)
        out += rows
        out.append("")
    out += foot_notes(b, things=any(b.accounts[n].kind == "fixed" and (b.accounts[n].rows or b.accounts[n].opening) for n in b.order))
    return out


def daybook_rows(b):
    rows = []
    for vch in b.vouchers:
        drs, crs = vch.dr_lines(), vch.cr_lines()
        dcell = drs[0][0] if len(drs) == 1 else "<br>".join("%s ₹%s" % (n, fmt(a)) for n, a in drs)
        ccell = crs[0][0] if len(crs) == 1 else "<br>".join("%s ₹%s" % (n, fmt(a)) for n, a in crs)
        moved = any(b.accounts[n].is_money for n, _ in vch.lines)
        rows.append([fdate(vch.date), vch.vid, PLAIN_VTYPE[vch.vtype] + ("" if moved else " — no money moved"), dcell, ccell, fmt(vch.amount), vch.narration])
    return rows


def sec_daybook(b):
    out = ["### 1. Day Book — every entry of the year", "", head_line(b.name, "%s to %s" % (fdate(FY_START), fdate(FY_END))), ""]
    out.append("In date order. Type: *Money in*, *Money out*, *Transfer* (between own cash, bank, card or deposit), *Gave on credit* / *Took on credit* (a khata entry with a person or shop — no money moved yet), "
               "*Advance settled* (an advance accounted for against the bills), *Paid by a partner* (a partner paid from his own pocket), *Paid by the joint family* (the family paid a household's bill), "
               "*Settled at year end* (a sub-family account squared for the year), *Paid from a fund* (one action: the cost is charged to the year and the same amount is transferred from the fund), "
               "*Interest added to a deposit* (the bank added it; no money moved), *Written off* (a balance known not to come back, charged to an expense head), "
               "*Deposit set off* (a deposit held used against what the same person owes) and *Deposit forfeited* (a deposit kept as income), *Retention released* (money a customer held back, now due), *Correction* (an earlier entry put right — its note names the entry and its date) and *Fix / Adjust* (no money moved). "
               "An entry that moves no money in or out of cash, bank, card or wallet is marked *no money moved*. An entry with more than one account on a side shows each account with its amount.")
    out.append("")
    out += table(["Date", "No.", "Type", "Debit (Dr)", "Credit (Cr)", "Amount ₹", "What happened"], ["l", "l", "l", "l", "l", "r", "l"], daybook_rows(b))
    out.append("")
    kinds = {}
    for vch in b.vouchers:
        kinds[PLAIN_VTYPE[vch.vtype]] = kinds.get(PLAIN_VTYPE[vch.vtype], 0) + 1
    out.append("*%d entries: %s.*" % (len(b.vouchers), " · ".join("%s %d" % (k, kinds[k]) for k in sorted(kinds))))
    out.append("")
    return out


def cash_book(b, names, heading):
    """04 §5.4: the Cash Book of cash and each bank account — receipts (Money in) on the left, payments (Money out) on the right, a column for each
    account on each side; a transfer between them stands on both sides. It opens with the opening balances on the Money in side (an overdrawn bank
    on the other), totals each month that had entries (the month's entries only) and gives each account's balance at the month end."""
    accts = [b.accounts[n] for n in names]
    short = {n: ("Cash" if b.accounts[n].kind == "cash" else n) for n in names}
    out = ["### %s" % heading, "", head_line(b.name, "%s to %s" % (fdate(FY_START), fdate(FY_END))), ""]
    out.append("Every receipt and every payment of cash and of the bank, with the note of each entry: money in on the left, money out on the right, a column for each. "
               "Money moved between the cash box and the bank stands on both sides — out of one, into the other. Each month that had entries ends with its totals and "
               "the balance of each; the cash balance is what the cash box must hold, the bank balance is the bank's.")
    out.append("")
    heads = ["Date", "No.", "Particulars"] + ["Money in (Dr) — %s ₹" % short[n] for n in names] + ["Money out (Cr) — %s ₹" % short[n] for n in names] + ["Balance — %s ₹" % short[n] for n in names]
    out += table(heads, ["l", "l", "l"] + ["r"] * (3 * len(names)), [])

    def bal_cell(x):
        return fmt(abs(x), show_zero=True) + (" Cr" if x < 0 else "")
    bal = {n: b.accounts[n].opening for n in names}
    out.append("| %s |  | Opening balance b/f | %s | %s | %s |" % (fdate(FY_START), " | ".join(fmt(max(bal[n], 0)) for n in names),
                                                                 " | ".join(fmt(max(-bal[n], 0)) for n in names), " | ".join(bal_cell(bal[n]) for n in names)))
    vchs = [v for v in b.vouchers if any(n in names for n, _ in v.lines)]
    for (y, m) in fy_months():
        mv = [v for v in vchs if (v.date.year, v.date.month) == (y, m)]
        if not mv:
            continue
        mdr = {n: 0 for n in names}
        mcr = {n: 0 for n in names}
        for v in mv:
            amt = {n: 0 for n in names}
            for n, x in v.lines:
                if n in names:
                    amt[n] += x
            for n in names:
                bal[n] += amt[n]
                mdr[n] += max(amt[n], 0)
                mcr[n] += max(-amt[n], 0)
            others = [(n, x) for n, x in v.lines if n not in names]
            if not others:
                part = "%s to %s" % (" / ".join(n for n in names if amt[n] < 0), " / ".join(n for n in names if amt[n] > 0))
            else:
                # as in the cash or bank ledger: only the accounts on the other side of the money that moved (an advance recovered, a lender's part, a fund's transfer stay in the note)
                moved = [n for n in names if amt[n]]
                net = sum(amt[n] for n in names)
                part = ([r["part"] for r in b.accounts[moved[0]].rows if r["vid"] == v.vid][0] if len(moved) == 1 else
                        " / ".join(("To " if net > 0 else "By ") + n for n, x in others if (x < 0) == (net > 0)))
            out.append("| %s | %s | %s<br><em>%s</em> | %s | %s | %s |" % (fdate(v.date), v.vid, part, v.narration, " | ".join(fmt(max(amt[n], 0)) for n in names),
                                                                        " | ".join(fmt(max(-amt[n], 0)) for n in names), " | ".join(bal_cell(bal[n]) for n in names)))
        out.append("| %s |  | %s | %s | %s | %s |" % (fdate(month_end(y, m)), bold("Month total — %s · closing balance" % month_name(y, m)),
                                                     " | ".join(bold(fmt(mdr[n], show_zero=True)) for n in names), " | ".join(bold(fmt(mcr[n], show_zero=True)) for n in names),
                                                     " | ".join(bold(bal_cell(bal[n])) for n in names)))
    for a in accts:
        assert bal[a.name] == a.closing, (b.name, a.name)
    out.append("")
    out.append("*On 31 Mar 2026: %s — the same as the closing balances in the ledgers of the printed book (its section 2).*" % " · ".join("%s ₹%s" % (n, bal_cell(bal[n])) for n in names))
    out.append("")
    return out


def sec_bank_extract(b, num):
    bank, (y, m) = b.bank_extract
    a = b.accounts[bank]
    out = ["#### 3.%d Bank statement → entries — %s, %s" % (num, bank, month_name(y, m)), "", head_line(b.name, month_name(y, m)), ""]
    out.append("How the book is kept from the bank: every line of the month's statement is answered with one question — where did the money come from, or where did it go? "
               "The bank's running balance is the balance of %s in the books." % bank)
    out.append("")
    bal = b.balance_at(bank, dt.date(y, m, 1) - dt.timedelta(days=1))
    rows = [[fdate(dt.date(y, m, 1)), "Opening balance", "", "", fmt(abs(bal), show_zero=True) + (" Cr" if bal < 0 else ""), "", ""]]
    for r in a.rows:
        if (r["date"].year, r["date"].month) != (y, m):
            continue
        vch = r["vch"]
        bal += r["dr"] - r["cr"]
        others = [(n, x) for n, x in vch.lines if n != bank]
        classified = others[0][0] if len(others) == 1 else "<br>".join("%s ₹%s" % (n, fmt(abs(x))) for n, x in others)
        rows.append([fdate(r["date"]), vch.stmt or vch.narration, fmt(r["cr"]), fmt(r["dr"]), fmt(abs(bal), show_zero=True) + (" Cr" if bal < 0 else ""), classified, vch.vid])
    rows.append([fdate(month_end(y, m)), bold("Closing balance"), "", "", bold(fmt(abs(bal), show_zero=True) + (" Cr" if bal < 0 else "")), "", ""])
    out += table(["Date", "As the bank printed it", "Withdrawal ₹", "Deposit ₹", "Balance ₹", "Which account", "No."], ["l", "l", "r", "r", "r", "l", "l"], rows)
    out.append("")
    return out


def sec_books(b):
    """The export: the Day Book and each Cash Book of one book, with notes."""
    out = sec_daybook(b)
    names = [n for n in b.order if b.accounts[n].kind == "cash"] + [n for n in b.order if b.accounts[n].kind == "bank"]
    out += cash_book(b, names, "2. Cash Book — %s" % " and ".join(names))
    return out


def fifo_open_items(a, upto):
    """Open items on `upto`: the later side's amounts settle the earlier side's oldest items first."""
    items = []
    if a.opening:
        items.append([FY_START, a.opening])
    for r in a.rows:
        if r["date"] > upto:
            break
        amt = r["dr"] - r["cr"]
        while amt and items and (items[0][1] > 0) != (amt > 0):
            take = min(abs(amt), abs(items[0][1]))
            items[0][1] += take if items[0][1] < 0 else -take
            amt += take if amt < 0 else -take
            if items[0][1] == 0:
                items.pop(0)
        if amt:
            items.append([r["date"], amt])
    return items


def sec_ageing(b, num):
    out = ["#### 3.%d You will get / You will give — who owes what, and since when (on %s)" % (num, fdate(FY_END)), "", head_line(b.name, "on %s" % fdate(FY_END)), ""]
    out.append("Every person or shop account with a balance, read straight from its own ledger, split by how long the amount has been open: money received settles the oldest amount first.")
    out.append("")
    rows = []
    tot = {1: [0, 0, 0, 0], -1: [0, 0, 0, 0]}
    for n in b.order:
        a = b.accounts[n]
        if a.kind != "party":
            continue
        bal = b.balance_at(n, FY_END)
        if bal == 0:
            continue
        items = fifo_open_items(a, FY_END)
        assert sum(x for _, x in items) == bal, (n, items, bal)
        bk = [0, 0, 0]
        for d0, x in items:
            days = (FY_END - d0).days
            bk[0 if days <= 30 else (1 if days <= 90 else 2)] += abs(x)
        sg = 1 if bal > 0 else -1
        t = tot[sg]
        t[0] += abs(bal)
        for i in range(3):
            t[i + 1] += bk[i]
        rows.append((sg, [n, "You will get (Dr)" if sg > 0 else "You will give (Cr)", fmt(abs(bal)), fmt(bk[0]), fmt(bk[1]), fmt(bk[2]), fdate(items[0][0])]))
    body = [r for sg, r in rows if sg > 0] + [[bold("Total you will get"), "", bold(fmt(tot[1][0], show_zero=True)), bold(fmt(tot[1][1])), bold(fmt(tot[1][2])), bold(fmt(tot[1][3])), ""]]
    body += [r for sg, r in rows if sg < 0] + [[bold("Total you will give"), "", bold(fmt(tot[-1][0], show_zero=True)), bold(fmt(tot[-1][1])), bold(fmt(tot[-1][2])), bold(fmt(tot[-1][3])), ""]]
    out += table(["Person / shop", "Side", "Balance ₹", "Up to 30 days ₹", "31–90 days ₹", "Over 90 days ₹", "Open since"], ["l", "l", "r", "r", "r", "r", "l"], body)
    out.append("")
    return out


def place(a, bal):
    """Where a balance-sheet account sits in the position: 'have', 'get' or 'give' (own-money accounts are not placed)."""
    if a.kind in HAVE_KINDS:
        return "have" if bal >= 0 else "give"
    if a.kind in ("party", "link"):
        return "get" if bal > 0 else "give"
    if a.kind == "fund":
        return "fund"                         # money held for a purpose: with the own money, beside the General Fund (O-02-1)
    return "give" if bal <= 0 else "have"     # loan, deposit


def shows_things_owned(b, date):
    return any(b.accounts[n].kind == "fixed" and b.balance_at(n, date) != 0 for n in b.order)


def position_table(b, date, heading):
    out = ["#### %s" % heading, "", head_line(b.name, "on %s" % fdate(date)), ""]
    funds = any(b.accounts[n].kind == "fund" and b.balance_at(n, date) != 0 for n in b.order)
    own = b.own_word if b.style == "npo" else b.own_word.lower()     # the General Fund is the account's name
    out.append("Every account with a balance on %s, placed on the side its balance falls. What I have plus what I will get, less what I will give%s, is the %s." % (fdate(date), " and less the funds held for a purpose" if funds else "", own))
    out.append("")
    groups = {"have": [], "get": [], "give": [], "fund": []}
    for n in b.order:
        a = b.accounts[n]
        if not a.is_bs or a.is_equity:
            continue
        bal = b.balance_at(n, date)
        if bal == 0:
            continue
        groups[place(a, bal)].append((n, abs(bal)))
    rows = []
    th = sum(x for _, x in groups["have"])
    to = sum(x for _, x in groups["get"])
    tw = sum(x for _, x in groups["give"])
    rows += [["What I have", n, fmt(x, show_zero=True), ""] for n, x in groups["have"]]
    rows.append(["", bold("Total — what I have"), bold(fmt(th, show_zero=True)), ""])
    rows += [["What I will get", n, fmt(x, show_zero=True), ""] for n, x in groups["get"]]
    rows.append(["", bold("Total — what I will get"), bold(fmt(to, show_zero=True)), ""])
    rows += [["What I will give", n, "", fmt(x, show_zero=True)] for n, x in groups["give"]]
    rows.append(["", bold("Total — what I will give"), "", bold(fmt(tw, show_zero=True))])
    tf = sum(x for _, x in groups["fund"])
    if groups["fund"]:
        rows += [["Funds held for a purpose", n, "", fmt(x, show_zero=True)] for n, x in groups["fund"]]
        rows.append(["", bold("Total — funds"), "", bold(fmt(tf, show_zero=True))])
    net = th + to - tw - tf
    rows.append(["", bold("%s = have + will get − will give%s" % (b.own_word, " − funds" if groups["fund"] else "")), bold(fmt(abs(net), show_zero=True) + (" Dr" if net < 0 else "")), ""])
    out += table(["", "Account", "Have / will get ₹", "Will give / funds ₹"], ["l", "l", "r", "r"], rows)
    out.append("")
    start, put, taken = b.equity_parts(date)
    inc, exp = b.result_to(date)
    result = inc - exp
    # the result first (income − spent), then the own money (start + put in − taken out ± the result), each chain adding up to its own line (04 §6.3)
    mk = [["Income so far", fmt(inc, show_zero=True)]]
    mk.append(["− Spent so far", fmt(exp, show_zero=True)])
    mk.append([bold("= Result so far (%s)" % (result_word(b, result))), bold(fmt(abs(result), show_zero=True))])
    mk.append(["%s at the start of the year (01 Apr 2025)" % b.own_word, fmt(start, show_zero=True)])
    mk.append(["+ Put in so far" + b.put_note, fmt(put, show_zero=True)])
    mk.append(["− Taken out so far" + b.taken_note, fmt(taken, show_zero=True)])
    mk.append(["%s Result so far (%s)" % ("+" if result >= 0 else "−", result_word(b, result)), fmt(abs(result), show_zero=True)])
    own = start + put - taken + result
    mk.append([bold("= %s now" % b.own_word), bold(fmt(own, show_zero=True))])
    assert own == net, ("position make-up", b.name, own, net, date)
    out += table(["How it is made up", "₹"], ["l", "r"], mk)
    out.append("")
    out += foot_notes(b, things=shows_things_owned(b, date), stock=True, stakes=shows_stakes(b, date), date=date)
    return out


def shows_stakes(b, date):
    """How many businesses a position on this date shows at the money put in (04 §4.3, 03 §1.9)."""
    return sum(1 for n in b.order if b.accounts[n].kind == "stake" and b.balance_at(n, date) != 0)


def built_to(b, date):
    """The building's cost charged to expenditure up to a date (the year-close entries are not vouchers)."""
    head = b.construction[0]
    return sum(a for v in b.vouchers if v.date <= date for n, a in v.lines if n == head and a > 0)


def foot_notes(b, things=False, stock=False, stakes=0, date=None):
    """04 §4.3: the standing notes a report prints at its foot — things owned at cost, and (a book that sells goods with no closing stock) the no-stock line
    on every report that gives the result or works it into own money (02 §6.2); a trust that charges a building to expenditure prints the construction
    line on the same reports (passed `date`), with the cost to that date (02 §5.8, 03 §5.7)."""
    out = []
    if date and b.construction and built_to(b, date):
        out += [BUILD_LINE % (b.construction[1], fmt(built_to(b, date))), ""]
    if stakes:
        out += [STAKE_LINE if stakes == 1 else STAKES_LINE, ""]
    if things:
        out += [COST_LINE, ""]
    if stock and b.stock_line:
        out += [STOCK_LINE, ""]
    return out


def result_word(b, result):
    if b.style == "npo":
        return "surplus" if result >= 0 else "deficit"
    if b.style == "household":
        return "saving" if result >= 0 else "spent more than came in"
    return "profit" if result >= 0 else "loss"


def sec_statements(b):
    out = ["### 3. Positions and statements during the year", ""]
    out += position_table(b, MID_YEAR, "3.1 Full position on %s — what I have, what I will get, what I will give" % fdate(MID_YEAR))
    out += position_table(b, FY_END, "3.2 Full position on %s — year end" % fdate(FY_END))
    y, m = STATEMENT_MONTH
    start, end = dt.date(y, m, 1), month_end(y, m)
    out.append("#### 3.3 One month — %s, account by account" % month_name(y, m))
    out.append("")
    out.append(head_line(b.name, month_name(y, m)))
    out.append("")
    out.append("Every account's balance on %s, what went on its Dr side and its Cr side during the month, and its balance on %s. The month's entries are in each account's ledger." % (fdate(start), fdate(end)))
    out.append("")
    rows = []
    tdr = tcr = 0
    for n in b.order:
        a = b.accounts[n]
        ob = b.balance_at(n, start - dt.timedelta(days=1))
        d, c = b.movement(n, start, end)
        cb = ob + d - c
        if ob == 0 and d == 0 and c == 0:
            continue
        tdr += d
        tcr += c
        rows.append([n, fmt(abs(ob), show_zero=True), side_of(ob), fmt(d), fmt(c), fmt(abs(cb), show_zero=True), side_of(cb)])
    rows.append([bold("Total of the month's entries"), "", "", bold(fmt(tdr, show_zero=True)), bold(fmt(tcr, show_zero=True)), "", ""])
    assert tdr == tcr
    out += table(["Account", "Opening %s ₹" % fdate(start), "Side", "Dr side in month ₹", "Cr side in month ₹", "Closing %s ₹" % fdate(end), "Side"],
                 ["l", "r", "c", "r", "r", "r", "c"], rows)
    out.append("")
    inc = sum(b.movement(n, start, end)[1] - b.movement(n, start, end)[0] for n in b.order if b.accounts[n].kind == "income")
    exp = sum(b.movement(n, start, end)[0] - b.movement(n, start, end)[1] for n in b.order if b.accounts[n].kind == "expense")
    out.append("*%s in brief: income ₹%s · spent ₹%s · %s ₹%s.*" % (month_name(y, m), fmt(inc, show_zero=True), fmt(exp, show_zero=True), result_word(b, inc - exp), fmt(abs(inc - exp), show_zero=True)))
    out.append("")
    out += foot_notes(b, things=any(b.accounts[n].kind == "fixed" and (b.balance_at(n, start - dt.timedelta(days=1)) or b.movement(n, start, end) != (0, 0)) for n in b.order), stock=True, date=end)
    name, s, e, why = b.custom
    a = b.accounts[name]
    out.append("#### 3.4 One account for a chosen period — %s, %s to %s" % (name, fdate(s), fdate(e)))
    out.append("")
    out.append(head_line(b.name + " — " + name, "%s to %s" % (fdate(s), fdate(e))))
    out.append("")
    out.append(why + " This is the statement the user shares.")
    out.append("")
    rows = [r for r in a.rows if s <= r["date"] <= e]
    out += statement_table(b, a, rows, s, e)
    out.append("")
    out += sec_ageing(b, 5)
    if b.bank_extract:
        out += sec_bank_extract(b, 6)
    return out


def sec_closing(b):
    out = ["### 4. Year end — FY 2025-26", ""]
    out.append("#### 4.1 Trial Balance on 31 Mar 2026 — closing balances only")
    out.append("")
    out.append(head_line(b.name, "on %s" % fdate(FY_END)))
    out.append("")
    out.append("The closing balance of every account after the last entry of the year (before the year-close entries below), Dr balances in one column and Cr balances in the other. The two totals must agree. "
               "Each account's opening, movements and closing are in its own ledger.")
    out.append("")
    rows, zero = [], []
    tdr = tcr = 0
    for n in b.order:
        a = b.accounts[n]
        if a.closing == 0:
            if a.rows or a.opening:
                zero.append(n)
            continue
        d = a.closing if a.closing > 0 else 0
        c = -a.closing if a.closing < 0 else 0
        tdr += d
        tcr += c
        rows.append([n, fmt(d), fmt(c)])
    rows.append([bold("TOTALS"), bold(fmt(tdr)), bold(fmt(tcr))])
    assert tdr == tcr
    out += table(["Account", "Dr balance ₹", "Cr balance ₹"], ["l", "r", "r"], rows)
    out.append("")
    out.append("**Checked: Dr ₹%s = Cr ₹%s. The books balance.**" % (fmt(tdr), fmt(tcr)))
    if zero:
        out.append("")
        out.append("*Accounts with entries in the year but nil on 31 Mar 2026 (not listed above): %s.*" % "; ".join(zero))
    out.append("")
    out += foot_notes(b, things=shows_things_owned(b, FY_END))
    num = 2
    if b.style == "npo":
        out += sec_npo_rp(b, num)
        num = 3
    ti = sum(-b.accounts[n].closing for n in b.order if b.accounts[n].kind == "income")
    te = sum(b.accounts[n].closing for n in b.order if b.accounts[n].kind == "expense")
    result = ti - te
    has_funds = any(b.accounts[n].kind == "fund" for n in b.order)
    n_stmt = num
    n_fund = num + 1 if has_funds else None
    n_next = num + 1 + (1 if has_funds else 0)
    n_appr = n_next if b.partners else None
    n_close = n_next + (1 if b.partners else 0)
    n_bs = n_close + 1
    n_cf = n_bs + 1
    out.append("#### 4.%d %s for FY 2025-26" % (n_stmt, b.pl_title))
    out.append("")
    out.append(head_line(b.name, "FY 2025-26"))
    out.append("")
    out.append("Every income and expense account's **total for the year** — the *Total for the year* line of its ledger — with the number of entries that made it up. "
               "Only what was really received, spent or charged on credit during the year; nothing is added or spread at the year end.")
    if b.pl_note:
        out.append(b.pl_note)
    out.append("")
    words = {"business": ("Net profit — closed to own money (4.%d)" % n_close, "Net loss — taken from own money (4.%d)" % n_close),
             "property": ("Net profit — closed to own money (4.%d)" % n_close, "Net loss — taken from own money (4.%d)" % n_close),
             "household": ("Saving for the year — closed to own money (4.%d)" % n_close, "Spent more than came in — taken from own money (4.%d)" % n_close),
             "npo": ("Surplus (income more than spent) — closed to the General Fund (4.%d)" % n_close, "Deficit (spent more than income) — taken from the General Fund (4.%d)" % n_close)}[b.style]
    if b.partners:
        words = ("Net profit — carried to the P&L Appropriation (4.%d)" % n_appr, "Net loss — carried to the P&L Appropriation (4.%d)" % n_appr)
    rows = []
    for n in b.order:
        a = b.accounts[n]
        if a.kind == "expense":
            rows.append(["To " + n, len(a.rows), fmt(a.closing, show_zero=True), "—"])
    for n in b.order:
        a = b.accounts[n]
        if a.kind == "income":
            rows.append(["By " + n, len(a.rows), "—", fmt(-a.closing, show_zero=True)])
    rows.append([bold("Total of the heads for the year"), "", bold(fmt(te, show_zero=True)), bold(fmt(ti, show_zero=True))])
    if result >= 0:
        rows.append(["To " + words[0], "", fmt(result, show_zero=True), "—"])
    else:
        rows.append(["By " + words[1], "", "—", fmt(-result, show_zero=True)])
    rows.append([bold("Total"), "", bold(fmt(max(te, ti))), bold(fmt(max(te, ti)))])
    out += table(["Particulars", "Entries", "Spent / expenses (Dr) ₹", "Income (Cr) ₹"], ["l", "r", "r", "r"], rows)
    out.append("")
    out.append("**FY 2025-26: income ₹%s · spent ₹%s · %s ₹%s.**" % (fmt(ti, show_zero=True), fmt(te, show_zero=True), result_word(b, result), fmt(abs(result), show_zero=True)))
    out.append("")
    out += foot_notes(b, stock=True, date=FY_END)
    if has_funds:
        out += sec_fund_statements(b, n_fund)
    if b.partners:
        out += sec_appropriation(b, result, n_appr, n_close)
    out += sec_close_entries(b, n_close)
    out += sec_balance_sheet(b, result, n_bs)
    out += sec_carry_forward(b, n_cf)
    return out


def sec_fund_statements(b, num):
    out = ["#### 4.%d Each fund — its year" % num, "", head_line(b.name, "FY 2025-26"), ""]
    out.append("A fund holds money given for one purpose. Gifts for it and the interest its deposit earns are added to it; what is spent for the purpose is charged to Income & Expenditure like any other cost, "
               "and the same amount is moved out of the fund as one action (*paid from the fund*), so the fund's own result stays nil. What is left is money held for that purpose, not free money.")
    out.append("")
    for n in [x for x in b.order if b.accounts[x].kind == "fund"]:
        a = b.accounts[n]
        out.append("**%s**" % n)
        out.append("")
        lines, _, _, _, _ = ledger_table(b, a, a.rows, FY_START, FY_END, "Opening balance b/f", "Closing balance c/d", "", show_bd=False, narr=True)
        out += lines
        out.append("")
    return out


def sec_close_entries(b, num):
    res = b.result_name()
    out = ["#### 4.%d Year close — the entries the book makes itself on %s" % (num, fdate(FY_END)), "", head_line(b.name, "year ended %s" % fdate(FY_END)), ""]
    own = "the General Fund" if b.style == "npo" else ("the partners' accounts, through the P&L Appropriation Account" if b.partners else "own money")
    dw = any(b.accounts[n].kind in ("drawings", "shareout") for n in b.order)
    out.append("Nobody types these. When the year is closed the book itself closes every income head and every expense head to **%s**, and then the result%s to %s. "
               "After them every income head, every expense head%s and %s stand at nil, and the ledgers above show each entry on its last row." % (
                   res[:-4], " and the drawings" if dw else "", own, ", the drawings" if dw else "", res[:-4]))
    out.append("")
    rows = []
    for vid, note, lines in b.close_entries():
        drs = [(n, a) for n, a in lines if a > 0]
        crs = [(n, -a) for n, a in lines if a < 0]
        rows.append([vid, fdate(FY_END), note, side_cell(drs), side_cell(crs), fmt(sum(a for _, a in drs))])
    out += table(["No.", "Date", "What the book does", "Debit (Dr)", "Credit (Cr)", "Amount ₹"], ["l", "l", "l", "l", "l", "r"], rows)
    out.append("")
    b.post_close_balances()
    return out


def sec_appropriation(b, result, num, close_num):
    out = ["#### 4.%d Profit & Loss Appropriation Account for FY 2025-26" % num, "", head_line(b.name, "FY 2025-26"), ""]
    ioc = [p for p in b.partners if p.get("ioc_bp")]
    ratio = " : ".join(str(p["share"]) for p in b.partners)
    if ioc:
        how = "interest on capital at %s%% a year on each partner's fixed capital first (the partners agreed it, and it is allowed only out of profit), then the rest in the ratio %s" % ((Decimal(ioc[0]["ioc_bp"]) / 100).normalize(), ratio)
    else:
        how = "no interest on capital is added (the partners did not agree it); the whole profit is shared in the ratio %s" % ratio
    out.append("How the year's profit is divided among the partners, as their agreement says: %s. The book posts this account at the year close and adds each partner's part to his account — entries in 4.%d." % (how, close_num))
    out.append("")
    rows = []
    weights = sum(p["share"] for p in b.partners)
    ap = b.appropriation(result)
    for p, i, s in ap:
        if p.get("ioc_bp"):
            rows.append(["To Interest on capital — %s" % p["name"], "%s%% on ₹%s" % ((Decimal(p["ioc_bp"]) / 100).normalize(), fmt(-b.accounts[p["capital"]].closing)), fmt(i, show_zero=True), "—"])
    for p, i, s in ap:
        rows.append(["To Share of profit — %s" % p["name"], "%d of %d" % (p["share"], weights), fmt(s, show_zero=True), "—"])
    rows.append(["By Net profit for the year (4.%d)" % (num - 1), "", "—", fmt(result, show_zero=True)])
    rows.append([bold("Total"), "", bold(fmt(result)), bold(fmt(result))])
    out += table(["Particulars", "Basis", "Dr ₹", "Cr ₹"], ["l", "l", "r", "r"], rows)
    out.append("")
    return out


def sec_npo_rp(b, num):
    out = ["#### 4.%d Receipts & Payments Account for FY 2025-26" % num, "", head_line(b.name, "FY 2025-26"), ""]
    out.append("The cash book and the bank together: opening cash and bank, everything received and paid by account (things bought included), closing cash and bank. "
               "Money moved between own cash, gollak and bank is neither a receipt nor a payment and is left out; a cost paid from a fund is a payment of the cost.")
    out.append("")
    receipts, payments = {}, {}
    for vch in b.vouchers:
        if vch.vtype == "Contra" or vch.vtype.startswith("Journal"):
            continue
        if vch.vtype == "Payment (from a fund)":
            for n, a in vch.lines:
                if a > 0 and b.accounts[n].kind in ("expense", "fixed"):
                    payments[n] = payments.get(n, 0) + a
            continue
        for n, a in vch.lines:
            if b.accounts[n].is_money:
                continue
            assert vch.vtype in ("Receipt", "Payment") and (a > 0 or b.accounts[n].kind not in ("advance", "loan")), ("R&P entry shape", vch.vid)
            if a < 0:
                receipts[n] = receipts.get(n, 0) - a
            else:
                payments[n] = payments.get(n, 0) + a
    money = [n for n in b.order if b.accounts[n].is_money]
    left = [("To Opening balance — " + n, b.accounts[n].opening) for n in money] + [("To " + n, receipts[n]) for n in b.order if n in receipts]
    right = [("By " + n, payments[n]) for n in b.order if n in payments] + [("By Closing balance — " + n, b.accounts[n].closing) for n in money]
    tr, tp = sum(x for _, x in left), sum(x for _, x in right)
    assert tr == tp, ("R&P", tr, tp)
    # two sides, as the textbooks print it (04 §6.7): receipts on the left, payments on the right, totals level at the foot
    rows = []
    for k in range(max(len(left), len(right))):
        l = left[k] if k < len(left) else ("", None)
        r = right[k] if k < len(right) else ("", None)
        rows.append([l[0], "" if l[1] is None else fmt(l[1], show_zero=True), r[0], "" if r[1] is None else fmt(r[1], show_zero=True)])
    rows.append([bold("Total"), bold(fmt(tr)), bold("Total"), bold(fmt(tp))])
    out += table(["Receipts", "₹", "Payments", "₹"], ["l", "r", "l", "r"], rows)
    out.append("")
    return out


def sec_balance_sheet(b, result, num):
    out = ["#### 4.%d Full position on 31 Mar 2026 (Balance Sheet)" % num, "", head_line(b.name, "on %s, after the year close" % fdate(FY_END)), ""]
    liab_rows, asset_rows, fund_rows = [], [], []
    tl = ta = 0
    for n in b.order:
        a = b.accounts[n]
        if not a.is_bs or a.is_equity or a.closing == 0:
            continue
        bal = a.closing
        if place(a, bal) in ("have", "get"):
            asset_rows.append([n, fmt(abs(bal), show_zero=True)])
            ta += abs(bal)
        elif place(a, bal) == "fund":
            fund_rows.append([n, fmt(-bal, show_zero=True)])
            tl += -bal
        else:
            liab_rows.append([n, fmt(-bal, show_zero=True)])
            tl += -bal
    start, put, taken = b.equity_parts(FY_END)
    own_close = start + put - taken + result
    pcb = b.post_close_balances()
    assert -sum(pcb[n] for n in b.order if b.accounts[n].is_equity) == own_close, ("post-close own money", b.name)
    eq_rows = []
    if b.partners:
        out.append("**The partners' accounts at the year end**")
        out.append("")
        prow = []
        ap = b.appropriation(result)
        for p, i, s in ap:
            # 04 §6.5: for each account of each partner, the year — opening, put in, interest on capital, share of profit, drawings, closing
            cap = -b.accounts[p["capital"]].closing if p.get("capital") else 0
            for n, close_cr in ((p["capital"], (0, 0)), (p["current"], (i, s))) if p.get("capital") else ((p["current"], (i, s)),):
                a = b.accounts[n]
                taken, put = b.movement(n, FY_START, FY_END)
                after = -a.closing + sum(close_cr)
                assert -pcb[n] == after and a.opening + taken - put == a.closing, ("partner's account for the year", n)
                prow.append([p["name"], "Capital" if n == p.get("capital") else "Current" if p.get("capital") else "Partner's account", amt_side(a.opening),
                             fmt(put), fmt(close_cr[0]), fmt(close_cr[1]), fmt(taken), amt_side(-after)])
            after = -b.accounts[p["current"]].closing + i + s
            eq_rows.append(["%s — %s at the end" % (p["name"], "capital and current account" if p.get("capital") else "partner's account"), fmt(cap + after, show_zero=True)])
        out += table(["Partner", "Account", "Opening ₹", "+ Put in ₹", "+ Interest on capital ₹", "+ Share of profit ₹", "− Drawings ₹", "Closing ₹"],
                     ["l", "l", "r", "r", "r", "r", "r", "r"], prow)
        out.append("")
        assert sum(int_or(r[1]) for r in eq_rows) == own_close
    else:
        label = b.own_word
        eq_rows.append([label + " — at the start, 01 Apr 2025", fmt(start, show_zero=True)])
        eq_rows.append(["Add: put in during the year" + b.put_note, fmt(put, show_zero=True)])
        eq_rows.append(["Less: taken out during the year" + b.taken_note, fmt(taken, show_zero=True)])
        eq_rows.append(["%s: %s for the year" % ("Add" if result >= 0 else "Less", result_word(b, result)), fmt(abs(result), show_zero=True)])
        eq_rows.append([bold(label + " — at the end, 31 Mar 2026"), bold(fmt(own_close, show_zero=True))])
    total_l = tl + own_close
    assert total_l == ta, ("balance sheet", b.name, total_l, ta)
    out.append("**Own money%s, and what I will give**" % (", funds" if fund_rows else ""))
    out.append("")
    out += table(["Particulars", "₹"], ["l", "r"], eq_rows + fund_rows + liab_rows + [[bold("Total"), bold(fmt(total_l, show_zero=True))]])
    out.append("")
    out.append("**What I have and will get**")
    out.append("")
    out += table(["Particulars", "₹"], ["l", "r"], asset_rows + [[bold("Total"), bold(fmt(ta, show_zero=True))]])
    out.append("")
    out.append("**Both sides ₹%s. The books balance.**" % fmt(ta, show_zero=True))
    out.append("")
    if b.assets_note:
        out.append(b.assets_note)
        out.append("")
    out += foot_notes(b, things=shows_things_owned(b, FY_END), stock=True, stakes=shows_stakes(b, FY_END), date=FY_END)
    b.counts["own_close"] = own_close
    b.counts["result"] = result
    return out


def int_or(cell):
    s = cell.replace("**", "").replace(",", "")
    neg = s.startswith("−")
    s = s.lstrip("−")
    r, _, p = s.partition(".")
    v = int(r) * 100 + (int(p) if p else 0)
    return -v if neg else v


def carry_rows(b):
    """(label, group, signed balance) of every account that opens FY 2026-27 with a balance — after the year close.
    A partner's capital and current account each carry their own balance, as their ledgers do (03 §2.2, 04 §2.6)."""
    pcb = b.post_close_balances()
    rows = []
    for n in b.order:
        a = b.accounts[n]
        if not a.is_bs or pcb[n] == 0:
            continue
        rows.append((n, a.group, pcb[n]))
    return rows


def has_drawings(b):
    return any(b.accounts[n].kind == "drawings" for n in b.order)


def sec_carry_forward(b, num):
    out = ["#### 4.%d Carried into FY 2026-27" % num, "", head_line(b.name, "opening balances on 01 Apr 2026"), ""]
    out.append("Every account that carries a balance takes its balance **after the year close** into the new year as its opening balance b/d on 01 Apr 2026 — the b/d line of its ledger. "
               "Income and expense accounts%s start FY 2026-27 at nil; %s." % (" and the drawings" if has_drawings(b) else "", "each partner's capital account and current account open at their own balances, as in their ledgers" if b.partners else "the General Fund and each fund open at one figure each" if b.style == "npo" else "the own money opens as one figure for each owner"))
    out.append("")
    rows = []
    tdr = tcr = 0
    for label, group, bal in carry_rows(b):
        # 04 §2.6: opening against closing — the closing balance after the close, and the same figure as the new year's opening b/d
        rows.append([label, group, fmt(abs(bal), show_zero=True), side_of(bal), fmt(abs(bal), show_zero=True), side_of(bal)])
        if bal > 0:
            tdr += bal
        else:
            tcr += -bal
    assert tdr == tcr, ("carry-forward", b.name, tdr, tcr)
    rows.append([bold("Σ Dr = Σ Cr"), "", bold(fmt(tdr)), bold("= " + fmt(tcr)), bold(fmt(tdr)), bold("= " + fmt(tcr))])
    out += table(["Account", "Type", "Closing 31 Mar 2026, after the close ₹", "Side", "Opening b/d 01 Apr 2026 ₹", "Side"], ["l", "l", "r", "c", "r", "c"], rows)
    out.append("")
    pcb = b.post_close_balances()
    out += foot_notes(b, things=any(b.accounts[n].kind == "fixed" and pcb[n] for n in b.order))
    return out


def render_book_sections(b):
    out = ["## Book: %s — %s" % (b.name, b.kindword), ""]
    if b.about:
        out += [b.about, ""]
    out += sec_chart(b)
    out += sec_ledgers(b)
    out += sec_statements(b)
    out += sec_closing(b)
    return out


def accounts_for(b, other):
    """A book's accounts for another book of the same file: the one named after it; in the owner's book the income head for the money the business sends home;
    in a sole proprietor's business book the owner's capital and drawings accounts, which are named after the owner — the personal book (O-13-4)."""
    return [n for n in b.order if n in ("%s A/c" % other.name, "Income from %s A/c" % other.name, "Capital A/c – %s" % other.name, "Drawings A/c – %s" % other.name)]


def link_pairs(case):
    """Every pair of books that keep accounts named after each other."""
    names = {b.name: b for b in case.books}
    pairs = []
    for b in case.books:
        for n in b.order:
            other = n[:-4] if n.endswith(" A/c") else None
            if other in names and other != b.name:
                ob = names[other]
                assert accounts_for(ob, b), ("mirror account missing", b.name, n)
                if (ob.name, b.name) not in [(x[0].name, x[1].name) for x in pairs]:
                    pairs.append((b, ob))
    return pairs


def sec_family_summary(case):
    pairs = link_pairs(case)
    if not pairs:
        return []
    out = ["## %s — the books agree" % ("Family summary" if len(case.books) > 2 else "The two books side by side"), "",
           head_line(" · ".join(b.name for b in case.books), "FY 2025-26"), ""]
    stake = [any(x.accounts[n].kind == "stake" for x, y in (pr, pr[::-1]) for n in accounts_for(x, y)) for pr in pairs]
    out.append("Money that moves between two books is written in both, in accounts named after the other book. For each pair: the balances brought forward agree, "
               "and what one book gave is what the other received, entry for entry."
               + (" A family and a sub-family also agree balance for balance on opposite sides." if not all(stake) else "")
               + (" An owner and the business he owns agree entry by entry — money put in against the business's capital, money sent home against its drawings — but not in balance: "
                  "the owner holds the business at the money put in, while the business's own money also carries its profit, so the difference is printed under the table as *profit kept in the business*." if any(stake) else ""))
    out.append("")
    rows = []
    kept = []
    for b, ob in pairs:
        mine, theirs = accounts_for(b, ob), accounts_for(ob, b)
        op1 = sum(b.accounts[n].opening for n in mine if b.accounts[n].is_bs)
        op2 = sum(ob.accounts[n].opening for n in theirs if ob.accounts[n].is_bs)
        assert op1 == -op2, ("pair openings do not agree", b.name, ob.name)
        p1 = sorted((r["date"], r["dr"] - r["cr"]) for n in mine for r in b.accounts[n].rows)
        p2 = sorted((r["date"], r["cr"] - r["dr"]) for n in theirs for r in ob.accounts[n].rows)
        assert p1 == p2, ("pair entries differ", b.name, ob.name)
        g1 = sum(x for _, x in p1 if x > 0)
        r1 = -sum(x for _, x in p1 if x < 0)
        rows.append([b.name, "<br>".join(mine), amt_side(op1), fmt(g1), fmt(r1), ob.name, "<br>".join(theirs), amt_side(op2), fmt(r1), fmt(g1), len(p1), "Yes"])
        for own, bus, oa, ba in ((b, ob, mine, theirs), (ob, b, theirs, mine)):
            if any(own.accounts[n].kind == "stake" for n in oa):
                pcb = bus.post_close_balances()
                a_ = -sum(pcb[n] for n in ba if bus.accounts[n].is_equity)
                b_ = sum(own.accounts[n].closing for n in oa if own.accounts[n].kind == "stake")
                takes = -sum(own.accounts[n].closing for n in oa if own.accounts[n].kind == "income")
                if bus.partners:
                    res = sum(i + x for p, i, x in bus.appropriation(bus.counts["result"]) if p["name"] == own.name)
                else:
                    res = bus.counts["result"]
                assert a_ - b_ == res - takes, ("profit kept in the business", own.name, bus.name, a_, b_, res, takes)
                m_ = lambda x: ("−" if x < 0 else "") + "₹" + fmt(abs(x), show_zero=True)
                if a_ - b_ >= 0:
                    kept.append("**Profit kept in the business — %s and %s:** the business's own money after the year close %s, less the money put in that %s holds %s, is %s. "
                                "That is the business's profit for %s %s less the %s taken out (%s − %s = %s)." % (own.name, bus.name, m_(a_), own.name, m_(b_), m_(a_ - b_), own.name, m_(res), m_(takes), m_(res), m_(takes), m_(res - takes)))
                else:   # 03 §4.1: more taken out than the profit
                    kept.append("**Taken out beyond the profit — %s and %s:** the business's own money after the year close %s, less the money put in that %s holds %s, is %s. "
                                "The business's profit for %s was %s and %s was taken out (%s − %s = %s)." % (own.name, bus.name, m_(a_), own.name, m_(b_), m_(a_ - b_), own.name, m_(res), m_(takes), m_(res), m_(takes), m_(res - takes)))
    out += table(["Book", "Its accounts for the other book", "Brought forward ₹", "Given (Dr) ₹", "Received (Cr) ₹", "Other book", "Its accounts", "Brought forward ₹", "Given (Dr) ₹", "Received (Cr) ₹", "Entries", "Agree"],
                 ["l", "l", "r", "r", "r", "l", "l", "r", "r", "r", "r", "c"], rows)
    out.append("")
    for k in kept:
        out += [k, ""]
    if case.summary_note:
        out += [case.summary_note, ""]
    return out


def render_export(case):
    """The Day Book and the Cash Book export (here: the full year, with notes)."""
    out = ["# Day Book and Cash Book — %s" % case.title, ""]
    out.append("An export, not part of the printed book: the Day Book and the Cash Book, which can be drawn for any period, with or without each entry's note. This export is the full year FY 2025-26, with notes. "
               "Entry numbers are the same as in the printed book's ledgers.")
    out.append("")
    for b in case.books:
        out += ["## Book: %s — %s" % (b.name, b.kindword), ""]
        out += sec_books(b)
    md = "\n".join(out).rstrip("\n") + "\n"
    lint_plain(md, case.slug + ".export")
    return md


def render_case(case):
    out = ["# %s" % case.title, ""]
    out += case.intro
    out.append("")
    if case.people:
        out += table(["Who", "Role in this example" + ("" if case.real_names else " (placeholder name)")], ["l", "l"], [[w, r] for w, r in case.people])
        out.append("")
    out.append("Amounts are in ₹; paise are shown only when there are paise. Plain words come first and the true side follows in small brackets — Money in (Dr), You will give (Cr) — "
               "so the side is never lost. %s" % ("Every figure is illustrative." if case.real_names else "Every name is a made-up placeholder and every figure is illustrative."))
    out.append("")
    for b in case.books:
        out += render_book_sections(b)
    out += sec_family_summary(case)
    md = "\n".join(out).rstrip("\n") + "\n"
    lint_plain(md, case.slug)
    return md


# ---------------------------------------------------------------------------------------------
# markdown → self-contained HTML (print-clean A4, phone-readable)
# ---------------------------------------------------------------------------------------------
CSS = """
@page { size: A4; margin: 13mm 12mm 14mm 12mm; }
html { font-size: 10.5px; }
body { font-family: -apple-system, "Helvetica Neue", Helvetica, Arial, "Noto Sans", sans-serif; color: #111; margin: 0; padding: 0 2mm; line-height: 1.35; max-width: 100%; }
h1 { font-size: 2em; margin: 0 0 .4em 0; }
h2 { font-size: 1.45em; margin: 1.3em 0 .4em 0; border-bottom: 1.5px solid #333; padding-bottom: .15em; page-break-after: avoid; }
h3 { font-size: 1.18em; margin: 1.1em 0 .3em 0; page-break-after: avoid; }
h4 { font-size: 1.02em; margin: .9em 0 .25em 0; page-break-after: avoid; }
p { margin: .35em 0 .55em 0; }
ul, ol { margin: .3em 0 .7em 1.2em; padding: 0; }
li { margin: .15em 0; }
table { border-collapse: collapse; width: 100%; margin: .35em 0 .9em 0; page-break-inside: auto; font-variant-numeric: tabular-nums; }
tr { page-break-inside: avoid; }
th, td { border: .5px solid #999; padding: 2.2px 4px; vertical-align: top; font-size: .95em; }
th { background: #eee; text-align: left; font-weight: 600; }
td.r, th.r { text-align: right; white-space: nowrap; }
td.c, th.c { text-align: center; }
em { color: #444; }
td em { font-size: .86em; color: #555; }
code { font-family: Menlo, Consolas, monospace; font-size: .92em; background: #f3f3f3; padding: 0 2px; }
hr { border: 0; border-top: 1px solid #bbb; margin: 1.2em 0; }
thead { display: table-header-group; }
@media screen and (max-width: 600px) { html { font-size: 12px; } body { padding: 0 8px; } table { display: block; overflow-x: auto; } }
@media print { a { color: inherit; text-decoration: none; } }
"""


def inline_md(s):
    s = html_mod.escape(s, quote=False)
    s = s.replace("&lt;br&gt;", "<br>").replace("&lt;em&gt;", "<em>").replace("&lt;/em&gt;", "</em>")
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"(?<![\w*])\*([^*\n]+?)\*(?![\w*])", r"<em>\1</em>", s)
    s = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', s)
    return s


def md_to_html(md, title):
    lines = md.split("\n")
    out = []
    i = 0
    in_list = None
    para = []

    def flush_para():
        if para:
            out.append("<p>%s</p>" % inline_md(" ".join(para)))
            del para[:]

    while i < len(lines):
        ln = lines[i]
        if ln.startswith("|") and i + 1 < len(lines) and re.match(r"^\|[:\-| ]+\|$", lines[i + 1].strip()):
            flush_para()
            if in_list:
                out.append("</%s>" % in_list)
                in_list = None
            header = [c.strip() for c in ln.strip().strip("|").split(" | ")]
            aligns = []
            for c in lines[i + 1].strip().strip("|").split("|"):
                c = c.strip()
                aligns.append("c" if c.startswith(":") and c.endswith(":") else "r" if c.endswith(":") else "l")
            i += 2
            out.append("<table><thead><tr>" + "".join('<th class="%s">%s</th>' % (aligns[k] if k < len(aligns) else "l", inline_md(h)) for k, h in enumerate(header)) + "</tr></thead><tbody>")
            while i < len(lines) and lines[i].startswith("|"):
                cells = [c.strip() for c in lines[i].strip().strip("|").split(" | ")]
                out.append("<tr>" + "".join('<td class="%s">%s</td>' % (aligns[k] if k < len(aligns) else "l", inline_md(c)) for k, c in enumerate(cells)) + "</tr>")
                i += 1
            out.append("</tbody></table>")
            continue
        m = re.match(r"^(#{1,6}) (.*)$", ln)
        if m:
            flush_para()
            if in_list:
                out.append("</%s>" % in_list)
                in_list = None
            lvl = len(m.group(1))
            out.append("<h%d>%s</h%d>" % (lvl, inline_md(m.group(2)), lvl))
            i += 1
            continue
        m = re.match(r"^(\s*)([-*]|\d+\.) (.*)$", ln)
        if m:
            flush_para()
            tag = "ol" if m.group(2)[0].isdigit() else "ul"
            if in_list != tag:
                if in_list:
                    out.append("</%s>" % in_list)
                out.append("<%s>" % tag)
                in_list = tag
            out.append("<li>%s</li>" % inline_md(m.group(3)))
            i += 1
            continue
        if ln.strip() == "":
            flush_para()
            if in_list:
                out.append("</%s>" % in_list)
                in_list = None
            i += 1
            continue
        para.append(ln)
        i += 1
    flush_para()
    if in_list:
        out.append("</%s>" % in_list)
    return ('<!doctype html>\n<html lang="en"><head><meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n'
            "<title>%s</title>\n<style>%s</style></head><body>\n%s\n</body></html>\n" % (html_mod.escape(title), CSS, "\n".join(out)))


def to_pdf(chrome, html_path, pdf_path):
    cmd = [chrome, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
           "--print-to-pdf=%s" % os.path.abspath(pdf_path), "file://%s" % os.path.abspath(html_path)]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    data = open(pdf_path, "rb").read()
    fixed = re.sub(rb"/(CreationDate|ModDate) \(D:\d{14}([+-]\d{2}'\d{2}')?\)",
                   lambda m: b"/" + m.group(1) + b" (D:20260401000000+00'00')", data)
    fixed = re.sub(rb"/ID \[<([0-9A-Fa-f]+)> ?<([0-9A-Fa-f]+)>\]",
                   lambda m: b"/ID [<" + b"0" * len(m.group(1)) + b"> <" + b"0" * len(m.group(2)) + b">]", fixed)
    open(pdf_path, "wb").write(fixed)
    return len(re.findall(rb"/Type\s*/Page[^s]", fixed))


FORBIDDEN_IN_PRINT = ["`", "§", "ADR", "⚠", "owner ruling", "build.py", "check_md", "GAPS", "README", "asserted", "equity", "(credit given)", "(credit taken)",
                      "Journal", "Contra", "vector", "money_in", "category_", "Standard type", "Nominal", "non-cash", "Receipt (", "voucher", "Voucher",
                      "Due to", "Due from", "narration", "accrual", "Vch", "app", "auditor"]


def lint_plain(md, slug):
    """The printed book must read in everyday words — no engine names, no spec references, no generator talk."""
    for tok in FORBIDDEN_IN_PRINT:
        m = re.search((r"\b%s\b" if tok[0].isalpha() and tok[-1].isalpha() else "%s") % re.escape(tok), md)
        if m:
            i = m.start()
            raise AssertionError("printed book %s contains %r near: %r" % (slug, tok, md[max(0, i - 80):i + 80]))


ENTRY_KINDS = [   # (formal voucher type, the kind of entry it is) — in the order the basis line lists them
    ("Receipt", "a bank or cash movement"), ("Payment", "a bank or cash movement"),
    ("Journal (credit given)", "a khata entry with a named party"), ("Journal (credit taken)", "a khata entry with a named party"),
    ("loan", "a loan instalment as the bank paid it"), ("Contra", "a transfer between own accounts"),
    ("Journal (advance settled)", "an advance or its settlement"), ("advance", "an advance or its settlement"),
    ("Journal (paid by partner)", "a partner's own-pocket payment"), ("Journal (paid by family)", "a payment the joint family made for a sub-family"),
    ("Payment (from a fund)", "a payment from a fund"), ("Journal (interest added)", "interest the bank adds to a deposit"),
    ("Journal", None), ("Journal (settled)", "a running account settled at year end"),
    ("Journal (set off)", "a deposit held set off against what is owed"), ("Journal (deposit forfeited)", "a deposit held kept as income"),
    ("Journal (retention released)", "retention money released"), ("Journal (written off)", "an amount written off"),
    ("Journal (correction)", "a correction"),
]


def entry_kinds(case):
    """The closed list of the kinds of entry this case's books hold (every voucher maps to at least one)."""
    seen = set()
    for b in case.books:
        for v in b.vouchers:
            keys = {v.vtype}
            if v.vtype in ("Receipt", "Payment"):
                keys |= {b.accounts[n].kind for n, a in v.lines if b.accounts[n].kind == "advance" or (b.accounts[n].kind == "loan" and a > 0)}
            assert v.vtype in dict(ENTRY_KINDS), ("no kind of entry for", v.vtype)
            seen |= keys
    words = []
    for key, w in ENTRY_KINDS:
        if key in seen:
            w = w or " or ".join(sorted({b.journal_word for b in case.books if any(v.vtype == "Journal" for v in b.vouchers)}))
            if w not in words:
                words.append(w)
    return ", ".join(words[:-1]) + ", or " + words[-1] if len(words) > 1 else words[0]


def render_tech(case, md):
    """Developer-facing companion: standard types, formal voucher types, app verbs, sources, gaps."""
    out = ["# Technical companion — %s" % case.title, ""]
    out.append("Generated by `build.py` beside `%s.md`. The printed book is the user-facing layout in everyday words; everything technical lives here, in `README.md` and in `GAPS.md`. "
               "Content hash of the printed book (BLAKE2b-256): `%s`." % (case.slug, hashlib.blake2b(md.encode("utf-8"), digest_size=32).hexdigest()))
    out.append("")
    out.append("## Basis (ADR 2026-10-12 §2, §10–§12; ADR 2026-10-20 §2; rulings of 20 Oct 2026 in `docs/archive/reference/accounting-research/OPEN.md`)")
    out.append("")
    out.append("- No tax, GST, TDS, invoicing, stock or payroll (`docs/00-vision.md`, non-goals). Purchases for resale are an expense when bought or taken on credit; there is no closing stock.")
    out.append("- Transaction-driven: every entry is %s." % entry_kinds(case))
    out.append("- The khata basis (O-01-1): no depreciation, prepaid, outstanding or accrued entries and no closing stock; things owned stay at cost (O-09-1). The year close is **posted** by the book itself (O-19-1) on 31 Mar 2026 — income and expense heads to the result, the result and Drawings to own money, a partnership through a posted P&L Appropriation Account (O-14-1), a trust's surplus or deficit to the General Fund — listed below as entries `<prefix>-Y1 …`, formal type `Journal (year close)`; none is typed by the user and none is in the Day Book export.")
    out.append("- Plain words in the printed book; the true side stays in a small bracket after the plain label (ADR 2026-10-10b §4). Ledger rows carry each entry's note in small type; the Day Book and the Cash Book are an export (`%s.export.md`), not part of the printed book (ADR 2026-10-12 §11, amended 13 Oct 2026)." % case.slug)
    out.append("")
    for b in case.books:
        out.append("## %s — %s (prefix `%s`, %d entries)" % (b.name, b.kindword, b.prefix, len(b.vouchers)))
        out.append("")
        out.append("### Accounts — standard type and traditional class (five types, O-02-1; a bank is a personal account, O-02-2)")
        out.append("")
        rows = []
        for i, n in enumerate(b.order, 1):
            a = b.accounts[n]
            rows.append([i, n, a.group, a.type, a.trad, "`%s`" % a.kind, a.natural, amt_side(a.opening)])
        out += table(["#", "Account", "Printed type", "Standard type", "Traditional class", "Kind (generator)", "Natural balance", "Opening 01 Apr 2025"], ["r", "l", "l", "l", "l", "l", "c", "r"], rows)
        out.append("")
        out.append("### Entries — formal voucher type and the app verb")
        out.append("")
        rows = []
        for v in b.vouchers:
            rows.append([v.vid, fdate(v.date), PLAIN_VTYPE[v.vtype], formal_vtype(b, v), APP_VERB[v.vtype], "; ".join("%s %s" % (n, fmt(a)) for n, a in v.dr_lines()),
                         "; ".join("%s %s" % (n, fmt(a)) for n, a in v.cr_lines())])
        out += table(["No.", "Date", "Printed type", "Formal voucher type", "App verb (02 §2)", "Dr", "Cr"], ["l", "l", "l", "l", "l", "l", "l"], rows)
        out.append("")
        kinds = {}
        for v in b.vouchers:
            kinds[formal_vtype(b, v)] = kinds.get(formal_vtype(b, v), 0) + 1
        out.append("*%d vouchers: %s.*" % (len(b.vouchers), " · ".join("%s %d" % (k, kinds[k]) for k in sorted(kinds))))
        out.append("")
        fund_entries = [v for v in b.vouchers if v.vtype == "Payment (from a fund)"]
        if fund_entries:
            out.append("### Spending from a fund — one action, two postings (O-17-1)")
            out.append("")
            for v in fund_entries:
                drs = [(n, a) for n, a in v.dr_lines() if b.accounts[n].kind != "fund"]
                fd = [(n, a) for n, a in v.dr_lines() if b.accounts[n].kind == "fund"][0]
                inc = [(n, a) for n, a in v.cr_lines() if b.accounts[n].kind == "income"][0]
                mon = [(n, a) for n, a in v.cr_lines() if b.accounts[n].is_money]
                out.append("- `%s`: posting 1 — Dr %s · Cr %s (the cost, charged to Income & Expenditure); posting 2 — Dr %s %s · Cr %s %s (the same amount moved out of the fund, so the fund's own result is nil)." % (
                    v.vid, "; ".join("%s %s" % (n, fmt(a)) for n, a in drs), "; ".join("%s %s" % (n, fmt(a)) for n, a in mon), fd[0], fmt(fd[1]), inc[0], fmt(inc[1])))
            out.append("")
        out.append("### Year close — the entries the book makes itself (O-19-1; formal type `Journal (year close)`, dated 31 Mar 2026)")
        out.append("")
        out += table(["No.", "What the book does", "Dr", "Cr"], ["l", "l", "l", "l"],
                     [[vid, note, "; ".join("%s %s" % (n, fmt(a)) for n, a in lines if a > 0), "; ".join("%s %s" % (n, fmt(-a)) for n, a in lines if a < 0)] for vid, note, lines in b.close_entries()])
        out.append("")
        if b.partners:
            out.append("*P&L Appropriation (posted): " + "; ".join("%s interest %s + share %s" % (p["name"], fmt(i, show_zero=True), fmt(s, show_zero=True)) for p, i, s in b.appropriation(b.counts["result"]))
                       + ". Leftover paise of the share go to the partner with the largest ratio, ties to the earliest partner account (02 §7.1). Interest on capital only where the partners agreed it and only out of profit (O-14-3).*")
            out.append("")
        if b.gaps:
            out.append("### Where this book needs what the app's rules do not yet provide (see `GAPS.md`)")
            out.append("")
            for ref, note in b.gaps:
                out.append("- `%s` — %s" % (ref, note))
            out.append("")
        if b.sources:
            out.append("### Practice sources")
            out.append("")
            for s in b.sources:
                out.append("- " + s)
            out.append("")
    out.append("## Checks")
    out.append("")
    out.append("- `build.py` asserts: every voucher sums to zero with ≥ 2 non-zero lines and no account twice; money in/out touches a money account and no-money entries do not (a Money out may also credit an advance it recovers or the lender's part of a purchase); a transfer joins two own money/deposit accounts; "
               "spending from a fund charges the year and moves the same amount out of the fund; the gollak is filled only by a count and emptied only into cash or bank; openings and the trial balance balance; cash, bank and wallet never go negative, a credit card never goes past nil; advances, loans given, retention, things owned and deposits are never over-settled; fixed capital does not move; "
               "every year-close entry balances, the result account and every income, expense and drawings account stand at nil after them, and the own money after them equals the balance sheet's; "
               "the position make-up equals the position at both dates; the balance sheet balances; the carry-forward sums to zero; every inter-book pair agrees entry for entry; the entry count is within the compact range; no book prints on more than 14 A4 pages.")
    out.append("- `check_md.py` re-derives the printed book independently (no shared code): chart totals, the Day Book entry by entry, every ledger row by row, the Cash Book with its month totals, the bank-statement extract, "
               "both positions and their make-up, the one-month summary, the chosen-period statement, the ageing, the trial balance, the year's statement, the appropriation, the Receipts & Payments, each fund's statement, the year-close entries, the balance sheet, the carry-forward and the family summary, "
               "and that every report head carries the book, the date or period, the basis, Year closed and Made on.")
    out.append("")
    return "\n".join(out) + "\n"


# =============================================================================================
# BOOK BUILDERS
# =============================================================================================

CASE_BUILDERS = []

# @@BUILDERS@@

def emi_schedule(principal, rate_bp, months, first_due, count):
    """The lender's statement: EMI (Decimal, half-up to the rupee); interest = opening × rate ÷ 12, rounded to the rupee."""
    P = Decimal(principal) / 100
    r = Decimal(rate_bp) / Decimal(10000) / 12
    f = (1 + r) ** months
    emi = int((P * r * f / (f - 1)).quantize(Decimal("1"), rounding=ROUND_HALF_UP)) * 100
    rows, bal, due = [], principal, first_due
    for i in range(1, count + 1):
        interest = half_up(bal * rate_bp, 10000 * 12 * 100) * 100
        rows.append((i, due, emi, interest, emi - interest))
        bal -= emi - interest
        due = dt.date(due.year + (due.month == 12), due.month % 12 + 1, due.day)
    return emi, rows


def build_individual():
    c = Case("individual-jasvinder-singh", "Individual and own business — Jasvinder Singh and Jasvinder Technologies")
    c.intro = [
        "**Jasvinder Singh** keeps two books. His **personal book** holds the household: a savings account, cash, a credit card, a FASTag wallet, a fixed deposit, two cars (the second bought in October on a car loan "
        "that the lender paid straight to the dealer), a hand loan to a friend, a driver's advance, a house help's salary advance and a grocer's khata. **Jasvinder Technologies** is his one-owner IT services business: "
        "clients billed on khata, a hosting supplier on credit, one developer on salary. Money moves between the two books only when he puts money into the business or when the business sends money home for the household — "
        "each time it is written in both books, in accounts named after the other book. What the business sends home is the household's income; the business is held in the personal book at the money put in. Both books are kept from the bank statement.",
    ]
    c.people = [
        ("Jasvinder Singh", "Owner of both books"),
        ("Gurpreet Sandhu", "Friend — borrowed ₹25,000 in May on a small interest, returned ₹15,000 in December; the rest written off in March"),
        ("Sharma General Store", "Grocer — household khata, settled every six months"),
        ("Balwinder Singh", "Part-time driver — took ₹15,000 for the family's Vaishno Devi trip in December and accounted for it"),
        ("HDFC Bank", "Car lender — ₹8,00,000 for the second car, paid to the dealer, 60 monthly instalments from 05 Dec 2025"),
        ("Medtech Solutions · Kaur Exports · Punjab Agro Board", "Clients of the business — billed on khata; Kaur Exports pays in advance once"),
        ("Cloudnine Hosting", "Hosting supplier — billed quarterly on credit"),
        ("Rohit Verma", "Developer on salary — took a salary advance in August, recovered in his salary"),
    ]
    # ---------------- the business book --------------------------------------------------------
    t = Book("Jasvinder Technologies", "own business book", "JT", "business")
    t.about = "One-owner business book · IT services · clients on khata · supplier on credit · a developer on salary · the owner's money put in and money sent home, in accounts named after the owner's personal book."
    tc = t.add(Account("Cash A/c", "cash", "Office cash", R(5000)))
    tb = t.add(Account("HDFC Bank Current A/c", "bank", "Business current account", R(320000)))
    med = t.add(Account("Medtech Solutions A/c", "party", "Client (khata) — monthly support retainer, billed quarterly", R(118000)))
    kaur = t.add(Account("Kaur Exports A/c", "party", "Client (khata) — website and mobile-application work; paid an advance before the work"))
    pab = t.add(Account("Punjab Agro Board A/c", "party", "Client (khata) — dashboard project billed in two stages"))
    cloud = t.add(Account("Cloudnine Hosting A/c", "party", "Supplier (khata) — servers and hosting, billed quarterly", -R(8260)))
    radv = t.add(Account("Advance – Rohit Verma A/c", "advance", "Salary advance to the developer, recovered in his salary"))
    lap = t.add(Account("Laptops & Office Equipment A/c", "fixed", "Laptops, monitors and office equipment at what they cost", R(145000)))
    cap = t.add(Account("Capital A/c – Jasvinder Singh", "capital", "The owner's own money in the business; named after the owner, whose personal book is the other book"))
    drw = t.add(Account("Drawings A/c – Jasvinder Singh", "drawings", "Money sent home for the household; closed to own money at the year end"))
    inc = t.add(Account("Service Income A/c", "income", "IT services billed to clients"))
    sal = t.add(Account("Salary A/c", "expense", "Developer's salary when paid"))
    rent = t.add(Account("Office Rent A/c", "expense", "Office rent, paid quarterly"))
    host = t.add(Account("Hosting & Software A/c", "expense", "Servers, hosting, domains and software"))
    net = t.add(Account("Internet & Phone A/c", "expense", "Broadband and mobile"))
    trav = t.add(Account("Travel A/c", "expense", "Travel to clients"))
    sund = t.add(Account("Office & Sundry A/c", "expense", "Stationery, accountant's fee, bank charges, small items"))
    t.balance_opening_into(cap)
    t.bank_extract = (tb, (2026, 1))
    t.custom = (kaur, D(2025, 4, 1), D(2026, 3, 31), "One client's khata for the year — an advance before the work (they are owed work), the bill that turned it round, and the payments.")
    q = ["April–June 2025", "July–September 2025", "October–December 2025", "January–March 2026"]
    qe = [D(2025, 6, 30), D(2025, 9, 30), D(2025, 12, 31), D(2026, 3, 31)]
    for k in range(4):
        t.gave(qe[k], med, inc, R(207000), "Support retainer, %s (₹69,000 a month)" % q[k])
        t.took(qe[k], host, cloud, [R(8260), R(9440), R(9440), R(11800)][k], "Hosting bill, %s" % q[k])
        t.pay(dt.date(qe[k].year, qe[k].month - 2, 5), rent, tb, R(54000), "Office rent, %s" % q[k], "NEFT DR–OFFICE RENT")
    t.rec(D(2025, 4, 12), tb, med, R(118000), "Medtech Solutions paid the March 2025 bill (opening balance)", "NEFT CR–MEDTECH SOLUTIONS")
    for d, k in [(D(2025, 7, 14), 0), (D(2025, 10, 13), 1), (D(2026, 1, 12), 2)]:
        t.rec(d, tb, med, R(207000), "Medtech Solutions paid the retainer of %s" % q[k], "NEFT CR–MEDTECH SOLUTIONS")
    t.pay(D(2025, 4, 10), cloud, tb, R(8260), "Hosting bill of January–March 2025 paid (opening balance)", "UPI DR–CLOUDNINE HOSTING")
    for d, k, a in [(D(2025, 7, 10), 0, R(8260)), (D(2025, 10, 10), 1, R(9440)), (D(2026, 1, 10), 2, R(9440))]:
        t.pay(d, cloud, tb, a, "Hosting bill of %s paid" % q[k], "UPI DR–CLOUDNINE HOSTING")
    t.rec(D(2025, 5, 6), tb, kaur, R(60000), "Advance from Kaur Exports for their export-order mobile application", "NEFT CR–KAUR EXPORTS")
    t.gave(D(2025, 7, 31), kaur, inc, R(140000), "Kaur Exports — export-order mobile application delivered")
    t.rec(D(2025, 9, 8), tb, kaur, R(80000), "Kaur Exports paid the rest of the application bill", "NEFT CR–KAUR EXPORTS")
    t.gave(D(2026, 1, 20), kaur, inc, R(90000), "Kaur Exports — website redesign")
    t.rec(D(2026, 3, 18), tb, kaur, R(90000), "Kaur Exports paid the website bill", "NEFT CR–KAUR EXPORTS")
    t.gave(D(2025, 8, 29), pab, inc, R(236000), "Punjab Agro Board — dashboard, first stage")
    t.rec(D(2025, 11, 21), tb, pab, R(236000), "Punjab Agro Board paid the first stage (late)", "RTGS CR–PUNJAB AGRO BOARD")
    t.gave(D(2026, 2, 27), pab, inc, R(177000), "Punjab Agro Board — dashboard, final stage")
    for k, a in enumerate([R(135000), R(115000), R(135000), R(135000)]):
        if k == 1:
            # O-07-5: the salary advance is recovered in the salary entry — full salary, less the advance, the rest paid
            t.v(qe[k], "Payment", "Salary of Rohit Verma, %s — ₹20,000 of it recovered from his advance, the rest paid" % q[k],
                [(sal, R(135000)), (radv, -R(20000)), (tb, -a)], stmt="NEFT DR–ROHIT VERMA–SAL")
        else:
            t.pay(qe[k], sal, tb, a, "Salary of Rohit Verma, %s" % q[k], "NEFT DR–ROHIT VERMA–SAL")
    t.pay(D(2025, 8, 11), radv, tb, R(20000), "Salary advance to Rohit Verma", "IMPS DR–ROHIT VERMA")
    t.pay(D(2025, 6, 18), lap, tb, R(110000), "Two laptops for the office — things owned, at cost", "NEFT DR–LAPTOP WORLD")
    t.pay(D(2025, 4, 3), net, tb, R(11800), "Broadband and mobile, April–September", "UPI DR–AIRTEL")
    wrong = t.pay(D(2025, 9, 26), net, tb, R(4720), "Domain and e-mail renewal", "UPI DR–DOMAIN RENEWAL")
    t.fix(D(2025, 10, 4), host, net, R(4720), "Entry {ref} (domain renewal) was written to Internet & Phone — moved to Hosting & Software", "Journal (correction)", ref=wrong)
    t.pay(D(2025, 10, 3), net, tb, R(11800), "Broadband and mobile, October–March", "UPI DR–AIRTEL")
    t.move(D(2025, 7, 7), tc, tb, R(15000), "Cash withdrawn for office cash (ATM)", "ATM WDL–MOHALI")
    t.pay(D(2025, 8, 22), trav, tc, R(6400), "Travel to Chandigarh for the Punjab Agro Board meetings, cash")
    t.pay(D(2026, 2, 14), trav, tc, R(5200), "Travel to Ludhiana for Kaur Exports, cash")
    t.pay(D(2025, 12, 19), sund, tc, R(2800), "Stationery and printer cartridges, cash")
    t.pay(D(2025, 9, 15), sund, tb, R(9000), "Accountant's fee for the FY 2024-25 books", "UPI DR–CA OFFICE")
    # ---------------- the personal book --------------------------------------------------------
    p = Book("Jasvinder Singh", "personal book", "JP", "household")
    p.about = "Personal book · savings, cash, credit card, FASTag wallet, fixed deposit, two cars (one on a loan) · grocer's khata, a hand loan to a friend, advances to a driver and the house help · money put into his business, and the business's money sent home as income."
    pc = p.add(Account("Cash A/c", "cash", "Cash at home", R(8000)))
    pb = p.add(Account("SBI Savings A/c", "bank", "Savings account — household money", R(185000)))
    tag = p.add(Account("FASTag Wallet A/c", "wallet", "Prepaid toll wallet for the cars — recharged from savings", R(1200)))
    card = p.add(Account("HDFC Credit Card A/c", "card", "Credit card — what is owed on it", -R(12400)))
    fd = p.add(Account("SBI Fixed Deposit A/c", "invest", "Fixed deposits", R(200000)))
    biz = p.add(Account("Jasvinder Technologies A/c", "stake", "Money put into the business, at what was put in; named after the business book"))
    gur = p.add(Account("Loan to – Gurpreet Sandhu A/c", "loanto", "Hand loan to a friend on a small interest — his own account, apart from any khata"))
    groc = p.add(Account("Sharma General Store A/c", "party", "Grocer (khata) — what is owed for groceries", -R(3200)))
    drvp = p.add(Account("Balwinder Singh A/c", "party", "Driver (khata) — what he owes after the trip, to be cut from his pay"))
    hadv = p.add(Account("Advance – house help A/c", "advance", "Salary advance to the house help, recovered in her wages"))
    dadv = p.add(Account("Advance – Balwinder Singh A/c", "advance", "Money with the driver for the trip, accounted for against his bills"))
    car = p.add(Account("Car – Maruti Baleno A/c", "fixed", "The family car at what it cost (2023)", R(640000)))
    car2 = p.add(Account("Car – Hyundai Venue A/c", "fixed", "The second car at what it cost (October 2025)"))
    cloan = p.add(Account("Car Loan – HDFC Bank A/c", "loan", "Loan for the second car — the principal still owed, as on the lender's statement"))
    cap = p.add(Account("Capital A/c – Jasvinder Singh", "capital", "Own money — what the household is worth in this book"))
    inb = p.add(Account("Income from Jasvinder Technologies A/c", "income", "Money the business sent home — the household's income"))
    pint = p.add(Account("Interest A/c", "income", "Interest on savings, deposits and the hand loan"))
    gift = p.add(Account("Gifts Received A/c", "income", "Gifts given to the household"))
    hh = p.add(Account("Groceries & Household A/c", "expense", "Groceries and household things"))
    util = p.add(Account("Electricity & Phone A/c", "expense", "Electricity, gas and phones"))
    sch = p.add(Account("School Fees A/c", "expense", "Children's school fees"))
    help_ = p.add(Account("House Help Wages A/c", "expense", "House help's wages"))
    carx = p.add(Account("Car Fuel & Upkeep A/c", "expense", "Fuel, service, car insurance"))
    toll = p.add(Account("Toll & Parking A/c", "expense", "Tolls off the FASTag wallet, and parking"))
    cint = p.add(Account("Interest on Car Loan A/c", "expense", "Interest part of each instalment, as the lender's statement splits it"))
    med_ = p.add(Account("Medical & Insurance A/c", "expense", "Doctor, medicines, health and life insurance"))
    soc = p.add(Account("Gifts & Social A/c", "expense", "Shagun, gifts, gurpurab and social occasions"))
    wo = p.add(Account("Written off A/c", "expense", "Money known not to come back — the part of the friend's loan he could not repay"))
    # the business opening is the owner's capital in the business book (mirror)
    p.accounts[biz].opening = -t.accounts[cap].opening
    p.balance_opening_into(cap)
    p.bank_extract = (pb, (2025, 10))
    p.custom = (gur, D(2025, 4, 1), D(2026, 3, 31), "The friend's loan account for the year — the loan, the part returned, and the rest written off.")
    # money between the two books — written in both (O-13-4: money sent home is income in the personal book; the business stays at money put in)
    for d, a in [(D(2025, 4, 1), R(120000)), (D(2025, 7, 15), R(120000)), (D(2025, 10, 20), R(120000)), (D(2025, 12, 22), R(120000))]:
        t.pay(d, drw, tb, a, "Sent home for the household — to Jasvinder Singh's savings account", "IMPS DR–JASVINDER SINGH–SELF")
        p.rec(d, pb, inb, a, "Received from Jasvinder Technologies — money sent home", "IMPS CR–JASVINDER TECHNOLOGIES")
    t.rec(D(2025, 6, 16), tb, cap, R(100000), "Put in by Jasvinder Singh for the new laptops", "NEFT CR–JASVINDER SINGH")
    p.pay(D(2025, 6, 16), biz, pb, R(100000), "Put into Jasvinder Technologies for the new laptops", "NEFT DR–JASVINDER TECHNOLOGIES")
    # household
    for d, a, nm in [(D(2025, 9, 30), R(48400), "April–September"), (D(2026, 3, 31), R(49500), "October–March")]:
        p.took(d, hh, groc, a, "Groceries on khata, %s" % nm)
    p.pay(D(2025, 4, 5), groc, pc, R(3200), "Grocer's khata of March paid, cash")
    p.pay(D(2025, 10, 6), groc, pb, R(48400), "Grocer's khata of April–September paid (UPI)", "UPI DR–SHARMA GENERAL STORE")
    for d, a in [(D(2025, 7, 21), R(15500)), (D(2026, 1, 21), R(14200))]:
        p.pay(d, util, pb, a, "Electricity and phone bills, six months", "BILLPAY DR–PSPCL / AIRTEL")
    p.pay(D(2025, 4, 15), sch, pb, R(42000), "School fees, first half-year", "NEFT DR–SCHOOL FEES")
    p.pay(D(2025, 10, 16), sch, pb, R(44000), "School fees, second half-year", "NEFT DR–SCHOOL FEES")
    for d, a, nm in [(D(2025, 6, 30), R(30000), "April–June"), (D(2025, 12, 31), R(30000), "October–December"), (D(2026, 3, 31), R(30000), "January–March")]:
        p.pay(d, help_, pc, a, "House help's wages, %s, cash" % nm)
    p.pay(D(2025, 7, 8), hadv, pc, R(6000), "Salary advance to the house help, cash")
    # O-07-5: recovered in the wages entry — full wages, less the advance, the rest paid
    p.v(D(2025, 9, 30), "Payment", "House help's wages, July–September — ₹6,000 of it recovered from her advance, the rest paid in cash",
        [(help_, R(30000)), (hadv, -R(6000)), (pc, -R(24000))])
    for d, a in [(D(2025, 4, 2), R(45000)), (D(2025, 9, 26), R(45000)), (D(2025, 12, 27), R(30000)), (D(2026, 3, 2), R(30000))]:
        p.move(d, pc, pb, a, "Cash withdrawn (ATM)", "ATM WDL–MOHALI")
    # a hand loan on interest, apart from any khata (O-02-4); part returned; the rest known not to come back is written off (O-12-1)
    p.pay(D(2025, 5, 18), gur, pb, R(25000), "Hand loan to Gurpreet Sandhu, on a small interest (UPI)", "UPI DR–GURPREET SANDHU")
    p.rec(D(2025, 12, 12), pb, gur, R(15000), "Gurpreet Sandhu returned part of the loan", "UPI CR–GURPREET SANDHU")
    p.rec(D(2025, 12, 12), pb, pint, R(1875), "Interest on the hand loan paid by Gurpreet Sandhu for seven months", "UPI CR–GURPREET SANDHU")
    p.v(D(2026, 3, 31), "Journal (written off)", "The last ₹10,000 of Gurpreet Sandhu's loan written off — he has said he cannot repay it", [(wo, R(10000)), (gur, -R(10000))])
    for d, a, nm in [(D(2025, 5, 12), R(9800), "Fuel, April–May"), (D(2025, 8, 9), R(14200), "Fuel and car service"), (D(2025, 11, 10), R(18600), "Car insurance renewal")]:
        p.pay(d, carx, card, a, "%s, on the credit card" % nm)
    for d, a in [(D(2025, 4, 18), R(12400)), (D(2025, 6, 18), R(9800)), (D(2025, 9, 17), R(14200)), (D(2025, 12, 17), R(18600))]:
        p.move(d, card, pb, a, "Credit-card bill paid from savings", "CC PAYMENT DR–HDFC CARD")
    p.pay(D(2025, 8, 28), med_, pb, R(38000), "LIC premium (yearly)", "NACH DR–LIC OF INDIA")
    p.pay(D(2025, 11, 5), soc, pc, R(11000), "Shagun at a cousin's wedding and Gurpurab, cash")
    wrong = p.pay(D(2026, 2, 20), hh, pb, R(5900), "Gas cylinder booking and pipe repair (UPI)", "UPI DR–INDANE GAS")
    p.fix(D(2026, 3, 2), util, hh, R(5900), "Entry {ref} (gas) was written to Groceries & Household — moved to Electricity & Phone", "Journal (correction)", ref=wrong)
    # a deposit that matured comes back as a transfer, not as income (O-13-5)
    p.move(D(2025, 9, 20), pb, fd, R(100000), "Fixed deposit of ₹1,00,000 matured — back to savings", "FD MATURITY")
    for d, a, nm in [(D(2026, 3, 31), R(3360), "Savings interest"), (D(2025, 12, 31), R(14400), "Interest on the fixed deposit, paid to savings")]:
        p.rec(d, pb, pint, a, nm, "INT.CR")
    p.rec(D(2025, 8, 3), pb, gift, R(11000), "Birthday gift from an uncle (UPI)", "UPI CR–UNCLE")
    # the second car on a loan: the lender pays the dealer, the margin is the owner's money (O-09-6)
    p.v(D(2025, 10, 25), "Payment", "Second car bought for ₹9,00,000: the lender paid the dealer ₹8,00,000 (the loan) and the margin ₹1,00,000 was paid from savings",
        [(car2, R(900000)), (cloan, -R(800000)), (pb, -R(100000))], stmt="RTGS DR–HYUNDAI DEALER (MARGIN)")
    emi, sched = emi_schedule(R(800000), 950, 60, D(2025, 12, 5), 4)
    for i, due, e, interest, principal in sched:
        p.v(due, "Payment", "Car loan instalment %d of 60, split as on the lender's statement" % i,
            [(cloan, principal), (cint, interest), (pb, -e)], stmt="ACH DR–HDFC BANK–CAR LOAN EMI %02d/60" % i)
    # a FASTag wallet, recharged by transfer, spent on tolls
    p.move(D(2025, 10, 3), tag, pb, R(3000), "FASTag wallet recharged from savings", "UPI DR–FASTAG RECHARGE")
    p.pay(D(2026, 3, 31), toll, tag, R(2640), "Tolls, October–March, per the FASTag statement")
    # a driver's advance, settled against several heads; the part with no bill moved to his own account; the unspent part returned
    p.pay(D(2025, 12, 18), dadv, pc, R(15000), "Advance to Balwinder Singh for the Vaishno Devi trip, cash")
    p.v(D(2025, 12, 28), "Journal (advance settled)", "Balwinder Singh's trip bills — fuel, tolls, parking — set against his advance; ₹1,800 with no bill moved to his own account",
        [(carx, R(8200)), (toll, R(3500)), (drvp, R(1800)), (dadv, -R(13500))])
    p.rec(D(2025, 12, 28), pc, dadv, R(1500), "Balwinder Singh returned the unspent part of the advance, cash")
    t.finalize()
    p.finalize()
    tr = sum(-t.accounts[n].closing for n in t.order if t.accounts[n].kind == "income") - sum(t.accounts[n].closing for n in t.order if t.accounts[n].kind == "expense")
    home = -p.accounts[inb].closing
    c.summary_note = ("The two sides agree entry by entry, on every date. The personal book holds the business at the money put in (₹%s) and takes the money the business sends home as income "
                      "(*Income from Jasvinder Technologies*, ₹%s this year); in the business book the same money is the owner's drawings. The business's net profit for the year, ₹%s, is worked out in its own book "
                      "and is not written in the personal book; after the year close the business's own money is ₹%s."
                      % (fmt(p.accounts[biz].closing), fmt(home), fmt(tr), fmt(-t.post_close_balances()[cap])))
    t.assets_note = ""
    p.assets_note = ""
    t.gaps = [("Capital / Drawings A/c – Jasvinder Singh", "a sole proprietor's business book keeps Capital and Drawings (O-13-1, O-13-2); both are named after the owner, whose personal book is the other book of the pair (O-13-4; GAPS A11)")]
    p.gaps = [("Jasvinder Technologies A/c · Income from …", "own money in a business held at what was put in; money the business sends home is income (O-13-4, cost method; GAPS A11)"),
              ("HDFC Credit Card A/c", "money subtype card, Cr by sign; card bill paid by transfer"), ("Car – Maruti Baleno A/c", "asset at cost (GAPS A1)"),
              ("Loan to – Gurpreet Sandhu A/c", "a loan to a person that carries interest: its own account beside the khata, written off to an expense head (O-02-4, O-12-1)")]
    c.books = [p, t]
    c.demonstrates = ["two books linked by accounts named after each other, agreeing entry for entry; the business's money sent home is the household's income (cost method)",
                      "a car bought on a loan the lender paid to the dealer; EMI lines split from the lender's statement", "a driver's advance settled against several heads, the part with no bill moved to his account, the rest returned; a FASTag wallet",
                      "a hand loan with its own account, part returned, the rest written off", "salary advances recovered in the salary entry in both books", "credit card as a money account; a deposit that matured; a gift received",
                      "a client who pays an advance and crosses zero", "a correction in each book"]
    return c


CASE_BUILDERS.append(build_individual)


Q4N = ["April–June 2025", "July–September 2025", "October–December 2025", "January–March 2026"]
Q4E = [D(2025, 6, 30), D(2025, 9, 30), D(2025, 12, 31), D(2026, 3, 31)]


def build_shop():
    c = Case("shop-sukhwinder-sales-co", "Shop — Sukhwinder Sales Co. (pipes & sanitary)")
    c.intro = [
        "**Sukhwinder Bal** runs a pipes-and-sanitary shop. Counter sales are in cash and the cash is banked; builders and plumbers buy on khata; the pipe company and the sanitary agency "
        "supply on khata. One salesman draws a salary and once takes an advance. The book is kept from the bank statement and the counter cash book. "
        "Goods bought for sale are written as spent when bought — no stock is counted.",
    ]
    c.people = [
        ("Sukhwinder Bal", "Proprietor; takes money for the household each quarter"),
        ("Manpreet Kaur", "Salesman — salary each quarter; a salary advance in August"),
        ("Guru Nanak Builders", "Customer on khata — pays the quarter's goods the next month"),
        ("Dhillon Plumbing Works", "Customer who pays in advance, then buys — the account turns round"),
        ("Supreme Pipes Ltd · Jaquar Sanitary Agency", "Suppliers on khata"),
        ("Kapoor Properties", "The shop's landlord — rent paid each quarter; holds the shop's ₹90,000 security deposit"),
    ]
    b = Book("Sukhwinder Sales Co.", "business book", "S", "business")
    b.about = "One-owner shop · counter cash banked · customers and suppliers on khata · a salesman on salary · kept from the bank statement."
    cash = b.add(Account("Cash A/c", "cash", "Counter cash", R(22000)))
    bank = b.add(Account("PNB Current A/c", "bank", "Shop's current account", R(480000)))
    gnb = b.add(Account("Guru Nanak Builders A/c", "party", "Customer (khata) — builder", R(64000)))
    dpw = b.add(Account("Dhillon Plumbing Works A/c", "party", "Customer (khata) — plumbing contractor"))
    sup = b.add(Account("Supreme Pipes Ltd A/c", "party", "Supplier (khata) — pipes and fittings", -R(118000)))
    jaq = b.add(Account("Jaquar Sanitary Agency A/c", "party", "Supplier (khata) — sanitary ware", -R(46500)))
    adv = b.add(Account("Advance – Manpreet Kaur A/c", "advance", "Salary advance to the salesman"))
    sdep = b.add(Account("Deposit paid – Kapoor Properties A/c", "deppaid", "Security deposit paid to the shop's landlord (six months' rent) — comes back when the shop is vacated", R(90000)))
    fit = b.add(Account("Shop Fittings & Counter A/c", "fixed", "Racks, counter and display at what they cost", R(120000)))
    cap = b.add(Account("Capital A/c – Sukhwinder Bal", "capital", "Owner's own money in the shop"))
    drw = b.add(Account("Drawings A/c – Sukhwinder Bal", "drawings", "Money taken for the household"))
    sales = b.add(Account("Sales A/c", "income", "Goods sold — counter cash and khata"))
    pur = b.add(Account("Goods Bought for Sale A/c", "expense", "Pipes, fittings and sanitary ware bought — spent when bought (no stock is counted)"))
    frt = b.add(Account("Freight & Cartage A/c", "expense", "Goods brought to the shop and delivered"))
    sal = b.add(Account("Salary A/c", "expense", "Salesman's salary"))
    rent = b.add(Account("Shop Rent A/c", "expense", "Rent of the shop"))
    util = b.add(Account("Electricity & Phone A/c", "expense", "Shop electricity and phone"))
    sund = b.add(Account("Bank Charges & Sundry A/c", "expense", "Bank charges, stationery, small items"))
    short = b.add(Account("Cash short / over A/c", "expense", "What the counter cash count found short (spent) or over (got back) against the cash book, charged at once"))
    wo = b.add(Account("Written off A/c", "expense", "A customer's balance known not to come"))
    b.balance_opening_into(cap)
    b.stock_line = True
    b.bank_extract = (bank, (2025, 8))
    b.custom = (dpw, D(2025, 4, 1), D(2026, 3, 31), "The plumbing contractor's khata for the year — an advance first, then goods that turned the balance round, then the payment.")
    cs = [R(386000), R(342500), R(412000), R(398500)]
    gs = [R(238000), R(214500), R(256000), R(247000)]
    sp = [R(334000), R(301500), R(352000), R(338000)]
    for k in range(4):
        b.rec(Q4E[k], cash, sales, cs[k], "Counter sales in cash, %s (from the daily cash memo book)" % Q4N[k])
        b.move(Q4E[k], bank, cash, cs[k] - R(6000) if k else cs[k] - R(4000), "Counter cash deposited in the bank", "CASH DEP–BRANCH")
        b.gave(Q4E[k], gnb, sales, gs[k], "Goods to Guru Nanak Builders on khata, %s" % Q4N[k])
        b.took(Q4E[k], pur, sup, sp[k], "Pipes and fittings from Supreme Pipes on khata, %s" % Q4N[k])
        b.pay(dt.date(Q4E[k].year, Q4E[k].month - 2, 3), rent, bank, R(45000), "Shop rent, %s" % Q4N[k], "NEFT DR–KAPOOR PROPERTIES")
        if k == 1:
            b.v(Q4E[k], "Payment", "Salary of Manpreet Kaur, %s — ₹10,000 of it recovered from her advance, the rest paid" % Q4N[k],
                [(sal, R(54000)), (adv, -R(10000)), (bank, -R(44000))], stmt="NEFT DR–MANPREET KAUR–SAL")
        else:
            b.pay(Q4E[k], sal, bank, R(54000), "Salary of Manpreet Kaur, %s" % Q4N[k], "NEFT DR–MANPREET KAUR–SAL")
        b.pay(dt.date(Q4E[k].year, Q4E[k].month - 1, 10), drw, bank, R(60000), "Drawings for the household", "IMPS DR–SUKHWINDER BAL–SELF")
    b.rec(D(2025, 4, 14), bank, gnb, R(64000), "Guru Nanak Builders paid March's goods (opening balance)", "NEFT CR–GURU NANAK BUILDERS")
    for d, k in [(D(2025, 7, 15), 0), (D(2025, 10, 22), 1), (D(2026, 1, 14), 2)]:
        b.rec(d, bank, gnb, gs[k], "Guru Nanak Builders paid for the goods of %s%s" % (Q4N[k], " (late)" if k == 1 else ""), "NEFT CR–GURU NANAK BUILDERS")
    b.pay(D(2025, 4, 8), sup, bank, R(118000), "Supreme Pipes paid — March bill (opening balance)", "RTGS DR–SUPREME PIPES")
    for d, k in [(D(2025, 7, 18), 0), (D(2025, 10, 9), 1), (D(2026, 1, 16), 2)]:
        b.pay(d, sup, bank, sp[k], "Supreme Pipes paid — goods of %s" % Q4N[k], "RTGS DR–SUPREME PIPES")
    b.took(D(2025, 5, 20), pur, jaq, R(118600), "Sanitary ware from Jaquar Sanitary Agency on khata")
    b.took(D(2025, 11, 18), pur, jaq, R(126400), "Sanitary ware from Jaquar Sanitary Agency on khata")
    b.pay(D(2025, 4, 25), jaq, bank, R(46500), "Jaquar Sanitary Agency paid — opening balance", "NEFT DR–JAQUAR SANITARY")
    b.pay(D(2025, 8, 26), jaq, bank, R(118600), "Jaquar Sanitary Agency paid — May bill", "NEFT DR–JAQUAR SANITARY")
    b.rec(D(2025, 6, 6), bank, dpw, R(50000), "Advance from Dhillon Plumbing Works against a hotel job", "UPI CR–DHILLON PLUMBING")
    b.gave(D(2025, 7, 4), dpw, sales, R(86500), "Pipes and fittings to Dhillon Plumbing Works for the hotel job")
    b.gave(D(2025, 12, 11), dpw, sales, R(42800), "Sanitary ware to Dhillon Plumbing Works")
    b.rec(D(2026, 2, 9), bank, dpw, R(60000), "Dhillon Plumbing Works paid part of the balance", "UPI CR–DHILLON PLUMBING")
    b.pay(D(2025, 8, 12), adv, bank, R(10000), "Salary advance to Manpreet Kaur", "IMPS DR–MANPREET KAUR")
    b.pay(D(2025, 8, 21), util, bank, R(14800), "Shop electricity and phone, April–August", "BILLPAY DR–PSPCL")
    b.pay(D(2026, 2, 19), util, bank, R(17200), "Shop electricity and phone, September–January", "BILLPAY DR–PSPCL")
    wrong = b.pay(D(2025, 8, 30), pur, cash, R(3200), "Tempo hire for a delivery to Phagwara, cash")
    b.fix(D(2025, 9, 6), frt, pur, R(3200), "Entry {ref} (tempo hire) was written to Goods Bought for Sale — moved to Freight & Cartage", "Journal (correction)", ref=wrong)
    b.pay(D(2025, 5, 16), frt, cash, R(4600), "Cartage of the Jaquar consignment, cash")
    b.pay(D(2026, 1, 24), frt, cash, R(5100), "Cartage and delivery, cash")
    b.move(D(2025, 11, 3), cash, bank, R(15000), "Cash withdrawn for change and small payments (ATM)", "ATM WDL–PHAGWARA")
    b.pay(D(2025, 11, 26), fit, bank, R(38000), "New display rack for sanitary ware — thing owned, at cost", "NEFT DR–STEEL RACKS")
    b.pay(D(2026, 3, 31), sund, bank, R(1180), "Bank charges for the year", "CHGS DR")
    b.pay(D(2025, 12, 31), short, cash, R(1150), "Counter cash counted ₹1,150 less than the cash book — charged to Cash short / over")
    b.rec(D(2026, 3, 31), cash, short, R(300), "Counter cash counted ₹300 more than the cash book — got back to Cash short / over")
    b.v(D(2026, 3, 31), "Journal (written off)", "₹2,300 of Dhillon Plumbing Works' balance written off — he disputes the sanitary-ware bill and will not pay it", [(wo, R(2300)), (dpw, -R(2300))])
    b.finalize()
    b.gaps = [("Deposit paid – Kapoor Properties A/c", "a deposit paid to a named person: its own asset account per person, apart from any khata (owner, 13 Oct 2026; GAPS A2b)"),
              ("Goods Bought for Sale A/c", "purchases expensed; no closing stock (owner ruling — no inventory); profit is therefore sales less purchases")]
    c.books = [b]
    c.demonstrates = ["counter cash sales banked by transfer", "customers and suppliers on khata; a customer whose advance turns round", "salary advance recovered from salary",
                      "a correction of a wrong head", "purchases expensed — no stock"]
    return c


def build_partnership():
    c = Case("partnership-bal-fabricators", "Partnership — Bal Fabricators")
    c.intro = [
        "**Bal Fabricators** is a steel-fabrication and aluminium workshop owned by **Sukhwinder Bal**, **Pradeep Bal** and **Harjeet Singh**, who is from outside the family, sharing profit **2 : 2 : 1**. "
        "Each partner has a **fixed capital account** and a **current account**: drawings and costs a partner pays from his own pocket go to his current account; the capitals do not move. "
        "Their agreement gives **interest on capital at 6% a year**, then the rest of the profit in the ratio. At the year close the book posts the P&L Appropriation Account and adds each partner's part to his account. "
        "The year's big job is a contract for a builder, **Sandhu Builders**: a mobilisation advance, three running bills of which 5% is held back until the work of that bill is accepted, and the retention money kept in its own account beside the builder's khata. "
        "The powder-coating supplier is paid in advance and then sends his bill; the site foreman runs the labour money as an advance and accounts for it.",
    ]
    c.people = [
        ("Sukhwinder Bal", "Partner — share 2, capital ₹3,00,000"),
        ("Pradeep Bal", "Partner — share 2, capital ₹3,00,000; pays some workshop costs from his own pocket, as Sukhwinder does once"),
        ("Harjeet Singh", "Partner from outside the family — share 1, capital ₹1,50,000; draws as much as the others, more than his share of the profit"),
        ("Verka Dairy Plant · Punjab Steel Sheds", "Customers on khata"),
        ("Sandhu Builders", "Builder — contract job: mobilisation advance, running bills with 5% held back"),
        ("Jindal Steel Traders", "Steel supplier on khata"),
        ("Shree Powder Coaters", "Powder-coating supplier — paid in advance, then billed"),
        ("Gurmeet Singh", "Site foreman — holds the labour money as an advance, settled against his slips"),
    ]
    b = Book("Bal Fabricators", "partnership business book", "BF", "business")
    b.about = "Shared business book · three partners 2 : 2 : 1 · fixed capital and current accounts · interest on capital: 6% a year, as the partners agreed · customers and supplier on khata · a contract job with retention money."
    cash = b.add(Account("Cash A/c", "cash", "Workshop cash", R(15000)))
    bank = b.add(Account("Punjab & Sind Bank Current A/c", "bank", "Firm's current account", R(514000)))
    verka = b.add(Account("Verka Dairy Plant A/c", "party", "Customer (khata) — sheds and racks", R(48000)))
    pss = b.add(Account("Punjab Steel Sheds A/c", "party", "Customer (khata) — fabrication on job work"))
    sandhu = b.add(Account("Sandhu Builders A/c", "party", "Builder (khata) — contract job: advance first, then running bills less the 5% held back"))
    ret = b.add(Account("Retention held by – Sandhu Builders A/c", "retention", "5% of each bill the builder holds back until the work of that bill is accepted — released to the khata when due"))
    jin = b.add(Account("Jindal Steel Traders A/c", "party", "Supplier (khata) — steel sections and sheets", -R(72000)))
    pcw = b.add(Account("Shree Powder Coaters A/c", "party", "Supplier (khata) — powder coating; paid in advance, then billed"))
    fadv = b.add(Account("Advance – Gurmeet Singh (foreman) A/c", "advance", "Money with the foreman for site labour and small purchases, accounted for against his slips"))
    mach = b.add(Account("Machinery & Tools A/c", "fixed", "Welding sets, cutters, drills at what they cost", R(265000)))
    partners = [("Sukhwinder Bal", R(300000), -R(12000), 2), ("Pradeep Bal", R(300000), -R(8000), 2), ("Harjeet Singh", R(150000), R(0), 1)]
    for nm, capv, cur, sh in partners:
        b.add(Account("Capital A/c – %s" % nm, "pcapital", "%s's fixed capital (share %d)" % (nm, sh), -capv))
    for nm, capv, cur, sh in partners:
        b.add(Account("Current A/c – %s" % nm, "pcurrent", "%s's current account — drawings, costs paid for the firm" % nm, cur))
    inc = b.add(Account("Fabrication Income A/c", "income", "Work billed to customers — job work and the Sandhu Builders contract"))
    steel = b.add(Account("Steel & Material A/c", "expense", "Steel, paint, electrodes, bolts"))
    coat = b.add(Account("Powder Coating A/c", "expense", "Powder coating of finished work"))
    wages = b.add(Account("Wages A/c", "expense", "Welders' and helpers' wages, and site labour from the foreman's slips"))
    rent = b.add(Account("Workshop Rent A/c", "expense", "Rent of the workshop"))
    elec = b.add(Account("Electricity A/c", "expense", "Workshop electricity"))
    trn = b.add(Account("Transport A/c", "expense", "Carrying material and finished work"))
    sund = b.add(Account("Sundry A/c", "expense", "Small items, bank charges"))
    wo = b.add(Account("Written off A/c", "expense", "Money known not to come back — the foreman's lost labour slips"))
    # the openings: partners' accounts are asked of each partner; the firm's other openings must agree with them
    tot = sum(b.accounts[n].opening for n in b.order)
    assert tot == 0, ("partnership openings must balance", tot)
    cur = {nm: "Current A/c – %s" % nm for nm, _, _, _ in partners}
    b.partners = [{"name": nm, "capital": "Capital A/c – %s" % nm, "current": cur[nm], "share": sh, "ioc_bp": 600} for nm, _, _, sh in partners]
    b.own_word = "Partners' own money"
    b.chart_note = "Each partner's capital and current account is the figure that partner agreed; cash, bank, the customers, the supplier, the foreman's advance and the machinery are what the firm held. The Dr and Cr totals agree."
    b.custom = (sandhu, D(2025, 4, 1), D(2026, 3, 31), "The builder's khata for the year — the advance, three running bills (the 5% held back is in its own account), payments net of the advance, the retention released when due.")
    b.rec(D(2025, 4, 16), bank, verka, R(48000), "Verka Dairy Plant paid the March bill (opening balance)", "NEFT CR–VERKA DAIRY")
    for d, a, what in [(D(2025, 5, 28), R(386000), "cattle-shed frames"), (D(2025, 10, 30), R(418500), "milk-can racks and a canopy")]:
        b.gave(d, verka, inc, a, "Verka Dairy Plant — %s" % what)
    b.rec(D(2025, 7, 9), bank, verka, R(386000), "Verka Dairy Plant paid for the cattle-shed frames", "NEFT CR–VERKA DAIRY")
    b.rec(D(2025, 12, 18), bank, verka, R(418500), "Verka Dairy Plant paid for the racks and canopy", "NEFT CR–VERKA DAIRY")
    for d, a, what in [(D(2025, 6, 30), R(264000), "job work, April–June"), (D(2025, 9, 30), R(276500), "job work, July–September")]:
        b.gave(d, pss, inc, a, "Punjab Steel Sheds — %s" % what)
    b.rec(D(2025, 8, 12), bank, pss, R(264000), "Punjab Steel Sheds paid for April–June", "NEFT CR–PUNJAB STEEL SHEDS")
    b.rec(D(2025, 11, 14), bank, pss, R(276500), "Punjab Steel Sheds paid for July–September", "NEFT CR–PUNJAB STEEL SHEDS")
    # the contract job for a builder: mobilisation advance recovered bill by bill, 5% retention in its own account (O-06-4)
    b.rec(D(2025, 4, 10), bank, sandhu, R(150000), "Mobilisation advance from Sandhu Builders for the staircases and railings of Sunny Enclave", "RTGS CR–SANDHU BUILDERS")
    bills = [(D(2025, 6, 28), R(300000)), (D(2025, 9, 27), R(360000)), (D(2025, 12, 27), R(320000))]
    for k, (d, a) in enumerate(bills):
        held = a * 5 // 100
        b.v(d, "Journal (credit given)", "Running bill %d to Sandhu Builders (Sunny Enclave staircases, towers A–B) — ₹%s billed, 5%% (₹%s) held back" % (k + 1, fmt(a), fmt(held)),
            [(sandhu, a - held), (ret, held), (inc, -a)])
    for d, k in [(D(2025, 7, 22), 0), (D(2025, 10, 24), 1), (D(2026, 1, 23), 2)]:
        a = bills[k][1]
        b.rec(d, bank, sandhu, a - a * 5 // 100 - R(50000), "Sandhu Builders paid running bill %d less the 5%% held back and ₹50,000 of the advance" % (k + 1), "RTGS CR–SANDHU BUILDERS")
    b.v(D(2026, 2, 15), "Journal (retention released)", "Retention of running bill 1 (₹15,000) released by Sandhu Builders — the work of that bill accepted; moved to his khata", [(sandhu, R(15000)), (ret, -R(15000))])
    b.rec(D(2026, 3, 6), bank, sandhu, R(15000), "Sandhu Builders paid the released retention", "RTGS CR–SANDHU BUILDERS")
    for k, a in enumerate([R(198000), R(176000), R(214000), R(168000)]):
        b.took(Q4E[k], steel, jin, a, "Steel from Jindal Steel Traders on khata, %s" % Q4N[k])
    b.pay(D(2025, 4, 22), jin, bank, R(72000), "Jindal Steel Traders paid — opening balance", "RTGS DR–JINDAL STEEL")
    for d, k in [(D(2025, 7, 21), 0), (D(2025, 10, 20), 1), (D(2026, 1, 20), 2)]:
        b.pay(d, jin, bank, [R(198000), R(176000), R(214000)][k], "Jindal Steel Traders paid — steel of %s" % Q4N[k], "RTGS DR–JINDAL STEEL")
    # a supplier paid in advance: his account crosses to the Cr side when his bill comes, and back to nil when the rest is paid
    b.pay(D(2025, 6, 2), pcw, bank, R(60000), "Advance to Shree Powder Coaters for the staircases' powder coating", "NEFT DR–SHREE POWDER COATERS")
    b.took(D(2025, 7, 10), coat, pcw, R(73500), "Shree Powder Coaters' bill for the staircases' powder coating")
    b.pay(D(2025, 8, 5), pcw, bank, R(13500), "Shree Powder Coaters paid the rest of the bill", "NEFT DR–SHREE POWDER COATERS")
    for k in range(4):
        b.pay(Q4E[k], wages, bank, [R(126000), R(118000), R(132000), R(124000)][k], "Wages of the welders and helpers, %s" % Q4N[k], "NEFT DR–WAGES")
        b.pay(dt.date(Q4E[k].year, Q4E[k].month - 2, 5), rent, bank, R(36000), "Workshop rent, %s" % Q4N[k], "NEFT DR–WORKSHOP RENT")
    b.pay(D(2025, 9, 18), elec, bank, R(31400), "Workshop electricity, April–August", "BILLPAY DR–PSPCL")
    b.v(D(2026, 2, 16), "Journal (paid by partner)", "Workshop electricity, September–January, paid by Pradeep Bal from his own account", [(elec, R(33800)), (cur["Pradeep Bal"], -R(33800))])
    b.v(D(2025, 6, 12), "Journal (paid by partner)", "Truck hire for the Verka frames, paid by Sukhwinder Bal in cash from his pocket", [(trn, R(8500)), (cur["Sukhwinder Bal"], -R(8500))])
    for d, nm, a in [(D(2025, 7, 15), "Sukhwinder Bal", R(150000)), (D(2025, 7, 15), "Pradeep Bal", R(150000)),
                     (D(2025, 6, 2), "Harjeet Singh", R(50000)), (D(2025, 10, 24), "Harjeet Singh", R(50000)), (D(2026, 2, 2), "Harjeet Singh", R(50000))]:
        b.pay(d, cur[nm], bank, a, "Drawings of %s" % nm, "IMPS DR–%s" % nm.upper())
    # the foreman's advances: the first settled against several heads; the second with part of it written off (O-12-3)
    b.pay(D(2025, 11, 3), fadv, cash, R(25000), "Advance to the foreman for the Verka canopy site, cash")
    b.v(D(2025, 11, 29), "Journal (advance settled)", "Foreman's account of the canopy site — site labour and bolts, against his advance", [(wages, R(16400)), (steel, R(7900)), (fadv, -R(24300))])
    b.pay(D(2026, 2, 2), fadv, bank, R(20000), "Labour money to the foreman for the Sunny Enclave railings", "IMPS DR–GURMEET SINGH")
    b.v(D(2026, 3, 28), "Journal (advance settled)", "Foreman's slips for the Sunny Enclave railings set against his advance — ₹1,000 of slips lost, written off; ₹1,700 stays with him",
        [(wages, R(11800)), (steel, R(6200)), (wo, R(1000)), (fadv, -R(19000))])
    b.move(D(2025, 10, 6), cash, bank, R(20000), "Cash withdrawn for the workshop (ATM)", "ATM WDL–MOGA")
    b.pay(D(2025, 12, 9), mach, bank, R(68000), "New MIG welding set — thing owned, at cost", "NEFT DR–WELDING SET")
    wrong = b.pay(D(2025, 8, 23), steel, cash, R(4200), "Tempo hire for the Verka frames' delivery, cash")
    b.fix(D(2025, 9, 2), trn, steel, R(4200), "Entry {ref} (tempo hire) was written to Steel & Material — moved to Transport", "Journal (correction)", ref=wrong)
    b.finalize()
    b.assets_note = "Each partner's account after the year's interest and share is shown in the table above. The builder's retention money is in its own account: money the firm will get as the work of each bill is accepted."
    b.gaps = [("Current A/c – each partner", "02 §1.2 has one `partner` account per member; practice keeps a fixed capital and a current account (GAPS B2)"),
              ("P&L Appropriation A/c", "interest on capital (as agreed, only out of profit) and the 2:2:1 share posted at the year close to the partners' current accounts (O-14-1, O-14-3; GAPS B1)"),
              ("Paid by a partner", "a partner pays a firm cost from his own pocket — Dr expense · Cr partner's current account"),
              ("Retention held by – Sandhu Builders A/c", "retention money in its own asset account beside the khata, released by transfer (O-06-4; GAPS D2)")]
    c.books = [b]
    c.demonstrates = ["fixed capital and current accounts for three partners; a posted P&L Appropriation: 6% interest on capital out of profit, then 2 : 2 : 1",
                      "a contract job for a builder: mobilisation advance recovered bill by bill, 5% retention in its own account, released when due", "a supplier paid in advance whose account crosses to the other side and back",
                      "an advance settled with part written off", "partners paying firm costs from their own pocket", "a partner whose current account stays on the Dr side after his interest and share", "a correction"]
    return c


CASE_BUILDERS += [build_shop, build_partnership]


def build_trust():
    c = Case("trust-radha-soami-satsang-sabha", "Trust — Radha Soami Satsang Sabha")
    c.intro = [
        "A satsang sabha with a **gollak** counted every two months before the secretary and a witness and emptied only into the cash box or the bank, sponsors' donations by bank, "
        "donations for the dairy, a **langar** run through the sewadar's advance, a small dairy, a new langar hall being built — written as **Construction**, an expense head — and two labourers, "
        "**Manni** and **Ravinder**, paid in cash each quarter, each with his own expense head. Daily-wage labour at the big diwans is *Labour*. "
        "Money given **for the langar hall** goes to the **Langar Hall Fund** with its own fixed deposit, whose interest is added to the fund; when the hall is paid for from the fund the cost is charged to the year "
        "and the same amount is moved out of the fund in one action. "
        "The year-end statements are Receipts & Payments, Income & Expenditure, the Balance Sheet with the General Fund, and a statement of each fund.",
    ]
    c.people = [
        ("Ranjeet Singh", "Secretary — witness at every gollak count; signs the bank payments"),
        ("Amritpal Singh", "Sewadar — counts the gollak; holds the langar advance and accounts for it"),
        ("Manni · Ravinder", "Labourers paid in cash each quarter — each has his own expense head"),
        ("Kotli Cement Store", "Building-material store — cement and bricks for the hall on khata"),
        ("Three families and an NRI donor", "Gave for the langar hall — the money went to the Langar Hall Fund; one family donated a steel almirah that the trust keeps"),
    ]
    b = Book("Radha Soami Satsang Sabha", "trust book", "RS", "npo")
    b.about = "Trust book · gollak counted and emptied into cash or bank · langar through the sewadar's advance · dairy · construction as an expense · a Langar Hall Fund (the donors' money for the hall) with its deposit and interest · two labourers with their own heads."
    b.own_word = "General Fund"
    cash = b.add(Account("Cash A/c", "cash", "The trust's cash box, with the secretary", R(22000)))
    gol = b.add(Account("Gollak Cash A/c", "gollak", "The gollak — counted every two months, emptied only into the cash box or the bank"))
    bank = b.add(Account("SBI Current A/c", "bank", "The trust's current account", R(485000)))
    lfd = b.add(Account("SBI Fixed Deposit (Langar Hall Fund) A/c", "invest", "Fixed deposit made from the langar hall donations — its interest goes to the Langar Hall Fund", R(200000)))
    adv = b.add(Account("Advance – Amritpal Singh A/c", "advance", "Langar money with the sewadar, accounted for with bills"))
    cem = b.add(Account("Kotli Cement Store A/c", "party", "Building-material store (khata) — cement and bricks for the hall"))
    furn = b.add(Account("Furniture & Equipment A/c", "fixed", "Things given to the trust and kept, at ₹1 each — the estimated value is in the entry's note"))
    lfund = b.add(Account("Langar Hall Fund A/c", "fund", "Money given for the langar hall and the interest on its deposit — kept for that purpose only", -R(250000)))
    gf = b.add(Account("General Fund A/c", "capital", "The trust's own money (the year's surplus or deficit is added at the year end)"))
    golinc = b.add(Account("Donations – gollak A/c", "income", "Money counted from the gollak (the count records the donation)"))
    ltr = b.add(Account("Transferred from the Langar Hall Fund A/c", "income", "What the fund pays for the hall, moved out of the fund so the fund's own result stays nil"))
    don = b.add(Account("Donation A/c", "income", "Donations from sponsors and the sangat by bank or receipt"))
    ddon = b.add(Account("Dairy Donation A/c", "income", "Donations given for the dairy"))
    bint = b.add(Account("Bank Interest A/c", "income", "Interest credited by the bank"))
    cons = b.add(Account("Construction A/c", "expense", "The new langar hall — cement, bricks, steel, mason (written as an expense)"))
    genx = b.add(Account("General Expense A/c", "expense", "Electricity, tent, printing, small items"))
    dairy = b.add(Account("Dairy Expense A/c", "expense", "Fodder, feed and the vet for the dairy"))
    lab = b.add(Account("Labour A/c", "expense", "Daily-wage labour at the big diwans and repairs"))
    manni = b.add(Account("Manni Labour A/c", "expense", "Manni's wages"))
    ravi = b.add(Account("Ravinder Labour A/c", "expense", "Ravinder's wages"))
    lang = b.add(Account("Langar A/c", "expense", "Langar provisions — atta, dal, ghee, sabzi, gas"))
    b.balance_opening_into(gf)
    b.custom = (gol, D(2025, 4, 1), D(2026, 3, 31), "The gollak for the year — each count (the donation is recorded when it is counted), and where its money went: always into the cash box or the bank, never spent from the box.")
    counts = [(D(2025, 5, 31), R(86450)), (D(2025, 7, 31), R(74200)), (D(2025, 9, 30), R(69850)), (D(2025, 11, 30), R(112600)), (D(2026, 1, 31), R(81300)), (D(2026, 3, 29), R(95750))]
    for k, (d, a) in enumerate(counts):
        b.rec(d, gol, golinc, a, "Gollak counted by Amritpal Singh, witnessed by Ranjeet Singh (note-count sheet %d)" % (k + 1))
        if k % 2 == 0:
            b.move(d, cash, gol, R(50000), "Part of the gollak put in the cash box the same day")
            b.move(d + dt.timedelta(days=2), bank, gol, a - R(50000), "Rest of the gollak deposited in the bank", "CASH DEP–GOLLAK")
        else:
            b.move(d + dt.timedelta(days=1), bank, gol, a, "Gollak deposited in the bank", "CASH DEP–GOLLAK")
    for d, a, who in [(D(2025, 4, 14), R(51000), "a family on Baisakhi"), (D(2025, 8, 9), R(25000), "a sponsor for the monthly satsang"), (D(2025, 11, 5), R(110000), "sponsors for the Gurpurab diwan"), (D(2026, 2, 21), R(31000), "an NRI family")]:
        b.rec(d, bank, don, a, "Donation from %s" % who, "NEFT CR–DONATION")
    b.rec(D(2025, 6, 12), cash, ddon, R(4100), "Donation for the dairy (cow feed), cash")
    b.rec(D(2025, 12, 8), bank, ddon, R(15000), "Donation for the dairy", "NEFT CR–DAIRY DONATION")
    b.rec(D(2026, 3, 31), bank, bint, R(6840), "Interest credited by the bank", "INT.CR")
    b.took(D(2025, 7, 18), cons, cem, R(148000), "Langar hall — cement and bricks on the store's khata")
    b.pay(D(2025, 9, 10), cem, bank, R(148000), "Kotli Cement Store paid for the cement and bricks", "NEFT DR–KOTLI CEMENT")
    for d, a, who in [(D(2025, 5, 20), R(51000), "a family, for the langar hall"), (D(2025, 8, 12), R(25000), "an NRI family, for the langar hall"), (D(2026, 1, 20), R(31000), "a family in memory of an elder, for the langar hall")]:
        b.rec(d, bank, lfund, a, "Donation from %s — to the Langar Hall Fund" % who, "NEFT CR–HALL DONATION")
    b.v(D(2026, 3, 20), "Journal (interest added)", "Yearly interest added by the bank to the deposit made from the langar hall donations — added to the Langar Hall Fund", [(lfd, R(14000)), (lfund, -R(14000))])
    for d, a, what in [(D(2025, 10, 14), R(186000), "steel and shuttering"), (D(2025, 12, 22), R(124000), "mason contractor, first bill")]:
        b.v(d, "Payment (from a fund)", "Langar hall — %s, paid from the Langar Hall Fund" % what, [(cons, a), (lfund, a), (bank, -a), (ltr, -a)], stmt="NEFT DR–CONSTRUCTION")
    b.pay(D(2026, 3, 16), cons, bank, R(96000), "Langar hall — mason contractor, second bill (from the trust's general money)", "NEFT DR–CONSTRUCTION")
    b.v(D(2026, 2, 8), "Journal", "A family gave a steel almirah for the office — kept by the trust, entered at ₹1; estimated value ₹18,000", [(furn, R(1)), (don, -R(1))])
    for k in range(4):
        b.pay(Q4E[k], manni, cash, R(27000), "Manni's wages, %s, cash" % Q4N[k])
        b.pay(Q4E[k], ravi, cash, R(25500), "Ravinder's wages, %s, cash" % Q4N[k])
    for d0, d1, give, spent in [(D(2025, 4, 2), D(2025, 6, 30), R(60000), R(58650)), (D(2025, 10, 1), D(2025, 12, 31), R(90000), R(88400)), (D(2026, 1, 2), D(2026, 3, 31), R(60000), R(61850))]:
        b.pay(d0, adv, bank, give, "Langar advance to Amritpal Singh", "IMPS DR–AMRITPAL SINGH")
        b.v(d1, "Journal (advance settled)", "Amritpal Singh's langar bills set against his advance", [(lang, spent), (adv, -spent)])
    b.pay(D(2025, 11, 4), lab, cash, R(18000), "Daily-wage labour for the Gurpurab diwan, cash")
    for d, a in [(D(2025, 6, 20), R(14600)), (D(2025, 10, 20), R(12800)), (D(2026, 2, 18), R(16200))]:
        b.pay(d, dairy, bank, a, "Fodder and feed for the dairy", "UPI DR–FODDER")
    b.pay(D(2025, 9, 15), genx, bank, R(21400), "Electricity, April–August", "BILLPAY DR–PSPCL")
    b.pay(D(2026, 2, 14), genx, bank, R(19800), "Electricity, September–January", "BILLPAY DR–PSPCL")
    b.move(D(2025, 6, 27), cash, bank, R(45000), "Cash withdrawn for wages (cheque, self)", "CHQ WDL–SELF")
    b.move(D(2025, 12, 29), cash, bank, R(45000), "Cash withdrawn for wages (cheque, self)", "CHQ WDL–SELF")
    wrong = b.pay(D(2025, 9, 6), genx, cash, R(2800), "Fodder for the dairy, cash")
    b.fix(D(2025, 9, 20), dairy, genx, R(2800), "Entry {ref} (fodder) was written to General Expense — moved to Dairy Expense", "Journal (correction)", ref=wrong)
    b.finalize()
    b.construction = ("Construction A/c", "the langar hall")
    b.journal_word = "a thing given in kind and kept"   # 04 §4.3: the hall's cost to date (construction began this year)
    b.assets_note = "The Langar Hall Fund is money held for that purpose and is shown with the own money, beside the General Fund, not inside it."
    b.gaps = [("Gollak Cash A/c", "money subtype cash_collection: the count records the donation (Dr Gollak · Cr Donations – gollak), emptying is a transfer (O-17-8)"),
              ("Langar Hall Fund A/c", "a fund for a purpose — the donors' money for the hall, restricted by them, not set aside by the committee (ICAI TG on NPOs ¶106); spending is one action, two postings: the cost to Income & Expenditure and the same amount transferred from the fund (O-17-1); interest on the fund's deposit goes to the fund (O-17-2) — GAPS A4, E2"),
              ("Furniture & Equipment A/c", "a thing donated and kept is entered at ₹1 with its estimated value in the note (O-17-7)"),
              ("Construction A/c", "an expense head — confirmed by the owner 13 Oct 2026, although ADR 2026-10-12 §6's asset class could hold a building at cost"),
              ("Dairy Donation A/c", "income (donations received for the dairy) — confirmed by the owner 13 Oct 2026"),
              ("R&P", "Receipts & Payments for organization books (GAPS A8)")]
    c.books = [b]
    c.demonstrates = ["gollak counts that record the donation, emptied only into cash or bank", "langar through the sewadar's advance", "Manni and Ravinder as expense heads", "construction as an expense head",
                      "a Langar Hall Fund for a purpose (the donors' money for the hall): donations for the hall, its fixed deposit's interest added to the fund, the hall paid from the fund in one action", "a donated thing kept at ₹1", "R&P, I&E, Balance Sheet and a statement of each fund", "a correction"]
    return c


CASE_BUILDERS.append(build_trust)


def build_family():
    c = Case("joint-family-randhawa", "Joint family and its businesses — the Randhawa family (seven books)")
    c.intro = [
        "Three brothers — **Amarjeet**, **Lakhbeer** and **Lakhwinder Randhawa** — keep a joint household. **Randhawa Joint Family** is the joint family's own book: the house, the gold, the deposits, "
        "the common kitchen, and one account for each sub-family — what the family spent for that household or gave it, less what the household put in, into the family or into a family business. "
        "A sub-family account is not a debt: at the year end it is settled or carried forward, as the family decides. Each brother's household keeps its own book. "
        "The family owns **Randhawa Agriculture** and **Randhawa Real Estate** outright and shares **Randhawa Brick Field** 3 : 2 with an outside partner, **Nirmaljeet Gill**; "
        "money a business sends home is the family's income. Money that moves between two books is written in both, in accounts named after the other book, and the family summary shows each pair agreeing.",
    ]
    c.people = [
        ("Amarjeet Randhawa", "Eldest brother — keeps the joint family's book and runs the farm; head of his household (with Indu Randhawa)"),
        ("Lakhbeer Randhawa", "Brother — runs the brick field; head of his household (with his son Aman Randhawa); took ₹50,000 from the family in August, to be returned"),
        ("Lakhwinder Randhawa", "Brother — a salaried teacher, looks after the real estate; head of his household (with Harjeet and Supreet Randhawa)"),
        ("Aman Randhawa", "Lakhbeer's son — runs the farm day to day; holds the farm-labour advance"),
        ("Nirmaljeet Gill", "Outside partner in the brick field — share 2 of 5"),
    ]
    q = Q4N
    qe = Q4E
    # ---------------- books and accounts ------------------------------------------------------
    F = Book("Randhawa Joint Family", "joint family book", "RJ", "household")
    F.journal_word = "money a sub-family put straight into a family business"
    F.about = "The joint family's own book · house, gold and deposits · the common kitchen · one account per sub-family, settled or carried forward · money put into the family businesses · their money sent home as family income."
    F.own_word = "Family's own money"
    F.put_note = " (by the sub-families, and their accounts settled)"
    F.taken_note = " (given to the sub-families or spent for them)"
    A = Book("Amarjeet's Family", "household book", "RA", "household")
    A.about = "Amarjeet and Indu's household · money from the joint family · Indu's stitching · a grocer's khata · the account with the family settled at the year end."
    Bb = Book("Lakhbeer's Family", "household book", "RB", "household")
    Bb.about = "Lakhbeer and Aman's household · money from the joint family, and ₹50,000 taken to be returned — part paid back through the brick field, the rest from his share · a motorcycle · a chemist's khata · a painter's advance."
    C = Book("Lakhwinder's Family", "household book", "RC", "household")
    C.about = "Lakhwinder, Harjeet and Supreet's household · Lakhwinder's salary · Harjeet's tuition · a credit card · a recurring deposit · money put into the family and into the brick field."
    G = Book("Randhawa Agriculture", "family business book", "RG", "business")
    G.about = "The family farm · KCC loan account · fertiliser khata · paddy through an arhtiya · Aman's labour advance · land on lease (theka)."
    E = Book("Randhawa Real Estate", "family business book", "RE", "property")
    E.about = "Two shops let at Kotli Chowk · rent charged quarterly · a plot sold and another bought · tenants' deposits, one set off and forfeited when a tenant left owing · rent written off · an improvement added to the cost."
    K = Book("Randhawa Brick Field", "shared business book", "RK", "business")
    K.about = "Brick kiln shared 3 : 2 by the joint family and Nirmaljeet Gill · no interest on capital — the profit is shared 3 : 2 · bricks on khata · coal on credit · the pathera's advance."
    for bk in (A, Bb, C, F, G, E, K):
        bk.counts["min"], bk.counts["max"] = 25, 40
    # Randhawa Joint Family
    fc = F.add(Account("Cash A/c", "cash", "The family's cash, with Amarjeet", R(35000)))
    fb = F.add(Account("SBI Joint Savings A/c", "bank", "The family's joint savings account", R(420000)))
    ffd = F.add(Account("SBI Fixed Deposit A/c", "invest", "The family's fixed deposits", R(500000)))
    fhouse = F.add(Account("Family House, Village Kotli A/c", "fixed", "The family house at what it cost", R(2500000)))
    fgold = F.add(Account("Family Gold A/c", "fixed", "Gold and jewellery at what it cost", R(600000)))
    SUBCOLS = ("Spent for them / given (Dr)", "Put in by them (Cr)")
    fA = F.add(Account("Amarjeet's Family A/c", "partner", "Amarjeet's household's account — spent for it or given, less put in; settled or carried forward", R(18000), group="Sub-family", cols=SUBCOLS))
    fB = F.add(Account("Lakhbeer's Family A/c", "partner", "Lakhbeer's household's account — spent for it or given, less put in; settled or carried forward", group="Sub-family", cols=SUBCOLS))
    fC = F.add(Account("Lakhwinder's Family A/c", "partner", "Lakhwinder's household's account — puts in more than it draws; carried forward", -R(12000), group="Sub-family", cols=SUBCOLS))
    fG = F.add(Account("Randhawa Agriculture A/c", "stake", "The family's money put into its farm, at what it put in"))
    fE = F.add(Account("Randhawa Real Estate A/c", "stake", "The family's money put into its real estate, at what it put in"))
    fK = F.add(Account("Randhawa Brick Field A/c", "stake", "The family's money put into the brick field (its 3 of 5 share), at what it put in"))
    fmilk = F.add(Account("Doodhwala (milk khata) A/c", "party", "Milkman (khata) — milk for the common kitchen, settled each half-year", -R(9600)))
    fmason = F.add(Account("Advance – mason A/c", "advance", "Advance to the mason for the roof, settled against his bill"))
    fcap = F.add(Account("Capital A/c – Randhawa family", "capital", "The family's own money"))
    fiG = F.add(Account("Income from Randhawa Agriculture A/c", "income", "Money the farm sent home — the family's income"))
    fiE = F.add(Account("Income from Randhawa Real Estate A/c", "income", "Money the real estate sent home — the family's income"))
    fiK = F.add(Account("Income from Randhawa Brick Field A/c", "income", "Money the family took from the brick field — the family's income"))
    fint = F.add(Account("Interest A/c", "income", "Interest on savings and fixed deposits"))
    fkit = F.add(Account("Common Kitchen & Ration A/c", "expense", "Atta, dal, ghee, milk and gas for the common kitchen"))
    felec = F.add(Account("Electricity & Water A/c", "expense", "The house's electricity and water"))
    fmed = F.add(Account("Elders' Medical A/c", "expense", "Doctor and medicines for the elders"))
    fsoc = F.add(Account("Gurdwara & Social A/c", "expense", "Gurdwara, weddings, shagun"))
    frep = F.add(Account("House Repairs A/c", "expense", "Repairs to the family house"))
    fcar = F.add(Account("Family Car A/c", "expense", "Fuel, service and insurance of the family car"))
    fhA = F.add(Account("Household Expenses – Amarjeet's family A/c", "expense", "Amarjeet's household's account for the year, borne by the family when settled"))
    fshare = F.add(Account("Business Income Shared Out A/c", "shareout", "A sub-family's share of the family's business income, shared out of the family's own money to settle its account — not a cost"))
    # households
    def household(bk, bank_name, bank_open, cash_open, link_open):
        bc = bk.add(Account("Cash A/c", "cash", "Cash at home", cash_open))
        bb = bk.add(Account(bank_name, "bank", "The household's bank account", bank_open))
        bl = bk.add(Account("Randhawa Joint Family A/c", "partner", "Our account with the joint family — received from it, less put in; settled or carried forward", link_open,
                            group="Joint family", cols=("Put in / paid back (Dr)", "Received from the family (Cr)")))
        return bc, bb, bl
    ac, ab, aF = household(A, "PNB Savings A/c", R(64000), R(6000), -R(18000))
    agro = A.add(Account("Gill Kiryana Store A/c", "party", "Grocer (khata)", -R(4200)))
    acust = A.add(Account("Sidhu family A/c", "party", "Neighbours — suits stitched on credit"))
    acap = A.add(Account("Capital A/c – Amarjeet's family", "capital", "The household's own money"))
    ast = A.add(Account("Stitching Income A/c", "income", "Indu's stitching work"))
    afam = A.add(Account("Received from the Joint Family A/c", "income", "Our account with the family for the year, borne by the family when settled"))
    aint = A.add(Account("Interest A/c", "income", "Savings interest"))
    ahh = A.add(Account("Household & Groceries A/c", "expense", "Groceries and household things"))
    acl = A.add(Account("Clothes & Personal A/c", "expense", "Clothes and personal things"))
    amed = A.add(Account("Medical A/c", "expense", "Doctor and medicines"))
    aph = A.add(Account("Phone & Travel A/c", "expense", "Mobiles and bus fares"))
    asoc = A.add(Account("Gifts & Social A/c", "expense", "Shagun and gifts"))
    ahelp = A.add(Account("House Help A/c", "expense", "The house help's wages"))
    aadv = A.add(Account("Advance – house help A/c", "advance", "Advance to the house help, set against her wages"))
    bc, bb, bF = household(Bb, "HDFC Savings A/c", R(85000), R(5000), 0)
    bchem = Bb.add(Account("Bajwa Medical Store A/c", "party", "Chemist (khata)"))
    bpaint = Bb.add(Account("Advance – painter A/c", "advance", "Advance to the painter for the rooms, settled against his bill"))
    bbike = Bb.add(Account("Motorcycle A/c", "fixed", "Aman's motorcycle at what it cost (August 2025)"))
    bcap = Bb.add(Account("Capital A/c – Lakhbeer's family", "capital", "The household's own money"))
    bint = Bb.add(Account("Interest A/c", "income", "Savings interest"))
    bshare = Bb.add(Account("Share of Family Business Income A/c", "income", "Our share of the family's business income, used to settle what we took"))
    bhh = Bb.add(Account("Household & Groceries A/c", "expense", "Groceries and household things"))
    bedu = Bb.add(Account("Education A/c", "expense", "College fees and books"))
    bmed = Bb.add(Account("Medical A/c", "expense", "Medicines on the chemist's khata"))
    bfuel = Bb.add(Account("Fuel & Phone A/c", "expense", "Motorcycle fuel and mobiles"))
    bhome = Bb.add(Account("Rooms & Furnishing A/c", "expense", "Painting and furnishing of the rooms"))
    cc_, cb, cF = household(C, "SBI Salary A/c", R(48000), R(7000), R(12000))
    ccard = C.add(Account("SBI Credit Card A/c", "card", "Credit card — what is owed on it", -R(6800)))
    crd = C.add(Account("Post Office RD A/c", "invest", "Recurring deposit in the post office", R(36000)))
    ccap = C.add(Account("Capital A/c – Lakhwinder's family", "capital", "The household's own money"))
    csal = C.add(Account("Salary A/c", "income", "Lakhwinder's salary as a government teacher (after deductions)"))
    ctu = C.add(Account("Tuition Income A/c", "income", "Harjeet's home tuition"))
    chh = C.add(Account("Household & Groceries A/c", "expense", "Groceries and household things"))
    csch = C.add(Account("School Fees A/c", "expense", "Supreet's school fees and books"))
    cel = C.add(Account("Electricity & Phone A/c", "expense", "Electricity of their floor, mobiles, internet"))
    cmed = C.add(Account("Medical A/c", "expense", "Doctor and medicines"))
    ccl = C.add(Account("Clothes & Social A/c", "expense", "Clothes, gifts and outings"))
    cdairy = C.add(Account("Kotli Dairy A/c", "party", "Dairy shop (khata) — milk and curd for their floor"))
    celad = C.add(Account("Advance – electrician A/c", "advance", "Advance to the electrician for rewiring their floor"))
    # Agriculture
    gc = G.add(Account("Cash A/c", "cash", "Farm cash, with Aman", R(8000)))
    gb = G.add(Account("PNB Savings A/c (farm)", "bank", "The farm's bank account", R(95000)))
    gk = G.add(Account("KCC – PNB A/c", "cc", "Kisan Credit Card loan account — what is owed to the bank (limit ₹5,00,000)", -R(320000)))
    gfert = G.add(Account("Sandhu Fertilisers A/c", "party", "Fertiliser and spray dealer (khata)", -R(26500)))
    garh = G.add(Account("Bansal & Sons A/c", "party", "Arhtiya (khata) — paddy sold through him"))
    gadv = G.add(Account("Advance – Aman Randhawa A/c", "advance", "Labour money with Aman, accounted for with the labour slips"))
    gmilkp = G.add(Account("Verka Milk Society A/c", "party", "Dairy society (khata) — milk bills, paid later", R(21600)))
    gland = G.add(Account("Farm Land, Village Kotli A/c", "fixed", "18 acres of family land at what it cost", R(5400000)))
    gtrac = G.add(Account("Tractor & Implements A/c", "fixed", "Tractor, combine attachments, implements at cost", R(920000)))
    gbuff = G.add(Account("Buffaloes A/c", "fixed", "Four buffaloes at what they cost", R(320000)))
    gF = G.add(Account("Capital A/c – Randhawa Joint Family", "capital", "The owner's own money in the farm — the joint family's; named after the owner's book"))
    gFd = G.add(Account("Drawings A/c – Randhawa Joint Family", "drawings", "Money the farm sent home to the joint family; closed to own money at the year end"))
    gwh = G.add(Account("Wheat Sales A/c", "income", "Wheat sold at MSP"))
    gpad = G.add(Account("Paddy Sales A/c", "income", "Paddy sold through the arhtiya (full sale value)"))
    gmilk = G.add(Account("Milk Sales A/c", "income", "Milk to the dairy society"))
    goth = G.add(Account("Straw & PM-Kisan Income A/c", "income", "Straw sold, and PM-Kisan instalments"))
    gseed = G.add(Account("Seed A/c", "expense", "Seed"))
    gfx = G.add(Account("Fertiliser & Sprays A/c", "expense", "Urea, DAP, sprays"))
    gdsl = G.add(Account("Diesel & Repairs A/c", "expense", "Diesel and tractor repairs"))
    glab = G.add(Account("Labour A/c", "expense", "Transplanting, harvest and daily labour"))
    gth = G.add(Account("Theka (Land Lease) A/c", "expense", "Rent for 6 acres taken on theka"))
    garx = G.add(Account("Arhtiya Charges A/c", "expense", "Commission and market charges kept by the arhtiya"))
    gki = G.add(Account("Interest on KCC A/c", "expense", "Interest charged to the KCC"))
    gfeed = G.add(Account("Cattle Feed & Vet A/c", "expense", "Feed, fodder and the vet for the buffaloes"))
    # Real Estate
    ec = E.add(Account("Cash A/c", "cash", "Cash, with Lakhwinder", R(3000)))
    eb = E.add(Account("Axis Bank Current A/c", "bank", "The real estate's current account", R(140000)))
    et1 = E.add(Account("Kotli Medical Hall A/c", "party", "Tenant (khata) — shop 1, ₹12,000 a month"))
    et2 = E.add(Account("Bhullar Hardware A/c", "party", "Tenant (khata) — shop 2, ₹10,000 a month", R(10000)))
    edep1 = E.add(Account("Deposit held – Kotli Medical Hall A/c", "deposit", "Security deposit from the shop 1 tenant — returned when he leaves", -R(36000)))
    edep2 = E.add(Account("Deposit held – Bhullar Hardware A/c", "deposit", "Security deposit from the shop 2 tenant", -R(30000)))
    eadv = E.add(Account("Advance – registry clerk A/c", "advance", "Money with the registry clerk for stamp duty, settled against the registry"))
    eshops = E.add(Account("Shops at Kotli Chowk A/c", "fixed", "Two shops at what they cost", R(1850000)))
    eplot = E.add(Account("Plot No. 14, Model Colony A/c", "fixed", "Plot bought in 2021, at what it cost — sold in November 2025", R(1200000)))
    eplot2 = E.add(Account("Plot No. 7, Green Enclave A/c", "fixed", "Plot bought in February 2026, at what it cost"))
    eF = E.add(Account("Capital A/c – Randhawa Joint Family", "capital", "The owner's own money in the real estate — the joint family's; named after the owner's book"))
    eFd = E.add(Account("Drawings A/c – Randhawa Joint Family", "drawings", "Money the real estate sent home to the joint family; closed to own money at the year end"))
    erent = E.add(Account("Rent Income A/c", "income", "Rent of the two shops"))
    egain = E.add(Account("Profit on Sale of Plot A/c", "income", "Sale price of the plot less what it cost"))
    eforf = E.add(Account("Deposit forfeited A/c", "income", "Part of a tenant's deposit kept when he left without notice"))
    etax = E.add(Account("Property Tax A/c", "expense", "Municipal property tax"))
    erep = E.add(Account("Repairs A/c", "expense", "Repairs to the shops"))
    ebrok = E.add(Account("Brokerage A/c", "expense", "Dealer's brokerage on the plot sale"))
    ewo = E.add(Account("Rent written off A/c", "expense", "Rent a tenant will not pay, after it was asked for"))
    # Brick field
    kc = K.add(Account("Cash A/c", "cash", "Kiln cash, with the munshi", R(15000)))
    kb = K.add(Account("HDFC Bank Current A/c", "bank", "The brick field's current account", R(210000)))
    ks1 = K.add(Account("Sidhu Builders A/c", "party", "Customer (khata) — bricks by the trolley", R(84000)))
    ks2 = K.add(Account("Dhaliwal Contractors A/c", "party", "Customer (khata)"))
    kcoal = K.add(Account("Jindal Coal Depot A/c", "party", "Coal supplier (khata)", -R(95000)))
    kadv = K.add(Account("Advance – pathera jamadar A/c", "advance", "Advance to the moulders' jamadar, settled against bricks moulded"))
    kkiln = K.add(Account("Kiln & Chimney A/c", "fixed", "The kiln, chimney and sheds at what they cost", R(1650000)))
    kF = K.add(Account("Randhawa Joint Family A/c", "partner", "The joint family's partner's account (share 3 of 5); named after its book"))
    kG = K.add(Account("Nirmaljeet Gill A/c", "partner", "Nirmaljeet Gill's partner's account (share 2 of 5)"))
    ksale = K.add(Account("Brick Sales A/c", "income", "Bricks sold"))
    kcx = K.add(Account("Coal A/c", "expense", "Coal for firing"))
    kmould = K.add(Account("Moulding Labour A/c", "expense", "Patheras paid per thousand bricks"))
    kload = K.add(Account("Loading & Transport A/c", "expense", "Loading, tractor-trolley hire"))
    kroy = K.add(Account("Land Lease & Royalty A/c", "expense", "Lease of the kiln land and earth royalty"))
    krep = K.add(Account("Repairs & Sundry A/c", "expense", "Kiln repairs and small items"))
    # openings: business books balance into the owners' accounts; the joint book mirrors them; households mirror the joint book
    G.balance_opening_into(gF)
    E.balance_opening_into(eF)
    K.accounts[kG].opening = -R(700000)
    K.balance_opening_into(kF)
    F.accounts[fG].opening = -G.accounts[gF].opening
    F.accounts[fE].opening = -E.accounts[eF].opening
    F.accounts[fK].opening = -K.accounts[kF].opening
    F.balance_opening_into(fcap)
    A.balance_opening_into(acap)
    Bb.balance_opening_into(bcap)
    C.balance_opening_into(ccap)
    K.partners = [{"name": "Randhawa Joint Family", "capital": None, "current": kF, "share": 3}, {"name": "Nirmaljeet Gill", "capital": None, "current": kG, "share": 2}]
    K.own_word = "Partners' own money"
    K.chart_note = "Nirmaljeet Gill's account is the figure he agreed; the joint family's account is the balancing figure, so the Dr and Cr totals agree."
    G.chart_note = E.chart_note = "The owner's capital — the joint family's — is the balancing figure, so the Dr and Cr totals agree."

    def pair(d, frm, frm_acct, frm_money, to, to_acct, to_money, amt, n_from, n_to, s_from=None, s_to=None):
        """Money moves from one family book to another: Money out in the first, Money in in the second."""
        frm.pay(d, frm_acct, frm_money, amt, n_from, s_from)
        to.rec(d, to_money, to_acct, amt, n_to, s_to)

    # ---------------- money between the books -------------------------------------------------
    # family businesses → joint family: money sent home is the family's income; joint family → business: money put in
    pair(D(2025, 5, 6), G, gFd, gb, F, fiG, fb, R(400000), "Wheat money sent home to the joint family", "Wheat money sent home by Randhawa Agriculture", "NEFT DR–RANDHAWA JOINT FAMILY", "NEFT CR–RANDHAWA AGRI")
    pair(D(2025, 11, 25), G, gFd, gb, F, fiG, fb, R(350000), "Paddy money sent home to the joint family", "Paddy money sent home by Randhawa Agriculture", "NEFT DR–RANDHAWA JOINT FAMILY", "NEFT CR–RANDHAWA AGRI")
    pair(D(2025, 6, 20), F, fG, fb, G, gF, gb, R(80000), "Put into Randhawa Agriculture for the paddy nursery and theka", "Put in by the joint family for the paddy nursery and theka", "NEFT DR–RANDHAWA AGRI", "NEFT CR–RANDHAWA JOINT FAMILY")
    pair(D(2025, 9, 15), E, eFd, eb, F, fiE, fb, R(60000), "Rent surplus sent home to the joint family", "Rent surplus sent home by Randhawa Real Estate", "NEFT DR–RANDHAWA JOINT FAMILY", "NEFT CR–RANDHAWA REAL ESTATE")
    pair(D(2025, 12, 10), E, eFd, eb, F, fiE, fb, R(250000), "Part of the plot money sent home to the joint family", "Plot money sent home by Randhawa Real Estate", "NEFT DR–RANDHAWA JOINT FAMILY", "NEFT CR–RANDHAWA REAL ESTATE")
    pair(D(2025, 10, 20), F, fK, fb, K, kF, kb, R(200000), "Put into the brick field for the season (the family's share)", "Put in by the joint family for the season", "NEFT DR–RANDHAWA BRICK FIELD", "NEFT CR–RANDHAWA JOINT FAMILY")
    pair(D(2025, 7, 10), K, kF, kb, F, fiK, fb, R(150000), "Taken out by the joint family", "Taken from the brick field — the family's income", "NEFT DR–RANDHAWA JOINT FAMILY", "NEFT CR–RANDHAWA BRICK FIELD")
    pair(D(2026, 3, 20), K, kF, kb, F, fiK, fb, R(180000), "Taken out by the joint family", "Taken from the brick field — the family's income", "NEFT DR–RANDHAWA JOINT FAMILY", "NEFT CR–RANDHAWA BRICK FIELD")
    # joint family ↔ sub-families: each household's running account, settled or carried forward
    for d, a in [(D(2025, 4, 3), R(45000)), (D(2025, 10, 3), R(45000))]:
        pair(d, F, fA, fb, A, aF, ab, a, "Household money for six months to Amarjeet's family", "Household money for six months from the joint family", "NEFT DR–AMARJEET", "NEFT CR–RANDHAWA JOINT FAMILY")
        pair(d, F, fB, fb, Bb, bF, bb, a + R(15000), "Household money for six months to Lakhbeer's family", "Household money for six months from the joint family", "NEFT DR–LAKHBEER", "NEFT CR–RANDHAWA JOINT FAMILY")
    pair(D(2025, 8, 6), F, fB, fb, Bb, bF, bb, R(70000), "Towards Aman's motorcycle", "From the joint family towards Aman's motorcycle", "NEFT DR–LAKHBEER", "NEFT CR–RANDHAWA JOINT FAMILY")
    pair(D(2025, 8, 18), F, fB, fb, Bb, bF, bb, R(50000), "Lakhbeer took ₹50,000 for a while — he will return it", "Took ₹50,000 from the joint family for a while — to be returned", "NEFT DR–LAKHBEER", "NEFT CR–RANDHAWA JOINT FAMILY")
    for d, a in [(D(2025, 7, 2), R(40000)), (D(2026, 1, 2), R(40000))]:
        pair(d, C, cF, cb, F, fC, fb, a, "Put into the joint family from Lakhwinder's salary", "Put in by Lakhwinder's family from his salary", "NEFT DR–RANDHAWA JOINT FAMILY", "NEFT CR–LAKHWINDER")
    # the family pays a household's bill straight from its own bank
    F.pay(D(2026, 1, 14), fB, fb, R(28500), "Aman's college fees for the second semester, paid by the family for Lakhbeer's household", "NEFT DR–COLLEGE")
    Bb.v(D(2026, 1, 14), "Journal (paid by family)", "College fees for the second semester, paid by the joint family", [(bedu, R(28500)), (bF, -R(28500))])
    # a household puts its own money into a family business — three books
    C.pay(D(2025, 10, 21), cF, cb, R(100000), "Put into the brick field from Lakhwinder's salary, for the family's share", "NEFT DR–RANDHAWA BRICK FIELD")
    K.rec(D(2025, 10, 21), kb, kF, R(100000), "Put in by Lakhwinder Randhawa for the joint family's share", "NEFT CR–LAKHWINDER RANDHAWA")
    F.v(D(2025, 10, 21), "Journal", "Lakhwinder's family put ₹1,00,000 straight into the brick field — the family's money in it, put in by his household", [(fK, R(100000)), (fC, -R(100000))])
    # Lakhbeer returns part of what he took by paying a brick-field bill from his own money — three books
    Bb.pay(D(2025, 12, 5), bF, bb, R(20000), "Paid the brick field's chimney repair from our money — set against what we took from the family", "UPI DR–KILN REPAIR")
    K.v(D(2025, 12, 5), "Journal (paid by partner)", "Chimney repair paid by Lakhbeer Randhawa from his own money, for the joint family's share", [(krep, R(20000)), (kF, -R(20000))])
    F.v(D(2025, 12, 5), "Journal", "Lakhbeer paid ₹20,000 of the brick field's chimney repair from his own money — the family's money in the brick field, set against what he took", [(fK, R(20000)), (fB, -R(20000))])
    # year end: the rest of what Lakhbeer took is settled from his share of the family's business income; Amarjeet's account is settled; Lakhwinder's is carried forward
    F.v(D(2026, 3, 31), "Journal (settled)", "The ₹30,000 still due from what Lakhbeer took, settled from his share of the family's business income", [(fshare, R(30000)), (fB, -R(30000))])
    Bb.v(D(2026, 3, 31), "Journal (settled)", "The ₹30,000 still due from what we took, settled from our share of the family's business income", [(bF, R(30000)), (bshare, -R(30000))])
    A_settle = R(18000) + R(90000) + R(9000)
    F.pay(D(2025, 12, 26), fA, fc, R(9000), "Amarjeet's household — Indu's dental treatment, paid by the family in cash")
    A.v(D(2025, 12, 26), "Journal (paid by family)", "Indu's dental treatment, paid by the joint family", [(amed, R(9000)), (aF, -R(9000))])
    F.v(D(2026, 3, 31), "Journal (settled)", "Amarjeet's family's account settled for the year — the family bears it as Amarjeet's household expenses", [(fhA, A_settle), (fA, -A_settle)])
    A.v(D(2026, 3, 31), "Journal (settled)", "Our account with the joint family settled for the year — the family bears it", [(aF, A_settle), (afam, -A_settle)])
    # ---------------- the joint family's own entries ------------------------------------------------
    F.pay(D(2025, 4, 8), fkit, fb, R(93500), "Ration and gas for the common kitchen, April–September (wholesale)", "UPI DR–RATION")
    F.pay(D(2025, 10, 8), fkit, fb, R(101500), "Ration and gas for the common kitchen, October–March (wholesale)", "UPI DR–RATION")
    F.pay(D(2026, 1, 21), felec, fb, R(35000), "Electricity and water, April–December", "BILLPAY DR–PSPCL")
    F.pay(D(2025, 12, 9), fmed, fb, R(24000), "Eye operation for Bapu ji", "UPI DR–EYE HOSPITAL")
    F.pay(D(2026, 2, 12), fsoc, fb, R(51000), "Shagun at a niece's wedding", "UPI DR–SHAGUN")
    F.pay(D(2025, 8, 25), fmason, fc, R(15000), "Advance to the mason for the roof, cash")
    F.v(D(2025, 9, 4), "Journal (advance settled)", "The mason's bill for the roof waterproofing set against his advance", [(frep, R(15000)), (fmason, -R(15000))])
    F.pay(D(2025, 9, 4), frep, fb, R(21000), "Rest of the mason's bill for the roof", "NEFT DR–ROOF REPAIR")
    F.took(D(2025, 9, 30), fkit, fmilk, R(57600), "Milk for April–September on the milkman's khata")
    F.took(D(2026, 3, 31), fkit, fmilk, R(59400), "Milk for October–March on the milkman's khata")
    F.pay(D(2025, 10, 4), fmilk, fb, R(67200), "Milkman's khata of February–September paid", "UPI DR–DOODHWALA")
    F.pay(D(2025, 7, 18), fcar, fb, R(28400), "Family car insurance", "NETBANKING DR–INSURANCE")
    wrong = F.pay(D(2025, 12, 28), fsoc, fc, R(6200), "Car service, cash")
    F.fix(D(2026, 1, 5), fcar, fsoc, R(6200), "Entry {ref} (car service) was written to Gurdwara & Social — moved to Family Car", "Journal (correction)", ref=wrong)
    F.move(D(2025, 8, 22), fc, fb, R(30000), "Cash withdrawn for the house (ATM)", "ATM WDL–KOTLI")
    F.move(D(2026, 1, 10), ffd, fb, R(300000), "New fixed deposit from the brick-field and plot money", "TRF TO FD")
    F.rec(D(2025, 9, 30), fb, fint, R(2860), "Savings interest", "INT.CR")
    F.rec(D(2026, 3, 31), fb, fint, R(36500), "Interest on the fixed deposits, paid to savings", "INT.CR–FD")
    F.custom = (fA, D(2025, 4, 1), D(2026, 3, 31), "One sub-family's account for the year — household money, a bill the family paid, and the year-end settlement.")
    # ---------------- Amarjeet's family ----------------------------------------------------------
    for k, a in enumerate([R(14800), R(13900), R(15600), R(14200)]):
        A.took(qe[k], ahh, agro, a, "Groceries on khata, %s" % q[k])
    A.pay(D(2025, 4, 6), agro, ac, R(4200), "Grocer's khata of March paid, cash")
    for d, a in [(D(2025, 7, 5), R(14800)), (D(2025, 10, 6), R(13900)), (D(2026, 1, 6), R(15600))]:
        A.pay(d, agro, ab, a, "Grocer's khata paid (UPI)", "UPI DR–GILL KIRYANA")
    for d, a in [(D(2025, 5, 30), R(6400)), (D(2025, 10, 30), R(9800)), (D(2026, 2, 27), R(7200))]:
        A.rec(d, ac, ast, a, "Indu's stitching — suits for the season, cash")
    A.gave(D(2025, 11, 12), acust, ast, R(5600), "Four wedding suits stitched for the Sidhu family, on credit")
    A.rec(D(2026, 1, 18), ac, acust, R(5600), "The Sidhu family paid for the suits, cash")
    A.pay(D(2025, 10, 12), acl, ab, R(12500), "Clothes for Diwali", "UPI DR–CLOTH HOUSE")
    A.pay(D(2026, 3, 8), acl, ac, R(4800), "Shoes and a shawl, cash")
    A.pay(D(2025, 8, 19), amed, ac, R(3600), "Doctor and medicines, cash")
    A.pay(D(2025, 6, 10), aph, ab, R(4400), "Mobiles for six months", "UPI DR–MOBILE RECHARGE")
    A.pay(D(2025, 12, 10), aph, ab, R(4400), "Mobiles for six months", "UPI DR–MOBILE RECHARGE")
    A.pay(D(2025, 11, 18), asoc, ac, R(5100), "Shagun at a wedding in the village, cash")
    wrong = A.pay(D(2025, 9, 9), asoc, ac, R(1800), "Bus fares to Amritsar, cash")
    A.fix(D(2025, 9, 20), aph, asoc, R(1800), "Entry {ref} (bus fares) was written to Gifts & Social — moved to Phone & Travel", "Journal (correction)", ref=wrong)
    A.move(D(2025, 8, 4), ac, ab, R(10000), "Cash withdrawn (ATM)", "ATM WDL–KOTLI")
    A.move(D(2025, 12, 20), ac, ab, R(15000), "Cash withdrawn (ATM)", "ATM WDL–KOTLI")
    A.rec(D(2026, 3, 31), ab, aint, R(910), "Savings interest", "INT.CR")
    A.pay(D(2025, 9, 30), ahelp, ac, R(9000), "House help's wages, July–September, cash")
    A.pay(D(2025, 10, 15), aadv, ac, R(3000), "Advance to the house help for Diwali, cash")
    A.v(D(2025, 12, 31), "Journal (advance settled)", "The house help's advance set against her October–December wages", [(ahelp, R(3000)), (aadv, -R(3000))])
    A.pay(D(2025, 12, 31), ahelp, ac, R(6000), "House help's wages, October–December, less the advance, cash")
    A.custom = (aF, D(2025, 4, 1), D(2026, 3, 31), "Our account with the joint family for the year — the same entries as the family's account for this household, on the other side, and its settlement.")
    # ---------------- Lakhbeer's family ----------------------------------------------------------
    Bb.pay(D(2025, 8, 8), bbike, bb, R(98500), "Motorcycle for Aman — thing owned, at cost", "NEFT DR–HERO MOTORS")
    for d, a in [(D(2025, 5, 14), R(2400)), (D(2025, 9, 22), R(3100)), (D(2026, 2, 3), R(2700))]:
        Bb.took(d, bmed, bchem, a, "Medicines on khata")
    Bb.pay(D(2025, 10, 4), bchem, bc, R(5500), "Chemist's khata paid, cash")
    for k, a in enumerate([R(13600), R(12900), R(14100), R(13300)]):
        Bb.pay(dt.date(qe[k].year, qe[k].month - 2, 12), bhh, bb, a, "Groceries and household, %s" % q[k], "UPI DR–GROCERIES")
    Bb.pay(D(2025, 7, 16), bedu, bb, R(28500), "College fees, first semester", "NEFT DR–COLLEGE")
    Bb.pay(D(2025, 10, 22), bfuel, bc, R(6200), "Motorcycle fuel, cash")
    Bb.pay(D(2026, 3, 18), bfuel, bb, R(7400), "Fuel and mobiles", "UPI DR–FUEL")
    Bb.pay(D(2025, 10, 8), bpaint, bc, R(8000), "Advance to the painter for the rooms, cash")
    Bb.v(D(2025, 10, 27), "Journal (advance settled)", "The painter's bill for the rooms set against his advance", [(bhome, R(8000)), (bpaint, -R(8000))])
    Bb.pay(D(2025, 10, 27), bhome, bc, R(6500), "Rest of the painter's bill, cash")
    Bb.pay(D(2025, 11, 20), bhome, bb, R(14800), "Curtains and a bed for the rooms", "UPI DR–FURNISHING")
    for d, a in [(D(2025, 10, 2), R(25000)), (D(2026, 2, 6), R(10000))]:
        Bb.move(d, bc, bb, a, "Cash withdrawn (ATM)", "ATM WDL–KOTLI")
    wrong = Bb.pay(D(2025, 12, 15), bhh, bc, R(2100), "Mobile recharges, cash")
    Bb.fix(D(2025, 12, 24), bfuel, bhh, R(2100), "Entry {ref} (mobiles) was written to Household — moved to Fuel & Phone", "Journal (correction)", ref=wrong)
    Bb.pay(D(2026, 3, 2), bchem, bc, R(2700), "Chemist's khata paid, cash")
    Bb.rec(D(2026, 3, 31), bb, bint, R(640), "Savings interest", "INT.CR")
    Bb.custom = (bchem, D(2025, 4, 1), D(2026, 3, 31), "The chemist's khata for the year — medicines on credit and the payments.")
    # ---------------- Lakhwinder's family --------------------------------------------------------
    for (y, m) in fy_months():
        C.rec(dt.date(y, m, 1), cb, csal, R(62400), "Salary for %s (after deductions)" % month_name(*(((y, m - 1) if m > 1 else (y - 1, 12)))), "SAL CR–DEO JALANDHAR")
    C.rec(D(2025, 7, 31), cc_, ctu, R(9000), "Harjeet's tuition fees, April–July, cash")
    C.rec(D(2026, 2, 28), cc_, ctu, R(12000), "Harjeet's tuition fees, August–February, cash")
    for d, a, what in [(D(2025, 5, 20), R(11800), "Groceries"), (D(2025, 10, 18), R(16400), "Clothes for Diwali"), (D(2026, 2, 16), R(12600), "Groceries")]:
        C.pay(d, chh if what == "Groceries" else ccl, ccard, a, "%s, on the credit card" % what)
    for d, a in [(D(2025, 4, 18), R(6800)), (D(2025, 6, 18), R(11800)), (D(2025, 11, 18), R(16400))]:
        C.move(d, ccard, cb, a, "Credit-card bill paid", "CC PAYMENT DR–SBI CARD")
    C.pay(D(2025, 4, 12), csch, cb, R(36000), "Supreet's school fees and books for the year", "NEFT DR–SCHOOL")
    C.pay(D(2025, 9, 8), chh, cb, R(18500), "Groceries and household, June–September", "UPI DR–GROCERIES")
    C.pay(D(2025, 8, 23), cel, cb, R(7800), "Electricity, mobiles and internet, April–July", "BILLPAY DR–PSPCL")
    C.pay(D(2026, 1, 22), cel, cb, R(9100), "Electricity, mobiles and internet, August–December", "BILLPAY DR–PSPCL")
    C.pay(D(2025, 12, 11), cmed, cc_, R(4600), "Doctor and medicines, cash")
    for d in [D(2025, 9, 5), D(2026, 3, 5)]:
        C.move(d, crd, cb, R(30000), "Six months of the recurring deposit", "TRF TO POST OFFICE RD")
    C.move(D(2025, 6, 4), cc_, cb, R(15000), "Cash withdrawn (ATM)", "ATM WDL–JALANDHAR")
    C.took(D(2025, 9, 30), chh, cdairy, R(16200), "Milk and curd for April–September on the dairy's khata")
    C.took(D(2026, 3, 31), chh, cdairy, R(17100), "Milk and curd for October–March on the dairy's khata")
    C.pay(D(2025, 10, 5), cdairy, cb, R(16200), "Dairy's khata of April–September paid", "UPI DR–KOTLI DAIRY")
    C.pay(D(2025, 7, 12), celad, cc_, R(5000), "Advance to the electrician for rewiring, cash")
    C.v(D(2025, 7, 26), "Journal (advance settled)", "The electrician's bill for rewiring set against his advance", [(cel, R(5000)), (celad, -R(5000))])
    wrong = C.pay(D(2025, 11, 26), chh, cb, R(3500), "Supreet's school trip", "UPI DR–SCHOOL TRIP")
    C.fix(D(2025, 12, 2), csch, chh, R(3500), "Entry {ref} (school trip) was written to Household — moved to School Fees", "Journal (correction)", ref=wrong)
    C.custom = (ccard, D(2025, 4, 1), D(2026, 3, 31), "The credit card for the year — what was spent on it and the bills paid from the salary account.")
    # ---------------- Randhawa Agriculture -------------------------------------------------------
    G.pay(D(2025, 4, 9), glab, gc, R(12000), "Wheat harvest labour, cash")
    G.rec(D(2025, 4, 28), gb, gwh, R(824500), "Wheat sold at MSP — 340 quintals @ ₹2,425, paid into the bank", "PFMS CR–WHEAT MSP")
    G.move(D(2025, 5, 2), gk, gb, R(320000), "KCC paid back from the wheat money", "TRF TO KCC")
    G.rec(D(2025, 5, 10), gb, goth, R(18000), "Wheat straw sold", "UPI CR–STRAW")
    G.pay(D(2025, 5, 20), gfert, gb, R(26500), "Sandhu Fertilisers paid — last season's khata", "UPI DR–SANDHU FERT")
    G.pay(D(2025, 6, 5), gth, gb, R(240000), "Theka for 6 acres for the year (₹40,000 an acre)", "NEFT DR–THEKA")
    G.move(D(2025, 6, 4), gb, gk, R(200000), "Money drawn on the KCC for the paddy season", "KCC DR–TRF TO SB")
    G.pay(D(2025, 6, 6), gseed, gb, R(34000), "Paddy nursery seed", "UPI DR–SEED STORE")
    G.took(D(2025, 6, 25), gfx, gfert, R(78000), "Urea and DAP for paddy on khata")
    G.took(D(2025, 8, 20), gfx, gfert, R(36500), "Sprays for paddy on khata")
    for d0, d1, give, spent in [(D(2025, 6, 10), D(2025, 7, 15), R(90000), R(88600)), (D(2025, 10, 1), D(2025, 10, 31), R(60000), R(61400)), (D(2026, 3, 25), D(2026, 3, 31), R(20000), R(16500))]:
        G.pay(d0, gadv, gb, give, "Labour money to Aman Randhawa", "IMPS DR–AMAN RANDHAWA")
        G.v(d1, "Journal (advance settled)", "Aman Randhawa's labour slips set against his advance", [(glab, spent), (gadv, -spent)])
    G.pay(D(2025, 7, 25), gdsl, gk, R(24600), "Diesel and puddler repairs, paid from the KCC")
    G.gave(D(2025, 10, 30), garh, gpad, R(1146600), "Paddy sold through Bansal & Sons — 490 quintals @ ₹2,340 (PR-126)")
    G.took(D(2025, 10, 30), garx, garh, R(28665), "Bansal & Sons' commission and market charges on the paddy")
    G.rec(D(2025, 11, 14), gb, garh, R(900000), "Bansal & Sons paid most of the paddy money", "RTGS CR–BANSAL & SONS")
    G.rec(D(2025, 12, 19), gb, garh, R(217935), "Bansal & Sons paid the rest of the paddy money", "RTGS CR–BANSAL & SONS")
    G.move(D(2025, 11, 17), gk, gb, R(200000), "KCC paid back from the paddy money", "TRF TO KCC")
    G.pay(D(2025, 12, 1), gfert, gb, R(114500), "Sandhu Fertilisers paid — paddy season khata", "UPI DR–SANDHU FERT")
    G.move(D(2025, 11, 3), gb, gk, R(150000), "Money drawn on the KCC for wheat sowing", "KCC DR–TRF TO SB")
    G.pay(D(2025, 11, 6), gseed, gb, R(46000), "Wheat seed", "UPI DR–SEED STORE")
    G.took(D(2025, 11, 10), gfx, gfert, R(84000), "DAP and urea for wheat on khata")
    for d, a in [(D(2025, 9, 30), R(9850)), (D(2026, 3, 31), R(5420))]:
        G.pay(d, gki, gk, a, "Interest charged by the bank to the KCC (half-year)")
    G.move(D(2025, 4, 7), gc, gb, R(10000), "Cash withdrawn for harvest labour (ATM)", "ATM WDL–KOTLI")
    # the buffaloes: milk to the dairy society on khata, paid later; feed; PM-Kisan by direct transfer
    G.rec(D(2025, 4, 7), gb, gmilkp, R(21600), "Verka Milk Society paid the March milk (opening balance)", "NEFT CR–VERKA MILK SOC")
    G.gave(D(2025, 9, 30), gmilkp, gmilk, R(122400), "Milk to Verka Milk Society, April–September (ten-day bills)")
    G.rec(D(2025, 10, 8), gb, gmilkp, R(122400), "Verka Milk Society paid for the milk of April–September", "NEFT CR–VERKA MILK SOC")
    G.gave(D(2026, 3, 31), gmilkp, gmilk, R(138600), "Milk to Verka Milk Society, October–March (ten-day bills)")
    G.pay(D(2025, 9, 10), gfeed, gb, R(34600), "Cattle feed and fodder, and the vet", "UPI DR–FEED STORE")
    G.rec(D(2025, 8, 2), gb, goth, R(6000), "PM-Kisan instalments, three", "DBT CR–PM KISAN")
    wrong = G.pay(D(2026, 1, 20), gfx, gb, R(9800), "Tractor tyre repair", "UPI DR–TYRE HOUSE")
    G.fix(D(2026, 1, 28), gdsl, gfx, R(9800), "Entry {ref} (tractor tyre) was written to Fertiliser & Sprays — moved to Diesel & Repairs", "Journal (correction)", ref=wrong)
    G.custom = (gk, D(2025, 4, 1), D(2026, 3, 31), "The KCC loan account for the year — drawn for each crop, the bank's interest, and the crop money paid back.")
    G.about = G.about.replace("land on lease (theka).", "land on lease (theka) · buffaloes and milk to the dairy society.")
    # ---------------- Randhawa Real Estate -------------------------------------------------------
    for k, d in enumerate([D(2025, 4, 1), D(2025, 7, 1), D(2025, 10, 1), D(2026, 1, 1)]):
        E.v(d, "Journal (credit given)", "Rent for %s%s" % (q[k], " (shop 2 left on 31 December)" if k == 3 else ""),
            ([(et1, R(36000)), (et2, R(30000)), (erent, -R(66000))] if k < 3 else [(et1, R(36000)), (erent, -R(36000))]))
    for k, d in enumerate([D(2025, 4, 7), D(2025, 7, 7), D(2025, 10, 7), D(2026, 1, 7)]):
        E.rec(d, eb, et1, R(36000) if k < 3 else R(34000), "Rent of %s received%s" % (q[k], "" if k < 3 else " — ₹2,000 short, he disputes the water charge"), "UPI CR–KOTLI MEDICAL")
    E.rec(D(2025, 4, 15), eb, et2, R(10000), "Rent of March 2025 received (opening balance)", "UPI CR–BHULLAR HARDWARE")
    for d, k, a in [(D(2025, 5, 12), 0, R(30000)), (D(2025, 9, 18), 1, R(30000)), (D(2025, 12, 22), 2, R(5000))]:
        E.rec(d, eb, et2, a, "Rent of %s received%s%s" % (q[k], " (late)" if k == 1 else "", " — only ₹5,000 of ₹30,000" if k == 2 else ""), "UPI CR–BHULLAR HARDWARE")
    # a tenant who leaves owing: his deposit is set off against the rent due, and what is left of it is kept (forfeited) for leaving without notice
    E.v(D(2025, 12, 31), "Journal (set off)", "Bhullar Hardware left shop 2 owing ₹25,000 of the October–December rent — ₹25,000 of his ₹30,000 deposit set off against it",
        [(edep2, R(25000)), (et2, -R(25000))])
    E.v(D(2025, 12, 31), "Journal (deposit forfeited)", "The other ₹5,000 of Bhullar Hardware's deposit kept — he left without the notice the agreement asks for",
        [(edep2, R(5000)), (eforf, -R(5000))])
    E.v(D(2026, 3, 25), "Journal (written off)", "₹2,000 of Kotli Medical Hall's January–March rent written off — he refuses to pay the disputed water charge",
        [(ewo, R(2000)), (et1, -R(2000))])
    E.v(D(2025, 11, 18), "Receipt", "Plot No. 14 sold for ₹15,50,000 — its cost ₹12,00,000 and the profit ₹3,50,000",
        [(eb, R(1550000)), (eplot, -R(1200000)), (egain, -R(350000))], stmt="RTGS CR–PLOT SALE")
    E.pay(D(2025, 11, 20), ebrok, eb, R(31000), "Dealer's brokerage on the plot sale (2%)", "NEFT DR–PROPERTY DEALER")
    E.pay(D(2025, 12, 12), eshops, eb, R(140000), "Mezzanine floor built over shop 1 — an improvement, added to the shops' cost", "NEFT DR–BUILDER")
    E.pay(D(2026, 2, 5), eplot2, eb, R(980000), "Plot No. 7, Green Enclave bought — thing owned, at cost", "RTGS DR–PLOT PURCHASE")
    E.pay(D(2026, 2, 9), eadv, eb, R(70000), "Money to the registry clerk for stamp duty and registry", "IMPS DR–REGISTRY CLERK")
    E.v(D(2026, 2, 16), "Journal (advance settled)", "Stamp duty and registry of Plot No. 7 set against the clerk's advance — part of the plot's cost", [(eplot2, R(68600)), (eadv, -R(68600))])
    E.rec(D(2026, 2, 20), ec, eadv, R(1400), "The registry clerk returned the rest, cash")
    E.pay(D(2025, 9, 26), etax, eb, R(14200), "Property tax 2025-26 for the shops", "NETBANKING DR–MC KOTLI")
    E.pay(D(2025, 6, 18), erep, ec, R(2800), "Shutter repair, shop 2, cash — a repair, charged to the year")
    wrong = E.pay(D(2026, 1, 9), etax, eb, R(6500), "Plumbing in shop 1", "UPI DR–PLUMBER")
    E.fix(D(2026, 1, 15), erep, etax, R(6500), "Entry {ref} (plumbing) was written to Property Tax — moved to Repairs", "Journal (correction)", ref=wrong)
    E.move(D(2025, 6, 16), ec, eb, R(5000), "Cash withdrawn (ATM)", "ATM WDL–KOTLI")
    E.custom = (et2, D(2025, 4, 1), D(2026, 3, 31), "The tenant who left — rent charged, paid late and in part, his deposit set off against what he owed and the rest of it kept.")
    # ---------------- Randhawa Brick Field -------------------------------------------------------
    K.rec(D(2025, 4, 18), kb, ks1, R(84000), "Sidhu Builders paid for March bricks (opening balance)", "NEFT CR–SIDHU BUILDERS")
    for d, a in [(D(2025, 4, 30), R(296000)), (D(2025, 5, 31), R(324000)), (D(2026, 3, 31), R(198000))]:
        K.rec(d, kc, ksale, a, "Bricks sold for cash at the kiln this month")
    for d, a in [(D(2025, 5, 2), R(280000)), (D(2025, 6, 2), R(310000)), (D(2026, 3, 31), R(185000))]:
        K.move(d, kb, kc, a, "Kiln cash deposited", "CASH DEP–BRANCH")
    for d, who, a in [(D(2025, 5, 20), ks1, R(312000)), (D(2025, 6, 25), ks2, R(268000)), (D(2026, 2, 28), ks1, R(244000)), (D(2026, 3, 25), ks2, R(196000))]:
        K.gave(d, who, ksale, a, "Bricks on khata — trolleys delivered this month")
    K.rec(D(2025, 7, 4), kb, ks1, R(312000), "Sidhu Builders paid for the May bricks", "NEFT CR–SIDHU BUILDERS")
    K.rec(D(2025, 9, 12), kb, ks2, R(268000), "Dhaliwal Contractors paid for the June bricks (late)", "NEFT CR–DHALIWAL CONTRACTORS")
    K.rec(D(2026, 3, 16), kb, ks1, R(160000), "Sidhu Builders paid part of the February bricks", "NEFT CR–SIDHU BUILDERS")
    for d, a in [(D(2025, 11, 25), R(420000)), (D(2026, 1, 28), R(365000))]:
        K.took(d, kcx, kcoal, a, "Coal from Jindal Coal Depot on khata")
    K.pay(D(2025, 4, 25), kcoal, kb, R(95000), "Jindal Coal Depot paid — last season's balance", "RTGS DR–JINDAL COAL")
    K.pay(D(2025, 12, 26), kcoal, kb, R(420000), "Jindal Coal Depot paid — November coal", "RTGS DR–JINDAL COAL")
    for d0, d1, give, spent in [(D(2025, 4, 2), D(2025, 6, 28), R(150000), R(148500)), (D(2025, 11, 10), D(2025, 12, 31), R(120000), R(116000)), (D(2026, 1, 5), D(2026, 3, 30), R(140000), R(142400))]:
        K.pay(d0, kadv, kb, give, "Advance to the pathera jamadar for moulding", "IMPS DR–PATHERA JAMADAR")
        K.v(d1, "Journal (advance settled)", "Bricks moulded, at the agreed rate per thousand, set against the jamadar's advance", [(kmould, spent), (kadv, -spent)])
    K.pay(D(2025, 5, 28), kload, kc, R(26000), "Loading and trolley hire, April–May, cash")
    K.pay(D(2026, 3, 28), kload, kc, R(21500), "Loading and trolley hire, February–March, cash")
    K.pay(D(2025, 10, 28), kroy, kb, R(180000), "Lease of the kiln land and earth royalty for the season", "NEFT DR–LAND LEASE")
    K.pay(D(2025, 11, 4), krep, kb, R(46000), "Kiln and chimney repairs before firing", "NEFT DR–KILN REPAIR")
    for d, a in [(D(2025, 7, 12), R(100000)), (D(2026, 3, 22), R(120000))]:
        K.pay(d, kG, kb, a, "Taken out by Nirmaljeet Gill (entered on his instruction)", "NEFT DR–NIRMALJEET GILL")
    K.rec(D(2025, 10, 22), kb, kG, R(130000), "Put in by Nirmaljeet Gill for the season", "NEFT CR–NIRMALJEET GILL")
    wrong = K.pay(D(2025, 6, 10), kmould, kc, R(3400), "Kiln office electricity bill, cash")
    K.fix(D(2025, 6, 30), krep, kmould, R(3400), "Entry {ref} (electricity) was written to Moulding Labour — moved to Repairs & Sundry", "Journal (correction)", ref=wrong)
    K.move(D(2025, 11, 12), kc, kb, R(20000), "Cash withdrawn for the kiln (ATM)", "ATM WDL–KOTLI")
    K.custom = (kG, D(2025, 4, 1), D(2026, 3, 31), "The outside partner's account for the year — what he put in and took out, before his share of the profit.")
    # ---------------- finish -------------------------------------------------------------------
    books = [F, A, Bb, C, G, E, K]
    for bk in books:
        bk.finalize()

    def res(bk):
        return sum(-bk.accounts[n].closing for n in bk.order if bk.accounts[n].kind == "income") - sum(bk.accounts[n].closing for n in bk.order if bk.accounts[n].kind == "expense")
    kshare = K.appropriation(res(K))[0][2]
    c.summary_note = ("How to read it. **Sub-families:** each household's account in the joint book and the joint-family account in the household's book move together; "
                      "Amarjeet's was settled on 31 Mar 2026 (the family bore it), Lakhbeer's ₹50,000 was returned through the brick field and from his share of the business income, "
                      "and the rest is carried forward. **Family businesses:** the joint book holds each business at the money the family put in; money a business sends home is the family's income "
                      "(*Income from …*). Each business works out its own profit in its own book and it is not written in the joint book: Randhawa Agriculture ₹%s, Randhawa Real Estate ₹%s, "
                      "and the family's 3 of 5 of the brick field's, ₹%s." % (fmt(res(G)), fmt(res(E)), fmt(kshare)))
    for bk in (F, G, E, K):
        bk.assets_note = "Things owned are shown at what they cost."
    F.gaps = [("Sub-family accounts", "a running account per sub-family inside the joint book, carried forward or settled at the year end (owner, 13 Oct 2026) — GAPS A11"),
              ("Income from …", "money a family business sends home is the family's income; money put in stays at cost (the cost method) — GAPS A11"),
              ("three-book entries", "a household paying into a family business, or paying its bill, writes in three books (household, business, joint) — GAPS A11")]
    K.gaps = [("partners", "fluctuating partner accounts (no fixed capital); 3 : 2 share computed, no interest")]
    c.books = books
    c.demonstrates = ["seven books, six pairs of accounts named after each other, agreeing entry for entry",
                      "a running account per sub-family in the joint book — money given, bills paid for it, money it put in; one settled at the year end, others carried forward",
                      "money taken to be returned, part returned by paying a family-business bill, the rest settled from the sub-family's share of business income",
                      "a household putting its own money into a family business (three books)", "family businesses held at money put in; money sent home is the family's income", "a KCC, an arhtiya, theka land",
                      "a plot sold at a profit and another bought with registry costs; an improvement added to the shops' cost; a tenant who left owing — deposit set off, the rest forfeited; rent written off",
                      "a brick field shared 3 : 2 with an outside partner, its P&L Appropriation posted at the year close; the farm's buffaloes and milk to the dairy society"]
    return c


CASE_BUILDERS.append(build_family)
CASE_BUILDERS[:] = [build_individual, build_family, build_shop, build_partnership, build_trust]    # the ADR's order


# =============================================================================================
# README
# =============================================================================================

def render_readme(cases, mds):
    h = hashlib.blake2b(digest_size=32)
    for c in sorted(cases, key=lambda x: x.slug):      # the order scripts/check_coverage.dart hashes the five files in
        h.update(mds[c.slug].encode("utf-8"))
    # Front-matter read by scripts/check_coverage.dart (golden governance, ADR 2026-09-05i §3; ADR 2026-10-20 §2).
    out = ["---",
           "approved_by:      # bookkeeper name — empty = PROVISIONAL (ADR 2026-09-05i §3)",
           "approved_on:      # YYYY-MM-DD",
           "content_hash:     # BLAKE2b-256 over the five reference books' .md files; checked by scripts/check_coverage.dart",
           "---", "",
           "# Reference books — five books, FY 2025-26", ""]
    out.append("**Status: ⚠️ PROVISIONAL — for the owner's review, then a bookkeeper's sign-off.** Five compact ledger books for 01 Apr 2025 – 31 Mar 2026, written the way a competent Indian "
               "bookkeeper keeps such books from real transactions. They are the **target output** of the app (ADR 2026-10-12 §10, reworked by ADR 2026-10-20 §2): nothing here was bent to fit `docs/02-ledger-rules.md`, "
               "the ADRs or the code; where the app cannot yet produce what a book shows, `GAPS.md` says so, and `COVERAGE.md` says which book and entry shows each ruling of 20 Oct 2026 "
               "(`docs/archive/reference/accounting-research/OPEN.md`) and each mechanic of the five practice books that were merged into these five. Everything is generated by `build.py`, asserted to balance, and re-derived from the "
               "printed markdown by `check_md.py`; the `.md`, `.html` and `.tech.md` files are outputs, never edited by hand. PDFs are local outputs and git-ignored (ADR 2026-10-12 §11).")
    out.append("")
    out.append("**Five books, ADR 2026-10-20 §2.** The practice set had ten books; the truck operator, the farmer, the landlord, the contractor and the committee were merged into the kept five (their finished outputs are archived at "
               "`docs/archive/reference/practice-books-merged/`): the truck's vehicle loan, the driver's advance and the FASTag wallet are in the individual; the farm's KCC, arhtiya, milk and buffaloes are in Randhawa Agriculture; the landlord's improvement, "
               "set-off, forfeiture and write-off are in Randhawa Real Estate; the contractor's retention money, mobilisation advance and supplier advance are in Bal Fabricators; the committee's fund for a purpose is in the trust.")
    out.append("")
    out.append("All five carry the owner's real names (ADR 2026-10-12 §12, extending ADR 2026-10-11 §2); the people the merged mechanics add (the driver, the foreman, the caretaker, the donors) are made-up names. Every figure is illustrative.")
    out.append("")
    out.append("## 1. The set")
    out.append("")
    rows = []
    for c in cases:
        for b in c.books:
            inc = sum(-b.accounts[n].closing for n in b.order if b.accounts[n].kind == "income")
            exp = sum(b.accounts[n].closing for n in b.order if b.accounts[n].kind == "expense")
            tb = sum(a.closing for a in b.accounts.values() if a.closing > 0)
            rows.append(["`%s`" % c.slug if b is c.books[0] else "", b.name, b.kindword, "`%s`" % b.prefix, len(b.vouchers), len(b.accounts), fmt(tb), fmt(inc), fmt(exp), fmt(inc - exp)])
    out += table(["File (`.md` · `.html` · `.tech.md` · `.export.md` · local `.pdf`)", "Book", "Kind", "Prefix", "Entries", "Accounts", "Trial balance ₹", "Income ₹", "Spent ₹", "Result ₹"],
                 ["l", "l", "l", "l", "r", "r", "r", "r", "r", "r"], rows)
    out.append("")
    out.append("Sizes (ADR 2026-10-12 §11, kept by ADR 2026-10-20 §2): about 40–60 entries per book, 25–40 for each of the seven Randhawa books; 10–14 A4 pages per book. `build.py` renders every book on its own and "
               "**fails when any book prints on more than 14 pages**; `check_md.py` fails on an entry count outside the range. Entry numbers (`JP-017`) are the printed ones.")
    out.append("")
    out.append("## 2. Rules every book follows")
    out.append("")
    out.append("- **No tax, GST, TDS, invoicing, stock or payroll** (`docs/00-vision.md`, non-goals). Goods bought for sale are spent when bought or taken on credit; there is no closing stock, and the shop's statement says so. A salary is simply paid.")
    out.append("- **One basis for every book — the khata basis** (O-01-1): money is recorded when it moves; an amount due to or from a named person when it arises; nothing for the passage of time alone. "
               "**Every report head** carries the book, the date or period, the basis in one plain line (*Kept on money paid and received, and what people owe; no year-end adjustments.*), *Year closed* and *Made on* — a fixed, pinned date, so a rerun is byte-identical (O-01-1, O-20-1, O-20-2).")
    out.append("- **Transaction-driven.** Every entry is a real event: money in or out of cash, bank, card, wallet or KCC; credit given or taken with a named person (khata); a transfer between own accounts or into a deposit; "
               "an advance and its settlement; a loan instalment as the lender's statement splits it; a partner paying from his own pocket; a correction of a wrong head. "
               "Every book has credit given or taken, receipts, a cash withdrawal, a transfer, an advance and a correction.")
    out.append("- **One running account per person; its own account for what is not everyday khata.** A deposit held or paid, retention money held back, an advance for spending, and a loan that carries interest each have their own account on the person's page, beside the khata (O-02-4, O-06-4, O-07-1, O-09-8).")
    out.append("- **Advances** are settled in one entry (Dr each head · Cr *Advance – {person}*); the unspent part is returned, left open and carried forward, moved to the person's own account, or written off; a salary advance is recovered in the salary entry (O-07-2…O-07-5, O-12-3). "
               "A balance known not to come back is *Written off* / *Rent written off* (O-06-5, O-12-1, O-18-5); a cash count that differs goes to *Cash short / over* (O-11-1).")
    out.append("- **Things owned stay at cost, no depreciation** (O-09-1, O-09-2): every position that shows them prints *Things owned are shown at what they cost; no depreciation is charged.* A thing bought on a loan the lender pays to the seller is one entry (O-09-6); an improvement is added to a building's cost, a repair is an expense (O-18-4).")
    out.append("- **Corrections are new entries**, never edits; each correction's note names the entry it fixes, with its number and date (O-11-2, O-11-5).")
    out.append("- **The year close is posted by the book itself** (O-19-1): income and expense heads to the result; the result and the drawings to own money; for both partnerships (Bal Fabricators and Randhawa Brick Field) through a posted P&L Appropriation Account to each partner — "
               "interest on capital only where the partners agreed it (Bal Fabricators does, 6% a year on fixed capital; Randhawa Brick Field does not) and only out of profit (O-14-1…O-14-3); the trust's surplus or deficit to the General Fund; the joint family's to its own money. "
               "The entries are printed in the year-end section (numbers ending Y1, Y2 …) and on the last rows of the ledgers they touch; the carry-forward then opens with one own-money figure for each owner; a partnership with fixed capital carries each partner's capital and current account at its own balance (04 §2.6, O-19-1).")
    out.append("- **Own business, and a business owned by another book** (O-13-4, O-15-3): the owner's personal book holds the business as one account at the money put in; money the business sends home is *Income from {business}* (the cost method), the same as the joint family's. "
               "A household's statement is *Income & Expenses*, its result *Saving* or *Spent more than came in*; loans, money returned, transfers between own accounts and a matured deposit are never income (O-13-5).")
    out.append("- **A fund is money for one purpose** (O-17-1, O-17-2): gifts for it and its deposit's interest are added to it; spending from it is one action — the cost is charged to Income & Expenditure and the same amount is moved out of the fund (two postings in the technical companion). "
               "The gollak count records the donation, and emptying the box is a transfer (O-17-8); a thing donated and kept is entered at ₹1 with its estimated value in the note (O-17-7).")
    out.append("- **Plain words, true side in brackets** (ADR 2026-10-12 §2, ADR 2026-10-10b §4): *Money in (Dr) / Money out (Cr)*, *You will get (Dr) / You will give (Cr)*, *Given (Dr) / Received (Cr)* … "
               "Engine names, rule references, ⚠️ notes and checks never appear on a printed book — `build.py` refuses to write one that does (`lint_plain`), and `check_md.py` checks the same independently. "
               "Each book's `.tech.md` maps every account to its standard type, traditional class and generator kind, every entry to its formal voucher type and the 02 §2 verb it needs, and lists the year-close entries.")
    out.append("- **No registers and no entry tags** (owner, 12 Oct 2026; GAPS A7). A trip, a tenant or a member is an account the user names; *who owes what, and since when* is the ageing list (up to 30 · 31–90 · over 90 days, oldest settled first — O-20-9).")
    out.append("- **Inter-book money** goes through an account named after the other book — never *Due to/from* (a sole proprietor's business book names its capital and drawings accounts after the owner, whose personal book is the other book) — written in both books, "
               "and each file with more than one book ends with a summary showing every pair agreeing entry for entry (O-15-*, O-16-*). A pair is carried forward by default, or settled when the books agree to.")
    out.append("")
    out.append("## 3. Layout of every book (the owner's order)")
    out.append("")
    out.append("The printed book (`<file>.md` / `.html` / local `.pdf`); every numbered heading is followed by its head line:")
    out.append("")
    out.append("1. **Accounts and opening balances** — every account with its plain type and what it is; Dr total = Cr total.")
    out.append("2. **Every account (ledger)** — Date · No. · Particulars (*To …* / *By …*, with the entry's note in small type) · plain Dr column · plain Cr column · Balance · Side. Balance accounts open *Opening balance b/f* and end *Closing balance c/d · Total · Opening balance b/d*, the opening and closing balances standing in the amount column of their side so that each column adds up to the Total; "
               "income and expense accounts end with *Total for the year*; the own-money, drawings and head accounts end with their year-close row.")
    out.append("3. **Positions and statements during the year** — the full position at 30 Sep 2025 and 31 Mar 2026 with how the own money is made up; **one month** (October 2025) as an account-by-account summary; "
               "**one account for a chosen period** (the statement a user shares); **You will get / You will give** with ageing; "
               "and, where the user works from a bank statement — the individual (both books) and the shop — one month's **bank statement → entries** table.")
    out.append("4. **Year end** — trial balance (closing balances only, O-19-2); Receipts & Payments (trust); the year's statement (Profit & Loss, Income & Expenditure, Income & Expenses for a household), with the no-stock line for the shop; **each fund's statement** (trust); "
               "the P&L Appropriation Account (the two partnerships); **the year-close entries**; the Balance Sheet (with the partners' table where there are partners); the carry-forward into FY 2026-27.")
    out.append("")
    out.append("**The export** (`<file>.export.md` / `.html`): the **Day Book** (every entry, its plain type, Dr and Cr accounts, amount, note) and the **Cash Book** (cash and the bank, a column for each on the Money in and the Money out side, "
               "a transfer between them on both sides, with each month's totals and balances — 04 §5.4) — "
               "what the app gives when the user downloads them, for any period and with or without notes; here the full year, with notes. They are not part of the printed book; there is no separate Bank Book, "
               "since the bank has its column in the Cash Book (ADR 2026-10-12 §11, amended 13 Oct 2026). The year-close entries are made by the book and are not in the Day Book. When printing or exporting, the app lets the user choose **All**, or a multi-select of the sections and the accounts to include, for any period and with or without notes.")
    out.append("")
    out.append("## 4. What each file shows")
    out.append("")
    for c in cases:
        out.append("- **%s** — %s." % (c.title, "; ".join(c.demonstrates)))
    out.append("")
    out.append("## 5. Rulings applied, and readings still open")
    out.append("")
    out.append("Ruled by the owner, 13 Oct 2026, and kept:")
    out.append("")
    out.append("- **Trust — *Dairy Donation* is income** (donations received for the dairy). **Trust — *Construction* is an expense head** (O-09-7), so the langar hall is in Income & Expenditure; the part paid from the Langar Hall Fund is moved out of the fund in the same entry.")
    out.append("- **Joint family — the joint book is *Randhawa Joint Family*.** It keeps **one running account per sub-family**: household money given and bills the family pays for that household on the Dr side; "
               "what the household puts in — into the family, or straight into a family business — on the Cr side. It is not a debt: at the year end it is **settled or carried forward**, as the family decides (O-15-5). "
               "The book shows all three ways: Amarjeet's account settled on 31 Mar (the family bears it as his household's expenses); Lakhbeer's ₹50,000 taken *to be returned*, part returned by paying a brick-field bill from his own money (written in three books) "
               "and the rest settled from his share of the family's business income; Lakhwinder's carried forward, including ₹1,00,000 he put straight into the brick field.")
    out.append("- **Joint family — family businesses** are held at the money the family put in; money a business sends home is the family's income (*Income from …*); the business's profit is computed in its own book and stated in the family summary (O-15-3, O-15-4).")
    out.append("")
    out.append("Ruled by the product architect on the owner's delegation, 20 Oct 2026 (`docs/archive/reference/accounting-research/OPEN.md`, all 125 rows), applied here: the khata basis and the report head; the posted year close and the partnership appropriation; "
               "the individual's income from his business; retention, advances and loans in their own accounts; write-offs and *Cash short / over*; things at cost; the no-stock line; the trust's three statements and each fund's; the ageing buckets; the joint-family pairs. "
               "`COVERAGE.md` maps each ruling to the entries that show it and lists the ruled rows these books do not show, with the reason.")
    out.append("")
    out.append("Still open:")
    out.append("")
    out.append("- ⚠️ **Bookkeeper's review.** Every ruling of 20 Oct 2026 goes to the bookkeeper (research outline, step 5) together with these books; the books follow the rulings as written, and where a ruling and the books seem to differ the ruling is right and the books are to be fixed.")
    out.append("- ⚠️ **Compact entries.** To stay at about 50 entries a year, some recurring items are written for a quarter or a half-year (a quarter's counter sales from the cash memo book, rent charged quarterly, a salary drawn quarterly, milk and groceries on a half-year's khata). Each entry is one real document or one real bank line; the note says what it covers.")
    out.append("- ⚠️ **What the app does today contradicts some rulings** (02 §5 amends a posted entry where the rulings correct by a new entry; 02 §7 requires approval for an advance; ADR 2026-09-05e §2 keeps drawings separate where the rulings close them to capital) — taken up once, in the app-requirements pass after the bookkeeper's review (ADR 2026-10-20, Consequences). `GAPS.md` lists them.")
    out.append("")
    out.append("## 6. Sources (bookkeeping only — no tax sources)")
    out.append("")
    out.append("- ICAI Board of Studies, CA Foundation *Principles and Practice of Accounting* — *Financial Statements of Not-for-Profit Organisations* (Receipts & Payments as the summary of the cash book; Income & Expenditure; a fund for a special purpose credited with its donations and debited with its spending) and *Accounting for Partnership* (fixed and fluctuating capital, P&L Appropriation, interest on capital out of profit only).")
    out.append("- ICAI, AS 10 *Property, Plant and Equipment* (revised 2016), paras 7, 17–18, 20 — what goes into the cost of a thing owned (the car's price, the plot's stamp duty, the mezzanine floor); used only for cost — no depreciation is posted.")
    out.append("- The twenty research notes and `docs/archive/reference/accounting-research/OPEN.md`, whose rulings the books follow.")
    out.append("")
    out.append("## 7. Regenerating and checking")
    out.append("")
    out.append("- `python3 -I build.py` in this folder regenerates every file (`--no-pdf` skips Chrome and the page check; `--chrome PATH`; `--skip-check` skips the checker). Standard library only, integer paise, no clock, no randomness; "
               "two runs give byte-identical `.md`, `.html` and `.tech.md` (PDF dates and ids are pinned too).")
    out.append("- **`build.py` asserts** on every run: every entry sums to zero with at least two lines and no account twice; money in/out touches a money account and no-money entries do not (a Money out may also credit an advance it recovers or the lender's part of a purchase); a transfer joins two own money/deposit accounts; "
               "spending from a fund charges the year and moves the same amount out of the fund; the gollak is filled only by a count and emptied only into cash or bank; openings and the trial balance balance; cash, bank and wallet never go negative, a credit card never goes past nil; advances, loans given, retention, things owned and deposits are never over-settled; fixed capital never moves; "
               "every year-close entry balances and leaves every head, the drawings and the result account at nil; the position make-up equals the position at both dates; the balance sheet balances; the carry-forward sums to zero; every inter-book pair agrees entry for entry; the entry count is in range; no book prints on more than 14 pages.")
    out.append("- **`check_md.py`** (no code shared with `build.py`) re-derives every printed figure from the markdown: chart, Day Book, every ledger row (including the year-close rows), the Cash Book, the bank extract, both positions and their make-up, the one-month summary (and that it does not repeat the entries), "
               "the chosen-period statement, the ageing, the trial balance, the year's statement, each fund's statement, the appropriation (interest from the printed rate and capital; each share within a paisa of the exact ratio, and posted to the partners' accounts), Receipts & Payments, the year-close entries, the balance sheet and partners' table, "
               "the carry-forward after the close, the family summaries, the report heads, the things-owned and no-stock lines, the corrections' notes, the entry counts and the plain-word lint. `build.py` runs it and stops before making PDFs if it fails.")
    out.append("- Content hash (BLAKE2b-256 over the five book `.md` files) of this generation: `%s`." % h.hexdigest())
    out.append("")
    out.append("## 8. For development — `GAPS.md` and `COVERAGE.md`")
    out.append("")
    out.append("`GAPS.md` lists, with entry numbers from these books, every place where producing them needs something the app's rules do not yet provide, and the order in which those gaps steer development. "
               "`COVERAGE.md` maps every ruled row of `OPEN.md` that a book can show, and every merged mechanic, to the book and entries that demonstrate it, and lists the ruled rows deliberately not shown.")
    out.append("")
    return "\n".join(out) + "\n"


# =============================================================================================
# main
# =============================================================================================

def write_text(path, text):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main(argv):
    no_pdf = "--no-pdf" in argv
    skip_check = "--skip-check" in argv
    chrome = DEFAULT_CHROME
    if "--chrome" in argv:
        chrome = argv[argv.index("--chrome") + 1]
    cases = [fn() for fn in CASE_BUILDERS]
    mds = {}
    for c in cases:
        md = render_case(c)
        mds[c.slug] = md
        write_text(os.path.join(HERE, c.slug + ".md"), md)
        write_text(os.path.join(HERE, c.slug + ".html"), md_to_html(md, c.title))
        write_text(os.path.join(HERE, c.slug + ".tech.md"), render_tech(c, md))
        ex = render_export(c)
        write_text(os.path.join(HERE, c.slug + ".export.md"), ex)
        write_text(os.path.join(HERE, c.slug + ".export.html"), md_to_html(ex, "Day Book and Cash Book — " + c.title))
        print("wrote %s.md (+ .html, .tech.md) — %s" % (c.slug, ", ".join("%s %d entries" % (b.prefix, len(b.vouchers)) for b in c.books)))
    readme = render_readme(cases, mds)
    write_text(os.path.join(HERE, "README.md"), readme)
    write_text(os.path.join(HERE, "README.html"), md_to_html(readme, "Reference books — README"))
    if not skip_check:
        rc = subprocess.call([sys.executable, "-I", os.path.join(HERE, "check_md.py"), HERE])
        if rc != 0:
            print("check_md.py reported problems — stopping before PDF generation", file=sys.stderr)
            return rc
    if not no_pdf:
        over = []
        tmp = tempfile.mkdtemp(prefix="practice-pages-")
        try:
            for c in cases:
                n = to_pdf(chrome, os.path.join(HERE, c.slug + ".html"), os.path.join(HERE, c.slug + ".pdf"))
                per = []
                if len(c.books) == 1:
                    per.append((c.books[0].name, n))
                else:
                    head = "\n".join(["# %s" % c.title, ""] + c.intro) + "\n"
                    for b in c.books:
                        part = head + "\n".join(render_book_sections(b)) + "\n"
                        hp = os.path.join(tmp, "%s.html" % b.prefix)
                        write_text(hp, md_to_html(part, b.name))
                        per.append((b.name, to_pdf(chrome, hp, os.path.join(tmp, "%s.pdf" % b.prefix))))
                for name, pages in per:
                    if pages > MAX_PAGES:
                        over.append("%s: %s prints on %d pages (limit %d)" % (c.slug, name, pages, MAX_PAGES))
                print("wrote %s.pdf — %d pages (%s)" % (c.slug, n, "; ".join("%s %d" % (nm, p) for nm, p in per)))
            n = to_pdf(chrome, os.path.join(HERE, "README.html"), os.path.join(HERE, "README.pdf"))
            print("wrote README.pdf — %d pages" % n)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        if over:
            for o in over:
                print("TOO LONG: " + o, file=sys.stderr)
            return 3
    h = hashlib.blake2b(digest_size=32)
    for c in sorted(cases, key=lambda x: x.slug):
        h.update(mds[c.slug].encode("utf-8"))
    print("content hash (BLAKE2b-256 over the five book .md files): %s" % h.hexdigest())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
