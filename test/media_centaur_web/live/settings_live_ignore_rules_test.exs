defmodule MediaCentaurWeb.SettingsLiveIgnoreRulesTest do
  @moduledoc """
  The Settings ignore-rules card: both rule kinds through one handler
  set, and the invariant guard.

  Replaces `SettingsLiveExcludeDirsTest` — the path-rule half used to be
  its own card in Library with its own handler triple, and the
  name-rule half a validation-free list in Media Import. The card
  merged because they are one idea with two matching modes; the guard
  is new, because a rule over imported titles would have starved their
  presence rows until `Library.AbsenceSweeper` purged them.
  """
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Settings.Config

  # SettingsLive's `ensure_loaded/1` defers its 15+ config / capability
  # / probe reads to an owned `start_async(:settings_load, …)` (ADR-049).
  # `render_async/1` awaits the load deterministically — no wall-clock sleep.
  defp wait_for_async_load(view) do
    _ = render_async(view)
    view
  end

  defp tmp_dir(label) do
    path = Path.join(System.tmp_dir!(), "ignore-rule-#{label}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  defp open_library(conn) do
    {:ok, view, _html} = live_async!(conn, "/settings?section=library")
    view
  end

  describe "path rules" do
    test "adds an absolute path that exists on disk", %{conn: conn} do
      tmp = tmp_dir("valid")
      view = open_library(conn)

      view
      |> form("form#ignore-rules-path-add", %{"item" => tmp})
      |> render_submit()

      assert tmp in Config.get(:exclude_dirs)
      assert render(view) =~ tmp
    end

    test "rejects a relative path inline and adds nothing", %{conn: conn} do
      view = open_library(conn)

      html =
        view
        |> form("form#ignore-rules-path-add", %{"item" => "cache"})
        |> render_change()

      assert html =~ "Must be an absolute path"
      refute "cache" in (Config.get(:exclude_dirs) || [])
    end

    test "rejects a path that doesn't exist on disk", %{conn: conn} do
      view = open_library(conn)

      html =
        view
        |> form("form#ignore-rules-path-add", %{
          "item" => "/does/not/exist/#{System.unique_integer([:positive])}"
        })
        |> render_change()

      assert html =~ "Path does not exist"
    end

    test "rejects a duplicate", %{conn: conn} do
      tmp = tmp_dir("dup")
      :ok = Config.update(:exclude_dirs, [tmp])

      view = conn |> open_library() |> wait_for_async_load()

      html =
        view
        |> form("form#ignore-rules-path-add", %{"item" => tmp})
        |> render_change()

      assert html =~ "Already in the list"

      view
      |> form("form#ignore-rules-path-add", %{"item" => tmp})
      |> render_submit()

      assert Config.get(:exclude_dirs) == [tmp]
    end

    test "deletes an entry", %{conn: conn} do
      tmp_a = tmp_dir("del-a")
      tmp_b = tmp_dir("del-b")
      :ok = Config.update(:exclude_dirs, [tmp_a, tmp_b])

      view = conn |> open_library() |> wait_for_async_load()

      view
      |> element(
        "button[phx-click='ignore_rule:delete'][phx-value-kind='path'][phx-value-item='#{tmp_a}']"
      )
      |> render_click()

      assert Config.get(:exclude_dirs) == [tmp_b]
    end

    test "rejects a path outside every media directory", %{conn: conn} do
      media_dir = tmp_dir("media")
      elsewhere = tmp_dir("elsewhere")

      :ok =
        Config.put_media_dirs([
          %{"id" => "m1", "dir" => media_dir, "images_dir" => nil, "name" => nil}
        ])

      view = conn |> open_library() |> wait_for_async_load()

      html =
        view
        |> form("form#ignore-rules-path-add", %{"item" => elsewhere})
        |> render_change()

      assert html =~ "Only paths inside a media directory"
      refute elsewhere in (Config.get(:exclude_dirs) || [])
    end
  end

  describe "name rules" do
    test "adds a folder name", %{conn: conn} do
      view = open_library(conn)

      view
      |> form("form#ignore-rules-name-add", %{"item" => "Proofs"})
      |> render_submit()

      assert "Proofs" in Config.get(:skip_dirs)
    end

    test "does not demand an absolute path", %{conn: conn} do
      view = open_library(conn)

      html =
        view
        |> form("form#ignore-rules-name-add", %{"item" => "Proofs"})
        |> render_change()

      refute html =~ "Must be an absolute path"
    end

    test "rejects a duplicate whatever its case", %{conn: conn} do
      :ok = Config.update(:skip_dirs, ["sample"])
      view = conn |> open_library() |> wait_for_async_load()

      html =
        view
        |> form("form#ignore-rules-name-add", %{"item" => "Sample"})
        |> render_change()

      assert html =~ "Already in the list"
    end

    test "deletes an entry", %{conn: conn} do
      :ok = Config.update(:skip_dirs, ["Sample", "Proofs"])
      view = conn |> open_library() |> wait_for_async_load()

      view
      |> element(
        "button[phx-click='ignore_rule:delete'][phx-value-kind='name'][phx-value-item='Sample']"
      )
      |> render_click()

      assert Config.get(:skip_dirs) == ["Proofs"]
    end
  end

  describe "the imported-content invariant" do
    test "refuses a path rule that covers an imported file", %{conn: conn} do
      media_dir = tmp_dir("invariant-path")
      captures = Path.join(media_dir, "Captures")
      File.mkdir_p!(captures)

      movie = create_movie(%{name: "Sample Movie"})

      create_linked_file(%{
        file_path: Path.join(captures, "imported.mkv"),
        media_dir: media_dir,
        movie_id: movie.id
      })

      view = conn |> open_library() |> wait_for_async_load()

      html =
        view
        |> form("form#ignore-rules-path-add", %{"item" => captures})
        |> render_change()

      assert html =~ "1 file already in your library"
      refute captures in (Config.get(:exclude_dirs) || [])
    end

    test "refuses a name rule whose folders hold imported files", %{conn: conn} do
      media_dir = tmp_dir("invariant-name")
      movie = create_movie(%{name: "Sample Movie"})

      create_linked_file(%{
        file_path: Path.join([media_dir, "Proofs", "imported.mkv"]),
        media_dir: media_dir,
        movie_id: movie.id
      })

      view = conn |> open_library() |> wait_for_async_load()

      html =
        view
        |> form("form#ignore-rules-name-add", %{"item" => "Proofs"})
        |> render_change()

      assert html =~ "already in your library"
      refute "Proofs" in (Config.get(:skip_dirs) || [])
    end

    test "allows a rule over a directory with nothing imported from it", %{conn: conn} do
      media_dir = tmp_dir("clean")
      captures = Path.join(media_dir, "Captures")
      File.mkdir_p!(captures)

      movie = create_movie(%{name: "Sample Movie"})

      create_linked_file(%{
        file_path: Path.join([media_dir, "Movies", "Sample.Movie.mkv"]),
        media_dir: media_dir,
        movie_id: movie.id
      })

      view = conn |> open_library() |> wait_for_async_load()

      view
      |> form("form#ignore-rules-path-add", %{"item" => captures})
      |> render_submit()

      assert captures in Config.get(:exclude_dirs)
    end
  end
end
