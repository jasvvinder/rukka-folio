#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
check_md.py — independent re-derivation of the five reference books from the PRINTED markdown.
Shares no code with build.py: it reads the tables as a reader would. Per book (a file may hold several,
each under "## Book: …"): the chart totals, the Day Book entry by entry, every ledger row by row, the Cash
Book with its month totals, the bank-statement extract, both positions and their make-up, the one-month
summary, the chosen-period statement, the You will get / You will give ageing, the trial balance, the year's
statement, each fund's statement, the P&L Appropriation, the Receipts & Payments, the year-close entries (every
income, expense and drawings account closed, the result account at nil, the appropriation posted as the printed
one says), the balance sheet and the carry-forward (after the close, one own-money figure per owner); every report
head (book, date or period, basis, Year closed, Made on); the things-owned and no-stock lines; every correction's
note naming the entry it fixes; per file, the family summary (every pair of accounts named after each other's book
agrees entry for entry); and the plain-word lint of the printed page.

usage:  python3 -I check_md.py [folder]        (default: the folder this script sits in)
exit 0 when every check agrees; the last line reads  "checks: N   problems: M".
"""
import datetime
import os
import re
import sys

AMOUNT = re.compile(r"^(\d{1,3}(?:,\d{2,3})*|\d+)(?:\.(\d{2}))?$")
FY_START = datetime.date(2025, 4, 1)
FY_END = datetime.date(2026, 3, 31)
EXPECTED = ["individual-jasvinder-singh", "joint-family-randhawa", "partnership-bal-fabricators", "shop-sukhwinder-sales-co", "trust-radha-soami-satsang-sabha"]
BASIS = "Kept on money paid and received, and what people owe; no year-end adjustments."
MADE_ON = "02 Apr 2026, 10:00"
COST_LINE = "Things owned are shown at what they cost; no depreciation is charged."
STOCK_LINE = "No stock is counted. Everything bought for sale is treated as sold or used in the year it was bought."
STAKE_LINE = "The business is shown at the money put into it, not at its worth."
STAKES_LINE = "The businesses are shown at the money put into them, not at their worth."
VTYPES = {"Money in", "Money out", "Transfer", "Gave on credit", "Took on credit", "Advance settled", "Paid by a partner", "Correction", "Paid by the joint family",
          "Settled at year end", "Fix / Adjust", "Paid from a fund", "Interest added to a deposit", "Written off", "Deposit set off", "Deposit forfeited", "Retention released"}
YEAR_CLOSE = r"^#### 4\.\d Year close — the entries the book makes itself on 31 Mar 2026$"
EQUITY = {"Own money", "Drawings", "Share-out", "Partner", "Owner", "Partner's capital", "Partner's current", "Sub-family", "Joint family"}
MONEY = {"Cash", "Gollak", "Bank", "Wallet", "Credit card", "KCC loan"}
MIXED_OK = {"Advance", "Loan"}     # a Money out may also credit an advance it recovers, or the lender's part of a purchase
NOT_ON_PAGE = ["`", "§", "ADR", "⚠", "build.py", "check_md", "GAPS", "README", "equity", "Journal", "Contra", "voucher", "Voucher", "Due to", "Due from",
               "narration", "accrual", "category_", "money_in", "Nominal", "app", "auditor"]
MAX_ENTRIES = {"single": (40, 60), "family": (25, 40)}

checks = 0
problems = []


def ok(cond, msg):
    global checks
    checks += 1
    if not cond:
        problems.append(msg)
    return cond


def clean(cell):
    cell = re.sub(r"<br><em>.*?</em>", "", cell)
    cell = re.sub(r"<em>.*?</em>", "", cell)
    return cell.replace("**", "").strip()


def paise(cell):
    """Printed amount → integer paise. '—' and '' → 0. Leading '= ', trailing ' Dr'/' Cr' tolerated (Dr kept +, Cr made −)."""
    s = clean(cell)
    s = re.sub(r"^=\s*", "", s)
    s = s.replace("₹", "").strip()
    if s in ("—", "", "-"):
        return 0
    neg = s.startswith("−") or s.startswith("-")
    s = s.lstrip("−-")
    m = AMOUNT.match(s)
    if not m:
        raise ValueError("bad amount %r" % cell)
    v = int(m.group(1).replace(",", "")) * 100 + (int(m.group(2)) if m.group(2) else 0)
    return -v if neg else v


def signed(cell):
    """'12,000 Dr' → +, '12,000 Cr' → −, '0' → 0."""
    s = clean(cell)
    m = re.match(r"^(.*?)(?:\s+(Dr|Cr))?$", s)
    v = paise(m.group(1))
    return -v if m.group(2) == "Cr" else v


def pdate(s):
    return datetime.datetime.strptime(clean(s), "%d %b %Y").date()


def cells(line):
    inner = line.strip()
    assert inner.startswith("|") and inner.endswith("|"), line
    inner = inner[1:-1]
    return [c.strip() for c in inner.split(" | ")]


def read_tables(lines, start, end):
    out = []
    i = start
    while i < end:
        if lines[i].startswith("|") and i + 1 < end and re.match(r"^\|[-:| ]+\|$", lines[i + 1].strip()):
            rows = [cells(lines[i])]
            j = i + 2
            while j < end and lines[j].startswith("|"):
                rows.append(cells(lines[j]))
                j += 1
            out.append((i, rows))
            i = j
        else:
            i += 1
    return out


def find(lines, pattern):
    for i, ln in enumerate(lines):
        if re.match(pattern, ln):
            return i
    return None


def block(lines, i):
    """From heading i to the next heading of any level."""
    j = i + 1
    while j < len(lines) and not lines[j].startswith("#"):
        j += 1
    return j


def side(bal):
    return "Dr" if bal > 0 else ("Cr" if bal < 0 else "—")


class Book(object):
    pass


def split_cell(cell, amount, label, vid):
    """A Day-Book style cell: one account alone (the whole amount) or 'Name ₹amount' parts joined by <br>."""
    if "<br>" in cell or re.search(r" ₹[\d,]+(\.\d\d)?$", cell):
        out = []
        for part in cell.split("<br>"):
            m = re.match(r"^(.*) ₹([\d,]+(?:\.\d\d)?)$", part.strip())
            ok(m is not None, "%s %s: cannot read %r" % (label, vid, part))
            out.append((m.group(1).strip(), paise(m.group(2))))
        return out
    return [(cell.strip(), amount)]


def head_ok(label, lines, i, name_prefix):
    """The line after a report heading is its head: the book, the date or period, the basis, Year closed, Made on (O-20-1, O-20-2)."""
    j = i + 1
    while j < len(lines) and lines[j].strip() == "":
        j += 1
    h = lines[j] if j < len(lines) else ""
    tail = " · %s · Year closed · Made on %s*" % (BASIS, MADE_ON)
    return ok(h.startswith("*" + name_prefix) and h.endswith(tail) and len(h) > len(tail) + len(name_prefix) + 6, "%s: the head under %r is missing or wrong: %r" % (label, lines[i][:70], h[:90]))


def parse_book(label, name, lines, export):
    bk = Book()
    bk.path = label
    bk.name = name
    bk.lines = lines
    i = find(lines, r"^### 1\. Accounts")
    ok(i is not None, "%s: chart missing" % label)
    tbl = read_tables(lines, i, find(lines, r"^### 2\. "))[0][1]
    bk.accounts, bk.type, bk.opening = [], {}, {}
    tdr = tcr = 0
    for r in tbl[1:]:
        if r[0].strip() == "":
            ok(paise(r[4]) == tdr and paise(r[5]) == tcr, "%s chart: printed totals" % label)
            continue
        ok(int(r[0]) == len(bk.accounts) + 1, "%s chart: numbering" % label)
        n = r[1]
        bk.accounts.append(n)
        bk.type[n] = r[2]
        bk.opening[n] = paise(r[4]) - paise(r[5])
        tdr += paise(r[4])
        tcr += paise(r[5])
        ok(r[2] not in ("Income", "Expense") or bk.opening[n] == 0, "%s chart: %s opens at zero" % (label, n))
    ok(tdr == tcr, "%s chart: opening Dr %d != Cr %d" % (label, tdr, tcr))
    bk.path = label
    foot_ok(bk, lines, i, block(lines, i), COST_LINE, any(bk.type[n] == "Thing owned" and bk.opening[n] != 0 for n in bk.accounts), "accounts list")
    bk.is_bs = {n: bk.type[n] not in ("Income", "Expense") for n in bk.accounts}
    bk.money = [n for n in bk.accounts if bk.type[n] in MONEY]
    # Day Book — from the export, not the printed book
    bk.export = export
    ok(find(lines, r"^#{2,4} .*(Day Book|Cash Book) — ") is None, "%s: the printed book carries a Day Book or Cash Book" % label)
    i = find(export, r"^### 1\. Day Book")
    if not ok(i is not None, "%s: export has no Day Book" % label):
        i = 0
    tbl = read_tables(export, i, block(export, i))[0][1]
    bk.vouchers = []
    prev = None
    for k, r in enumerate(tbl[1:], 1):
        date, vid, vtype, drc, crc, amt, narr = r[:7]
        amount = paise(amt)
        marked = vtype.endswith(" — no money moved")      # O-03-3: an entry that moves no money is marked as such in the Day Book
        vtype = vtype[:-len(" — no money moved")] if marked else vtype

        drs, crs = split_cell(drc, amount, label, vid), split_cell(crc, amount, label, vid)
        ok(sum(a for _, a in drs) == amount == sum(a for _, a in crs), "%s Day Book %s: sides differ from the amount" % (label, vid))
        for n, _ in drs + crs:
            ok(n in bk.type, "%s Day Book %s: unknown account %r" % (label, vid, n))
        ok(not ({n for n, _ in drs} & {n for n, _ in crs}), "%s Day Book %s: an account on both sides" % (label, vid))
        d = pdate(date)
        ok(FY_START <= d <= FY_END and (prev is None or d >= prev), "%s Day Book %s: date" % (label, vid))
        prev = d
        ok(vid.endswith("-%03d" % k), "%s Day Book: %s out of sequence" % (label, vid))
        money_touched = [n for n, _ in drs + crs if n in bk.money]
        ok(vtype in VTYPES, "%s Day Book %s: unknown type %r" % (label, vid, vtype))
        ok(marked == (not money_touched), "%s Day Book %s: the no-money-moved mark must be there exactly when no cash, bank, card or wallet is touched" % (label, vid))
        if vtype == "Transfer":
            ok(len(drs) == len(crs) == 1 and money_touched, "%s Day Book %s: a transfer joins two own accounts" % (label, vid))
        elif vtype == "Money in":
            ok(all(n in bk.money for n, _ in drs), "%s Day Book %s: money in must land in cash/bank" % (label, vid))
        elif vtype == "Money out":
            ok(all(n in bk.money or bk.type[n] in MIXED_OK for n, _ in crs) and any(n in bk.money for n, _ in crs) and not any(n in bk.money for n, _ in drs),
               "%s Day Book %s: money out must leave cash/bank (it may also credit an advance or a loan)" % (label, vid))
        elif vtype == "Paid from a fund":
            fd = [(n, a) for n, a in drs if bk.type[n] == "Fund"]
            ic = [(n, a) for n, a in crs if bk.type[n] == "Income"]
            ok(len(fd) == 1 and len(ic) == 1 and len(drs) + len(crs) == 4 and all(n in bk.money for n, _ in crs if bk.type[n] != "Income")
               and fd[0][1] == ic[0][1] == sum(a for n, a in crs if n in bk.money) and all(bk.type[n] in ("Fund", "Expense", "Thing owned") for n, _ in drs),
               "%s Day Book %s: spending from a fund charges the year and moves the same amount out of the fund" % (label, vid))
        else:
            ok(not money_touched, "%s Day Book %s: %s must not touch cash/bank" % (label, vid, vtype))
        if vtype == "Correction":
            m = re.search(r"Entry (\S+-\d{3}) of (\d{2} \w{3} \d{4})", narr)
            ok(m is not None and any(w["vid"] == m.group(1) and w["date"] == pdate(m.group(2)) for w in bk.vouchers) and m.group(1) != vid,
               "%s Day Book %s: a correction's note must name the entry it fixes, with its number and date" % (label, vid))
        if vtype == "Written off":
            ok(len(drs) == 1 and bk.type[drs[0][0]] == "Expense" and "written off" in drs[0][0].lower(), "%s Day Book %s: a write-off goes to a Written off head" % (label, vid))
        if vtype == "Deposit set off":
            ok(len(drs) == 1 and bk.type[drs[0][0]] == "Deposit held", "%s Day Book %s: a set-off uses the deposit held" % (label, vid))
        if vtype == "Deposit forfeited":
            ok(len(drs) == 1 and bk.type[drs[0][0]] == "Deposit held" and len(crs) == 1 and bk.type[crs[0][0]] == "Income" and "forfeited" in crs[0][0].lower(),
               "%s Day Book %s: a forfeited deposit goes to Deposit forfeited" % (label, vid))
        if vtype == "Retention released":
            ok(len(crs) == 1 and bk.type[crs[0][0]] == "Retention held", "%s Day Book %s: retention is released from its own account" % (label, vid))
        bk.vouchers.append({"date": d, "vid": vid, "vtype": vtype, "lines": [(n, a) for n, a in drs] + [(n, -a) for n, a in crs], "amount": amount, "narr": narr.strip()})
    bk.narr = {v["vid"]: v["narr"] for v in bk.vouchers}
    bk.post = {n: [] for n in bk.accounts}
    for v in bk.vouchers:
        for n, a in v["lines"]:
            bk.post[n].append((v["date"], v["vid"], a))
    bk.closing = {n: bk.opening[n] + sum(a for _, _, a in bk.post[n]) for n in bk.accounts}
    for n in bk.accounts:
        if bk.type[n] in ("Cash", "Bank", "Wallet", "Gollak"):
            bal = bk.opening[n]
            for d, vid, a in bk.post[n]:
                bal += a
                ok(bal >= 0, "%s %s goes negative at %s" % (label, n, vid))
        if bk.type[n] == "Gollak":
            for v in bk.vouchers:
                for m, a in v["lines"]:
                    if m == n and a < 0:
                        ok(v["vtype"] == "Transfer" and all(bk.type[x] in ("Cash", "Bank") for x, y in v["lines"] if y > 0), "%s gollak emptied other than into cash/bank at %s" % (label, v["vid"]))
    parse_close(bk)
    return bk


def equity_parts(bk, date):
    eq = [n for n in bk.accounts if bk.type[n] in EQUITY]
    start = -sum(bk.opening[n] for n in eq)
    put = sum(-a for n in eq for d, _, a in bk.post[n] if d <= date and a < 0)
    taken = sum(a for n in eq for d, _, a in bk.post[n] if d <= date and a > 0)
    return start, put, taken


def parse_close(bk):
    """The year-close entries printed in section 4: each balances; after them every income, expense and drawings account and the result account stand at nil;
    the own money after them is what the year's make-up says (start + put in - taken out + result)."""
    lines = bk.lines
    bk.close, bk.close_posts = [], {}
    bk.pcb = dict(bk.closing)
    i = find(lines, YEAR_CLOSE)
    if not ok(i is not None, "%s: the year-close entries are missing" % bk.path):
        return
    head_ok(bk.path, lines, i, bk.name)
    tbl = read_tables(lines, i, block(lines, i))[0][1]
    prefix = bk.vouchers[0]["vid"].rsplit("-", 1)[0]
    pseudo = {}
    for k, r in enumerate(tbl[1:], 1):
        vid, date, note, dcell, ccell, amt = r[:6]
        amount = paise(amt)
        ok(vid == "%s-Y%d" % (prefix, k) and pdate(date) == FY_END, "%s close entry %s: number or date" % (bk.path, vid))
        drs, crs = split_cell(dcell, amount, bk.path, vid), split_cell(ccell, amount, bk.path, vid)
        ok(sum(a for _, a in drs) == amount == sum(a for _, a in crs), "%s close entry %s: sides differ from the amount" % (bk.path, vid))
        ok(not ({n for n, _ in drs} & {n for n, _ in crs}), "%s close entry %s: an account on both sides" % (bk.path, vid))
        lns = [(n, a) for n, a in drs] + [(n, -a) for n, a in crs]
        bk.close.append((vid, note.strip(), lns))
        for n, a in lns:
            if n in bk.type:
                ok(bk.type[n] in ("Income", "Expense", "Drawings", "Share-out") or bk.type[n] in EQUITY, "%s close entry %s: touches %s (%s)" % (bk.path, vid, n, bk.type[n]))
                bk.pcb[n] += a
                others = [m for m, b in lns if (b > 0) != (a > 0)]
                bk.close_posts.setdefault(n, []).append((vid, note.strip(), a, others))
            else:
                pseudo[n] = pseudo.get(n, 0) + a
    ok(all(v == 0 for v in pseudo.values()) and len(pseudo) >= 1, "%s close: the result account is not closed (%r)" % (bk.path, pseudo))
    ok(all(bk.pcb[n] == 0 for n in bk.accounts if bk.type[n] in ("Income", "Expense", "Drawings", "Share-out")), "%s close: an income, expense or drawings account is left open" % bk.path)
    start, put, taken = equity_parts(bk, FY_END)
    inc = sum(-bk.closing[n] for n in bk.accounts if bk.type[n] == "Income")
    exp = sum(bk.closing[n] for n in bk.accounts if bk.type[n] == "Expense")
    ok(-sum(bk.pcb[n] for n in bk.accounts if bk.type[n] in EQUITY) == start + put - taken + inc - exp, "%s close: own money after the close is not start + put in - taken out + result" % bk.path)
    ok(sum(a for _, _, lns in bk.close for n, a in lns if n not in bk.type and a > 0) >= max(inc, exp), "%s close: the heads are not all closed to the result" % bk.path)


