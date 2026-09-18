# Spec Delta

## MODIFIED Requirements

### Requirement: A write is accepted only from the app that registered the helper

The privileged side MUST verify that a request comes from its own app, and MUST
refuse requests from any other client. When the running daemon itself carries a
team identifier — that is, when it was signed for distribution — the requirement
it checks MUST anchor that team as well as the app's identifier, so that an
ad-hoc build of the same identifier cannot write. When the daemon carries no team
identifier, the requirement MUST be the app's identifier alone, so a development
build works without a certificate.

#### Scenario: Foreign client
- **WHEN** an unrelated process connects and requests a write
- **THEN** the request is refused and the file is unchanged

#### Scenario: A signed daemon and an ad-hoc client
- **WHEN** a daemon signed with a team identifier receives a request from a client of the same identifier that is signed ad-hoc
- **THEN** the request is refused and the file is unchanged

#### Scenario: A client from another team
- **WHEN** a daemon signed with a team identifier receives a request from a client signed by a different team
- **THEN** the request is refused and the file is unchanged

#### Scenario: A development daemon
- **WHEN** a daemon that carries no team identifier receives a request from the app built beside it
- **THEN** the request is accepted on the strength of the identifier both carry
