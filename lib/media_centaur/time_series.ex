defmodule MediaCentaur.TimeSeries do
  @moduledoc """
  Bounded, multi-resolution counts of an event along time — a round-robin
  store in ETS with a snapshot file, and the fold that turns its rows into
  the columns a strip chart draws.

  A tenant declares a `Schema` (its counter fields, each summed or kept as
  a maximum), starts one `Store` per series family, calls `Store.add/5`
  from wherever the event happens, and reads with `Fold.series/6`. The
  first tenant is `MediaCentaur.HttpClient.Traffic`.

  Vocabulary (see `docs/GLOSSARY.md` § Time series): a **time bucket** is
  the span one bar covers; a **resolution** is one of the four stored
  bucket widths (`Resolution`); a **window** is the span a viewer selects
  (`Window`); a **snapshot** is the store's on-disk copy (`Snapshot`).
  Durable state outside the main database is a bounded exception to
  ADR-041, recorded in ADR-070.
  """
  use Boundary,
    top_level?: true,
    deps: [MediaCentaur.Retention],
    exports: [Fold, LocalDay, Resolution, Schema, Snapshot, Store, Window]
end
