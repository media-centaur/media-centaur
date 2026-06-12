defmodule MediaCentaur.ErrorReports.HeadlineTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.ErrorReports.Headline

  # Inputs are Redactor-normalized incident messages: whitespace collapsed
  # to single spaces, paths/ids redacted. The grammar must work on that
  # one-line form — newline boundaries are gone by the time we see it.

  describe "derive/1 — GenServer terminations" do
    test "names the crashing process and the inner exception, dropping the stack frames" do
      message =
        "GenServer MediaCentaur.Pipeline.Image.RetryScheduler terminating " <>
          "** (Exqlite.Error) no such column: p0.media_dir " <>
          "(ecto_sql 3.13.5) lib/ecto/adapters/sql.ex: Ecto.Adapters.SQL.raise_sql_call_error/1"

      assert Headline.derive(message) ==
               "Pipeline.Image.RetryScheduler crashed — Exqlite.Error: no such column: p0.media_dir"
    end

    test "falls back to a generic identity for unnamed processes" do
      message =
        "GenServer #PID<0.<num>.0> terminating ** (RuntimeError) boom " <>
          "(stdlib 6.2.2.3) gen_server.erl: :gen_server.try_handle_info/3"

      assert Headline.derive(message) == "GenServer crashed — RuntimeError: boom"
    end
  end

  describe "derive/1 — exceptions" do
    test "leads with the exception's identifying segment, keeping the message" do
      message =
        "** (Phoenix.Ecto.PendingMigrationError) migrations are pending for repo MediaCentaur.Repo"

      assert Headline.derive(message) ==
               "PendingMigrationError: migrations are pending for repo MediaCentaur.Repo"
    end

    test "keeps two-segment exception modules whole" do
      message = ~s{** (Bandit.HTTPError) Request line HTTP error: "GET <redacted:path>"}

      assert Headline.derive(message) ==
               ~s{Bandit.HTTPError: Request line HTTP error: "GET <redacted:path>"}
    end

    test "finds the exception behind a wrapping prefix" do
      message = "an exception was raised: ** (KeyError) key :headline not found in: %{count: 9}"

      assert Headline.derive(message) == "KeyError: key :headline not found in: %{count: 9}"
    end

    test "keeps one parent segment when the last segment alone is generic" do
      message = "** (Exqlite.Error) Database busy"

      assert Headline.derive(message) == "Exqlite.Error: Database busy"
    end
  end

  describe "derive/1 — fallback" do
    test "plain messages pass through unchanged" do
      assert Headline.derive("watch path not accessible — <redacted:path> (waiting for mount)") ==
               "watch path not accessible — <redacted:path> (waiting for mount)"
    end

    test "long messages clamp to the length budget" do
      long = String.duplicate("a", 400)
      derived = Headline.derive(long)

      assert String.length(derived) <= 161
      assert String.ends_with?(derived, "…")
    end

    test "empty input yields empty output" do
      assert Headline.derive("") == ""
    end
  end
end
