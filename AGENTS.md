# ElkBuffBars - Codex Context

## Environment
- Game version: WoW Retail 12.0+ (Midnight).
- Language: Lua 5.1 in the WoW addon sandbox.
- Local reference checkout: `D:\Program Files\Blizzard\World of Warcraft\_retail_\Interface\wow-ui-source\`.
- External reference, when uncertain: https://github.com/JBurlison/WoWAddonAPIAgents

## Current Working Status
- This local ElkBuffBars copy has been tested in open-world training dummy combat and in a full low-level Stockade dungeon run.
- The tested version had no Lua errors in those runs.
- Player buff bars show names, icons, and durations in combat.
- Timeless buffs display as timeless bars.
- Debuffs use the same Retail `C_UnitAuras.GetAuraDataByIndex` scan path as buffs, with `HARMFUL` instead of `HELPFUL`.
- `TENCH` is separate from aura secret handling. It uses weapon enchant / inventory / tooltip fallback code, so the aura secret fixes should not be assumed to affect it.
- Known acceptable edge case: some very short combat-generated proc/passive auras, for example Paladin `Hammer of Wrath` / SpellID `1241288`, can briefly appear at the top with `0.0s`. Do not destabilize the working path just to chase this unless there is a clear, low-risk fix.
- If this version later passes Mythic+ and raid testing, use it as the source behavior for a Retail-only extraction.

## Midnight Secret Aura Rules
- Many aura fields can be secret in combat or instances: names, counts, texture/icon IDs, durations, expiration times, source units, and booleans.
- Do not compare, sort, concatenate, index tables by, or do math on secret values unless guarded by `issecretvalue` / `canaccessvalue`.
- Passing a secret texture token directly to a widget API such as `Texture:SetTexture(...)` can work. Do not require icon/texture to be readable before using it.
- For timer display, prefer Blizzard duration objects and native formatting:
  - `C_UnitAuras.GetAuraDuration(unit, auraInstanceID)`
  - `DurationObject:FormatRemainingDuration(formatter)`
  - `C_StringUtil.CreateNumericRuleFormatter()`
- Avoid `SecondsToTimeAbbrev`, modulo, `math.floor`, comparisons, or `string.format` on secret duration numbers.
- For sorting timed auras in combat, prefer Blizzard ordered aura instance IDs:
  - `C_UnitAuras.GetUnitAuraInstanceIDs(unit, filter, nil, Enum.UnitAuraSortRule.ExpirationOnly, Enum.UnitAuraSortDirection.Reverse)`
  - Do not sort secret expiration fields directly in Lua.

## What Not To Reintroduce
- Do not read or hook Blizzard `BuffFrame` / `DebuffFrame` aura buttons as a fallback for icons or timers.
- Do not keep Blizzard buff frames shown but transparent to harvest their duration text.
- That approach caused taint and secret comparison errors inside `Blizzard_BuffFrame/BuffFrame.lua`.
- Do not import `AbstractFramework` as an icon/timer fix. In the EBBMidnight fork, AbstractFramework only patched UTF-8 string handling for secret names.
- Do not use name-based `C_Spell.GetSpellTexture(name)` / `C_Spell.GetSpellInfo(name)` as the primary icon fallback. It was tested here and made icons disappear out of combat.
- Do not add LibQTip back for the Retail test extraction. Its old role was only a richer broker/minimap hover tooltip, not aura bar behavior.

## Current Implementation Notes
- `ElkBuffBars.lua`
  - Uses `CanReadValue` / `CanReadNumber` guards around secret-prone aura fields.
  - Keeps previous aura data by `auraInstanceID` to preserve readable values across combat updates.
  - Uses `GetAuraIconTexture(texture, spellId, previous)`:
    - first pass through non-nil `texture` directly,
    - then previous icon,
    - then readable spell-id lookup,
    - then question mark fallback.
  - Filters already-expired timed auras only when `expirationTime` is readable, positive, and `<= GetTime()`.
    - Important: `expirationTime == 0` is timeless, not expired.
- `EBB_Bar.secrets.lua`
  - Uses safe wrappers for aura duration, count, and dispel color calls.
  - Caches/resolves time left without doing Lua math on unreadable secret values.
  - Uses `DurationObject:FormatRemainingDuration(...)` for secret duration display.
  - Avoids comparing possibly secret formatted timer strings to `""`.
- `EBB_BarGroup.secrets.lua`
  - Uses `GetUnitAuraInstanceIDs` sorting where possible.
  - Has fallback sorting guards that avoid direct secret comparisons.
  - Allows combat live updates for aura groups while deferring unsafe structural operations.

## Retail Extraction Notes
- Standalone test addon name: `OdysseusBuffBarsTest`.
- Initial staged extraction folder from this work:
  - `_RetailTestAddon/OdysseusBuffBarsTest/OdysseusBuffBarsTest.toc`
  - `_RetailTestAddon/OdysseusBuffBarsTest/Core.lua`
  - `_RetailTestAddon/OdysseusBuffBarsTest/AuraEngine.lua`
  - `_RetailTestAddon/OdysseusBuffBarsTest/Bars.lua`
- The copied full ElkBuffBars addon should live only under a reference folder, for example `Reference/ElkBuffBars/`.
  - Do not list reference files in the `.toc`.
  - Treat reference code as read-only comparison material unless explicitly porting a feature.
- First active test addon scope:
  - Retail 12.0+ only.
  - No Classic, MoP, Wrath, or compatibility branches.
  - No profiles. Use one global SavedVariables table first.
  - Keep settings small at first: group definitions, width, height, scale, colors, filters, sort, max bars, show timed, show timeless.
  - Add override settings and per-group filters later, after combat behavior is proven.
  - LibSharedMedia is optional for bar textures only.
  - LibDBIcon/minimap launcher can be added later.
  - LibQTip is dropped.
- Test addon bar movement:
  - The staged test addon uses a small anchor/title strip above each group.
  - `/obbtest` toggles anchors locked/unlocked.
  - Anchor positions are saved in `OdysseusBuffBarsTestDB`, not an AceDB profile.
- Suggested first-test bar width is wider than old EBB defaults, around `340` to `360`, so long spell names have room beside icon and timer text.

## Testing Checklist
After any aura-related change, test at minimum:
- `/reload` on player login: timeless buffs should display immediately.
- Open-world training dummy combat: icons, names, and timers should remain visible.
- Instance combat, such as Stormwind Stockade: no Lua errors on pull, during combat, or after leaving combat.
- Timeless buffs should not become `0.0s`.
- Timed buffs/debuffs should count down.
- Buffs should not disappear after leaving combat.
- For the extracted test addon, also test drag/save position by moving anchors, reloading, and confirming positions persist.
- If errors occur, capture the first full stack trace.

## Development Constraints
- Retail 12.0+ API only unless explicitly working on non-Retail compatibility.
- No `loadstring`.
- Avoid hooks/replacements of protected Blizzard frames/functions.
- Use `pcall` around risky C API calls that may reject secret/tainted input.
- Keep changes minimal and scoped. This addon is fragile around combat taint.
- Prefer one-file-at-a-time changes when actively debugging.
- Run `luacheck ElkBuffBars.lua EBB_Bar.secrets.lua EBB_BarGroup.secrets.lua` after changes.
  - Current baseline has many WoW-global warnings, but should report `0 errors`.
