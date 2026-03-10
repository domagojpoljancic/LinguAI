# Words in a box

## Adding words

### Scenario: User adds a word to a box

**Given** a box exists and is open  
**When** the user adds a word pair (e.g. primary "Hello", target "Hallo") and saves  
**Then** the word appears in the box's word list  
**And** the word starts at level 1 (first box)  
**And** the word has a next review date set so it can appear in a session

### Scenario: Duplicate word pairs are rejected

**Given** a box already contains the pair "Hello" / "Hallo"  
**When** the user tries to add the same pair again (case-insensitive)  
**Then** the app shows an error and does not save  
**And** no duplicate is added

### Scenario: Empty word fields are rejected

**Given** the user is on the Add Word sheet  
**When** the user leaves primary or target text empty and tries to save  
**Then** the app shows an error and does not add a word

---

## Editing words

### Scenario: User edits a word's text

**Given** a box contains a word "Hello" / "Hallo"  
**When** the user edits it to "Hi" / "Hallo" and saves  
**Then** the word in the box shows the new text  
**And** the word's level and review state are unchanged