def bal_at(bk, name, date):
    return bk.opening[name] + sum(a for d, _, a in bk.post[name] if d <= date)


def mov(bk, name, s, e):
    d = sum(a for dd, _, a in bk.post[name] if s <= dd <= e and a > 0)
    c = -sum(a for dd, _, a in bk.post[name] if s <= dd <= e and a < 0)
    return d, c


def check_ledger_rows(bk, name, rows, where):
    """One ledger-style table (an account's ledger, or a fund's statement) against the Day Book and the year-close entries."""
    posts = bk.post[name]
    cposts = bk.close_posts.get(name, [])
    bal = 0
    idx = cidx = 0
    tdr = tcr = 0
    closed = False
    for r in rows:
        part = clean(r[2])
        vid = clean(r[1])
        if part.startswith("Opening balance b/f"):
            bal = bk.opening[name]
            ok(bk.is_bs[name] and paise(r[3]) == max(bal, 0) and paise(r[4]) == max(-bal, 0) and paise(r[5]) == abs(bal) and clean(r[6]) == side(bal), "%s %s: b/f" % (where, name))
        elif part.startswith("Closing balance c/d"):
            closed = True
            ok(paise(r[3]) == (-bal if bal < 0 else 0) and paise(r[4]) == (bal if bal > 0 else 0), "%s %s: c/d" % (where, name))
        elif part == "Total":
            op = bk.opening[name]
            t1 = tdr + (op if op > 0 else 0) + (-bal if bal < 0 else 0)
            t2 = tcr + (-op if op < 0 else 0) + (bal if bal > 0 else 0)
            ok(paise(r[3]) == t1 == t2 == paise(r[4]), "%s %s: total" % (where, name))
        elif part.startswith("Opening balance b/d"):
            ok(paise(r[3]) == (bal if bal > 0 else 0) and paise(r[4]) == (-bal if bal < 0 else 0) and paise(r[5]) == abs(bal) and clean(r[6]) == side(bal), "%s %s: b/d" % (where, name))
        elif part.startswith("Total for the year"):
            closed = True
            ok(not bk.is_bs[name] and paise(r[3]) == tdr and paise(r[4]) == tcr and paise(r[5]) == abs(bal) and clean(r[6]) == side(bal), "%s %s: year total" % (where, name))
        elif re.search(r"-Y\d+$", vid):
            if not ok(cidx < len(cposts), "%s %s: a year-close row the close entries do not have" % (where, name)):
                continue
            cv, cnote, a, others = cposts[cidx]
            cidx += 1
            note = re.search(r"<br><em>(.*)</em>$", r[2])
            ok(vid == cv and pdate(r[0]) == FY_END and paise(r[3]) == max(a, 0) and paise(r[4]) == max(-a, 0) and note is not None and note.group(1) == cnote, "%s %s: close row %s" % (where, name, vid))
            ok(part.startswith("To " if a > 0 else "By ") and sorted(re.sub(r"^(To|By) ", "", part).split(" / ")) == sorted(others), "%s %s: close row %s names the other accounts" % (where, name, vid))
            if bk.is_bs[name]:
                bal += a
                tdr += max(a, 0)
                tcr += max(-a, 0)
                ok(paise(r[5]) == abs(bal) and clean(r[6]) == side(bal), "%s %s: close row %s balance" % (where, name, vid))
            else:
                ok(paise(r[5]) == 0 and clean(r[6]) == "—", "%s %s: close row %s must leave nil" % (where, name, vid))
        else:
            if not ok(idx < len(posts), "%s %s: more rows than Day Book postings" % (where, name)):
                break
            d, pvid, a = posts[idx]
            idx += 1
            ok(pdate(r[0]) == d and vid == pvid and paise(r[3]) == max(a, 0) and paise(r[4]) == max(-a, 0), "%s %s row %s differs from the Day Book" % (where, name, pvid))
            note = re.search(r"<br><em>(.*)</em>$", r[2])
            ok(note is not None and note.group(1) == bk.narr[pvid], "%s %s row %s: note differs from the Day Book" % (where, name, pvid))
            ok(part.startswith("To ") if a > 0 else part.startswith("By "), "%s %s row %s: To/By" % (where, name, pvid))
            bk.__dict__.setdefault("lpart", {})[(name, pvid)] = part
            bal += a
            tdr += max(a, 0)
            tcr += max(-a, 0)
            ok(paise(r[5]) == abs(bal) and clean(r[6]) == side(bal), "%s %s row %s: running balance" % (where, name, pvid))
            ok(bk.type[name] != "Credit card" or bal <= 0, "%s %s row %s: a credit card paid past nil" % (where, name, pvid))
    final = bk.pcb[name] if bk.is_bs[name] else bk.closing[name]
    ok(idx == len(posts) and cidx == len(cposts) and closed and (bal == final if bk.is_bs[name] else bal == bk.closing[name]), "%s %s: rows/closing" % (where, name))


