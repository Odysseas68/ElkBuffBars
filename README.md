Version next

- Updated aura handling for Retail 12.x
- Fixed errors caused by hidden/secret aura values returned by the modern aura API
- Improved combat updating for buff and debuff groups
- Fixed several timer and sorting issues on Retail
- Fixed timeless buffs showing incorrect bar state on login/reload
- Replaced outdated debuff color fallback handling
- Added safer fallback behavior when aura timer data is unreadable

Note:
Some newly gained timed buffs in combat may still not provide a readable
remaining time through the Retail API. In those cases the bar is shown and
the timer text will display "?" until a readable value becomes available.