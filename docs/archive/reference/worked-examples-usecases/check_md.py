#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Independent re-derivation of every trial balance, every ledger's running balances and every
year-close vector from the PRINTED markdown of this folder.  Shares no code with build.py: it
parses the tables as a reader would, sums the day book, and compares.  It also checks the
reading order of the plain headings and that no technical token (rule reference, engine class,
verb id, backtick, ⚠️) appears on a printed report (ADR 2026-10-12 §2).  The .tech.md companions
are technical by design and are not read.

usage:  python3 -I check_md.py [folder]        (default: the folder this script sits in)
exit 0 when every check agrees; the last line reads  "checks: N   problems: M".

build.py runs this after writing the seven use-case files and refuses to continue on any problem.
"""
import os
import re
import sys

AMT = re.compile(r"^(\d{1,3}(?:,\d{2,3})*|\d+)(?:\.(\d{2}))?$")
TAG_SUFFIX = re.compile(r"\s\((interest on capital|profit share)\)$")

# The printed report speaks the user's language (ADR 2026-10-12 §2): none of these may appear in it.
# This list is written independently of build.py's own lint.
FORBIDDEN = [r"§", r"\bADR\b", r"`", r"⚠", r"🔒", r"build\.py", r"PROVISIONAL", r"\bSPEC\b",
             r"\b(money_in|money_out|gave_credit|took_credit)\b", r"\b(equity_system|category_income|category_expense|cash_collection)\b",
             r"\b(transfer_group|import_line|structural_quorum|peer_reviewer)\b", r"refs\.", r"\bEngine class\b",
             r"\b[Vv]ouchers?\b", r"\bVch\b", r"\b[Nn]arration\b", r"\b[Jj]ournal\b", r"\b[Cc]ontra\b", r"Cross-check"]

# the plain headings of a printed book, in reading order (regexes on the title after its number)
H_ACCOUNTS = r"Accounts and opening balances"
H_LEDGERS = r"Account statements"
H_DAYBOOK = r"Day book"
H_TB = r"Closing balances"
H_PL = r"Income and expenses for the year"
H_POS = r"What .* \(position\)"
H_YEAR = r"Year end"


def paise(s):
    s = s.strip().strip("*").strip()
    if s in ("—", "", "-"):
        return 0
    m = AMT.match(s)
    if not m:
        raise ValueError("bad amount %r" % s)
    r = int(m.group(1).replace(",", ""))
    p = int(m.group(2)) if m.group(2) else 0
    return r * 100 + p


def cells(line):
    assert line.startswith("|") and line.rstrip().endswith("|"), line
    inner = line.strip()[1:-1]
    return [c.strip() for c in inner.split(" | ")] if " | " in inner else [c.strip() for c in inner.split("|")]


def tables_after(lines, start_idx, stop_prefix):
    i = start_idx
    while i < len(lines):
        ln = lines[i]
        if ln.startswith(stop_prefix):
            return
        if ln.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                rows.append(cells(lines[i]))
                i += 1
            yield rows
            continue
        i += 1


def section(seg, pattern):
    """Index of the ### heading whose title (after its number) matches `pattern`; sections are numbered per book."""
    for i, ln in enumerate(seg):
        m = re.match(r"^### \d+\. (.*)$", ln)
        if m and re.match(pattern, m.group(1)):
            return i
    return None


def section_end(seg, i):
    for j in range(i + 1, len(seg)):
        if seg[j].startswith("### ") or seg[j].startswith("## "):
            return j
    return len(seg)


def table_at(seg, i, end, first_header):
    for rows in tables_after(seg[:end], i + 1, "\x00"):
        if rows[0][0].startswith(first_header):
            return rows
    return None


def strip_md(s):
    return s.replace("~~", "").replace("**", "").strip()


def parse_side_cell(name_cell, total, multi):
    """Daybook Debit/Credit cell → list of (account, paise)."""
    items = [strip_md(x) for x in name_cell.split("<br>") if strip_md(x)]
    out = []
    if len(items) == 1 and not multi:
        return [(items[0], total)]
    for it in items:
        it = TAG_SUFFIX.sub("", it)
        m = re.match(r"^(.*) (\d[\d,]*(?:\.\d{2})?)$", it)
        if not m:
            if len(items) == 1:
                return [(it, total)]
            raise ValueError("cannot parse side item %r" % it)
        out.append((m.group(1).strip(), paise(m.group(2))))
    return out