def check_ledgers(bk):
    lines = bk.lines
    s, e = find(lines, r"^### 2\. "), find(lines, r"^### 3\. ")
    head_ok(bk.path, lines, s, bk.name)
    heads = [i for i in range(s, e) if lines[i].startswith("#### ")]
    seen = set()
    for hi, h in enumerate(heads):
        name = lines[h][5:].strip()
        hend = heads[hi + 1] if hi + 1 < len(heads) else e
        if not ok(name in bk.type, "%s ledger %r not in the chart" % (bk.path, name)):
            continue
        seen.add(name)
        tbls = read_tables(lines, h, hend)
        if not tbls:
            ok(not bk.post[name] and bk.opening[name] == 0, "%s ledger %s: no table but entries/opening" % (bk.path, name))
            continue
        check_ledger_rows(bk, name, tbls[0][1][1:], "%s ledger" % bk.path)
    ok(seen == set(bk.accounts), "%s: %d ledgers for %d accounts" % (bk.path, len(seen), len(bk.accounts)))
    foot_ok(bk, lines, s, e, COST_LINE, any(bk.type[n] == "Thing owned" and (bk.post[n] or bk.opening[n]) for n in bk.accounts), "ledgers")
    # every account that the close entries touch carries a close row (checked by the row counts above); each fund has its statement below


def bal_paise(cell):
    c = clean(cell)
    return -paise(c[:-3]) if c.endswith(" Cr") else paise(c)


BUILD_RE = re.compile(r"^The cost of (.+?), ₹([\d,]+) to date, is charged to expenditure and is not shown as a thing owned\.$")


def build_ok(bk, lines, s, e, date, what):
    """04 §4.3, 02 §5.8: a book that charges a building to expenditure (a Construction A/c) prints the construction note, with the cost to the
    report's date, at the foot of every report that gives the result — exactly when that cost is not nil."""
    cost = sum(a for d, _, a in bk.post.get("Construction A/c", []) if d <= date and a > 0)
    found = [(j, BUILD_RE.match(lines[j])) for j in range(s, e) if BUILD_RE.match(lines[j])]
    ok(len(found) == (1 if cost else 0), "%s %s: the construction note must be printed exactly when the cost to date is not nil" % (bk.path, what))
    for j, m in found:
        ok(paise(m.group(2)) == cost, "%s %s: the construction note says %s, the cost to %s is %d paise" % (bk.path, what, m.group(2), date, cost))
        last = max([k for k in range(s, e) if lines[k].startswith("|")] or [-1])
        ok(j > last, "%s %s: the construction note must stand at the foot of the report" % (bk.path, what))


def foot_ok(bk, lines, s, e, note, expected, what):
    """04 §4.3: a standing note is printed exactly when it applies, and at the foot — after the report's last table."""
    seg = lines[s:e]
    ok((note in seg) == expected, "%s %s: the note %r must be printed exactly when it applies" % (bk.path, what, note[:30]))
    if note in seg:
        k = s + seg.index(note)
        last = max([j for j in range(s, e) if lines[j].startswith("|")] or [-1])
        ok(k > last, "%s %s: the note %r must stand at the foot of the report" % (bk.path, what, note[:30]))


def check_cash_books(bk):
    """04 §5.4: one Cash Book of cash and each bank account — a Money in and a Money out column for each, a transfer between them on both sides."""
    lines = bk.export
    heads = [i for i, ln in enumerate(lines) if re.match(r"^### \d+\. Cash Book — ", ln)]
    ok(len(heads) == 1, "%s: one Cash Book expected, found %d" % (bk.path, len(heads)))
    ok(not any(re.search(r"(Bank|Wallet) Book", ln) for ln in lines + bk.lines), "%s: a separate Bank Book is printed or exported" % bk.path)
    if len(heads) != 1:
        return
    i = heads[0]
    names = re.match(r"^### \d+\. Cash Book — (.*)$", lines[i]).group(1).strip().split(" and ")
    want = [n for n in bk.accounts if bk.type[n] == "Cash"] + [n for n in bk.accounts if bk.type[n] == "Bank"]
    ok(names == want and want, "%s Cash Book: columns %s, expected cash and each bank %s" % (bk.path, names, want))
    k = len(names)
    tbl = read_tables(lines, i, block(lines, i))[0][1]
    ok(len(tbl[0]) == 3 + 3 * k and all("Money in" in h for h in tbl[0][3:3 + k]) and all("Money out" in h for h in tbl[0][3 + k:3 + 2 * k]),
       "%s Cash Book: a Money in and a Money out column for each of cash and the bank" % bk.path)
    vchs = [v for v in bk.vouchers if any(n in names for n, _ in v["lines"])]
    bal = {n: bk.opening[n] for n in names}
    mdr = {n: 0 for n in names}
    mcr = {n: 0 for n in names}
    idx = 0
    for r in tbl[1:]:
        part = clean(r[2])
        ins, outs, bals = r[3:3 + k], r[3 + k:3 + 2 * k], r[3 + 2 * k:3 + 3 * k]
        if part.startswith("Opening balance b/f"):
            ok(all(paise(ins[c]) == max(bal[n], 0) and paise(outs[c]) == max(-bal[n], 0) and bal_paise(bals[c]) == bal[n] for c, n in enumerate(names)),
               "%s Cash Book: opening balances on the Money in side" % bk.path)
        elif part.startswith("Month total"):
            mon = datetime.datetime.strptime(re.search(r"Month total — (\w+ \d{4})", part).group(1), "%B %Y").date()
            ok(all((v["date"].year, v["date"].month) != (mon.year, mon.month) for v in vchs[idx:]), "%s Cash Book: %s closed early" % (bk.path, mon))
            ok(all(paise(ins[c]) == mdr[n] and paise(outs[c]) == mcr[n] and bal_paise(bals[c]) == bal[n] for c, n in enumerate(names)),
               "%s Cash Book: month total %s" % (bk.path, mon))
            mdr = {n: 0 for n in names}
            mcr = {n: 0 for n in names}
        else:
            if not ok(idx < len(vchs), "%s Cash Book: extra row %s" % (bk.path, r[1])):
                break
            v = vchs[idx]
            idx += 1
            amt = {n: sum(a for m, a in v["lines"] if m == n) for n in names}
            ok(pdate(r[0]) == v["date"] and clean(r[1]) == v["vid"], "%s Cash Book row %s: date/number" % (bk.path, v["vid"]))
            for c, n in enumerate(names):
                ok(paise(ins[c]) == max(amt[n], 0) and paise(outs[c]) == max(-amt[n], 0), "%s Cash Book row %s: %s amounts" % (bk.path, v["vid"], n))
                bal[n] += amt[n]
                mdr[n] += max(amt[n], 0)
                mcr[n] += max(-amt[n], 0)
                ok(bal_paise(bals[c]) == bal[n], "%s Cash Book row %s: %s balance" % (bk.path, v["vid"], n))
                ok(bk.type[n] != "Cash" or bal[n] >= 0, "%s Cash Book row %s: cash below nil" % (bk.path, v["vid"]))
            if all(m in names for m, _ in v["lines"]):
                ok(any(amt[n] > 0 for n in names) and any(amt[n] < 0 for n in names), "%s Cash Book row %s: a transfer stands on both sides" % (bk.path, v["vid"]))
            else:
                moved = [n for n in names if amt[n]]
                came_in = sum(amt[n] for n in names) > 0
                want_part = (bk.lpart[(moved[0], v["vid"])] if len(moved) == 1 else
                             " / ".join(("To " if came_in else "By ") + m for m, a in v["lines"] if m not in names and (a < 0) == came_in))
                ok(part == want_part, "%s Cash Book row %s: particulars %r, expected %r (only the accounts on the other side of the money that moved, as in its ledger)" % (bk.path, v["vid"], part, want_part))
    ok(idx == len(vchs) and all(bal[n] == bk.closing[n] for n in names), "%s Cash Book: rows/closing" % bk.path)


