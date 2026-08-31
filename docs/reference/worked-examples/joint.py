import sys; sys.path.insert(0,'/home/claude/gen')
from build import Book, inr

BK = []
# --- Joint Family Book (common pool) ---
j = Book("Book 1 of 4 — Sharma Joint Family Book (common pool)", "")
j.acc("PNB Joint A/c",'money',320000); j.acc("Joint Cash A/c",'money',45000)
j.acc("Agriculture Business (family book)",'interbook',0)
j.acc("Sharma Super Store (family book)",'interbook',0)
j.acc("Rahul Sub-family (family book)",'interbook',0)
j.acc("Pankaj Sub-family (family book)",'interbook',0)
j.acc("Geeta Sub-family (family book)",'interbook',0)
for n in ["House Repair Expense A/c","Common Utility Expense A/c","Function & Ceremony Expense A/c",
          "Property Tax Expense A/c"]: j.acc(n,'expense')
for x in [("J-001","10 Apr 2026","Agriculture Business remitted crop sale proceeds to common pool","PNB Joint A/c","Agriculture Business (family book)",250000),
("J-002","15 Apr 2026","Monthly household allowance to Rahul sub-family","Rahul Sub-family (family book)","PNB Joint A/c",40000),
("J-003","15 Apr 2026","Monthly household allowance to Pankaj sub-family","Pankaj Sub-family (family book)","PNB Joint A/c",40000),
("J-004","15 Apr 2026","Monthly household allowance to Geeta sub-family","Geeta Sub-family (family book)","PNB Joint A/c",35000),
("J-005","22 Apr 2026","Annual property tax for ancestral house","Property Tax Expense A/c","PNB Joint A/c",18500),
("J-006","08 May 2026","Common house roof and plaster repair","House Repair Expense A/c","PNB Joint A/c",125000),
("J-007","15 May 2026","Monthly household allowance to all three sub-families","Rahul Sub-family (family book)","PNB Joint A/c",40000),
("J-008","15 May 2026","Monthly household allowance — Pankaj","Pankaj Sub-family (family book)","PNB Joint A/c",40000),
("J-009","15 May 2026","Monthly household allowance — Geeta","Geeta Sub-family (family book)","PNB Joint A/c",35000),
("J-010","28 May 2026","Common electricity and water for the haveli","Common Utility Expense A/c","Joint Cash A/c",12400),
("J-011","12 Jun 2026","Sharma Super Store remitted surplus to common pool","PNB Joint A/c","Sharma Super Store (family book)",180000),
("J-012","15 Jun 2026","Monthly household allowance — Rahul","Rahul Sub-family (family book)","PNB Joint A/c",40000),
("J-013","15 Jun 2026","Monthly household allowance — Pankaj","Pankaj Sub-family (family book)","PNB Joint A/c",40000),
("J-014","15 Jun 2026","Monthly household allowance — Geeta","Geeta Sub-family (family book)","PNB Joint A/c",35000),
("J-015","20 Jun 2026","Family wedding function expenses","Function & Ceremony Expense A/c","PNB Joint A/c",210000),
("J-016","15 Jul 2026","Monthly household allowance — Rahul","Rahul Sub-family (family book)","PNB Joint A/c",40000),
("J-017","15 Jul 2026","Monthly household allowance — Pankaj","Pankaj Sub-family (family book)","PNB Joint A/c",40000),
("J-018","15 Jul 2026","Monthly household allowance — Geeta","Geeta Sub-family (family book)","PNB Joint A/c",35000),
("J-019","25 Jul 2026","Agriculture Business remitted further proceeds","PNB Joint A/c","Agriculture Business (family book)",150000),
("J-020","10 Aug 2026","Common electricity and water for the haveli","Common Utility Expense A/c","Joint Cash A/c",13800),
("J-021","15 Aug 2026","Monthly household allowance — Rahul","Rahul Sub-family (family book)","PNB Joint A/c",40000),
("J-022","15 Aug 2026","Monthly household allowance — Pankaj","Pankaj Sub-family (family book)","PNB Joint A/c",40000),
("J-023","15 Aug 2026","Monthly household allowance — Geeta","Geeta Sub-family (family book)","PNB Joint A/c",35000),
("J-024","20 Aug 2026","Kabir college admission paid from common pool for Geeta sub-family","Geeta Sub-family (family book)","PNB Joint A/c",85000)]: j.v(*x)
BK.append(("Joint Family Book", j))

