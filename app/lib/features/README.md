# `app/lib/features/` — one folder per feature, one lane per folder

The shell (`app/lib/shared/`) owns theme, router, tokens, seams and the tab bar.
Everything a user sees lives here, one folder per feature, built by one lane at a time.

## Layout

```
app/lib/features/<feature>/
  <feature>_routes.dart      exports `final List<RouteBase> <feature>Routes`
  screens/                   one file per S-id (13 §3.2), e.g. s1_home_screen.dart
  widgets/                   widgets private to this feature
app/test/features/<feature>/ widget tests, one per screen minimum
app/lib/l10n/parts/<feature>_{en,pa,hi}.arb   the feature's strings — ALL THREE
```

## Routes

- `<feature>_routes.dart` exports `final List<RouteBase> <feature>Routes` (top-level routes
  mounted on the **root** navigator — they cover the tab bar, as entry and detail screens do).
- A feature that owns a **tab root** (Home S1, Ledger S3, Inbox S6, Menu S8) also exports an
  `RkTabRoot` (`shared/router.dart`) — `builder` for the root screen, `routes` for screens that
  stay *inside* the shell with the bar visible. The entry screen (S2) exports a `WidgetBuilder`.
- Integration (`main.dart`) composes them:
  `buildRouter(featureRoutes: [...homeRoutes, ...ledgerRoutes], home: homeRoot, entry: entryBuilder)`.
- Paths come from `RkPaths` — never re-type `/home`. Nothing deeper than two levels from a
  bottom-bar root (13 §3.1). No hamburger, no nested tabs.

## Strings

- Only in `app/lib/l10n/parts/<feature>_{en,pa,hi}.arb`, dotted keys `screen.element.state`
  (01 §1 rule 9), EN + PA + HI in the same commit, `@key` descriptions in EN.
- Compile: `dart run scripts/gen_l10n_arb.dart && (cd app && flutter gen-l10n)`; the script merges
  parts into `app_*.arb` (generated — never edit) and writes the identifier-keyed copies gen_l10n
  reads. `home.money_in.label` → `l10n.homeMoneyInLabel`.
- Forbidden jargon on user surfaces (01 §1.3): journal, voucher, contra, accrual, folio, narration.
  Consumer surfaces say *Money in / Money out*; professional surfaces say Dr/Cr (02 §10).

## Colour, type, space

- Tokens only: `Theme.of(context)` (ColorScheme, TextTheme from the RkType scale),
  `RkStatusColors.of(context)` for credit/debit/pending/locked/…, `RkSpace`/`RkRadius`/`RkMotion`
  from `shared/tokens.dart`. A hex literal in a widget is review-blocking (purity check).
- credit/debit colour **numerals only**, with sign and column (07 §1 rule 3). Amounts are integer
  paise, tabular figures (`RkType.tabular`), ₹ Indian grouping.
- Every interactive component: default · pressed · disabled-with-reason · loading · error. Every
  list: populated · empty (one next action) · error-with-retry · offline (13 §4.3). No dead ends.

## Dependencies

- `RkScope.of(context)` → `db` (LedgerDatabase), `sync` (SyncClient), `auth` (AuthClient),
  `now()` (injected clock — never `DateTime.now()` in a widget). Fakes live in `shared/seams/`.
- Sync status is the sealed `SyncStatus` — exactly the five 05 §9 states. Do not add a sixth.

## Tests

- `app/test/features/<feature>/<screen>_test.dart`; pump with
  `pumpRk(tester, widget, {locale, sync, auth})` from `app/test/shared/test_app.dart` — real theme,
  real strings, in-memory ledger, swappable fakes.
- Ids: `F1-<source>-<n>` where `<source>` is the owning spec (`F1-07-…` for 07 flows,
  `F1-13-…` for 13 architecture); every test name starts with its id. Mint upward from the last
  id in that file; check `dart run scripts/check_coverage.dart` for collisions.
- Run by file while working; the package once at the end; never `scripts/ci.sh` (the gate does).
