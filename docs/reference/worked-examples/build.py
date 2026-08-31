import os
from collections import defaultdict, OrderedDict

HDR = {
 'money':      ("Money in (Dr.)", "Money out (Cr.)"),
 'debtor':     ("Given / owed to you (Dr.)", "Received back (Cr.)"),
 'creditor':   ("You paid (Dr.)", "You took / owed (Cr.)"),
 'advance':    ("Handed out (Dr.)", "Settled / returned (Cr.)"),
 'expense':    ("Spent (Dr.)", "Refund / adj. (Cr.)"),
 'income':     ("Refund / adj. (Dr.)", "Earned (Cr.)"),
 'equity':     ("Withdrawn (Dr.)", "Added (Cr.)"),
 'interbook':  ("They owe this book (Dr.)", "This book owes them (Cr.)"),
 'interbook_note': ("",""),
}
NATURAL = {'money':'Dr','debtor':'Dr','advance':'Dr','expense':'Dr','equity':'Cr',
           'creditor':'Cr','income':'Cr','interbook':'Dr'}

def inr(n):
    n = int(round(n))
    if n == 0: return "—"
    s = str(abs(n)); 
    if len(s) > 3:
        head, tail = s[:-3], s[-3:]
        parts = []
        while len(head) > 2:
            parts.insert(0, head[-2:]); head = head[:-2]
        if head: parts.insert(0, head)
        s = ",".join(parts) + "," + tail
    return s

class Book:
    def __init__(self, name, subtitle=""):
        self.name, self.subtitle = name, subtitle
        self.accounts = OrderedDict()   # name -> (type, opening_signed)
        self.vouchers = []              # (vid, date, narration, dr, cr, amt)
    def acc(self, name, typ, opening=0):
        self.accounts[name] = (typ, opening)
    def v(self, vid, date, narration, dr, cr, amt):
        self.vouchers.append((vid, date, narration, dr, cr, amt))

    def build(self):
        for _, _, _, dr, cr, _ in self.vouchers:
            for a in (dr, cr):
                assert a in self.accounts, f"{self.name}: undefined account {a}"
        opening_total = sum(o for _, o in self.accounts.values())
        if opening_total != 0:
            self.accounts["Opening Balance / Capital A/c"] = ('equity', -opening_total)
        led = defaultdict(list)
        bal = {a: o for a, (t, o) in self.accounts.items()}
        run = {a: o for a in bal for o in [bal[a]]}
        for a, (t, o) in self.accounts.items():
            led[a].append(("01 Apr 2026", "", "Opening balance b/f", "", 0, 0, o))
        for vid, date, narr, dr, cr, amt in self.vouchers:
            run[dr] += amt; led[dr].append((date, vid, f"To {cr}", narr, amt, 0, run[dr]))
            run[cr] -= amt; led[cr].append((date, vid, f"By {dr}", narr, 0, amt, run[cr]))
        self.led, self.final = led, run
        return self

    def side(self, a, val):
        return "Dr" if val > 0 else ("Cr" if val < 0 else NATURAL[self.accounts[a][0]])

    def md(self):
        L = [f"# {self.name}", ""]
        if self.subtitle: L += [self.subtitle, ""]
        L += ["**Period:** 01 April 2026 – 29 August 2026 (FY 2026-27) · **Every figure below is generated from the vouchers and verified to balance.**",
              "", "---", "", "## 1. Chart of accounts & opening balances (as on 01 April 2026)", "",
              "| # | Account | Type | Opening balance (₹) |", "|---:|---|---|---:|"]
        for i, (a, (t, o)) in enumerate(self.accounts.items(), 1):
            L.append(f"| {i} | {a} | {t.title()} | {inr(abs(o))+' '+self.side(a,o) if o else '—'} |")
        L += ["", "## 2. Daybook / Cash book — chronological voucher register", "",
              "| Date | Particulars of transaction | Account debited (Dr.) | Account credited (Cr.) | Amount (₹) |",
              "|:---|:---|:---|:---|---:|"]
        for vid, date, narr, dr, cr, amt in self.vouchers:
            L.append(f"| {date}<br><em>{vid}</em> | {narr} | {dr} | {cr} | {inr(amt)} |")
        L += ["", f"*Total vouchers: {len(self.vouchers)}. Each voucher ID appears in both ledger accounts it touches (§3), so any row can be traced to its opposite leg.*",
              "", "## 3. Ledger accounts", ""]
        for a, (t, o) in self.accounts.items():
            dh, ch = HDR[t]
            fin = self.final[a]
            L += [f"### {a}", f"*Type: {t.title()} · Natural balance: {NATURAL[t]}.*", "",
                  f"| Date | Particulars | {dh} | {ch} | Balance (₹) |",
                  "|:---|:---|---:|---:|---:|"]
            for date, vid, part, narr, d, c, b in self.led[a]:
                dcell = date + (f"<br><em>{vid}</em>" if vid else "")
                p = part + (f"<br><em>{narr}</em>" if narr else "")
                L.append(f"| {dcell} | {p} | {inr(d)} | {inr(c)} | {inr(abs(b))} {self.side(a,b)} |")
            L.append(f"| **29 Aug 2026** | **Closing balance c/f** | — | — | **{inr(abs(fin))} {self.side(a,fin)}** |")
            dt = sum(r[4] for r in self.led[a]); ct = sum(r[5] for r in self.led[a])
            L += ["", f"*Cross-check: opening {inr(abs(o))} {self.side(a,o) if o else ''} + debits {inr(dt)} − credits {inr(ct)} = **{inr(abs(fin))} {self.side(a,fin)}**.*", ""]
        drs = {a: v for a, v in self.final.items() if v > 0}
        crs = {a: -v for a, v in self.final.items() if v < 0}
        L += ["## 4. Trial balance as on 29 August 2026", "",
              "| Account | Debit (Dr.) ₹ | Credit (Cr.) ₹ |", "|---|---:|---:|"]
        for a in self.accounts:
            if a in drs: L.append(f"| {a} | {inr(drs[a])} | — |")
            elif a in crs: L.append(f"| {a} | — | {inr(crs[a])} |")
        td, tc = sum(drs.values()), sum(crs.values())
        L += [f"| **TOTALS** | **{inr(td)}** | **{inr(tc)}** |", "",
              f"**Verified: Dr ₹{inr(td)} = Cr ₹{inr(tc)}. The books balance.**", ""]
        assert td == tc, f"{self.name} UNBALANCED {td} vs {tc}"
        return "\n".join(L), td