def check_file(path):
    text = open(path, encoding="utf-8").read()
    lines = text.split("\n")
    problems = []
    checks = 0
    # --- plain language: nothing technical on a printed report
    checks += 1
    for pat in FORBIDDEN:
        m = re.search(pat, text)
        if m:
            problems.append("%s: technical token %r at line %d: %r" % (os.path.basename(path), m.group(0), text.count("\n", 0, m.start()) + 1, text[max(0, m.start() - 50):m.start() + 50]))
    book_idx = [i for i, ln in enumerate(lines) if ln.startswith("## Book: ")]
    book_idx.append(len(lines))
    summary = []
    for bi in range(len(book_idx) - 1):
        s, e = book_idx[bi], book_idx[bi + 1]
        name = lines[s][len("## Book: "):]
        seg = lines[s:e]
        # --- daybook → balances
        di = section(seg, H_DAYBOOK)
        if di is None:
            problems.append("%s: no day book" % name)
            continue
        # the order a ledger book is read in: accounts → every statement → … → closing balances (TB) → income and expenses → position → year end
        order = [section(seg, t) for t in (H_ACCOUNTS, H_LEDGERS, H_TB, H_PL, H_POS, H_YEAR)]
        o = [x for x in order if x is not None]
        checks += 1
        if len(o) != 6 or o != sorted(o) or order[0] != o[0] or order[-1] != o[-1]:
            problems.append("%s: sections out of order or missing %s" % (name, order))
        checks += 1
        if len(o) == 6 and not (o[1] < di < o[2]):   # the day book is a supporting register: after the statements, before the closing balances
            problems.append("%s: day book is not between the statements and the closing balances" % name)
        bal = {}
        n_v = n_counted = 0
        for rows in tables_after(seg[:section_end(seg, di)], di + 1, "\x00"):
            if rows[0][0] != "Date":
                continue
            for r in rows[2:]:
                n_v += 1
                if "amended by" in r[8]:
                    continue  # amended-away original — not counted (02 §5)
                n_counted += 1
                total = paise(strip_md(r[6]))
                multi = ("<br>" in r[4]) or ("<br>" in r[5])
                drs = parse_side_cell(r[4], total, multi)
                crs = parse_side_cell(r[5], total, multi)
                sd, sc = sum(p for _, p in drs), sum(p for _, p in crs)
                checks += 1
                if sd != sc or sd != total:
                    problems.append("%s: voucher %s does not balance (Dr %d Cr %d total %d)" % (name, r[1], sd, sc, total))
                for a, p in drs:
                    bal[a] = bal.get(a, 0) + p
                for a, p in crs:
                    bal[a] = bal.get(a, 0) - p
        # --- trial balance
        ti = section(seg, H_TB)
        tb = {}
        tot_dr = tot_cr = None
        for rows in tables_after(seg[:section_end(seg, ti)], ti + 1, "\x00"):
            if rows[0][0] != "Account":
                continue
            for r in rows[2:]:
                acc = strip_md(r[0])
                if acc == "Total":
                    tot_dr, tot_cr = paise(r[2]), paise(r[3])
                    continue
                tb[acc] = paise(r[2]) - paise(r[3])
        for acc, p in tb.items():
            checks += 1
            if bal.get(acc, 0) != p:
                problems.append("%s: %s — daybook gives %d, TB shows %d" % (name, acc, bal.get(acc, 0), p))
        for acc in bal:
            if acc not in tb:
                problems.append("%s: %s appears in the daybook but not in the TB" % (name, acc))
        sdr = sum(p for p in tb.values() if p > 0)
        scr = -sum(p for p in tb.values() if p < 0)
        checks += 1
        if sdr != tot_dr or scr != tot_cr or sdr != scr:
            problems.append("%s: TB totals (printed %s/%s; recomputed %d/%d)" % (name, tot_dr, tot_cr, sdr, scr))
        # --- ledgers: running balances, the khata block, agreement with the TB
        li = section(seg, H_LEDGERS)
        le = section_end(seg, li)
        j = li + 1
        n_ledgers = 0
        ledger_bf = {}
        ledger_names = []
        while j < le:
            if not seg[j].startswith("#### "):
                j += 1
                continue
            acc = seg[j][5:].strip()
            k = j + 1
            ledger_names.append(acc)
            while k < le and not seg[k].startswith("|") and not seg[k].startswith("#### "):
                k += 1
            if k >= le or seg[k].startswith("#### "):
                if tb.get(acc, 0) != 0:
                    problems.append("%s: %s has no ledger table but TB %d" % (name, acc, tb.get(acc, 0)))
                j = k
                continue
            rows = []
            while k < le and seg[k].startswith("|"):
                rows.append(cells(seg[k]))
                k += 1
            n_ledgers += 1
            running = None
            sum_dr = sum_cr = 0
            closing = None
            is_cat = True
            for r in rows[2:]:
                part = strip_md(r[2])
                dr, cr = paise(strip_md(r[3])), paise(strip_md(r[4]))
                amt = paise(strip_md(r[5])) if len(r) > 5 else 0
                side = strip_md(r[6]) if len(r) > 6 else ""
                shown = amt if side == "Dr" else (-amt if side == "Cr" else 0)
                if part.startswith("Opening balance b/f"):
                    is_cat = False
                    running = shown
                    ledger_bf[acc] = shown
                    checks += 1
                    if dr != 0 or cr != 0:
                        problems.append("%s: %s b/f row must carry its amount under Balance only (standards §2)" % (name, acc))
                    if running > 0:
                        sum_dr += running
                    elif running < 0:
                        sum_cr += -running
                    continue
                if part.startswith("Closing balance c/d"):
                    closing = running
                    exp_dr = -running if running < 0 else 0
                    exp_cr = running if running > 0 else 0
                    checks += 1
                    if dr != exp_dr or cr != exp_cr:
                        problems.append("%s: %s c/d row wrong (%d/%d vs %d/%d)" % (name, acc, dr, cr, exp_dr, exp_cr))
                    sum_dr += dr
                    sum_cr += cr
                    continue
                if part.startswith("Total"):
                    checks += 1
                    if is_cat:
                        closing = running or 0
                        if dr != sum_dr or cr != sum_cr:
                            problems.append("%s: %s category total row (%d/%d vs %d/%d)" % (name, acc, dr, cr, sum_dr, sum_cr))
                        if shown != closing:
                            problems.append("%s: %s category balance %d vs %d" % (name, acc, shown, closing))
                    else:
                        if dr != cr or dr != sum_dr or cr != sum_cr:
                            problems.append("%s: %s Total row does not foot (%d/%d; recomputed incl. b/f %d/%d)" % (name, acc, dr, cr, sum_dr, sum_cr))
                    continue
                if part.startswith("Opening balance b/d"):
                    checks += 1
                    if shown != closing:
                        problems.append("%s: %s b/d %d vs closing %d" % (name, acc, shown, closing))
                    continue
                if running is None:
                    running = 0
                running += dr - cr
                sum_dr += dr
                sum_cr += cr
                checks += 1
                if shown != running:
                    problems.append("%s: %s running balance at %s %s: shown %d, recomputed %d" % (name, acc, r[0], r[1], shown, running))
            if closing is None:
                closing = running or 0
            if acc not in tb:
                problems.append("%s: ledger %s not in TB" % (name, acc))
            elif tb[acc] != closing:
                problems.append("%s: ledger %s closes at %d, TB says %d" % (name, acc, closing, tb[acc]))
            j = k
        # --- year-close vector
        # --- chart: complete, opening Dr = Cr, each opening = the ledger's b/f row
        ci = section(seg, H_ACCOUNTS)
        chart = table_at(seg, ci, section_end(seg, ci), "#")
        chart_accts = []
        cdr = ccr = 0
        for r in chart[2:]:
            acc = strip_md(r[1])
            if acc == "Total of opening balances":
                checks += 1
                if paise(r[4]) != cdr or paise(r[5]) != ccr or cdr != ccr:
                    problems.append("%s: chart opening totals %s/%s vs recomputed %d/%d" % (name, r[4], r[5], cdr, ccr))
                continue
            chart_accts.append(acc)
            op = paise(r[4]) - paise(r[5])
            cdr += paise(r[4])
            ccr += paise(r[5])
            checks += 1
            if ledger_bf.get(acc, 0) != op:
                problems.append("%s: chart opening of %s is %d, its ledger b/f is %d" % (name, acc, op, ledger_bf.get(acc, 0)))
        checks += 1
        if sorted(chart_accts) != sorted(tb) or sorted(ledger_names) != sorted(tb):
            problems.append("%s: chart / ledgers / TB do not list the same accounts" % name)
        # --- P&L / I&E: every head's year total = its TB balance; the statement balances
        pi = section(seg, H_PL)
        pl = table_at(seg, pi, section_end(seg, pi), "Particulars")
        heads = {}
        net = None
        sdr2 = scr2 = 0
        for r in pl[2:]:
            part = strip_md(r[0])
            dr, cr = paise(r[2]), paise(r[3])
            if part.startswith("Total of the heads"):
                checks += 1
                if dr != sdr2 or cr != scr2:
                    problems.append("%s: P&L head totals %d/%d vs %d/%d" % (name, dr, cr, sdr2, scr2))
                net = cr - dr
                continue
            if part == "Total":
                checks += 1
                if dr != cr or dr != max(sdr2, scr2):
                    problems.append("%s: P&L does not balance (%d/%d)" % (name, dr, cr))
                continue
            if net is not None:   # the balancing line
                checks += 1
                if dr - cr != net:
                    problems.append("%s: P&L balancing line %d vs net %d" % (name, dr - cr, net))
                continue
            acc = re.sub(r"^(To|By) ", "", part).replace(" (nets to nil)", "")
            heads[acc] = dr - cr
            sdr2 += dr
            scr2 += cr
        for acc, p in tb.items():
            if acc in heads:
                checks += 1
                if heads[acc] != p:
                    problems.append("%s: P&L %s %d vs TB %d" % (name, acc, heads[acc], p))
        # --- position: has − owes = the computed equity, and its make-up adds up
        qi = section(seg, H_POS)
        qe = section_end(seg, qi)
        pos = table_at(seg, qi, qe, "Account")
        has = owes = eq = acct_has = acct_owes = 0
        for r in pos[2:]:
            acc = strip_md(r[0])
            dr, cr = paise(r[2]), paise(r[3])
            if acc == "Total":
                checks += 1
                if dr != cr or dr != has:
                    problems.append("%s: position total %d/%d vs has %d" % (name, dr, cr, has))
                continue
            if r[1] == "own money":   # the computed line — net worth / owner's or partners' funds / Corpus
                eq = cr - dr
                has += dr
                continue
            checks += 1
            if tb.get(acc) != dr - cr:
                problems.append("%s: position %s %d vs TB %s" % (name, acc, dr - cr, tb.get(acc)))
            has += dr
            owes += cr
            acct_has, acct_owes = has, owes
        checks += 1
        if acct_has - acct_owes != eq:
            problems.append("%s: position has %d − owes %d ≠ %d" % (name, acct_has, acct_owes, eq))
        mk = table_at(seg, qi, qe, "Particulars")
        run = 0
        for r in mk[2:]:
            part = strip_md(r[0])
            v = paise(r[1]) * (1 if strip_md(r[2]) == "Dr" else (-1 if strip_md(r[2]) == "Cr" else 0))
            if part.startswith("="):
                checks += 1
                if v != run or -v != eq:
                    problems.append("%s: equity make-up %d vs lines %d vs position %d" % (name, -v, -run, eq))
                continue
            if part.startswith("Net ") and net is not None:
                checks += 1
                if -v != net:
                    problems.append("%s: equity make-up net %d vs P&L %d" % (name, -v, net))
            run += v
        yi = section(seg, H_YEAR)
        vec_ok = "n/a"
        if yi is not None:
            for rows in tables_after(seg, yi + 1, "#### FY 2026-27"):
                if not rows[0][0].startswith("Account carried to"):
                    continue
                tot = vdr = vcr = 0
                for r in rows[2:]:
                    amt = paise(strip_md(r[2]))
                    side = strip_md(r[3])
                    v = amt if side == "Dr" else (-amt if side == "Cr" else 0)
                    tot += v
                    vdr += amt if side == "Dr" else 0
                    vcr += amt if side == "Cr" else 0
                    acc = strip_md(r[0])
                    if acc in tb:
                        checks += 1
                        if tb[acc] != v:
                            problems.append("%s: vector %s %d vs TB %d" % (name, acc, v, tb[acc]))
                checks += 1
                vec_ok = "sum 0 ok" if tot == 0 else "sum %d" % tot
                if tot != 0:
                    problems.append("%s: vector does not sum to zero (%d)" % (name, tot))
                # the printed sentence under the table restates the two totals
                sent = next((ln for ln in seg[yi:] if ln.startswith("The carried balances agree: Dr ₹")), None)
                checks += 1
                m = re.match(r"^The carried balances agree: Dr ₹(\S+) = Cr ₹(\S+)\.", sent or "")
                if not m or paise(m.group(1)) != vdr or paise(m.group(2)) != vcr:
                    problems.append("%s: carried-balance totals sentence (%r) vs recomputed %d/%d" % (name, sent, vdr, vcr))
        summary.append((name, n_v, n_counted, len(tb), sdr, n_ledgers, vec_ok))
    return summary, problems, checks


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    files = sorted(f for f in os.listdir(folder) if f.endswith(".md") and f != "README.md" and not f.endswith(".tech.md"))
    all_problems = []
    total_checks = 0
    for f in files:
        summary, problems, checks = check_file(os.path.join(folder, f))
        total_checks += checks
        print(f)
        for name, nv, nc, na, tot, nl, vec in summary:
            print("   %-48s vouchers %4d (counted %4d) accounts %2d ledgers %2d  TB paise %14d  vector %s" % (name[:48], nv, nc, na, nl, tot, vec))
        for p in problems:
            print("   PROBLEM:", p)
        all_problems.extend(problems)
    print("checks: %d   problems: %d" % (total_checks, len(all_problems)))
    sys.exit(1 if all_problems else 0)


if __name__ == "__main__":
    main()
