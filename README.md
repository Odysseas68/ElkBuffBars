Retail 12.x compatibility update

This patched version updates ElkBuffBars for the modern Retail aura system.

What changed
- Updated aura handling for Retail 12.x
- Fixed Lua errors caused by hidden/secret aura values returned by C_UnitAuras
- Improved buff and debuff live updates in combat
- Fixed several timer and sorting errors on Retail
- Fixed timeless buffs showing the wrong bar state on login/reload
- Replaced outdated debuff color fallback handling
- Added safer fallback logic for unreadable aura duration data

Current Retail API limitations
- On current Retail, some aura values are hidden/protected by Blizzard
- Because of that, some newly gained timed buffs in combat may not immediately provide a readable remaining time
- In those cases, the buff bar is still shown, but the timer text may display "?" until a readable value becomes available
- Timeless buffs remain supported, but combat transitions may still briefly show fallback timer text in some cases depending on what the API exposes at that moment

Notes
- Out of combat, bars, timers, and sorting should behave normally
- The goal of this patch is stability and compatibility on modern Retail, even when the API does not expose full timer information