def check_bank_extract(bk, wanted):
    lines = bk.lines
    i = find(lines, r"^#### 3\.\d+ Bank statement → entries — ")
    ok((i is not None) == wanted, "%s: bank-statement extract %s" % (bk.path, "missing" if wanted else "not expected"))
    if i is None:
        return
    m = re.match(r"^#### 3\.\d+ Bank statement → entries — (.*), (\w+ \d{4})$", lines[i])
    bank, mon = m.group(1).strip(), datetime.datetime.strptime(m.group(2), "%B %Y").date()
    end = datetime.date(mon.year + (mon.month == 12), mon.month % 12 + 1, 1) - datetime.timedelta(days=1)
    rows = read_tables(lines, i, block(lines, i))[0][1][1:]
    bal = bal_at(bk, bank, mon - datetime.timedelta(days=1))
    ok(signed(rows[0][4]) == bal, "%s extract: opening" % bk.path)
    posts = [p for p in bk.post[bank] if mon <= p[0] <= end]
    ok(len(rows) - 2 == len(posts), "%s extract: %d lines vs %d bank postings" % (bk.path, len(rows) - 2, len(posts)))
    for r, (d, vid, a) in zip(rows[1:-1], posts):
        ok(pdate(r[0]) == d and clean(r[6]) == vid and paise(r[2]) == max(-a, 0) and paise(r[3]) == max(a, 0), "%s extract %s" % (bk.path, vid))
        bal += a
        ok(signed(r[4]) == bal, "%s extract %s: balance" % (bk.path, vid))
        v = [x for x in bk.vouchers if x["vid"] == vid][0]
        ok(all(n in r[5] for n, _ in v["lines"] if n != bank), "%s extract %s: account not named" % (bk.path, vid))
    ok(signed(rows[-1][4]) == bal == bal_at(bk, bank, end), "%s extract: closing" % bk.path)


def check_ageing(bk):
    lines = bk.lines
    i = find(lines, r"^#### 3\.\d+ You will get / You will give — who owes what, and since when \(on ")
    if not ok(i is not None, "%s: You will get / You will give list missing" % bk.path):
        return
    asof = pdate(re.search(r"\(on (\d{2} \w{3} \d{4})\)", lines[i]).group(1))
    rows = read_tables(lines, i, block(lines, i))[0][1][1:]
    printed = {}
    tot = {1: [0, 0, 0, 0], -1: [0, 0, 0, 0]}
    for r in rows:
        name = clean(r[0])
        if name.startswith("Total you will"):
            sg = 1 if "get" in name else -1
            ok([paise(r[k]) for k in (2, 3, 4, 5)] == tot[sg], "%s ageing: %s" % (bk.path, name))
            continue
        sg = 1 if "(Dr)" in r[1] else -1
        bal, b1, b2, b3 = paise(r[2]), paise(r[3]), paise(r[4]), paise(r[5])
        printed[name] = sg * bal
        items = [[FY_START, bk.opening[name]]] if bk.opening[name] else []
        for d, _, amt in bk.post[name]:
            if d > asof:
                break
            while amt and items and (items[0][1] > 0) != (amt > 0):
                take = min(abs(amt), abs(items[0][1]))
                items[0][1] += take if items[0][1] < 0 else -take
                amt += take if amt < 0 else -take
                if items[0][1] == 0:
                    items.pop(0)
            if amt:
                items.append([d, amt])
        bks = [0, 0, 0]
        for d, x in items:
            days = (asof - d).days
            bks[0 if days <= 30 else (1 if days <= 90 else 2)] += abs(x)
        ok(bks == [b1, b2, b3] and b1 + b2 + b3 == bal, "%s ageing: %s buckets" % (bk.path, name))
        ok(items and pdate(r[6]) == items[0][0], "%s ageing: %s open-since date" % (bk.path, name))
        for k, x in enumerate((bal, b1, b2, b3)):
            tot[sg][k] += x
    expected = {n: bal_at(bk, n, asof) for n in bk.accounts if bk.type[n] == "Person / shop" and bal_at(bk, n, asof)}
    ok(printed == expected, "%s ageing: accounts/balances differ from the ledgers" % bk.path)


def result_to(bk, date):
    inc = sum(-bal_at(bk, n, date) for n in bk.accounts if bk.type[n] == "Income")
    exp = sum(bal_at(bk, n, date) for n in bk.accounts if bk.type[n] == "Expense")
    return inc, exp


def check_positions(bk):
    lines = bk.lines
    n_pos = 0
    for i, ln in enumerate(lines):
        m = re.match(r"^#### 3\.\d Full position on (\d{2} \w{3} \d{4})", ln)
        if not m:
            continue
        n_pos += 1
        date = pdate(m.group(1))
        head_ok(bk.path, lines, i, bk.name)
        shows = any(bk.type[n] == "Thing owned" and bal_at(bk, n, date) != 0 for n in bk.accounts)
        foot_ok(bk, lines, i, block(lines, i), COST_LINE, shows, "position %s" % date)
        foot_ok(bk, lines, i, block(lines, i), STOCK_LINE, "Goods Bought for Sale A/c" in bk.type, "position %s" % date)
        build_ok(bk, lines, i, block(lines, i), date, "position %s" % date)
        nst = sum(1 for n in bk.accounts if bk.type[n] == "Money in a business" and bal_at(bk, n, date) != 0)
        foot_ok(bk, lines, i, block(lines, i), STAKE_LINE, nst == 1, "position %s" % date)
        foot_ok(bk, lines, i, block(lines, i), STAKES_LINE, nst > 1, "position %s" % date)
        tbls = read_tables(lines, i, block(lines, i))
        have = get = give = fund = 0
        seen = set()
        for r in tbls[0][1][1:]:
            label = clean(r[1])
            grp = clean(r[0])
            if grp == "":
                if label.startswith("Total — what I have"):
                    ok(paise(r[2]) == have, "%s position %s: total have" % (bk.path, date))
                elif label.startswith("Total — what I will get"):
                    ok(paise(r[2]) == get, "%s position %s: total get" % (bk.path, date))
                elif label.startswith("Total — what I will give"):
                    ok(paise(r[3]) == give, "%s position %s: total give" % (bk.path, date))
                elif label.startswith("Total — funds"):
                    ok(paise(r[3]) == fund, "%s position %s: total funds" % (bk.path, date))
                else:
                    own = -paise(clean(r[2])[:-3]) if clean(r[2]).endswith(" Dr") else paise(r[2])
                    ok(own == have + get - give - fund, "%s position %s: own money" % (bk.path, date))
                continue
            seen.add(label)
            bal = bal_at(bk, label, date)
            ok(bk.type.get(label) not in EQUITY, "%s position %s: own-money account %s placed" % (bk.path, date, label))
            if grp == "What I will give":
                ok(paise(r[3]) == -bal > 0 and bk.type[label] != "Fund", "%s position %s: %s give (a fund is own money, not something to give)" % (bk.path, date, label))
                give += paise(r[3])
            elif grp == "Funds held for a purpose":
                ok(paise(r[3]) == -bal > 0 and bk.type[label] == "Fund", "%s position %s: %s fund" % (bk.path, date, label))
                fund += paise(r[3])
            elif grp == "What I will get":
                ok(paise(r[2]) == bal > 0, "%s position %s: %s get" % (bk.path, date, label))
                get += paise(r[2])
            else:
                ok(paise(r[2]) == bal >= 0, "%s position %s: %s have" % (bk.path, date, label))
                have += abs(bal)
        for n in bk.accounts:
            if bk.is_bs[n] and bk.type[n] not in EQUITY and bal_at(bk, n, date) != 0:
                ok(n in seen, "%s position %s: %s missing" % (bk.path, date, n))
        vals = [(clean(r[0]), paise(r[1])) for r in tbls[1][1][1:]]
        start, put, taken = equity_parts(bk, date)
        inc, exp = result_to(bk, date)
        # the result first (income − spent = result), then start + put in − taken out ± result = own money now (04 §6.3)
        res = inc - exp
        # a household's book names its account with the joint family in the make-up, in the words of that account's columns (MU-3)
        hh = any(bk.type[n] == "Joint family" for n in bk.accounts)
        put_w, taken_w = ("+ Received from the joint family so far", "− Put into the joint family, paid back or settled so far") if hh else ("+ Put in so far", "− Taken out so far")
        ok(vals[0] == ("Income so far", inc) and vals[1] == ("− Spent so far", exp) and vals[2][0].startswith("= Result so far") and vals[2][1] == abs(res)
           and vals[3][1] == start and vals[4][0].startswith(put_w) and vals[4][1] == put and vals[5][0].startswith(taken_w) and vals[5][1] == taken
           and vals[6][0].startswith(("+ " if res >= 0 else "− ") + "Result so far") and vals[6][1] == abs(res),
           "%s position %s: make-up lines" % (bk.path, date))
        ok(vals[7][1] == start + put - taken + res == have + get - give - fund, "%s position %s: make-up != position" % (bk.path, date))
    ok(n_pos == 2, "%s: two positions expected" % bk.path)


