# Study session

## Starting a session

### Scenario: Session uses up to the saved word count when enough words exist

**Given** the user's saved "words per session" preference is 10  
**And** a box has 20 words in the selected levels  
**When** the user starts a study session for that box  
**Then** the session contains 10 words  
**And** due words (next review date in the past or today) are chosen first  
**And** if fewer than 10 are due, the rest are filled from future words (soonest first, then shuffled)

### Scenario: Session uses fewer words when the box has fewer than the preference

**Given** the user's saved "words per session" preference is 10  
**And** a box has only 3 words in the selected levels  
**When** the user starts a study session for that box  
**Then** the session contains 3 words  
**And** the saved preference remains 10 for future sessions (not overwritten)

### Scenario: Session has at least one word when any words exist

**Given** a box has 1 word in the selected levels  
**And** the user's saved preference might be higher  
**When** the user starts a study session  
**Then** the session contains that 1 word

### Scenario: Words are filtered by selected level

**Given** a box has words at levels 1, 2, and 3  
**And** the user has selected only level 2 for study  
**When** the user starts a study session  
**Then** only words at level 2 are included in the session
