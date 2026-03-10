# Settings

## Session word count

### Scenario: Saved word count preference is not overwritten by current box size

**Given** the user has previously set "words per session" to 20  
**When** the user opens Settings from a box that has only 5 words (so the picker options are 1 and 5)  
**Then** the stored preference remains 20  
**And** the picker shows a valid selection (e.g. 5) for display only, without saving 5  
**And** when the user starts a session in that box, 5 words are used for that session only

### Scenario: User can change the word count in Settings

**Given** the user has a saved preference (e.g. 10)  
**When** the user opens Settings and selects a different value (e.g. 15) in the "Number of words" picker  
**Then** the new value (15) is saved as the preference  
**And** future sessions (in boxes with enough words) use 15 words

### Scenario: Default word count is 10

**Given** the user has never changed "words per session"  
**When** the app uses the session word count  
**Then** the value used is 10