def check_month(bk):
    lines = bk.lines
    i = find(lines, r"^#### 3\.3 One month — ")
    if not ok(i is not None, "%s: one-month summary missing" % bk.path):
        return
    mon = datetime.datetime.strptime(re.search(r"— (\w+ \d{4}), account by account$", lines[i]).group(1), "%B %Y").date()
    end = datetime.date(mon.year + (mon.month == 12), mon.month % 12 + 1, 1) - datetime.timedelta(days=1)
    tbls = read_tables(lines, i, block(lines, i))
    ok(len(tbls) == 1, "%s one-month: the month's entries must not be repeated" % bk.path)
    rows = tbls[0][1][1:]
    tdr = tcr = 0
    seen = set()
    for r in rows[:-1]:
        n = clean(r[0])
        seen.add(n)
        ob = bal_at(bk, n, mon - datetime.timedelta(days=1))
        d, c = mov(bk, n, mon, end)
        ok(paise(r[1]) == abs(ob) and clean(r[2]) == side(ob) and paise(r[3]) == d and paise(r[4]) == c and paise(r[5]) == abs(ob + d - c) and clean(r[6]) == side(ob + d - c),
           "%s one-month: %s" % (bk.path, n))
        tdr += d
        tcr += c
    ok(paise(rows[-1][3]) == tdr == tcr == paise(rows[-1][4]), "%s one-month: totals" % bk.path)
    foot_ok(bk, lines, i, block(lines, i), COST_LINE, any(bk.type[n] == "Thing owned" and (bal_at(bk, n, mon - datetime.timedelta(days=1)) or mov(bk, n, mon, end) != (0, 0)) for n in bk.accounts), "one-month")
    foot_ok(bk, lines, i, block(lines, i), STOCK_LINE, "Goods Bought for Sale A/c" in bk.type, "one-month")
    build_ok(bk, lines, i, block(lines, i), end, "one-month")
    for n in bk.accounts:
        if n not in seen:
            ok(bal_at(bk, n, mon - datetime.timedelta(days=1)) == 0 and mov(bk, n, mon, end) == (0, 0), "%s one-month: %s omitted" % (bk.path, n))


def check_custom(bk):
    lines = bk.lines
    i = find(lines, r"^#### 3\.4 One account for a chosen period — ")
    if not ok(i is not None, "%s: chosen-period statement missing" % bk.path):
        return
    m = re.match(r"^#### 3\.4 One account for a chosen period — (.*), (\d{2} \w{3} \d{4}) to (\d{2} \w{3} \d{4})$", lines[i])
    name, s, e = m.group(1).strip(), pdate(m.group(2)), pdate(m.group(3))
    rows = read_tables(lines, i, block(lines, i))[0][1][1:]
    posts = [p for p in bk.post[name] if s <= p[0] <= e]
    if e == FY_END and bk.is_bs[name]:
        # 04 §5.6, nothing is left out of the period: a statement to the closed year's last day carries the year-close entries on the account (CA-7)
        posts += [(FY_END, vid, a) for vid, _, a, _ in bk.close_posts.get(name, [])]
    bal = bal_at(bk, name, s - datetime.timedelta(days=1)) if bk.is_bs[name] else 0
    start_bal = bal
    # 04 §5.6: opening with its side; the entries; the totals of the period's entries only; the closing balance with its side
    ok(clean(rows[0][2]).startswith("Opening balance on") and paise(rows[0][3]) == 0 and paise(rows[0][4]) == 0
       and paise(rows[0][5]) == abs(bal) and clean(rows[0][6]) == side(bal), "%s custom %s: opening (balance only, not in the totals)" % (bk.path, name))
    tdr = tcr = 0
    idx = 0
    for r in rows[1:-2]:
        if not ok(idx < len(posts), "%s custom %s: extra row" % (bk.path, name)):
            break
        d, vid, a = posts[idx]
        idx += 1
        bal += a
        tdr += max(a, 0)
        tcr += max(-a, 0)
        ok(pdate(r[0]) == d and clean(r[1]) == vid and paise(r[3]) == max(a, 0) and paise(r[4]) == max(-a, 0) and paise(r[5]) == abs(bal)
           and clean(r[6]) == side(bal) and "<em>" in r[2], "%s custom %s row %s" % (bk.path, name, vid))
    tot, clo = rows[-2], rows[-1]
    ok(clean(tot[2]) == "Total for the period" and paise(tot[3]) == tdr and paise(tot[4]) == tcr, "%s custom %s: totals of the period's entries only" % (bk.path, name))
    word = ("You will get" if bal > 0 else "You will give") if bk.type[name] == "Person / shop" and bal else None
    if bk.type[name] in ("Sub-family", "Joint family") and bal:
        # 04 §6.6: a sub-family's running account reads against / in favour of the household, or of the family in the household's book
        word = (("against the household" if bal > 0 else "in the household's favour") if bk.type[name] == "Sub-family"
                else ("against the family" if bal > 0 else "in the family's favour"))
    ok(clean(clo[2]).startswith("Closing balance on") and (word is None or clean(clo[2]).endswith(word)) and paise(clo[3]) == 0 and paise(clo[4]) == 0
       and paise(clo[5]) == abs(bal) and clean(clo[6]) == side(bal), "%s custom %s: closing line" % (bk.path, name))
    ok(idx == len(posts) and posts and bal == start_bal + sum(a for _, _, a in posts), "%s custom %s: rows" % (bk.path, name))


def appropriation(bk, result, rows_printed):
    """Interest on capital as printed basis says, then the shares: each within a paisa of the exact share, summing to the rest."""
    interest = {}
    shares = {}
    for r in rows_printed:
        p = clean(r[0])
        m = re.match(r"^To Interest on capital — (.*)$", p)
        if m:
            who = m.group(1)
            mm = re.match(r"^([\d.]+)% on ₹([\d,]+)$", clean(r[1]))
            cap = -bk.closing["Capital A/c – %s" % who]
            ok(paise(mm.group(2)) == cap, "%s appropriation: capital of %s" % (bk.path, who))
            rate_bp = int(round(float(mm.group(1)) * 100))
            exp = (2 * cap * rate_bp + 10000) // 20000
            ok(paise(r[2]) == exp, "%s appropriation: interest of %s" % (bk.path, who))
            interest[who] = exp
        m = re.match(r"^To Share of profit — (.*)$", p)
        if m:
            w, t = re.match(r"^(\d+) of (\d+)$", clean(r[1])).groups()
            shares[m.group(1)] = (int(w), int(t), paise(r[2]))
    rest = result - sum(interest.values())
    ok(rest > 0 and sum(x[2] for x in shares.values()) == rest, "%s appropriation: shares do not add up to the rest" % bk.path)
    for who, (w, t, s) in shares.items():
        ok(abs(s * t - rest * w) < t, "%s appropriation: share of %s" % (bk.path, who))
    return interest, shares


