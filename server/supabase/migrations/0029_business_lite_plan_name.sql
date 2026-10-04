-- 0029 — the `shop` plan is displayed as **Business Lite** (ADR 2026-10-04c §3 🔒, owner 4 Oct 2026).
-- ⟦tests: E-04c-1⟧ — tests/rls/plan_catalogue.test.ts (database, PgStore on rf_api) and
-- functions/_tests/plan_catalogue.test.ts (MemStore seed + GET /sync-meta/plans).
--
-- The Business ladder now reads Business Lite · Business · Business+, the shape of Family Lite ·
-- Family · Family+. This amends ADR 2026-09-25 §5's DISPLAY NAME only. The id `shop` is what
-- subscriptions.plan, every entitlement token and billing carry, so it stays; entity type, step,
-- limits, prices, extras and `popular` stay 0018's.
--
-- Migrations are append-only: 0018's seed is not edited, it is amended here. store_mem.ts's
-- CATALOGUE_SEED changes in the same commit, so E-25-3's drift check keeps the two one catalogue.
-- rf.plan_catalogue_guard (0018) forbids renaming `free` and moving any id; a rename of `shop` is
-- neither. plan_catalogue_touch (0018) moves the row's updated_at, so GET /sync-meta/plans'
-- catalogue_updated_at moves and a client re-reads the names.
--
-- CLAUDE.md rule 2: nothing here touches `envelopes`; no table, column, policy or grant changes.

do $$
begin
  update plan_catalogue set name = 'Business Lite' where id = 'shop';
  -- 0018 seeds `shop` on every database; a catalogue without it is not one this file may guess about.
  if not found then
    raise exception '0029: plan_catalogue has no row `shop` to rename';
  end if;
end $$;
