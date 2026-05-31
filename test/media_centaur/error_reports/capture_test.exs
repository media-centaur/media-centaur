defmodule MediaCentaur.ErrorReports.CaptureTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Console.Entry
  alias MediaCentaur.ErrorReports.Capture
  alias MediaCentaur.ErrorReports.Store

  defp entry(overrides) do
    Entry.new(
      Map.merge(
        %{
          id: System.unique_integer([:positive]),
          timestamp: DateTime.utc_now(),
          level: :error,
          component: :pipeline,
          message: "import failed",
          metadata: %{}
        },
        Map.new(overrides)
      )
    )
  end

  describe "persist_entry/1 level filtering" do
    test "ignores debug and info, persisting nothing" do
      assert Capture.persist_entry(entry(level: :debug, message: "noise")) == :ignored
      assert Capture.persist_entry(entry(level: :info, message: "fyi")) == :ignored

      assert Store.list_incidents() == []
    end

    test "captures warning entries as warning-severity incidents" do
      assert {:ok, incident} = Capture.persist_entry(entry(level: :warning, message: "slow query"))
      assert incident.origin == :log
      assert incident.severity == :warning
      assert incident.status == :open
    end

    test "captures error entries as error-severity incidents" do
      assert {:ok, incident} = Capture.persist_entry(entry(level: :error, message: "crashed"))
      assert incident.severity == :error
    end
  end

  describe "persist_entry/1 persistence" do
    test "writes one event and opens one incident per occurrence" do
      {:ok, incident} = Capture.persist_entry(entry(message: "boom"))

      assert [event] = Store.list_recent_events(incident.fingerprint)
      assert event.level == :error
      assert event.component == "pipeline"
      assert incident.count == 1
    end

    test "groups recurrences of the same fingerprint into one incident, many events" do
      {:ok, _} = Capture.persist_entry(entry(message: "duplicate failure"))
      {:ok, incident} = Capture.persist_entry(entry(message: "duplicate failure"))

      assert incident.count == 2
      assert length(Store.list_recent_events(incident.fingerprint)) == 2
      assert [_one] = Store.list_incidents()
    end

    test "stamps the current app version on the incident" do
      {:ok, incident} = Capture.persist_entry(entry(message: "versioned"))
      assert incident.app_version_at_first == to_string(Application.spec(:media_centaur, :vsn))
    end
  end

  describe "persist_entry/1 redaction" do
    test "stores the redacted, normalized message — not the raw one" do
      {:ok, incident} =
        Capture.persist_entry(entry(message: "failed reading /home/alice/Movies/secret.mkv"))

      assert [event] = Store.list_recent_events(incident.fingerprint)
      refute event.message =~ "/home/alice/Movies/secret.mkv"
      assert event.message =~ "<path>"
    end

    test "two users hitting the same bug on different paths land in one incident" do
      {:ok, _} = Capture.persist_entry(entry(message: "no such file /home/alice/a.mkv"))
      {:ok, second} = Capture.persist_entry(entry(message: "no such file /home/bob/b.mkv"))

      assert second.count == 2
      assert [_single_incident] = Store.list_incidents()
    end

    test "prunes metadata to scalar values only" do
      metadata = %{tmdb_id: 42, title: "kept-scalar", conn: self(), tuple: {:a, :b}}
      {:ok, incident} = Capture.persist_entry(entry(message: "with metadata", metadata: metadata))

      assert [event] = Store.list_recent_events(incident.fingerprint)
      assert event.metadata["tmdb_id"] == 42
      assert event.metadata["title"] == "kept-scalar"
      refute Map.has_key?(event.metadata, "conn")
      refute Map.has_key?(event.metadata, "tuple")
    end
  end
end