def check_closing(bk):
    lines = bk.lines
    i = find(lines, r"^#### 4\.1 Trial Balance")
    rows = read_tables(lines, i, block(lines, i))[0][1][1:]
    tdr = tcr = 0
    seen = set()
    for r in rows[:-1]:
        n = clean(r[0])
        seen.add(n)
        ok(len(r) == 3 and paise(r[1]) == max(bk.closing[n], 0) and paise(r[2]) == max(-bk.closing[n], 0) and bk.closing[n] != 0, "%s TB: %s" % (bk.path, n))
        tdr += paise(r[1])
        tcr += paise(r[2])
    ok(paise(rows[-1][1]) == tdr == tcr == paise(rows[-1][2]), "%s TB: totals" % bk.path)
    ok(all(bk.closing[n] == 0 for n in bk.accounts if n not in seen), "%s TB: a balance is missing" % bk.path)
    ti = find(lines, r"^#### 4\.1 Trial Balance")
    foot_ok(bk, lines, ti, block(lines, ti), COST_LINE, any(bk.type[n] == "Thing owned" and bk.closing[n] != 0 for n in bk.accounts), "TB")
    inc = {n: -bk.closing[n] for n in bk.accounts if bk.type[n] == "Income"}
    exp = {n: bk.closing[n] for n in bk.accounts if bk.type[n] == "Expense"}
    result = sum(inc.values()) - sum(exp.values())
    bk.result = result
    bk.appr_credit = {}
    # Receipts & Payments (organization books)
    rp = find(lines, r"^#### 4\.2 Receipts & Payments Account")
    if rp is not None:
        rows = read_tables(lines, rp, block(lines, rp))[0][1][1:]
        rec, pay = {}, {}
        head_ok(bk.path, lines, rp, bk.name)
        for v in bk.vouchers:
            if v["vtype"] == "Paid from a fund":
                for n, a in v["lines"]:
                    if a > 0 and bk.type[n] in ("Expense", "Thing owned"):
                        pay[n] = pay.get(n, 0) + a
                continue
            if v["vtype"] not in ("Money in", "Money out"):
                continue
            for n, a in v["lines"]:
                if n in bk.money:
                    continue
                ok(a > 0 or bk.type[n] not in MIXED_OK, "%s R&P: %s recovers an advance or a loan, which a Receipts & Payments account cannot show" % (bk.path, v["vid"]))
                if a < 0:
                    rec[n] = rec.get(n, 0) - a
                else:
                    pay[n] = pay.get(n, 0) + a
        # 04 §6.7: two sides — receipts (To …) on the left, payments (By …) on the right, totals level at the foot
        hdr = [clean(c) for c in read_tables(lines, rp, block(lines, rp))[0][1][0]]
        if not ok(hdr == ["Receipts", "₹", "Payments", "₹"], "%s R&P: receipts on the left, payments on the right (04 §6.7)" % bk.path):
            rows = []
        tr = tp = 0
        prec, ppay = set(), set()
        totals = 0
        for r in rows:
            for p, amt, sidex in ((clean(r[0]), r[1], "To "), (clean(r[2]), r[3], "By ")):
                if not p:
                    ok(not clean(amt), "%s R&P: an amount with no particulars" % bk.path)
                    continue
                if p == "Total":
                    ok(paise(amt) == (tr if sidex == "To " else tp), "%s R&P: total %s" % (bk.path, "receipts" if sidex == "To " else "payments"))
                    totals += 1
                    continue
                ok(p.startswith(sidex), "%s R&P: %r on the wrong side" % (bk.path, p))
                if p.startswith("To Opening balance — "):
                    ok(paise(amt) == bk.opening[p[21:]], "%s R&P: opening" % bk.path)
                    tr += paise(amt)
                elif p.startswith("By Closing balance — "):
                    ok(paise(amt) == bk.closing[p[21:]], "%s R&P: closing" % bk.path)
                    tp += paise(amt)
                elif p.startswith("To "):
                    ok(rec.get(p[3:]) == paise(amt), "%s R&P: %s" % (bk.path, p))
                    prec.add(p[3:])
                    tr += paise(amt)
                elif p.startswith("By "):
                    ok(pay.get(p[3:]) == paise(amt), "%s R&P: %s" % (bk.path, p))
                    ppay.add(p[3:])
                    tp += paise(amt)
        ok(totals == 2 and clean(rows[-1][0]) == clean(rows[-1][2]) == "Total", "%s R&P: both totals level on the last row" % bk.path)
        ok(tr == tp and prec == set(rec) and ppay == set(pay), "%s R&P: heads / totals" % bk.path)
    # the year's statement
    i = None
    for k, ln in enumerate(lines):
        if re.match(r"^#### 4\.\d (.*) for FY 2025-26$", ln) and "Receipts & Payments" not in ln and "Appropriation" not in ln:
            i = k
            break
    head_ok(bk.path, lines, i, bk.name)
    foot_ok(bk, lines, i, block(lines, i), STOCK_LINE, "Goods Bought for Sale A/c" in bk.type, "year's statement")
    build_ok(bk, lines, i, block(lines, i), FY_END, "year's statement")
    rows = read_tables(lines, i, block(lines, i))[0][1][1:]
    heads = set()
    for r in rows:
        p = clean(r[0])
        if p.startswith("To ") and p[3:] in exp:
            heads.add(p[3:])
            ok(paise(r[2]) == exp[p[3:]] and int(clean(r[1])) == len(bk.post[p[3:]]), "%s statement: %s" % (bk.path, p))
        elif p.startswith("By ") and p[3:] in inc:
            heads.add(p[3:])
            ok(paise(r[3]) == inc[p[3:]] and int(clean(r[1])) == len(bk.post[p[3:]]), "%s statement: %s" % (bk.path, p))
        elif p.startswith("Total of the heads"):
            ok(paise(r[2]) == sum(exp.values()) and paise(r[3]) == sum(inc.values()), "%s statement: heads total" % bk.path)
        elif p == "Total":
            ok(paise(r[2]) == paise(r[3]) == max(sum(exp.values()), sum(inc.values())), "%s statement: grand total" % bk.path)
        else:
            ok((paise(r[2]) if result >= 0 else paise(r[3])) == abs(result), "%s statement: result line" % bk.path)
    ok(heads == set(inc) | set(exp), "%s statement: every income and expense head" % bk.path)
    # appropriation (partnerships)
    interest, shares = {}, {}
    ap = find(lines, r"^#### 4\.\d Profit & Loss Appropriation Account")
    if ap is not None:
        rows = read_tables(lines, ap, block(lines, ap))[0][1][1:]
        head_ok(bk.path, lines, ap, bk.name)
        interest, shares = appropriation(bk, result, rows)
        by = [r for r in rows if clean(r[0]).startswith("By Net profit")]
        ok(len(by) == 1 and paise(by[0][3]) == result, "%s appropriation: net profit" % bk.path)
        # posted: each partner's account is credited with exactly his interest and share, out of the P&L Appropriation Account
        for who, (w, t, sh) in shares.items():
            bk.appr_credit[who] = interest.get(who, 0) + sh
            acct = "Current A/c – %s" % who if "Current A/c – %s" % who in bk.type else "%s A/c" % who
            credited = sum(-x[2] for x in bk.close_posts.get(acct, []) if x[2] < 0)
            ok(credited == interest.get(who, 0) + sh, "%s appropriation: %s's account is credited %d by the close, expected %d" % (bk.path, who, credited, interest.get(who, 0) + sh))
        appr_dr = sum(a for _, _, lns in bk.close for n, a in lns if n.startswith("P&L Appropriation") and a > 0)
        ok(appr_dr == result and sum(interest.values()) + sum(x[2] for x in shares.values()) == result, "%s appropriation: the account posted at the close is not the net profit" % bk.path)
    # balance sheet
    i = find(lines, r"^#### 4\.\d Full position on 31 Mar 2026")
    head_ok(bk.path, lines, i, bk.name)
    foot_ok(bk, lines, i, block(lines, i), COST_LINE, any(bk.type[n] == "Thing owned" and bk.closing[n] != 0 for n in bk.accounts), "balance sheet")
    foot_ok(bk, lines, i, block(lines, i), STOCK_LINE, "Goods Bought for Sale A/c" in bk.type, "balance sheet")
    build_ok(bk, lines, i, block(lines, i), FY_END, "balance sheet")
    nst = sum(1 for n in bk.accounts if bk.type[n] == "Money in a business" and bk.closing[n] != 0)
    foot_ok(bk, lines, i, block(lines, i), STAKE_LINE, nst == 1, "balance sheet")
    foot_ok(bk, lines, i, block(lines, i), STAKES_LINE, nst > 1, "balance sheet")
    tbls = read_tables(lines, i, block(lines, i))
    start, put, taken = equity_parts(bk, FY_END)
    own_close = start + put - taken + result
    k = 0
    partners_total = {}
    if ap is not None:
        prow = tbls[0][1][1:]
        k = 1
        ok(len(tbls[0][1][0]) == 8 and "Drawings" in tbls[0][1][0][6], "%s partners: 04 §6.5 columns (opening, put in, interest, share, drawings, closing)" % bk.path)
        seen = []
        for r in prow:
            who, which = clean(r[0]), clean(r[1])
            n = {"Capital": "Capital A/c – %s" % who, "Current": "Current A/c – %s" % who}.get(which, "%s A/c" % who)
            ok(n in bk.closing, "%s partners: no account %s" % (bk.path, n))
            if n not in bk.closing:
                continue
            put = -sum(a for _, _, a in bk.post[n] if a < 0)
            drawn = sum(a for _, _, a in bk.post[n] if a > 0)
            i_, s_ = (0, 0) if which == "Capital" else (interest.get(who, 0), shares[who][2])
            ok(signed(r[2]) == bk.opening[n] and paise(r[3]) == put and paise(r[4]) == i_ and paise(r[5]) == s_ and paise(r[6]) == drawn,
               "%s partners: %s %s — opening, put in, interest, share, drawings" % (bk.path, who, which))
            after = -bk.closing[n] + i_ + s_
            ok(signed(r[7]) == -after and bk.pcb[n] == -after, "%s partners: %s %s closing after the close" % (bk.path, who, which))
            partners_total[who] = partners_total.get(who, 0) + after
            seen.append(n)
        want = [n for n in bk.accounts if n.startswith(("Capital A/c – ", "Current A/c – ")) or any(n == "%s A/c" % w for w in shares)]
        ok(sorted(seen) == sorted(want), "%s partners: every partner's account once %s" % (bk.path, sorted(set(want) ^ set(seen))))
        ok(sum(partners_total.values()) == own_close, "%s partners: totals != own money" % bk.path)
    liab, assets = tbls[k][1][1:], tbls[k + 1][1][1:]
    kinds_seq = [bk.type.get(clean(r[0])) for r in liab if clean(r[0]) in bk.type]
    ok(kinds_seq == sorted(kinds_seq, key=lambda t: 0 if t == "Fund" else 1), "%s balance sheet: a fund must be listed with the own money, before what I will give" % bk.path)
    tl = ta = 0
    for r in liab:
        p = clean(r[0])
        if p.endswith("at the start, 01 Apr 2025"):
            ok(paise(r[1]) == start, "%s BS: own money at the start" % bk.path)
        elif p.startswith(("Add: put in", "Add: received from the joint family")):
            ok(paise(r[1]) == put, "%s BS: put in" % bk.path)
        elif p.startswith(("Less: taken out", "Less: put into the joint family")):
            ok(paise(r[1]) == taken, "%s BS: taken out" % bk.path)
        elif p.startswith("Add: ") or p.startswith("Less: "):
            ok(paise(r[1]) == abs(result), "%s BS: result" % bk.path)
        elif p.endswith("at the end, 31 Mar 2026"):
            ok(paise(r[1]) == own_close, "%s BS: own money at the end" % bk.path)
            tl += paise(r[1])
        elif " at the end" in p and ap is not None:
            who = p.split(" — ")[0]
            ok(paise(r[1]) == partners_total.get(who), "%s BS: partner %s" % (bk.path, who))
            tl += paise(r[1])
        elif p == "Total":
            ok(paise(r[1]) == tl, "%s BS: total of what I will give" % bk.path)
        else:
            ok(bk.closing.get(p, 0) < 0 and paise(r[1]) == -bk.closing[p], "%s BS: %s" % (bk.path, p))
            tl += paise(r[1])
    for r in assets:
        p = clean(r[0])
        if p == "Total":
            ok(paise(r[1]) == ta, "%s BS: total of what I have" % bk.path)
        else:
            ok(paise(r[1]) == abs(bk.closing[p]), "%s BS: %s" % (bk.path, p))
            ta += paise(r[1])
    listed = {clean(r[0]) for r in liab + assets}
    for n in bk.accounts:
        if bk.is_bs[n] and bk.type[n] not in EQUITY and bk.closing[n] != 0:
            ok(n in listed, "%s BS: %s missing" % (bk.path, n))
    ok(tl == ta, "%s BS: sides %d / %d" % (bk.path, tl, ta))
    # carry-forward: after the year close; every balance-sheet account at its own balance (a partner's capital and current separately, 04 §2.6)
    i = find(lines, r"^#### 4\.\d Carried into FY 2026-27")
    head_ok(bk.path, lines, i, bk.name)
    rows = read_tables(lines, i, block(lines, i))[0][1][1:]
    owners = {}
    expect = {}
    inowner = {n for ns in owners.values() for n in ns}
    for lab, ns in owners.items():
        expect[lab] = sum(bk.pcb[n] for n in ns)
    for n in bk.accounts:
        if bk.is_bs[n] and n not in inowner and bk.pcb[n] != 0:
            expect[n] = bk.pcb[n]
    tdr = tcr = 0
    seen = {}
    foot_ok(bk, lines, i, block(lines, i), COST_LINE, any(bk.type[n] == "Thing owned" and bk.pcb[n] != 0 for n in bk.accounts), "carry-forward")
    for r in rows[:-1]:
        p = clean(r[0])
        amt = paise(r[2]) * (1 if clean(r[3]) == "Dr" else -1)
        ok(len(r) == 6 and paise(r[4]) == paise(r[2]) and clean(r[5]) == clean(r[3]), "%s carry-forward %s: opening b/d against the closing after the close" % (bk.path, p))
        seen[p] = amt
        if amt > 0:
            tdr += amt
        else:
            tcr -= amt
    ok(seen == expect, "%s carry-forward: rows differ from the balances after the close (%s)" % (bk.path, sorted(set(seen.items()) ^ set(expect.items()))[:4]))
    ok(all(bk.pcb[n] == 0 for n in bk.accounts if bk.type[n] in ("Income", "Expense", "Drawings", "Share-out")), "%s carry-forward: a head or the drawings is carried" % bk.path)
    ok(tdr == tcr == paise(rows[-1][2]) == paise(rows[-1][3]) == paise(rows[-1][4]) == paise(rows[-1][5]), "%s carry-forward: Σ" % bk.path)
    # a fund's statement (trusts and committees)
    fi = find(lines, r"^#### 4\.\d Each fund — its year")
    funds = [n for n in bk.accounts if bk.type[n] == "Fund"]
    ok((fi is not None) == bool(funds), "%s: a statement of each fund is %s" % (bk.path, "missing" if funds else "unexpected"))
    if fi is not None:
        head_ok(bk.path, lines, fi, bk.name)
        end = block(lines, fi)
        while end < len(lines) and not lines[end].startswith("#### "):
            end = block(lines, end)
        subs = [k for k in range(fi, end) if re.match(r"^\*\*(.*)\*\*$", lines[k])]
        ok([re.match(r"^\*\*(.*)\*\*$", lines[k]).group(1) for k in subs] == funds, "%s: the fund statements are not one per fund" % bk.path)
        for k in subs:
            name = re.match(r"^\*\*(.*)\*\*$", lines[k]).group(1)
            tb = read_tables(lines, k, min([x for x in subs if x > k] + [end]))
            if ok(bool(tb) and name in bk.type, "%s fund %s: no table, or not an account" % (bk.path, name)):
                check_ledger_rows(bk, name, tb[0][1][1:], "%s fund statement" % bk.path)
    return result