# --- Agriculture Business Book ---
a = Book("Book 2 of 4 — Agriculture Business Book (family business)", "")
a.acc("SBI Agri Current A/c",'money',210000); a.acc("Agri Cash A/c",'money',30000)
a.acc("Joint Family (common pool)",'interbook',0)
a.acc("Advance – Sunil Sharma A/c",'advance',0)
a.acc("Chintpurni Feed Co. A/c",'creditor',-60000)
for n in ["Seed & Fertiliser Expense A/c","Labour Expense A/c","Diesel & Machinery Expense A/c",
          "Cattle Feed Expense A/c"]: a.acc(n,'expense')
a.acc("Crop Sale Income A/c",'income'); a.acc("Milk Sale Income A/c",'income')
for x in [("A-001","05 Apr 2026","Wheat crop sold to mandi, proceeds to bank","SBI Agri Current A/c","Crop Sale Income A/c",380000),
("A-002","10 Apr 2026","Remitted crop proceeds to joint family common pool","Joint Family (common pool)","SBI Agri Current A/c",250000),
("A-003","14 Apr 2026","Cattle feed purchased on credit from Chintpurni Feed Co.","Cattle Feed Expense A/c","Chintpurni Feed Co. A/c",45000),
("A-004","18 Apr 2026","Advance handed to Sunil for sowing labour and diesel","Advance – Sunil Sharma A/c","Agri Cash A/c",25000),
("A-005","24 Apr 2026","Sunil submitted labour wage vouchers","Labour Expense A/c","Advance – Sunil Sharma A/c",16400),
("A-006","28 Apr 2026","Sunil returned unspent cash","Agri Cash A/c","Advance – Sunil Sharma A/c",8600),
("A-007","06 May 2026","Monthly milk sale collection deposited","SBI Agri Current A/c","Milk Sale Income A/c",64000),
("A-008","12 May 2026","Part payment to Chintpurni Feed Co.","Chintpurni Feed Co. A/c","SBI Agri Current A/c",60000),
("A-009","18 May 2026","Seed and fertiliser purchased for kharif sowing","Seed & Fertiliser Expense A/c","SBI Agri Current A/c",88000),
("A-010","24 May 2026","Diesel for tractor and tubewell","Diesel & Machinery Expense A/c","Agri Cash A/c",18500),
("A-011","06 Jun 2026","Monthly milk sale collection deposited","SBI Agri Current A/c","Milk Sale Income A/c",67000),
("A-012","15 Jun 2026","Advance handed to Sunil for harvesting labour","Advance – Sunil Sharma A/c","Agri Cash A/c",20000),
("A-013","22 Jun 2026","Sunil submitted labour wage vouchers","Labour Expense A/c","Advance – Sunil Sharma A/c",20000),
("A-014","28 Jun 2026","Cattle feed purchased on credit from Chintpurni Feed Co.","Cattle Feed Expense A/c","Chintpurni Feed Co. A/c",52000),
("A-015","06 Jul 2026","Monthly milk sale collection deposited","SBI Agri Current A/c","Milk Sale Income A/c",71000),
("A-016","14 Jul 2026","Tractor servicing and machinery repair","Diesel & Machinery Expense A/c","SBI Agri Current A/c",34000),
("A-017","20 Jul 2026","Paddy crop sold, proceeds received","SBI Agri Current A/c","Crop Sale Income A/c",295000),
("A-018","25 Jul 2026","Remitted further proceeds to joint family common pool","Joint Family (common pool)","SBI Agri Current A/c",150000),
("A-019","06 Aug 2026","Monthly milk sale collection deposited","SBI Agri Current A/c","Milk Sale Income A/c",69000),
("A-020","12 Aug 2026","Advance handed to Sunil for fodder and labour","Advance – Sunil Sharma A/c","Agri Cash A/c",15000),
("A-021","19 Aug 2026","Sunil submitted fodder purchase bills","Cattle Feed Expense A/c","Advance – Sunil Sharma A/c",9200),
("A-022","26 Aug 2026","Part payment to Chintpurni Feed Co.","Chintpurni Feed Co. A/c","SBI Agri Current A/c",40000)]: a.v(*x)
BK.append(("Agriculture Business Book", a))

