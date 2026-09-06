# testing/goldens — export and report byte-goldens (suite F3)

Created at M2 (CLAUDE.md § Layout; ADR 2026-09-05i §7–§8). Empty until exports exist (M5 day-book, M12 report suite).

- Byte comparison of generated PDF / XLSX / CSV against approved goldens, **locale-pinned**, plus Indian digit
  grouping and amount-in-words in EN / PA / HI (09 §2 F3). Runs in the **RC** lane.
- A golden changes only with a doc change that explains why; the diff is reviewed as a rendering decision,
  never regenerated blindly.
- Synthetic content only (see `../fixtures/README.md`).
