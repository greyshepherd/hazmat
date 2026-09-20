# Spec Delta

## MODIFIED Requirements

### Requirement: Bytes are validated before anything is written

A request MUST be refused unless the bytes hold exactly one well-formed managed
block of a supported version, and MUST be refused when the bytes exceed the
size bound of 16 MiB. The bound exists so a client cannot make the privileged
side write an arbitrarily large file; it MUST admit a block of several hundred
thousand short host entries. Nothing is written when a request is refused.

#### Scenario: Malformed or foreign content
- **WHEN** the bytes hold no block, more than one block, a malformed marker, or an unsupported version
- **THEN** the request is refused with a reason and the file is unchanged

#### Scenario: Oversized request
- **WHEN** the bytes exceed 16 MiB
- **THEN** the request is refused, the reason names the size and the bound, and the file is unchanged

#### Scenario: A large block within the bound
- **WHEN** the bytes hold one well-formed block of 100,000 entries and are no larger than 16 MiB
- **THEN** the request is not refused for its size