def check_pair_section(label, lines, b, ob, mine, theirs):
    """04 §6.6 item 1, 03 §4.6: the account between two books — each opening, every entry once with its number in both books (the two numbers post the
    same amount on opposite sides of the pair's accounts), the year-close entries on the pair's accounts (net per entry), each closing after the close;
    a running-account pair ends *Agrees* in the 04 §6.6 words."""
    i = find(lines, r"^### Account between %s and %s — " % (re.escape(b.name), re.escape(ob.name)))
    if not ok(i is not None, "%s: the account between %s and %s is missing" % (label, b.name, ob.name)):
        return
    head_ok(label, lines, i, "%s · %s" % (b.name, ob.name))
    end = block(lines, i)
    tbls = read_tables(lines, i, end)
    if not ok(len(tbls) == 1, "%s: account between %s and %s: one table expected" % (label, b.name, ob.name)):
        return
    rows = tbls[0][1][1:]
    val = lambda r, k: paise(r[k]) - paise(r[k + 1])
    op1 = sum(b.opening[x] for x in mine if b.is_bs[x])
    op2 = sum(ob.opening[x] for x in theirs if ob.is_bs[x])
    ok(clean(rows[0][1]) == "Brought forward" and val(rows[0], 3) == op1 and val(rows[0], 6) == op2, "%s: %s / %s pair section: brought forward" % (label, b.name, ob.name))
    want1 = sorted((d, vid, a) for x in mine for d, vid, a in b.post[x])
    want2 = sorted((d, vid, a) for x in theirs for d, vid, a in ob.post[x])
    got1, got2, bal1, bal2 = [], [], op1, op2
    close1, close2 = {}, {}
    for x in mine:
        for vid, _, a, _ in b.close_posts.get(x, []):
            close1[vid] = close1.get(vid, 0) + a
    for x in theirs:
        for vid, _, a, _ in ob.close_posts.get(x, []):
            close2[vid] = close2.get(vid, 0) + a
    seen1, seen2 = {}, {}
    for r in rows[1:-1]:
        d, v1, v2 = pdate(r[0]), clean(r[2]), clean(r[5])
        a1, a2 = val(r, 3), val(r, 6)
        bal1 += a1
        bal2 += a2
        if "-Y" in v1 or "-Y" in v2:
            ok(d == FY_END and (not v1 or not v2), "%s: %s / %s pair section: a year-close row belongs to one book" % (label, b.name, ob.name))
            if v1:
                seen1[v1] = a1
            else:
                seen2[v2] = a2
            continue
        ok(a1 == -a2 != 0, "%s: %s / %s pair section %s/%s: not the same amount on opposite sides" % (label, b.name, ob.name, v1, v2))
        got1.append((d, v1, a1))
        got2.append((d, v2, a2))
    ok(sorted(got1) == want1 and sorted(got2) == want2, "%s: %s / %s pair section: the entries are not every entry of the pair's accounts" % (label, b.name, ob.name))
    ok(seen1 == {k: v for k, v in close1.items() if v} and seen2 == {k: v for k, v in close2.items() if v}, "%s: %s / %s pair section: year-close rows" % (label, b.name, ob.name))
    c1 = sum(b.pcb[x] for x in mine)
    c2 = sum(ob.pcb[x] for x in theirs)
    clo = rows[-1]
    ok(clean(clo[1]).startswith("Closing balance") and val(clo, 3) == c1 == bal1 and val(clo, 6) == c2 == bal2, "%s: %s / %s pair section: closing after the close" % (label, b.name, ob.name))
    tail = [ln for ln in lines[i:end] if ln.startswith("**")]
    stake = any(b.type[x] == "Money in a business" for x in mine) or any(ob.type[x] == "Money in a business" for x in theirs)
    if stake:
        ok(any(ln == "**Entries agree one for one.**" for ln in tail), "%s: %s / %s pair section: last line" % (label, b.name, ob.name))
    else:
        ok(c1 == -c2, "%s: %s / %s running-account pair does not agree" % (label, b.name, ob.name))
        words = {("Sub-family", 1): "against the household", ("Sub-family", -1): "in the household's favour",
                 ("Joint family", 1): "against the family", ("Joint family", -1): "in the family's favour"}
        if c1 == 0:
            exp = "**Agrees** — nil in both books."
        else:
            w = lambda bk, x, c: words.get((bk.type[x], 1 if c > 0 else -1), side(c))
            exp = "**Agrees** — ₹%s %s in %s's book, and ₹%s %s in %s's book." % (fmt_in(abs(c1)), w(b, mine[0], c1), b.name, fmt_in(abs(c2)), w(ob, theirs[0], c2), ob.name)
        ok(exp in tail, "%s: %s / %s pair section: expected %r" % (label, b.name, ob.name, exp))


def fmt_in(p):
    """Integer paise → Indian-grouped rupees (paise only when non-zero), as the books print them."""
    r, ps = divmod(p, 100)
    s = str(r)
    if len(s) > 3:
        head, tail = s[:-3], s[-3:]
        parts = []
        while len(head) > 2:
            parts.insert(0, head[-2:])
            head = head[:-2]
        if head:
            parts.insert(0, head)
        s = ",".join(parts) + "," + tail
    return s + (".%02d" % ps if ps else "")


