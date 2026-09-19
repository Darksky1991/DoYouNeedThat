# Recipient Upgrade Filters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make whisper failures recoverable, preserve row order on removal, and filter loot that is demonstrably an item-level or upgrade-track improvement for its looter.

**Architecture:** Keep the existing immediate-row and priority-inspect flow. Add pure comparison helpers in `Core.lua`, then re-evaluate visible rows when inspect data arrives; uncertain data fails open. Centralize removal so user deletion and automatic filtering share order-preserving cleanup.

**Tech Stack:** World of Warcraft Lua API, Lua 5.1-compatible code, local Lua runtime test harness.

**Spec:** `docs/superpowers/specs/2026-09-19-recipient-upgrade-filters-design.md`

## Global Constraints

- Both new filters default to disabled.
- Comparisons are strict greater-than comparisons.
- Missing equipment or track information keeps the row visible.
- Ring and trinket comparisons use the lower metric.
- A two-hand drop against main/off-hand must exceed both items.
- A one-hand/off-hand drop against an equipped two-hand is not automatically filtered.

---

### Task 1: Recoverable whisper and stable removal

**Files:**
- Modify: `tests/run.lua`
- Modify: `Core.lua`
- Modify: `Frame.lua`
- Modify: `Locales/enUS.lua`
- Modify: `Locales/zhCN.lua`

**Interfaces:**
- Produces: `AddOn:SendWhisper(itemLink, looter) -> boolean`
- Produces: `AddOn:HandleWhisperClick(entry) -> boolean`
- Produces: `AddOn:RemoveEntry(entry)`
- Changes: `AddOn:repositionFrames(sortEntries)` where `false` preserves current order.

- [x] **Step 1: Write failing tests**

Add tests which prove chat lockdown and thrown send errors return false, print a message, and leave the button visible. Add a removal test with equal-level rows that asserts surviving entries retain their relative order.

- [x] **Step 2: Verify red**

Run: `lua tests/run.lua`

Expected: failures for missing return-aware whisper handling and `RemoveEntry`.

- [x] **Step 3: Implement minimal behavior**

Check `C_ChatInfo.InChatMessagingLockdown`, call the send API through `pcall`, return a boolean, and hide the button only on success. Add `RemoveEntry`; make delete call it; allow `repositionFrames(false)` to skip sorting and clear anchors before layout.

- [x] **Step 4: Verify green**

Run: `lua tests/run.lua`

Expected: all whisper and removal tests pass.

### Task 2: Upgrade-track and weapon-aware comparison engine

**Files:**
- Modify: `tests/run.lua`
- Modify: `Core.lua`

**Interfaces:**
- Produces: `AddOn:GetUpgradeTrackRank(itemLink) -> number|nil`
- Produces: `AddOn:ShouldIgnoreLootForRecipient(itemLink, equipLoc, raidMember) -> boolean`

- [x] **Step 1: Write failing table-driven tests**

Cover strict equality, lower ring/trinket baseline, generic one-hand against the weaker weapon, main/off-hand-only targeting, two-hand against the stronger of two hands, two-hand against two-hand, and the undecidable one-hand-against-two-hand direction. Exercise item level and track independently with literal expected booleans.

- [x] **Step 2: Verify red**

Run: `lua tests/run.lua`

Expected: failure because the comparison interfaces do not exist.

- [x] **Step 3: Implement tooltip track parsing and slot policy**

Read `C_TooltipInfo.GetHyperlink(itemLink).lines`, normalize known English/zhCN aliases, select comparable equipped links by equip location, reduce their metric with `min` or `max`, and return true only for a proven enabled condition.

- [x] **Step 4: Verify green**

Run: `lua tests/run.lua`

Expected: all comparison cases pass.

### Task 3: Integrate filtering with inspect refresh and options

**Files:**
- Modify: `tests/run.lua`
- Modify: `Core.lua`
- Modify: `Frame.lua`
- Modify: `Locales/enUS.lua`
- Modify: `Locales/zhCN.lua`

**Interfaces:**
- Consumes: `ShouldIgnoreLootForRecipient`, `RemoveEntry`.
- Produces saved config keys `ignoreLooterItemLevelUpgrades` and `ignoreLooterTrackUpgrades`.

- [x] **Step 1: Write failing integration tests**

Prove a cached recipient upgrade prevents row creation, an initially unknown row is removed after `RefreshEntriesForGUID`, and automatic removal preserves other row order.

- [x] **Step 2: Verify red**

Run: `lua tests/run.lua`

Expected: rows are still always created/refreshed.

- [x] **Step 3: Implement integration and settings UI**

Initialize both keys to false for fresh and migrated databases. Evaluate cached data before populating an entry, re-evaluate on inspect refresh, and add two localized checkboxes to the options panel.

- [x] **Step 4: Verify green**

Run: `lua tests/run.lua`

Expected: all tests pass.

### Task 4: Full verification

**Files:**
- Verify: all `*.lua`

- [x] **Step 1: Run regression suite**

Run: `lua tests/run.lua`

Expected: zero failures.

- [x] **Step 2: Syntax-check addon files**

Run PowerShell to invoke `luac -p` once per repository Lua file.

Expected: every file exits successfully with no syntax output.

- [x] **Step 3: Review diff and whitespace**

Run: `git diff --check`

Expected: no whitespace errors. Inspect `git diff` to ensure prior scanner and dedupe changes remain intact.