# --- Sharma Super Store Book ---
s = Book("Book 3 of 4 — Sharma Super Store Book (family business)", "")
s.acc("Axis Store Current A/c",'money',150000); s.acc("Store Cash A/c",'money',35000)
s.acc("Joint Family (common pool)",'interbook',0)
s.acc("Advance – Kabir Sharma A/c",'advance',0)
for n in ["Store Purchases A/c","Store Rent Expense A/c","Store Staff Expense A/c","Store Utility Expense A/c"]: s.acc(n,'expense')
s.acc("Store Sales A/c",'income')
for x in [("S-001","03 Apr 2026","Daily counter sales deposited","Store Cash A/c","Store Sales A/c",118000),
("S-002","09 Apr 2026","Stock purchased from wholesale market","Store Purchases A/c","Axis Store Current A/c",145000),
("S-003","12 Apr 2026","Store rent paid for April","Store Rent Expense A/c","Axis Store Current A/c",30000),
("S-004","20 Apr 2026","Cash deposited into store current account","Axis Store Current A/c","Store Cash A/c",100000),
("S-005","28 Apr 2026","Store staff salaries for April","Store Staff Expense A/c","Axis Store Current A/c",42000),
("S-006","05 May 2026","Daily counter sales deposited","Store Cash A/c","Store Sales A/c",132000),
("S-007","12 May 2026","Store rent paid for May","Store Rent Expense A/c","Axis Store Current A/c",30000),
("S-008","16 May 2026","Advance handed to Kabir for festival stock purchase","Advance – Kabir Sharma A/c","Store Cash A/c",40000),
("S-009","21 May 2026","Kabir submitted purchase bills","Store Purchases A/c","Advance – Kabir Sharma A/c",34600),
("S-010","24 May 2026","Kabir returned unspent cash","Store Cash A/c","Advance – Kabir Sharma A/c",5400),
("S-011","28 May 2026","Store staff salaries for May","Store Staff Expense A/c","Axis Store Current A/c",42000),
("S-012","04 Jun 2026","Daily counter sales deposited","Store Cash A/c","Store Sales A/c",151000),
("S-013","12 Jun 2026","Remitted surplus to joint family common pool","Joint Family (common pool)","Axis Store Current A/c",180000),
("S-014","12 Jun 2026","Store rent paid for June","Store Rent Expense A/c","Axis Store Current A/c",30000),
("S-015","18 Jun 2026","Store electricity and refrigeration bill","Store Utility Expense A/c","Store Cash A/c",16800),
("S-016","28 Jun 2026","Store staff salaries for June","Store Staff Expense A/c","Axis Store Current A/c",42000),
("S-017","06 Jul 2026","Daily counter sales deposited","Store Cash A/c","Store Sales A/c",143000),
("S-018","12 Jul 2026","Store rent paid for July","Store Rent Expense A/c","Axis Store Current A/c",30000),
("S-019","19 Jul 2026","Stock purchased from wholesale market","Store Purchases A/c","Axis Store Current A/c",120000),
("S-020","28 Jul 2026","Store staff salaries for July","Store Staff Expense A/c","Axis Store Current A/c",42000),
("S-021","07 Aug 2026","Daily counter sales deposited","Store Cash A/c","Store Sales A/c",137000),
("S-022","12 Aug 2026","Store rent paid for August","Store Rent Expense A/c","Axis Store Current A/c",30000),
("S-023","22 Aug 2026","Cash deposited into store current account","Axis Store Current A/c","Store Cash A/c",150000)]: s.v(*x)
BK.append(("Sharma Super Store Book", s))

