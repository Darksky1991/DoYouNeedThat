# Recipient Upgrade Filters and Row Actions Design

## Goals

- Keep the whisper button visible when chat messaging is restricted or the send API raises an error.
- Removing a row must preserve the relative order of every remaining row.
- Add independent item-level and upgrade-track filters that suppress loot which is demonstrably an upgrade for the looter.
- Fail open when inspected equipment or tooltip track data is incomplete so useful loot is never silently lost.

## Whisper behavior

`SendWhisper` returns a boolean. It checks `C_ChatInfo.InChatMessagingLockdown()` before sending and wraps `C_ChatInfo.SendChatMessage` in `pcall`. A restricted or failed send prints a localized message and returns `false`; only a successful call returns `true`. The row click handler hides the button only after `true`.

## Stable row removal

Row removal is centralized in `RemoveEntry`. It clears the row identity, hides the frame, and lays out active rows without sorting. New rows retain the existing item-level sort behavior. Re-anchoring clears old points first.

## Recipient filters

Two saved settings default to disabled:

- `ignoreLooterItemLevelUpgrades`
- `ignoreLooterTrackUpgrades`

An enabled condition suppresses a row only when the dropped metric is strictly greater than the selected equipped baseline. If both settings are enabled, either proven condition is sufficient. Missing equipment, uncached item information, or an unrecognized track is undecidable and therefore keeps the row.

Rows are created immediately when the equipment comparison is undecidable. The existing priority inspect is queued. When inspect data arrives, the row is refreshed and removed without reordering if the comparison now proves it should be ignored.

Inventory-change invalidations clear both the scanner cache and Core's recipient mirror before a replacement scan is queued. Expired cache/mirror entries are also excluded from pre-filtering, so stale equipment can never silently suppress a new row.

Upgrade tracks are read from `C_TooltipInfo.GetHyperlink` tooltip lines. Known aliases are normalized to this order:

`Explorer < Adventurer < Veteran < Champion < Hero < Myth`

English and Simplified Chinese aliases are supported. Same-track rank differences such as Hero 1/6 versus Hero 6/6 are intentionally left to the item-level filter.

## Slot policy

| Dropped type | Current equipment | Baseline |
|---|---|---|
| Ring or trinket | Two slots | Lower known metric |
| Generic one-hand | Two weapon-capable one-hands | Lower known metric |
| Main-hand-only | One-hand setup | Main hand |
| Off-hand/shield/holdable | One-hand setup | Off hand |
| Two-hand | Current two-hand | Main hand |
| Two-hand | Main hand plus off hand | Higher metric; the drop must exceed both replaced items |
| Two-hand | Proven main-hand-only setup | Main hand |
| One-hand or off-hand | Current two-hand | Undecidable; keep row |

For a generic one-hand drop, an equipped shield or holdable is not treated as an interchangeable weapon slot. Empty and missing slots are not assigned a synthetic zero because remote inspection cannot reliably distinguish an empty slot from incomplete data; when that distinction cannot be proven, the row is kept.

## Validation

The Lua test harness covers chat lockdown/errors, row-order preservation, strict comparison boundaries, rings/trinkets, generic one-hand, main/off-hand-only, and both two-hand conversion directions. All addon Lua files are syntax-checked with the installed Lua runtime.