def check_family(label, books, lines):
    """Pairs of books keeping accounts named after each other: the account named after the other book, and (joint book) its
    'Income from …' head. Openings must be opposite and every posting mirrored on the other side, entry for entry."""
    names = {b.name: b for b in books}

    def accts(b, o):
        return [n for n in b.accounts if n in ("%s A/c" % o.name, "Income from %s A/c" % o.name, "Capital A/c – %s" % o.name, "Drawings A/c – %s" % o.name)]
    pairs = {}
    for b in books:
        for n in b.accounts:
            if n.endswith(" A/c") and n[:-4] in names and n[:-4] != b.name:
                ob = names[n[:-4]]
                if not ok(bool(accts(ob, b)), "%s: %s has %s but %s has no account named after it" % (label, b.name, n, ob.name)):
                    continue
                key = tuple(sorted([b.name, ob.name]))
                mine, theirs = accts(b, ob), accts(ob, b)
                op1 = sum(b.opening[x] for x in mine if b.is_bs[x])
                op2 = sum(ob.opening[x] for x in theirs if ob.is_bs[x])
                p1 = sorted((d, a) for x in mine for d, _, a in b.post[x])
                p2 = sorted((d, -a) for x in theirs for d, _, a in ob.post[x])
                ok(op1 == -op2 and p1 == p2, "%s: %s / %s do not mirror" % (label, b.name, ob.name))
                pairs[key] = (op1, sum(a for _, a in p1 if a > 0), -sum(a for _, a in p1 if a < 0), len(p1))
    i = find(lines, r"^## (Family summary|The two books side by side)")
    ok((i is not None) == bool(pairs), "%s: family summary %s" % (label, "missing" if pairs else "unexpected"))
    if i is None:
        return
    head_ok(label, lines, i, " · ".join(b.name for b in books))
    rows = read_tables(lines, i, len(lines))[0][1][1:]
    ok(len(rows) == len(pairs), "%s: summary rows %d, pairs %d" % (label, len(rows), len(pairs)))
    for r in rows:
        b, ob = names[clean(r[0])], names[clean(r[5])]
        mine = [x.strip() for x in r[1].split("<br>")]
        theirs = [x.strip() for x in r[6].split("<br>")]
        ok(set(mine) == set(accts(b, ob)) and set(theirs) == set(accts(ob, b)), "%s: summary accounts %s" % (label, r[1]))
        check_pair_section(label, lines, b, ob, mine, theirs)
        op1 = sum(b.opening[x] for x in mine if b.is_bs[x])
        g1 = sum(a for x in mine for _, _, a in b.post[x] if a > 0)
        r1 = -sum(a for x in mine for _, _, a in b.post[x] if a < 0)
        ok(signed(r[2]) == op1 and signed(r[7]) == -op1 and paise(r[3]) == g1 and paise(r[4]) == r1 and paise(r[8]) == r1 and paise(r[9]) == g1
           and int(clean(r[10])) == pairs[tuple(sorted([b.name, ob.name]))][3], "%s: summary row %s / %s" % (label, b.name, ob.name))
        # an owner and the business he owns agree entry by entry but not in balance; a running-account pair agrees balance for balance (O-16-1, amended 20 Oct 2026)
        owner = None
        for own, bus, oa, ba in ((b, ob, mine, theirs), (ob, b, theirs, mine)):
            if any(own.type[x] == "Money in a business" for x in oa):
                owner = (own, bus, oa, ba)
        if owner is None:
            ok(sum(b.closing[x] for x in mine) == -sum(ob.closing[x] for x in theirs), "%s: %s / %s are a running-account pair but do not agree balance for balance" % (label, b.name, ob.name))
        else:
            own, bus, oa, ba = owner
            a_ = -sum(bus.pcb[x] for x in ba if bus.type[x] in EQUITY)
            b_ = sum(own.closing[x] for x in oa if own.type[x] == "Money in a business")
            # 03 §4.1: a negative difference is printed as taken out beyond the profit
            hdr = ("**Profit kept in the business — %s and %s:**" if a_ - b_ >= 0 else "**Taken out beyond the profit — %s and %s:**") % (own.name, bus.name)
            kl = [ln for ln in lines if ln.startswith(hdr)]
            if ok(len(kl) == 1, "%s: the profit-kept line for %s / %s is missing" % (label, own.name, bus.name)):
                nums = [(-1 if sg else 1) * paise(v) for sg, v in re.findall(r"(−?)₹(\d(?:[\d,]*\d)?(?:\.\d\d)?)", kl[0].replace(hdr, ""))]
                takes = -sum(own.closing[x] for x in oa if own.type[x] == "Income")
                res = bus.appr_credit.get(own.name) if bus.appr_credit else bus.result
                ok(res is not None and nums == [a_, b_, a_ - b_, res, takes, res, takes, res - takes] and a_ - b_ == res - takes,
                   "%s: profit kept in the business, %s / %s: printed %r, expected %r" % (label, own.name, bus.name, nums, [a_, b_, a_ - b_, res, takes]))


def check_heads(bk):
    """Every report heading of the printed book and of the export is followed by its head (O-20-1, O-20-2)."""
    for i, ln in enumerate(bk.lines):
        if re.match(r"^(### [12]\. |#### [34]\.\d)", ln):
            head_ok(bk.path, bk.lines, i, bk.name)
    for i, ln in enumerate(bk.export):
        if re.match(r"^### \d+\. (Day Book|Cash Book)", ln):
            head_ok(bk.path, bk.export, i, bk.name)


def check_coverage_md(folder, books_by_prefix):
    """COVERAGE.md and GAPS.md are hand-written; every entry number they cite must exist in the regenerated books (a Y number in the year-close entries)."""
    for fname, minimum in (("COVERAGE.md", 100), ("GAPS.md", 60)):
        path = os.path.join(folder, fname)
        if not ok(os.path.exists(path), "%s is missing" % fname):
            continue
        text = open(path, encoding="utf-8").read()
        cited = set(re.findall(r"`((?:JP|JT|RJ|RA|RB|RC|RG|RE|RK|S|BF|RS)-(?:Y)?\d+)(?:…Y\d+)?`", text))
        ok(len(cited) > minimum, "%s: only %d entry numbers cited" % (fname, len(cited)))
        for ref in sorted(cited):
            pre, num = ref.rsplit("-", 1)
            bk = books_by_prefix.get(pre)
            if not ok(bk is not None, "%s cites %s but no book has the prefix %s" % (fname, ref, pre)):
                continue
            if num.startswith("Y"):
                ok(any(cl[0] == ref for cl in bk.close), "%s cites %s, which is not a year-close entry of %s" % (fname, ref, bk.name))
            else:
                ok(ref in bk.narr, "%s cites %s, which is not an entry of %s" % (fname, ref, bk.name))
        for rid in re.findall(r"O-\d\d-\d+", text):
            ok(1 <= int(rid.split("-")[1]) <= 20, "%s: bad row id %s" % (fname, rid))
    text = open(os.path.join(folder, "COVERAGE.md"), encoding="utf-8").read() if os.path.exists(os.path.join(folder, "COVERAGE.md")) else ""
    for slug in ("individual", "family", "shop", "partnership", "trust"):
        ok(slug in text, "COVERAGE.md does not mention %s" % slug)


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    files = sorted(f[:-3] for f in os.listdir(folder) if f.endswith(".md") and not f.endswith(".tech.md") and not f.endswith(".export.md") and f not in ("README.md", "GAPS.md", "COVERAGE.md"))
    ok(files == sorted(EXPECTED), "expected the five book files, found %s" % files)
    books_by_prefix = {}
    for f in files:
        text = open(os.path.join(folder, f + ".md"), encoding="utf-8").read()
        ok(os.path.exists(os.path.join(folder, f + ".export.md")), "%s: the Day Book and Cash Book export is missing" % f)
        etext = open(os.path.join(folder, f + ".export.md"), encoding="utf-8").read()
        for tok in NOT_ON_PAGE:
            pat = (r"\b%s\b" if tok[0].isalpha() and tok[-1].isalpha() else "%s") % re.escape(tok)
            ok(re.search(pat, text) is None and re.search(pat, etext) is None, "%s: the printed page or the export carries %r" % (f, tok))
        lines = text.split("\n")
        elines = etext.split("\n")
        estarts = {ln[9:].split(" — ")[0].strip(): k for k, ln in enumerate(elines) if ln.startswith("## Book: ")}
        starts = [i for i, ln in enumerate(lines) if ln.startswith("## Book: ")]
        tail = find(lines, r"^## (Family summary|The two books side by side)")
        books = []
        for k, s in enumerate(starts):
            e = starts[k + 1] if k + 1 < len(starts) else (tail if tail is not None else len(lines))
            name = lines[s][9:].split(" — ")[0].strip()
            es = estarts.get(name)
            ok(es is not None, "%s: no export for book %s" % (f, name))
            ee = min([k for k in estarts.values() if es is not None and k > es] + [len(elines)])
            bk = parse_book("%s [%s]" % (f, name), name, lines[s:e], elines[es:ee] if es is not None else [])
            lo, hi = MAX_ENTRIES["family" if f.startswith("joint-family") else "single"]
            ok(lo <= len(bk.vouchers) <= hi, "%s: %d entries, expected %d–%d" % (bk.path, len(bk.vouchers), lo, hi))
            check_ledgers(bk)
            check_cash_books(bk)
            check_bank_extract(bk, f.split("-")[0] in ("individual", "shop"))
            check_heads(bk)
            check_ageing(bk)
            check_positions(bk)
            check_month(bk)
            check_custom(bk)
            check_closing(bk)
            books.append(bk)
            books_by_prefix[bk.vouchers[0]["vid"].rsplit("-", 1)[0]] = bk
            print("%-62s entries %3d  accounts %3d  checks so far %6d" % (bk.path, len(bk.vouchers), len(bk.accounts), checks))
        ok(len(books) >= 1, "%s: no book" % f)
        check_family(f, books, lines)
    check_coverage_md(folder, books_by_prefix)
    for p in problems:
        print("PROBLEM: " + p)
    print("checks: %d   problems: %d" % (checks, len(problems)))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