BOOKS = []
# ============ 1. RAHUL SHARMA — PERSONAL BOOK ============
b = Book("Individual / Personal Book — Rahul Sharma",
 "Entity type: **Individual**. Salary earner with household spending, a friend who borrows, an NRI relative he owed money to, a dairy khata and a credit card.")
b.acc("SBI Savings A/c",'money',85000); b.acc("Axis Salary A/c",'money',42000)
b.acc("Cash in Hand",'money',15000); b.acc("PNB Credit Card A/c",'creditor',0)
b.acc("Sundar Singh A/c",'debtor',12000); b.acc("Raman USA A/c",'creditor',-50000)
b.acc("Vardhman Dairy A/c",'creditor',-2800)
for n in ["Household Expense A/c","Utility Expense A/c","Milk Expense A/c","Education Expense A/c",
          "Medical Expense A/c","Travel & Fuel Expense A/c","Insurance Expense A/c"]: b.acc(n,'expense')
b.acc("Salary Income A/c",'income')
V=[("V-001","01 Apr 2026","Monthly salary credited by employer","Axis Salary A/c","Salary Income A/c",95000),
("V-002","03 Apr 2026","ATM withdrawal for household cash","Cash in Hand","Axis Salary A/c",20000),
("V-003","05 Apr 2026","Transfer to savings account","SBI Savings A/c","Axis Salary A/c",40000),
("V-004","07 Apr 2026","Electricity bill paid online","Utility Expense A/c","SBI Savings A/c",3200),
("V-005","10 Apr 2026","Monthly grocery purchase in cash","Household Expense A/c","Cash in Hand",8500),
("V-006","15 Apr 2026","Sundar Singh repaid part of old loan","Cash in Hand","Sundar Singh A/c",5000),
("V-007","20 Apr 2026","School fees paid for Kabir","Education Expense A/c","SBI Savings A/c",22000),
("V-008","25 Apr 2026","Vardhman Dairy monthly milk bill received","Milk Expense A/c","Vardhman Dairy A/c",3100),
("V-009","28 Apr 2026","Paid Vardhman Dairy previous month dues","Vardhman Dairy A/c","Cash in Hand",2800),
("V-010","01 May 2026","Monthly salary credited by employer","Axis Salary A/c","Salary Income A/c",95000),
("V-011","04 May 2026","Repaid Raman USA by bank transfer","Raman USA A/c","Axis Salary A/c",15000),
("V-012","08 May 2026","Petrol and travel expenses in cash","Travel & Fuel Expense A/c","Cash in Hand",4200),
("V-013","12 May 2026","Hospital consultation and medicines","Medical Expense A/c","SBI Savings A/c",6800),
("V-014","18 May 2026","Fresh hand loan given to Sundar Singh","Sundar Singh A/c","Cash in Hand",10000),
("V-015","25 May 2026","Vardhman Dairy monthly milk bill received","Milk Expense A/c","Vardhman Dairy A/c",3400),
("V-016","28 May 2026","Paid Vardhman Dairy April bill","Vardhman Dairy A/c","Cash in Hand",3100),
("V-017","01 Jun 2026","Monthly salary credited by employer","Axis Salary A/c","Salary Income A/c",95000),
("V-018","06 Jun 2026","Household purchases on PNB credit card","Household Expense A/c","PNB Credit Card A/c",12400),
("V-019","15 Jun 2026","PNB credit card bill settled in full","PNB Credit Card A/c","Axis Salary A/c",12400),
("V-020","20 Jun 2026","Electricity and water bills paid","Utility Expense A/c","SBI Savings A/c",3600),
("V-021","25 Jun 2026","Vardhman Dairy monthly milk bill received","Milk Expense A/c","Vardhman Dairy A/c",3300),
("V-022","28 Jun 2026","Paid Vardhman Dairy May bill","Vardhman Dairy A/c","Cash in Hand",3400),
("V-023","01 Jul 2026","Monthly salary credited by employer","Axis Salary A/c","Salary Income A/c",95000),
("V-024","05 Jul 2026","Transfer to savings account","SBI Savings A/c","Axis Salary A/c",50000),
("V-025","12 Jul 2026","Sundar Singh repaid by UPI","SBI Savings A/c","Sundar Singh A/c",8000),
("V-026","20 Jul 2026","Annual life insurance premium","Insurance Expense A/c","SBI Savings A/c",18000),
("V-027","25 Jul 2026","Vardhman Dairy monthly milk bill received","Milk Expense A/c","Vardhman Dairy A/c",3500),
("V-028","01 Aug 2026","Monthly salary credited by employer","Axis Salary A/c","Salary Income A/c",95000),
("V-029","10 Aug 2026","Repaid Raman USA by bank transfer","Raman USA A/c","SBI Savings A/c",20000),
("V-030","14 Aug 2026","ATM withdrawal for household cash","Cash in Hand","Axis Salary A/c",25000),
("V-031","18 Aug 2026","Household provisions purchased in cash","Household Expense A/c","Cash in Hand",9200),
("V-032","25 Aug 2026","Vardhman Dairy monthly milk bill received","Milk Expense A/c","Vardhman Dairy A/c",3600),
("V-033","27 Aug 2026","Paid Vardhman Dairy June and July bills","Vardhman Dairy A/c","Cash in Hand",6800)]
for x in V: b.v(*x)
BOOKS.append(("individual-rahul-sharma", b))

