defmodule MediaCentaur.ContextMap.Rules.CrossContextKeyTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Context
  alias MediaCentaur.ContextMap.Finding
  alias MediaCentaur.ContextMap.Rules.CrossContextKey
  alias MediaCentaur.ContextMap.Schema

  @contexts [
    %Context{name: MediaCentaur.Discovery, kernel?: false, deps: [MediaCentaur.Library], exports: []},
    %Context{name: MediaCentaur.Activities, kernel?: false, deps: [MediaCentaur.Discovery], exports: []},
    %Context{name: MediaCentaur.Library, kernel?: true, deps: [], exports: []},
    %Context{name: MediaCentaur.WatchHistory, kernel?: false, deps: [MediaCentaur.Library], exports: []},
    %Context{
      name: MediaCentaur.ReleaseTracking,
      kernel?: false,
      deps: [MediaCentaur.Library],
      exports: []
    }
  ]

  @activity %Schema{
    module: MediaCentaur.Activities.Activity,
    file: "lib/media_centaur/activities/activity.ex",
    context: MediaCentaur.Activities,
    table: "activities",
    fields: [],
    associations: []
  }
  @movie %Schema{
    module: MediaCentaur.Library.Movie,
    file: "lib/media_centaur/library/movie.ex",
    context: MediaCentaur.Library,
    table: "movies",
    fields: [],
    associations: []
  }
  @episode %Schema{
    module: MediaCentaur.Library.Episode,
    file: "lib/media_centaur/library/episode.ex",
    context: MediaCentaur.Library,
    table: "episodes",
    fields: [],
    associations: []
  }
  @intent %Schema{
    module: MediaCentaur.Discovery.TitleIntent,
    file: "lib/media_centaur/discovery/title_intent.ex",
    context: MediaCentaur.Discovery,
    table: "title_intents",
    fields: [
      %{name: :tmdb_id, type: ":integer", values: nil},
      %{name: :activity_id, type: "Ecto.UUID", values: nil}
    ],
    associations: []
  }
  @event %Schema{
    module: MediaCentaur.WatchHistory.Event,
    file: "lib/media_centaur/watch_history/event.ex",
    context: MediaCentaur.WatchHistory,
    table: "watch_history_events",
    fields: [%{name: :movie_id, type: "Ecto.UUID", values: nil}],
    associations: [
      %{name: :movie, kind: :belongs_to, target: MediaCentaur.Library.Movie, foreign_key: :movie_id}
    ]
  }
  @item %Schema{
    module: MediaCentaur.ReleaseTracking.Item,
    file: "lib/media_centaur/release_tracking/item.ex",
    context: MediaCentaur.ReleaseTracking,
    table: "release_tracking_items",
    fields: [%{name: :library_container_id, type: "Ecto.UUID", values: nil}],
    associations: []
  }
  @override %Schema{
    module: MediaCentaur.Library.MediaTrackOverride,
    file: "lib/media_centaur/library/media_track_override.ex",
    context: MediaCentaur.Library,
    table: "media_track_overrides",
    fields: [
      %{name: :owner_type, type: "Ecto.Enum", values: [:movie, :episode]},
      %{name: :owner_id, type: "Ecto.UUID", values: nil}
    ],
    associations: []
  }
  @schemas [@activity, @movie, @episode, @intent, @event, @item, @override]

  setup do
    {findings, kernel_reads} = CrossContextKey.findings(@schemas, @contexts)
    %{findings: findings, kernel_reads: kernel_reads}
  end

  test "a soft key into a context outside the owner's deps is a finding", %{findings: findings} do
    assert %Finding{
             rule: "R4",
             owner: MediaCentaur.Discovery,
             field: :activity_id,
             detail: %{target: MediaCentaur.Activities.Activity, in_deps: false}
           } = Enum.find(findings, &(&1.field == :activity_id))
  end

  test "an association into the kernel is a kernel read, not a finding", %{
    findings: findings,
    kernel_reads: kernel_reads
  } do
    refute Enum.find(findings, &(&1.field == :movie_id))

    assert %{
             schema: MediaCentaur.WatchHistory.Event,
             field: :movie_id,
             target: MediaCentaur.Library.Movie
           } =
             Enum.find(kernel_reads, &(&1.field == :movie_id))
  end

  test "an unresolvable key is reported as unresolved", %{findings: findings} do
    assert %Finding{detail: %{unresolved: true}} =
             Enum.find(findings, &(&1.field == :library_container_id))
  end

  test "external identifiers are kernel references", %{findings: findings, kernel_reads: kernel_reads} do
    refute Enum.find(findings, &(&1.field == :tmdb_id))
    assert Enum.find(kernel_reads, &(&1.field == :tmdb_id and &1.target == :external))
  end

  test "a polymorphic key resolves through its discriminator values; same-context targets are not crossings",
       %{findings: findings, kernel_reads: kernel_reads} do
    refute Enum.find(findings, &(&1.field == :owner_id))
    refute Enum.find(kernel_reads, &(&1.field == :owner_id))
  end

  test "a polymorphic key with several unresolvable discriminator values yields one unresolved finding" do
    ghost = %Schema{
      module: MediaCentaur.Pipeline.ImageQueueEntry,
      file: "lib/media_centaur/pipeline/image_queue_entry.ex",
      context: MediaCentaur.Pipeline,
      table: "image_queue_entries",
      fields: [
        %{name: :owner_type, type: "Ecto.Enum", values: [:ghost_a, :ghost_b]},
        %{name: :owner_id, type: "Ecto.UUID", values: nil}
      ],
      associations: []
    }

    {findings, _kernel_reads} = CrossContextKey.findings([ghost], @contexts)

    assert [%Finding{field: :owner_id, detail: %{unresolved: true}}] =
             Enum.filter(findings, &(&1.field == :owner_id))
  end

  test "an embedded schema sharing a stem does not block resolution" do
    embedded = %Schema{
      module: MediaCentaur.Activities.Activity.Episode,
      context: MediaCentaur.Activities,
      file: "lib/media_centaur/activities/activity.ex",
      table: nil,
      fields: [],
      associations: []
    }

    {findings, _kernel_reads} = CrossContextKey.findings([embedded | @schemas], @contexts)
    refute Enum.find(findings, &(&1.field == :owner_id))
  end
end
