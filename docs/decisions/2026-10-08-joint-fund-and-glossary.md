# ADR 2026-10-08 — *Joint fund* replaces *pool*; the 8 Oct ਪੰਜਾਬੀ / हिन्दी glossary rulings

On 8 Oct 2026 the design session drafted the held-English frames and swept every canvas. Along the way the owner
ruled on wording in the design project (recorded in its `TRANSLATION-PENDING.md`, 8 Oct sections). Several of those
rulings contradict owner-locked lines here: 01 §1 rule 8 and the §2 term table, and the 07 §13 quote *"Joint pool not
started"*. The app's ARB strings still carry the old wording (`books.type.joint` *"Shared pool"*, the S0.6d–f
onboarding strings, HI *साझा पूल*).

**Owner confirmed, 8 Oct 2026** (in this repo, after `/design-pull` listed each conflict): adopt *joint fund*
everywhere it is user-facing, and adopt every glossary ruling below under this one ADR.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. *Joint fund* is the user-facing name of a family's common book 🔒 ⟦tests: F1-1008-1 @M13⟧
- English: **joint fund** (title case *Joint fund*), never *pool* or *joint pool*. PA **ਸਾਂਝਾ ਫ਼ੰਡ** (oblique ਸਾਂਝੇ ਫ਼ੰਡ),
  HI **साझा फ़ंड** (oblique साझे फ़ंड). ਪੂੰਜੀ / पूँजी now means only *Capital*.
- The live canvas copy: S0.6d *"This is the joint fund everyone shares."*; S0.6f *"What is in the joint fund?"*,
  *What the joint fund has* · *Who owes the joint fund* · *What the joint fund owes*; S10.1 *"Close the joint fund
  anyway"*, *"Joint fund — not started"*; S8.2 / D5 *Joint fund ↔ …*.
- The engine is unchanged. 02's *pool* wording (`BookType.joint`, 02 §6/§7) is internal and stays. Rule 9 of
  CLAUDE.md applies: the display word never bends the engine.

### 2. Term-table rulings 🔒 ⟦tests: F1-1008-2 @M13⟧
| English | ਪੰਜਾਬੀ | हिन्दी | was |
|---|---|---|---|
| Cash in hand | ਹੱਥ ਵਿੱਚ ਰੋਕੜ | हाथ में रोकड़ | ਰੋਕੜ / रोकड़ |
| You will get | ਤੁਸੀਂ ਲੈਣੇ ਹਨ | आपने लेने हैं | ਲੈਣੇ ਹਨ / लेने हैं |
| You will give | ਤੁਸੀਂ ਦੇਣੇ ਹਨ | आपने देने हैं | ਦੇਣੇ ਹਨ / देने हैं |
| Advance out | ਐਡਵਾਂਸ ਦਿੱਤਾ | एडवांस दिया | ਐਡਵਾਂਸ / एडवांस |
| Save | ਸੇਵ ਕਰੋ (unchanged) | सुरक्षित करें | सेव करें |
| Sub-family (household) | ਪਰਿਵਾਰ | कुनबा (unchanged) | ਟੱਬਰ / कुनबा |

- *Rokad* replaces ਨਗਦ / नगद for cash in hand. *आपने लेने हैं* is the owner's choice over the standard *आपको लेने हैं*.
  *Advance* is masculine (ਦਿੱਤਾ / दिया).
- *You will get, by age* → ਤੁਸੀਂ ਲੈਣੇ ਹਨ, ਉਮਰ ਅਨੁਸਾਰ / आपने लेने हैं, उम्र के अनुसार. *Cash in hand and bank balances* is
  unchanged.
- A sub-family is ਰਾਹੁਲ ਦਾ ਪਰਿਵਾਰ, the same word as the whole family (ਸੰਧੂ ਪਰਿਵਾਰ). The household/family distinction
  is carried by context alone.

### 3. Unlock-method names are four separate terms 🔒 ⟦tests: F1-1008-3 @M13⟧
The app names the method the phone actually uses. These are not translations of one another.

| Method | English | ਪੰਜਾਬੀ | हिन्दी |
|---|---|---|---|
| iPhone face | Face ID | ਫੇਸ ਆਈਡੀ | फ़ेस आईडी |
| iPhone fingerprint | Touch ID | ਟੱਚ ਆਈਡੀ | टच आईडी |
| Android fingerprint | Fingerprint | ਫ਼ਿੰਗਰਪ੍ਰਿੰਟ | फ़िंगरप्रिंट |
| Android face | Face unlock | ਫੇਸ ਅਨਲਾਕ | फ़ेस अनलॉक |

- HI *Face ID* gains the nukta (फ़ेस, was फेस). No *"(Face ID)"* gloss after the transliteration.
- This settles PLAN desk 166: an Android fingerprint phone is never told *Face ID*. The canvases draw an Android twin
  for every platform screen (c3 S15/S15.2/R4/S19.1, c10 S12.3/S17.2, c15 S8/S8.2, c1 O4b/O5/S15.3/R2.5, c11 O4b/O5).

### 4. Platform nouns on Android; store names transliterated 🔒 ⟦tests: F3-01-3 @M12⟧
- Android swaps, applied wherever the iPhone screen names Apple: iCloud Keychain → **Google Password Manager**,
  iCloud Drive → **Google Drive**, App Store → **Play Store**, Apple account → **Google account**, iPhone → **Android
  phone** (Android ਫ਼ੋਨ / Android फ़ोन), *Cancel in Apple settings* → *Cancel in Google Play*. The Android share sheet
  says *Save to device* (Downloads or Google Drive) and *Any Mopria or Wi-Fi printer*. All of these stay Latin under
  01 §1 rule 8.
- **Exception to rule 8:** *App Store* → **ਐਪ ਸਟੋਰ / ऐप स्टोर** and *Play Store* → **ਪਲੇ ਸਟੋਰ / प्ले स्टोर** are
  transliterated in PA/HI UI text.

## Consequences
- Docs (this commit): 01 §1 rule 8 and the §2 tables gain the rulings and a cross-reference line; 07 §13's owner-locked
  S10.1 line quotes *Joint fund not started*; DESIGN-PACK S10.1, O6 and §D say *joint fund*.
- Code (not in this commit): ARB EN/PA/HI. `books.type.joint`, `onboarding.family.*` (S0.6d–f), the S10.1 status, every
  *Cash in hand* / *You will get* / *You will give* / *Advance out* key, HI *Save*, and the biometric labels by
  platform. This is a `lane-mech` transcription. `lane-ui` writes the F1-1008-1…3 tests that assert them, because
  lane-mech never authors tests. Biometric-by-platform wording also touches S15, S15.2 and S0.8 widgets (desk 166).
- Design match: S0.8, S15 and S15.3 records are stale (their frames are now iPhone/Android pairs).

## Open ⚠️
- Native-speaker pass: every PA/HI string above except the owner-given rows is still a machine draft (01 §4.1).
