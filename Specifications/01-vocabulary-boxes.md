# Vocabulary boxes

## Creating a box

### Scenario: User creates a new box with a name and language

**Given** the user has no boxes (or is on the vocabulary boxes list)  
**When** the user taps "Add", enters a name (e.g. "Travel"), selects a target language (e.g. German), and saves  
**Then** a new box exists with that name and language  
**And** the box appears in the list and can be opened  
**And** the box has zero words initially

### Scenario: Duplicate box names are rejected

**Given** a box named "German" already exists  
**When** the user tries to create (or rename to) another box named "German" (case-insensitive)  
**Then** the app shows an error and does not save  
**And** the existing box is unchanged

---

## Editing and deleting boxes

### Scenario: User renames a box

**Given** a box named "Old Name" exists  
**When** the user renames it to "New Name" and saves  
**Then** the box appears in the list as "New Name"  
**And** its words and progress are unchanged

### Scenario: User deletes a box

**Given** a box exists and may contain words  
**When** the user deletes the box (and confirms)  
**Then** the box is removed from the list  
**And** all words in that box are removed (cascade delete)
