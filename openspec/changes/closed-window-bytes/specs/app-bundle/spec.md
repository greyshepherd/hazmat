# Spec Delta

## ADDED Requirements

### Requirement: The bundle launches the application in malloc's space-efficient mode

The bundle's property list MUST declare `MallocSpaceEfficient` set to `1` in
its launch environment, so that what the application frees — the view tree and
the composition of a closed window, the bytes of a read — goes back to the
system rather than into malloc's caches. The verifier MUST refuse a bundle that
does not declare it.

#### Scenario: The window closes over a large profile
- **WHEN** the window is closed after showing a profile of 100,000 entries
- **THEN** the application's footprint returns to what it holds, not to what the window allocated

#### Scenario: A bundle without the declaration
- **WHEN** a bundle's property list lacks the declaration
- **THEN** the verifier reports it and fails
