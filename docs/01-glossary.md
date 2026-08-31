# 01 — Glossary & Strings (EN / ਪੰਜਾਬੀ / हिन्दी)

**Status:** Draft 2 (professional-terms revision per owner + `docs/reference/punjabi_accounting_terms.md`). ⚠️ **Every ਪੰਜਾਬੀ and हिन्दी string is a working draft and must be reviewed by a native speaker (ideally pilot family members) before ship.** The EN column is the string-key source of truth.

---

## 1. Language rules 🔒

1. **Three launch languages:** English (default), ਪੰਜਾਬੀ, हिन्दी. Language is a per-member setting.
2. **Register:** always respectful (ਤੁਸੀਂ / आप forms). Warm, plain, no officialese.
3. **Professional terms are used, not hidden 🔒 (revised):** Dr./Cr. — **ਨਾਮੇ / ਜਮ੍ਹਾਂ**, **नामे / जमा** — plus balance, opening/closing balance, capital, debtors/creditors appear wherever a professional expects them: A/C statements, ledgers, reports, exports. **The entry screen stays verb-based** — the user never chooses Dr/Cr; the app derives the posting and then displays it professionally. Still forbidden in UI: journal, voucher, contra, accrual, folio, narration. **Carve-out 🔒:** *folio* is forbidden **as a common noun only**. The product name **Rukka Folio** is exempt wherever it appears as the name — splash, About, store listings, invoices, export footers — and the `check_strings.dart` jargon rule must whitelist the app-name keys (`app.name`, `app.name.short`, `about.*`) rather than flagging them. Never write "the folio" to mean a ledger page.
4. **Loanwords are fine** where they're what people say: ਬੈਂਕ/बैंक, ਐਂਟਰੀ/एंट्री, ਕੋਡ/कोड, ਰਿਕਵਰੀ/रिकवरी, ਟ੍ਰਾਂਸਫਰ/ट्रांसफ़र.
5. **Digits:** Latin digits, Indian grouping (₹12,34,567) in all languages. Gurmukhi/Devanagari digits are not used.
6. **Dates:** English `DD Aug YYYY` (abbreviated months); ਪੰਜਾਬੀ/हिन्दी use **full month names** (`02 ਅਗਸਤ 2026`, `02 अगस्त 2026`) — these scripts don't abbreviate months naturally 🔒 (owner). Today/Yesterday = ਅੱਜ/ਕੱਲ੍ਹ, आज/कल.
7. **No string concatenation** — ICU MessageFormat, named placeholders, plural rules per language.
8. **User-typed content carries its own language tag 🔒** — account names, notes and party names may be in any script regardless of the UI language, so each is stored and rendered with a `lang` marker (`pa`/`hi`/`en`) for correct screen-reader pronunciation and font selection (design-system §3.1 rule 1).
9. Strings live in ARB files (`app_en.arb`, `app_pa.arb`, `app_hi.arb`); keys are `screen.element.state`; **CI fails if any key is missing in any language.**
9. **Statement layout rule 🔒:** A/C statements and ledger exports use the traditional three columns — **ਨਾਮੇ | ਜਮ੍ਹਾਂ | ਬਾਕੀ** / **नामे | जमा | बाकी** / **Dr | Cr | Balance** — with b/d and c/d rows. Day-book lists keep the in/out arrows; the Dr/Cr detail shows on the entry view.
10. **Amount-in-words** on receipts/exports in the user's language (…ਰੁਪਏ ਸਿਰਫ਼ / …रुपये मात्र). ⚠️ number-to-words functions need native review in both.

---

## 2. Core term table 🔒 (concept → internal → EN → ਪੰਜਾਬੀ → हिन्दी)

### Entry verbs (plain by design — never replaced by Dr/Cr)
| Concept | Internal | EN | ਪੰਜਾਬੀ | हिन्दी |
|---|---|---|---|---|
| Verb 1 | money_in | Money in | ਪੈਸੇ ਆਏ | पैसे आए |
| Verb 2 | money_out | Money out | ਪੈਸੇ ਗਏ | पैसे गए |
| Verb 3 | gave_credit | Gave on credit | ਉਧਾਰ ਦਿੱਤਾ | उधार दिया |
| Verb 4 | took_credit | Took on credit | ਉਧਾਰ ਲਿਆ | उधार लिया |
| Verb 5 | transfer | Transfer | ਟ੍ਰਾਂਸਫਰ | ट्रांसफ़र |
| Verb 6 | adjustment | Fix / Adjust | ਸੁਧਾਈ | सुधार |

