# app — Rukka Folio (Flutter UI layer)

UI only. Ledger, crypto, storage and sync live in `../packages/*` (pure Dart) and are imported, never reimplemented here (CLAUDE.md § Layout).

- Screens: `docs/07-ui-flows.md` · `docs/13-ux-architecture.md` · brand `docs/11-brand-guidelines.md`
- Tokens: `lib/shared/tokens.dart` is **generated** from `design/tokens/tokens.json` — run `dart run scripts/gen_tokens.dart` from the repo root; never edit it, never write a hex literal in a widget.
- Strings: canonical dotted-key ARBs in `lib/l10n/` (EN / PA / HI, all three required); `lib/l10n/gen/` is derived and git-ignored.
- Run from the repo root: `dart pub get` · `./scripts/ci.sh` · `cd app && flutter run`