# ============ 2. SHARMA TEXTILE — BUSINESS BOOK ============
b = Book("Business Book — Sharma Textile",
 "Entity type: **Commercial business** (proprietor: Pankaj Sharma). Cash and credit sales, credit purchases of yarn, freight, rent, staff salary, supplier settlement and owner's drawings.")
b.acc("Indian Bank Current A/c",'money',240000); b.acc("Business Cash A/c",'money',18000)
b.acc("Guru Nanak Cloth House A/c",'debtor',45000); b.acc("Tuglaq Yarn Company A/c",'creditor',-85000)
b.acc("Avtar Transport Co. A/c",'creditor',0)
for n in ["Purchases A/c","Rent Expense A/c","Staff Salary Expense A/c","Freight Expense A/c",
          "Shop Utility Expense A/c","Packing & Misc. Expense A/c"]: b.acc(n,'expense')
b.acc("Sales A/c",'income'); b.acc("Drawings A/c",'equity')
V=[("B-001","02 Apr 2026","Counter cash sales for the day","Business Cash A/c","Sales A/c",32000),
("B-002","05 Apr 2026","Cloth sold on credit to Guru Nanak Cloth House","Guru Nanak Cloth House A/c","Sales A/c",120000),
("B-003","08 Apr 2026","Yarn purchased on credit from Tuglaq Yarn Company","Purchases A/c","Tuglaq Yarn Company A/c",95000),
("B-004","10 Apr 2026","Freight billed by Avtar Transport Co. (on credit)","Freight Expense A/c","Avtar Transport Co. A/c",8500),
("B-005","12 Apr 2026","Shop rent paid for April","Rent Expense A/c","Indian Bank Current A/c",25000),
("B-006","15 Apr 2026","Guru Nanak Cloth House paid by UPI","Indian Bank Current A/c","Guru Nanak Cloth House A/c",60000),
("B-007","18 Apr 2026","Part payment to Tuglaq Yarn Company","Tuglaq Yarn Company A/c","Indian Bank Current A/c",50000),
("B-008","22 Apr 2026","Staff salaries paid for April","Staff Salary Expense A/c","Indian Bank Current A/c",34000),
("B-009","28 Apr 2026","Shop electricity bill paid in cash","Shop Utility Expense A/c","Business Cash A/c",4800),
("B-010","03 May 2026","Counter cash sales","Business Cash A/c","Sales A/c",41000),
("B-011","07 May 2026","Freight bill of Avtar Transport paid","Avtar Transport Co. A/c","Indian Bank Current A/c",8500),
("B-012","12 May 2026","Shop rent paid for May","Rent Expense A/c","Indian Bank Current A/c",25000),
("B-013","16 May 2026","Cloth sold on credit to Guru Nanak Cloth House","Guru Nanak Cloth House A/c","Sales A/c",78000),
("B-014","20 May 2026","Packing material and miscellaneous","Packing & Misc. Expense A/c","Business Cash A/c",6200),
("B-015","22 May 2026","Staff salaries paid for May","Staff Salary Expense A/c","Indian Bank Current A/c",34000),
("B-016","26 May 2026","Guru Nanak Cloth House paid in cash","Business Cash A/c","Guru Nanak Cloth House A/c",45000),
("B-017","02 Jun 2026","Yarn purchased on credit from Tuglaq Yarn Company","Purchases A/c","Tuglaq Yarn Company A/c",120000),
("B-018","08 Jun 2026","Cash deposited into current account","Indian Bank Current A/c","Business Cash A/c",60000),
("B-019","12 Jun 2026","Shop rent paid for June","Rent Expense A/c","Indian Bank Current A/c",25000),
("B-020","18 Jun 2026","Part payment to Tuglaq Yarn Company","Tuglaq Yarn Company A/c","Indian Bank Current A/c",80000),
("B-021","22 Jun 2026","Staff salaries paid for June","Staff Salary Expense A/c","Indian Bank Current A/c",34000),
("B-022","30 Jun 2026","Owner's drawings for household use","Drawings A/c","Business Cash A/c",25000),
("B-023","06 Jul 2026","Counter cash sales","Business Cash A/c","Sales A/c",52000),
("B-024","12 Jul 2026","Shop rent paid for July","Rent Expense A/c","Indian Bank Current A/c",25000),
("B-025","18 Jul 2026","Cloth sold on credit to Guru Nanak Cloth House","Guru Nanak Cloth House A/c","Sales A/c",96000),
("B-026","22 Jul 2026","Staff salaries paid for July","Staff Salary Expense A/c","Indian Bank Current A/c",34000),
("B-027","28 Jul 2026","Guru Nanak Cloth House paid by UPI","Indian Bank Current A/c","Guru Nanak Cloth House A/c",90000),
("B-028","05 Aug 2026","Freight billed by Avtar Transport Co. (on credit)","Freight Expense A/c","Avtar Transport Co. A/c",11200),
("B-029","12 Aug 2026","Shop rent paid for August","Rent Expense A/c","Indian Bank Current A/c",25000),
("B-030","20 Aug 2026","Counter cash sales","Business Cash A/c","Sales A/c",38000),
("B-031","26 Aug 2026","Owner's drawings for household use","Drawings A/c","Indian Bank Current A/c",30000)]
for x in V: b.v(*x)
BOOKS.append(("business-sharma-textile", b))

