Retail 12.x compatibility update

This update improves ElkBuffBars behavior on modern Retail, especially around the newer C_UnitAuras API and Blizzard’s protected/secret aura values.

Fixed
- Fixed multiple Lua errors caused by arithmetic/comparisons on secret aura values
- Fixed sorting errors caused by secret strings/numbers
- Fixed debuff update issues in combat
- Fixed startup/login visual issue where timeless buffs could appear as full bars
- Fixed outdated debuff color fallback usage that could error on current Retail
- Fixed several combat update regressions introduced while adapting the addon to Retail 12.x

Changed
- Reworked timer handling to safely deal with hidden/unreadable aura times
- Buff and debuff groups now live-update more safely in combat
- Timeless buffs now keep their intended empty-bar visual behavior
- Combat sorting uses safer fallback logic when expiration data is unreadable
- Added safer max-duration caching for normal aura timing fallbacks

Behavior note
- On current Retail, some newly gained timed buffs in combat may not expose a readable remaining time through the API
- In those cases the buff bar still appears, but the timer text shows "?" until readable timing becomes available
- This is an intentional fallback to avoid broken timers or Lua errors