### Books & ledger
| Concept | Internal | EN | ਪੰਜਾਬੀ | हिन्दी |
|---|---|---|---|---|
| Ledger container | book | Book | ਵਹੀ | बही |
| Account (all classes) | account | A/C | ਖਾਤਾ | खाता |
| Ledger tab / index | — | Ledger | ਖਾਤੇ | खाते |
| Day book | — | Day Book | ਰੋਜ਼ਨਾਮਚਾ | रोज़नामचा |
| Cash book | — | Cash Book | ਰੋਕੜ ਵਹੀ | रोकड़ बही |
| Entry | entry | Entry | ਐਂਟਰੀ | एंट्री |
| Books of account (collective) | — | the books | ਹਿਸਾਬ-ਕਿਤਾਬ | हिसाब-किताब |

### Professional money terms (per reference file)
| Concept | Internal | EN | ਪੰਜਾਬੀ | हिन्दी |
|---|---|---|---|---|
| Debit | line Dr | Dr. | ਨਾਮੇ | नामे |
| Credit | line Cr | Cr. | ਜਮ੍ਹਾਂ | जमा |
| Balance | — | Balance | ਬਾਕੀ | बाकी |
| Opening balance b/f | — | Opening balance | ਸ਼ੁਰੂਆਤੀ ਬਾਕੀ | शुरुआती बाकी |
| Closing balance c/f | — | Closing balance | ਅਖੀਰਲੀ ਬਾਕੀ | आख़िरी बाकी |
| Cash in hand | money(cash) | Cash in hand | ਰੋਕੜ | रोकड़ |
| Shop cash drawer | money(cash) | Galla | ਗੱਲਾ | गल्ला |
| Donation box | money(cash_collection) | Gollak | ਗੋਲਕ | गोलक |
| Count the cash | — | Count cash | ਰੋਕੜ ਗਿਣੋ | रोकड़ गिनें |
| Open and count | — | Open and count | ਖੋਲ੍ਹ ਕੇ ਗਿਣੋ | खोलकर गिनें |
| Bank balance | money(bank) | Bank balance | ਬੈਂਕ ਬਾਕੀ | बैंक बाकी |
| Debtors (receivable side) | party Dr | Debtors — You will get | ਦੇਣਦਾਰ (ਲੈਣੇ ਹਨ) | देनदार (लेने हैं) |
| Creditors (payable side) | party Cr | Creditors — You will give | ਲੈਣਦਾਰ (ਦੇਣੇ ਹਨ) | लेनदार (देने हैं) |
| Advance to a member | advance | Advance | ਪੇਸ਼ਗੀ | पेशगी |
| Money you're holding | — | Advance with you | ਤੁਹਾਡੇ ਕੋਲ ਪੇਸ਼ਗੀ | आपके पास पेशगी |
| Suspense | equity_system | Unexplained | ਅਣਪਛਾਤੀ ਰਕਮ | अज्ञात रकम |
| Capital | equity | Capital | ਪੂੰਜੀ | पूँजी |
| Drawings | equity | Drawings | ਘਰੂ ਖਾਤਾ | निजी खर्च |
| Write-off (bad debt) | adjustment | Write off | ਡੁੱਬਿਆ ਕਰਜ਼ਾ | डूबा कर्ज़ा |
| Income / Expenses | categories | Income / Expenses | ਆਮਦਨ / ਖਰਚੇ | आमदनी / खर्चे |
| Profit & Loss | report | Profit & Loss | ਨਫਾ-ਨੁਕਸਾਨ ਖਾਤਾ | नफ़ा-नुकसान खाता |
| Full position (balance sheet) | report | Full position | ਚਿੱਠਾ | चिट्ठा |
| Books-balanced check (on Home) | verification card | Books balanced | ਹਿਸਾਬ ਮਿਲਦਾ ਹੈ | हिसाब मिलता है |
| Trial Balance (report) | report | Trial Balance | ਕੱਚਾ ਚਿੱਠਾ | कच्चा चिट्ठा |
| Assets / Liabilities | report sides | Assets / Liabilities | ਸੰਪੱਤੀ / ਦੇਣਦਾਰੀਆਂ | संपत्ति / देनदारियाँ |

### Process & security
| Concept | EN | ਪੰਜਾਬੀ | हिन्दी |
|---|---|---|---|
| Waiting for approval | Waiting for approval | ਮਨਜ਼ੂਰੀ ਬਾਕੀ | मंज़ूरी बाकी |
| Approve / Reject | Approve / Reject | ਮਨਜ਼ੂਰ ਕਰੋ / ਰੱਦ ਕਰੋ | मंज़ूर करें / रद्द करें |
| Close the month | Close the month | ਮਹੀਨਾ ਬੰਦ ਕਰੋ | महीना बंद करें |
| Close the year | Close the year | ਸਾਲ ਬੰਦ ਕਰੋ | साल बंद करें |
| Late arrivals | Old entries waiting | ਪੁਰਾਣੀਆਂ ਐਂਟਰੀਆਂ ਬਾਕੀ | पुरानी एंट्रियाँ बाकी |
| In transit | In transit | ਰਸਤੇ ਵਿੱਚ | रास्ते में |
| Guardian | Trusted member | ਭਰੋਸੇਮੰਦ ਮੈਂਬਰ | भरोसेमंद सदस्य |
| Recovery sheet | Recovery sheet | ਰਿਕਵਰੀ ਪਰਚੀ | रिकवरी पर्ची |
| Show my code / Verify | Show my code / Verify | ਮੇਰਾ ਕੋਡ ਦਿਖਾਓ / ਤਸਦੀਕ ਕਰੋ | मेरा कोड दिखाएँ / तसदीक करें |
| Family match check | Family match check | ਪਰਿਵਾਰ ਮਿਲਾਨ | परिवार मिलान |
| Today / Save / Undo | Today / Save / Undo | ਅੱਜ / ਸੇਵ ਕਰੋ / ਵਾਪਸ ਲਓ | आज / सेव करें / वापस लें |

