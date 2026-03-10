# Persistence

## Data survives app restart

### Scenario: User-created boxes persist after app restart

**Given** the user has created one or more boxes (with or without words)  
**When** the app is closed and opened again (or the device restarts)  
**Then** all boxes still appear in the list with the same names and languages  
**And** no boxes are lost

### Scenario: Words in a box persist after app restart

**Given** a box exists and contains words  
**When** the app is closed and opened again  
**Then** the box still contains the same words  
**And** each word's level and review dates are unchanged

### Scenario: App starts with an empty database for new users

**Given** the app is installed and never had demo data seeded  
**When** the user opens the app for the first time  
**Then** no boxes are shown (empty state)  
**And** the "Grundlagen" demo box is not created automatically
