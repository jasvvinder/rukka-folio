import sys; sys.path.insert(0,'/home/claude/gen')
import build
from build import Book, inr

build.HDR['partner'] = ("Taken out / paid to them (Dr.)", "Put in / owed to them (Cr.)")
build.NATURAL['partner'] = 'Cr'

b = Book("Joint Business Book — Kaur Family Agriculture",
 "Entity type: **Jointly-owned family business (partnership).** Three sub-families own it equally (1/3 each). Each pays business costs from its own pocket; each draws money out; profit is shared by the agreed ratio regardless of who paid more. Partner Current A/cs are where the whole story lands.")
b.acc("SBI Agri Current A/c",'money',50000)
b.acc("Amrit Kaur — Partner Current A/c",'partner',0)
b.acc("Sukhdev Singh — Partner Current A/c",'partner',0)
b.acc("Harjit Kaur — Partner Current A/c",'partner',0)
for n in ["Seed & Fertiliser Expense A/c","Diesel & Machinery Expense A/c","Labour Expense A/c","Machinery Repair Expense A/c"]:
    b.acc(n,'expense')
b.acc("Crop Sale Income A/c",'income'); b.acc("Milk Sale Income A/c",'income')
b.acc("Profit Distributed A/c",'equity',0)

V=[("G-001","08 Apr 2026","Amrit Kaur paid for seed and fertiliser from her own cash","Seed & Fertiliser Expense A/c","Amrit Kaur — Partner Current A/c",180000),
("G-002","12 Apr 2026","Sukhdev Singh paid diesel and tractor fuel from his own bank","Diesel & Machinery Expense A/c","Sukhdev Singh — Partner Current A/c",95000),
("G-003","20 Apr 2026","Harjit Kaur paid sowing labour wages in cash","Labour Expense A/c","Harjit Kaur — Partner Current A/c",60000),
("G-004","06 May 2026","Tractor overhaul paid from the business bank account","Machinery Repair Expense A/c","SBI Agri Current A/c",41000),
("G-005","18 Jun 2026","Wheat crop sold at mandi, proceeds to business bank","SBI Agri Current A/c","Crop Sale Income A/c",850000),
("G-006","30 Jun 2026","Monthly milk sale collections deposited","SBI Agri Current A/c","Milk Sale Income A/c",120000),
("G-007","10 Jul 2026","Amrit Kaur withdrew money from the business for household use","Amrit Kaur — Partner Current A/c","SBI Agri Current A/c",50000)]
for x in V: b.v(*x)
b.build()

inc = -(b.final["Crop Sale Income A/c"] + b.final["Milk Sale Income A/c"])
exp = sum(b.final[a] for a in b.accounts if b.accounts[a][0]=='expense')
profit = inc - exp
share = profit // 3
print(f"Income {inr(inc)}  Expenses {inr(exp)}  Net profit {inr(profit)}  Share each {inr(share)}")

# distribution as one multi-line entry, expressed here as three paired vouchers sharing an id
for i,p in enumerate(["Amrit Kaur","Sukhdev Singh","Harjit Kaur"]):
    b.v(f"G-008","31 Jul 2026",f"Profit share for the season credited to {p} (one-third)","Profit Distributed A/c",f"{p} — Partner Current A/c",share)
b.build()
txt,tot = b.md()
open('/home/claude/gen/out/joint-business-partnership.md','w',encoding='utf-8').write(txt)
print("TB total:", inr(tot))
print("\nPartner positions:")
contrib={"Amrit Kaur":180000,"Sukhdev Singh":95000,"Harjit Kaur":60000}
draw={"Amrit Kaur":50000,"Sukhdev Singh":0,"Harjit Kaur":0}
tc=sum(contrib.values()); fair=tc//3
for p in contrib:
    net=-b.final[f"{p} — Partner Current A/c"]
    print(f"  {p:16s} put in {inr(contrib[p]):>9}  took out {inr(draw[p]):>7}  profit {inr(share)}  net owed {inr(net):>9}  vs fair share of costs: {'+' if contrib[p]-fair>0 else ''}{inr(abs(contrib[p]-fair))}")
print(f"  total contributed {inr(tc)}, equal share would be {inr(fair)} each")
print("  bank has", inr(b.final['SBI Agri Current A/c']), "· business owes partners", inr(sum(-b.final[f'{p} — Partner Current A/c'] for p in contrib)))