**Deliberate deviations from the reference file 🔒:** ਸ਼ਾਹੂਕਾਰ (moneylender) is avoided for creditors — loaded connotation; neutral ਲੈਣਦਾਰ is used. ਅਸਾਮੀ (debtor) is authentic bahi-khata but regional — kept as a **search synonym**, not a label. The A/C picker's search matches synonyms (ਅਸਾਮੀ→ਦੇਣਦਾਰ, ਸਰਮਾਇਆ→ਪੂੰਜੀ, ਮੀਜ਼ਾਨ→ਬਾਕੀ, बीजक→बिल) so users can type what they know.

**Advance (ਪੇਸ਼ਗੀ) vs Suspense — kept distinct on purpose:** Advance = unexplained money **with a known responsible person**, settled by that person (02 §7). Suspense = unexplained money **with no person attached** (an unmatched bank line), which must reach zero before month close (02 §10). Merging them would lose "who is answerable."

**Reserved name (brand §2):** *Rokad* is the in-product feature name for the simple cash-book view — the day-one shopkeeper mode — never used in marketing.

**"Books" alignment (brand 11 §1) 🔒:** *books* always means the books of account — the product's own Book (ਵਹੀ/बही) objects; the collective renders as ਹਿਸਾਬ-ਕਿਤਾਬ / हिसाब-किताब. The literal ਕਿਤਾਬ/किताब never appears for books of account — in-product, in copy, or in translation. Context split for *ledger*: the in-app tab stays ਖਾਤੇ/खाते (the A/C index); the concept in prose/marketing is ਖਾਤਾ-ਵਹੀ/खाता-बही.

**Surface precedence:** this document governs in-product terminology; marketing/site/deck copy follows the brand voice and localisation rules (11 §5). Brand's "financial terms stay in English" rule applies to marketing and search-facing text, not to this table.

Seeded category trees (household/shop/trust) ship in all three languages in a separate seed file, same review gate.

## 2.1 Entry preview string 🔒 (07 §5 step 5.5)
**One template, all languages** — the arrow carries the flow, so no postposition and no per-language word order:

`{amt} · {credited_account} → {debited_account} · {note}`

| Lang | Rendered |
|---|---|
| EN | ₹2,400 · Cash A/c → Diesel Expense A/c · for diesel in Isuzu car |
| PA | ₹2,400 · ਰੋਕੜ ਖਾਤਾ → ਡੀਜ਼ਲ ਖਰਚ ਖਾਤਾ · ਇਸੁਜ਼ੂ ਗੱਡੀ ਦੇ ਡੀਜ਼ਲ ਲਈ |
| HI | ₹2,400 · रोकड़ खाता → डीज़ल खर्च खाता · इसुज़ू गाड़ी के डीज़ल के लिए |

The `· {note}` clause and its separator are omitted when the narration is blank. Splits render the many side as a count: `{amt} · {n} accounts → {debited_account} · {note}` (⚠️ plural forms with the native reviewer). **This avoids the oblique-case trap** — Punjabi and Hindi inflect a noun before a postposition (ਖਾਤਾ → ਖਾਤੇ, खाता → खाते), which the app cannot reliably do to user-typed account names.

## 3. Voice & microcopy rules 🔒
Honest and unbabying: the recovery explanation says plainly *"ਤੁਹਾਡਾ ਡਾਟਾ ਇੰਨਾ ਸੁਰੱਖਿਅਤ ਹੈ ਕਿ ਅਸੀਂ ਵੀ ਨਹੀਂ ਖੋਲ੍ਹ ਸਕਦੇ"* / *"आपका डेटा इतना सुरक्षित है कि हम भी नहीं खोल सकते"*. Blocked actions state the reason and the path (07 §1.6). Success is quiet; security warnings (mismatch, recovery request, new device) are loud, red, never cute.

## 4. Open items ⚠️
1. Native review of all PA + HI strings and both number-to-words functions. 2. Seed category trees final trilingual list. 3. Synonym dictionary final set for picker search. 4. Optional **expert Dr/Cr entry mode** (raw two-line journal for pro users) — decide post-pilot; default remains verb-only entry.
