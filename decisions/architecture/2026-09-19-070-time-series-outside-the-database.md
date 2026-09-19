---
status: accepted
date: 2026-09-19
---
# Durable observational time series live outside the main database

## Context and Problem Statement

ADR-041 makes the database the only source of truth: no ETS state is
authoritative for a persistent fact. The request history behind the
Connections strip charts is a persistent fact (its events are gone once
counted) but it is observational, of fixed size, and written on a timer.
The main SQLite database is single-writer and already reports busy errors;
the owner refused another periodic writer on it. A second SQLite database
would thread a second Repo through config, release migration, the test
sandbox and every override TOML for transactional durability and SQL the
data does not need.

## Decision Outcome

Chosen option: "an ETS round-robin store with a periodic snapshot file",
because it adds no writer to the database, has a ceiling by construction,
and needs no migration machinery. `MediaCentaur.TimeSeries.Store` keeps
the rows; once a minute, if anything changed, and on clean shutdown, it
writes the whole table to `<database dir>/<tenant>.snapshot` atomically,
and loads it on boot. A file whose version or field list does not match
is ignored and the store starts empty: observational data is never
migrated.

This is a bounded exception to ADR-041, not a new rule for state in
general. It applies to a time series a tenant would graph — counts of an
event over time, kept at fixed resolutions — and to nothing that a user
created or that another table refers to.

### Consequences

* Good, because the database gains no writer and the busy-error surface
  does not grow.
* Good, because the store's cost is fixed and visible: about 12,000 rows
  per tenant, one file, listed on the Connections retention panel and in
  the System tile's datastore figure.
* Bad, because a hard crash loses up to one minute of counts. Accepted
  for request tallies.
* Bad, because a second answer to "where does durable state live" now
  exists; `MediaCentaur.TimeSeries` and this record are the only places it
  may.