# ============ 4. TRUST ============
b = Book("Trust Book — Singh Sabha Gurudwara",
 "Entity type: **Trust / religious organization**. Gollak collections, sponsor donations, langar expenses, and a sevadar advance (ਪੇਸ਼ਗੀ) tracked as its own account so every movement stays a real journal entry.")
b.acc("Trust SBI A/c",'money',180000); b.acc("Gollak Cash A/c",'money',24000)
b.acc("Advance – Amritpal Singh A/c",'advance',0)
for n in ["Langar Expense A/c","Building Repair Expense A/c","Electricity Expense A/c",
          "Granthi Honorarium A/c","Sound & Media Expense A/c"]: b.acc(n,'expense')
b.acc("Gollak Donation Income A/c",'income'); b.acc("Sponsor Donation Income A/c",'income')
V=[("T-001","05 Apr 2026","Gollak counted and deposited in cash box","Gollak Cash A/c","Gollak Donation Income A/c",62000),
("T-002","08 Apr 2026","Sponsor donation received by bank transfer","Trust SBI A/c","Sponsor Donation Income A/c",100000),
("T-003","10 Apr 2026","Advance handed to Amritpal Singh for langar purchases","Advance – Amritpal Singh A/c","Gollak Cash A/c",25000),
("T-004","14 Apr 2026","Amritpal Singh submitted vegetable and atta bills","Langar Expense A/c","Advance – Amritpal Singh A/c",14500),
("T-005","16 Apr 2026","LPG cylinders for langar kitchen paid by bank","Langar Expense A/c","Trust SBI A/c",9600),
("T-006","20 Apr 2026","Amritpal Singh returned unspent cash","Gollak Cash A/c","Advance – Amritpal Singh A/c",10500),
("T-007","25 Apr 2026","Granthi monthly honorarium","Granthi Honorarium A/c","Trust SBI A/c",22000),
("T-008","30 Apr 2026","Gurudwara electricity bill","Electricity Expense A/c","Trust SBI A/c",8400),
("T-009","05 May 2026","Gollak counted and deposited in cash box","Gollak Cash A/c","Gollak Donation Income A/c",58000),
("T-010","10 May 2026","Cash deposited into trust bank account","Trust SBI A/c","Gollak Cash A/c",80000),
("T-011","15 May 2026","Advance handed to Amritpal Singh for langar purchases","Advance – Amritpal Singh A/c","Gollak Cash A/c",30000),
("T-012","19 May 2026","Amritpal Singh submitted grocery bills","Langar Expense A/c","Advance – Amritpal Singh A/c",21300),
("T-013","25 May 2026","Granthi monthly honorarium","Granthi Honorarium A/c","Trust SBI A/c",22000),
("T-014","28 May 2026","Sound system repair and mic replacement","Sound & Media Expense A/c","Trust SBI A/c",16500),
("T-015","03 Jun 2026","Gollak counted and deposited in cash box","Gollak Cash A/c","Gollak Donation Income A/c",71000),
("T-016","09 Jun 2026","Sponsor donation for building work","Trust SBI A/c","Sponsor Donation Income A/c",150000),
("T-017","14 Jun 2026","Hall roof waterproofing work paid","Building Repair Expense A/c","Trust SBI A/c",95000),
("T-018","20 Jun 2026","Langar ration purchased in cash","Langar Expense A/c","Gollak Cash A/c",18700),
("T-019","25 Jun 2026","Granthi monthly honorarium","Granthi Honorarium A/c","Trust SBI A/c",22000),
("T-020","30 Jun 2026","Gurudwara electricity bill","Electricity Expense A/c","Trust SBI A/c",9100),
("T-021","06 Jul 2026","Gollak counted and deposited in cash box","Gollak Cash A/c","Gollak Donation Income A/c",64000),
("T-022","12 Jul 2026","Advance handed to Amritpal Singh for langar purchases","Advance – Amritpal Singh A/c","Gollak Cash A/c",20000),
("T-023","17 Jul 2026","Amritpal Singh submitted langar bills","Langar Expense A/c","Advance – Amritpal Singh A/c",16800),
("T-024","25 Jul 2026","Granthi monthly honorarium","Granthi Honorarium A/c","Trust SBI A/c",22000),
("T-025","04 Aug 2026","Gollak counted and deposited in cash box","Gollak Cash A/c","Gollak Donation Income A/c",69000),
("T-026","11 Aug 2026","Cash deposited into trust bank account","Trust SBI A/c","Gollak Cash A/c",60000),
("T-027","18 Aug 2026","Langar ration purchased in cash","Langar Expense A/c","Gollak Cash A/c",22400),
("T-028","25 Aug 2026","Granthi monthly honorarium","Granthi Honorarium A/c","Trust SBI A/c",22000)]
for x in V: b.v(*x)
BOOKS.append(("trust-singh-sabha-gurudwara", b))

os.makedirs("/home/claude/gen/out", exist_ok=True)
for slug, bk in BOOKS:
    txt, tot = bk.build().md()
    open(f"/home/claude/gen/out/{slug}.md","w",encoding="utf-8").write(txt)
    print(f"OK {slug}: {len(bk.vouchers)} vouchers, TB = {inr(tot)}, accounts = {len(bk.accounts)}")