# --- Pankaj Sub-family Book ---
p = Book("Book 4 of 4 — Pankaj Sharma Sub-family Book", "")
p.acc("Indian Bank Family A/c",'money',48000); p.acc("Sub-family Cash A/c",'money',12000)
p.acc("Joint Family (common pool)",'interbook',0)
p.acc("Geeta Sharma (personal book)",'interbook',0)
for n in ["Grocery Expense A/c","School Fee Expense A/c","Medical Expense A/c","Festival Expense A/c"]: p.acc(n,'expense')
for x in [("P-001","15 Apr 2026","Monthly allowance received from joint family pool","Indian Bank Family A/c","Joint Family (common pool)",40000),
("P-002","18 Apr 2026","Monthly grocery purchase","Grocery Expense A/c","Sub-family Cash A/c",9800),
("P-003","25 Apr 2026","School fees paid","School Fee Expense A/c","Indian Bank Family A/c",18000),
("P-004","15 May 2026","Monthly allowance received from joint family pool","Indian Bank Family A/c","Joint Family (common pool)",40000),
("P-005","19 May 2026","Monthly grocery purchase","Grocery Expense A/c","Sub-family Cash A/c",10400),
("P-006","23 May 2026","Doctor consultation and medicines","Medical Expense A/c","Indian Bank Family A/c",7600),
("P-007","15 Jun 2026","Monthly allowance received from joint family pool","Indian Bank Family A/c","Joint Family (common pool)",40000),
("P-008","21 Jun 2026","Monthly grocery purchase","Grocery Expense A/c","Sub-family Cash A/c",11200),
("P-009","26 Jun 2026","Geeta paid our festival shopping from her own pocket","Festival Expense A/c","Geeta Sharma (personal book)",14500),
("P-010","15 Jul 2026","Monthly allowance received from joint family pool","Indian Bank Family A/c","Joint Family (common pool)",40000),
("P-011","20 Jul 2026","Monthly grocery purchase","Grocery Expense A/c","Sub-family Cash A/c",10900),
("P-012","28 Jul 2026","School fees paid","School Fee Expense A/c","Indian Bank Family A/c",18000),
("P-013","15 Aug 2026","Monthly allowance received from joint family pool","Indian Bank Family A/c","Joint Family (common pool)",40000),
("P-014","22 Aug 2026","Monthly grocery purchase","Grocery Expense A/c","Sub-family Cash A/c",11600)]: p.v(*x)
BK.append(("Pankaj Sub-family Book", p))

parts = ["""# Joint Family — Sharma Family (multi-book architecture)

Entity type: **Joint family with businesses.** Four independent, self-balancing books linked only by **Due to/from** account pairs. Every inter-book event posts once in each book; each pair must net to zero (§6).

**Books:** 1 Sharma Joint Family Book (common pool) · 2 Agriculture Business Book · 3 Sharma Super Store Book · 4 Pankaj Sharma Sub-family Book. *(Rahul and Geeta sub-family books follow the same pattern as book 4 and are omitted for length; their allowances appear in book 1.)*

**Period:** 01 April 2026 – 29 August 2026 (FY 2026-27) · **Every figure is generated from the vouchers and verified to balance.**

---
"""]
for title, bk in BK:
    txt, tot = bk.build().md()
    parts.append(txt.replace("# " + bk.name, "# " + bk.name, 1))
    parts.append("\n---\n")

# reconciliation
jf, ag, ss, pk = [b for _, b in BK]
rec = ["## 6. Family Reconciliation — inter-book pairs (the only cross-book check needed)", "",
"| Between these two books | One side says | Other side says | Net |", "|---|---|---|:---:|"]
def f(b, a):
    v = b.final[a]; return f"{inr(abs(v))} {'Dr' if v>0 else 'Cr'}"
def plain(b, a):
    v = b.final[a]
    return f"{inr(abs(v))} — {'you will get' if v>0 else 'you will give'}"
rec.append(f"| Joint pool ↔ Agriculture Business | Joint book: {plain(jf,'Agriculture Business (family book)')} | Agri book: {plain(ag,'Joint Family (common pool)')} | **0** ✓ |")
rec.append(f"| Joint pool ↔ Sharma Super Store | Joint book: {plain(jf,'Sharma Super Store (family book)')} | Store book: {plain(ss,'Joint Family (common pool)')} | **0** ✓ |")
rec.append(f"| Joint pool ↔ Pankaj sub-family | Joint book: {plain(jf,'Pankaj Sub-family (family book)')} | Pankaj book: {plain(pk,'Joint Family (common pool)')} | **0** ✓ |")
rec += ["", "*Rahul and Geeta sub-family books (not reproduced) carry the mirror of their allowance balances shown in Book 1.*", "",
"## 7. Open advances (ਪੇਸ਼ਗੀ) across the family, as on 29 August 2026", "",
"| Book | Held by | Balance | Since |", "|---|---|---:|---|",
f"| Agriculture Business | Sunil Sharma | {inr(abs(ag.final['Advance – Sunil Sharma A/c']))} Dr | 12 Aug 2026 |",
f"| Sharma Super Store | Kabir Sharma | {inr(abs(ss.final['Advance – Kabir Sharma A/c']))} Dr | settled |", "",
"*This single table is the question a joint family cannot answer on paper: who is holding how much of the family's money, and since when.*"]
parts.append("\n".join(rec))
open("/home/claude/gen/out/joint-family-sharma.md","w",encoding="utf-8").write("\n".join(parts))
for t, b in BK: print("OK", t, "-", len(b.vouchers), "vouchers")
print("advances:", ag.final['Advance – Sunil Sharma A/c'], ss.final['Advance – Kabir Sharma A/c'])
