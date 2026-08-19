defmodule MediaCentaurWeb.SettingsLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Playback.LanguagePolicy

  alias MediaCentaur.Preferences.{
    AutoPlayNextEpisode,
    IncomingBackdrop,
    LetterboxdLinks,
    LibraryBackdrop,
    LibraryCardInfo,
    UIScale,
    WatchlistVisibility
  }

  # `SettingsLive.ensure_loaded/1` loads its config / capability / probe
  # reads synchronously on first render (desktop first-paint correctness),
  # so the data is present immediately. `render_async/1` is retained as a
  # no-op-safe await for any incidental async (e.g. the update check).
  defp render_after_async_load(view) do
    render_async(view)
  end

  test "mounts at /settings", %{conn: conn} do
    {:ok, _view, html} = live_async!(conn, ~p"/settings")
    assert html =~ "Services"
  end

  test "renders the page header with a title and subtitle", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, ~p"/settings")
    assert has_element?(view, "h1.text-3xl", "Settings")
    assert has_element?(view, "header p", "Services, preferences, and configuration")
  end

  # Smoke test — each settings section renders without crashing. This exists
  # because section_content/1 is invoked as a function component with an
  # explicit attribute list; adding a new socket assign without also threading
  # it through the function component invocation crashes the section that
  # references it. Mounting `/settings` alone exercises only the default
  # "services" section, so the failure mode is per-section.
  for section <- [
        "services",
        "preferences",
        "tmdb",
        "acquisition",
        "import",
        "playback",
        "language",
        "library",
        "danger"
      ] do
    test "section #{section} mounts without crashing", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, ~p"/settings?section=#{unquote(section)}")
      assert is_binary(html)
    end
  end

  describe "sections nav active marker" do
    # The input system enters the sections menu on the DOM-marked active item
    # (`activeClassNames` in assets/js/input/config.js — `menu-item-active`).
    # Without the marker, re-entering from the sidebar lands the cursor on the
    # first section instead of the one currently open.
    test "the active section link carries menu-item-active", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=library")

      assert has_element?(
               view,
               "[data-nav-zone='sections'] a.menu-item-active[href='/settings?section=library']"
             )

      refute has_element?(
               view,
               "[data-nav-zone='sections'] a.menu-item-active[href='/settings?section=services']"
             )
    end
  end

  describe "interface scale" do
    test "renders the stepper at the current value with step targets either side",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=preferences")

      assert has_element?(view, "span", "Interface scale")
      assert has_element?(view, "span", "100%")

      # The stepper buttons carry precomputed absolute targets, one step away.
      assert has_element?(
               view,
               "button[phx-click=set_ui_scale][phx-value-choice='0.95'][aria-label='Decrease scale']"
             )

      assert has_element?(
               view,
               "button[phx-click=set_ui_scale][phx-value-choice='1.05'][aria-label='Increase scale']"
             )

      # At the default, Reset is rendered but inert.
      assert has_element?(view, "button[aria-label='Reset scale'][aria-disabled='true']")
    end

    test "stepping up persists the new scale and pushes the live update", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=preferences")

      view
      |> element("button[phx-click=set_ui_scale][aria-label='Increase scale']")
      |> render_click()

      assert_push_event(view, "ui-scale", %{scale: 1.05})
      assert UIScale.scale() == 1.05

      # The stepper re-renders around the new value.
      assert has_element?(view, "span", "105%")

      assert has_element?(
               view,
               "button[phx-click=set_ui_scale][phx-value-choice='1.1'][aria-label='Increase scale']"
             )
    end

    test "stepping down goes below 100%", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=preferences")

      view
      |> element("button[phx-click=set_ui_scale][aria-label='Decrease scale']")
      |> render_click()

      assert_push_event(view, "ui-scale", %{scale: 0.95})
      assert UIScale.scale() == 0.95
      assert has_element?(view, "span", "95%")
    end

    test "reset returns a modified scale to 100%", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=preferences")

      # Step away from the default first (the assign reads the DB-free cache,
      # so the state is driven through the UI, not seeded).
      increase = element(view, "button[phx-click=set_ui_scale][aria-label='Increase scale']")
      render_click(increase)
      render_click(increase)
      assert has_element?(view, "span", "110%")

      view
      |> element("button[phx-click=set_ui_scale][aria-label='Reset scale']")
      |> render_click()

      assert_push_event(view, "ui-scale", %{scale: 1.0})
      assert UIScale.scale() == 1.0
      assert has_element?(view, "span", "100%")
    end

    test "the increase button is inert at the 200% ceiling", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=preferences")

      # Walk the stepper all the way up — each click re-renders with the next
      # precomputed target, so this exercises the whole grid.
      increase = element(view, "button[phx-click=set_ui_scale][aria-label='Increase scale']")
      Enum.each(1..20, fn _step -> render_click(increase) end)

      assert UIScale.scale() == UIScale.max()
      assert has_element?(view, "span", "200%")

      # The target clamps to the current value and the control reads disabled —
      # but it stays a focusable nav item so the gamepad nav graph never shifts.
      assert has_element?(
               view,
               "button[phx-value-choice='2.0'][aria-label='Increase scale'][aria-disabled='true']"
             )

      render_click(increase)
      assert UIScale.scale() == UIScale.max()
    end
  end

  describe "page backdrop toggles" do
    test "renders both rows unchecked by default", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=preferences")

      assert has_element?(view, "span", "Library backdrop")
      assert has_element?(view, "span", "Incoming backdrop")

      refute has_element?(
               view,
               "div[phx-click=toggle_library_backdrop] input[type=checkbox][checked]"
             )

      refute has_element?(
               view,
               "div[phx-click=toggle_incoming_backdrop] input[type=checkbox][checked]"
             )
    end

    test "toggling the Library backdrop persists the flag", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=preferences")

      view |> element("div[phx-click=toggle_library_backdrop]") |> render_click()
      assert LibraryBackdrop.enabled?() == true

      view |> element("div[phx-click=toggle_library_backdrop]") |> render_click()
      assert LibraryBackdrop.enabled?() == false
    end

    test "toggling the Incoming backdrop persists the flag", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=preferences")

      view |> element("div[phx-click=toggle_incoming_backdrop]") |> render_click()
      assert IncomingBackdrop.enabled?() == true

      view |> element("div[phx-click=toggle_incoming_backdrop]") |> render_click()
      assert IncomingBackdrop.enabled?() == false
    end

    test "the Letterboxd links row renders checked by default", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=preferences")

      assert has_element?(view, "span", "Letterboxd links")

      assert has_element?(
               view,
               "div[phx-click=toggle_letterboxd_links] input[type=checkbox][checked]"
             )
    end

    test "toggling Letterboxd links persists the flag", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=preferences")

      assert LetterboxdLinks.enabled?() == true

      view |> element("div[phx-click=toggle_letterboxd_links]") |> render_click()
      assert LetterboxdLinks.enabled?() == false

      view |> element("div[phx-click=toggle_letterboxd_links]") |> render_click()
      assert LetterboxdLinks.enabled?() == true
    end

    test "toggling the watchlist persists the flag", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=preferences")

      assert WatchlistVisibility.enabled?() == false

      view |> element("div[phx-click=toggle_show_watchlist]") |> render_click()
      assert WatchlistVisibility.enabled?() == true

      view |> element("div[phx-click=toggle_show_watchlist]") |> render_click()
      assert WatchlistVisibility.enabled?() == false
    end

    # Personal display preferences live together — this toggle moved here
    # from the Library section's one-row Display card.
    test "toggling poster titles persists the flag from Preferences", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=preferences")

      assert LibraryCardInfo.enabled?() == true

      view |> element("div[phx-click=toggle_show_card_info]") |> render_click()
      assert LibraryCardInfo.enabled?() == false
    end

    test "toggling auto-play next episode persists the flag", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=preferences")

      assert AutoPlayNextEpisode.enabled?() == true

      view |> element("div[phx-click=toggle_auto_play_next_episode]") |> render_click()
      assert AutoPlayNextEpisode.enabled?() == false

      view |> element("div[phx-click=toggle_auto_play_next_episode]") |> render_click()
      assert AutoPlayNextEpisode.enabled?() == true
    end
  end

  describe "language & subtitle policy" do
    test "renders the picker and the audio/subtitle form", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=language")
      assert has_element?(view, "h2", "Languages you understand")
      assert has_element?(view, "h2", "Audio & subtitles")
    end

    test "adding a language persists it and shows a chip", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=language")

      view
      |> form("form[phx-submit=add_language]", %{"lang" => "French"})
      |> render_submit()

      assert has_element?(view, "#understood-lang-fra", "French")
      assert "fra" in LanguagePolicy.load().understood_languages
    end

    test "adding an unknown language is ignored", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=language")

      before = LanguagePolicy.load().understood_languages

      view
      |> form("form[phx-submit=add_language]", %{"lang" => "Klingon"})
      |> render_submit()

      assert LanguagePolicy.load().understood_languages == before
    end

    test "removing a language persists the removal", %{conn: conn} do
      {:ok, _} =
        LanguagePolicy.save(%{LanguagePolicy.defaults() | understood_languages: ["eng", "spa"]})

      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=language")

      view
      |> element("#understood-lang-spa button[phx-click=remove_language]")
      |> render_click()

      refute has_element?(view, "#understood-lang-spa")
      refute "spa" in LanguagePolicy.load().understood_languages
    end

    test "reordering a language persists the new order", %{conn: conn} do
      {:ok, _} =
        LanguagePolicy.save(%{LanguagePolicy.defaults() | understood_languages: ["eng", "spa"]})

      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=language")

      view
      |> element("#understood-lang-spa button[phx-click=move_language_up]")
      |> render_click()

      assert LanguagePolicy.load().understood_languages == ["spa", "eng"]
    end

    test "saving the audio/subtitle form persists a normalized policy", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=language")

      view
      |> form("form[phx-submit=save_language_policy]", %{
        "audio_priority" => "understood_first",
        "subtitles_when" => "always",
        "subtitles_language" => "audio_language",
        "subtitles_variant" => "sdh_preferred",
        "forced_subs" => "never"
      })
      |> render_submit()

      policy = LanguagePolicy.load()
      assert policy.audio_priority == ["understood", "original", "any"]
      assert policy.subtitles_when == "always"
      assert policy.subtitles_language == "audio_language"
      assert policy.subtitles_variant == "sdh_preferred"
      assert policy.forced_subs == "never"
    end

    test "persisted languages render as chips on load", %{conn: conn} do
      {:ok, _} =
        LanguagePolicy.save(%{LanguagePolicy.defaults() | understood_languages: ["spa", "fra"]})

      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=language")
      assert has_element?(view, "#understood-lang-spa", "Spanish")
      assert has_element?(view, "#understood-lang-fra", "French")
    end
  end

  describe "post-tour critical-failure banner" do
    # Banner fires only for configured-but-broken critical probes
    # (`status == :error`), not for `:not_configured`. Both tests put
    # `media_dirs` in `:error` state by configuring a path that does not
    # exist on disk — `Probes.media_dirs/1` returns `:error` when every
    # configured dir is unreachable. Restored on exit.
    setup do
      previous = MediaCentaur.Config.get(:media_dirs) || []
      :ok = MediaCentaur.Config.put_media_dirs([%{"dir" => "/var/empty/nope/missing"}])
      on_exit(fn -> MediaCentaur.Config.put_media_dirs(previous) end)
      :ok
    end

    test "renders when a critical probe is :error", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings")

      html = render_after_async_load(view)

      assert html =~ "Setup is incomplete"
      assert html =~ "Run tour"
      assert html =~ "media dirs"
    end

    test "first paint (disconnected render) shows the banner, not an empty flash",
         %{conn: conn} do
      # Desktop first-paint correctness: with a broken media dir (setup
      # above) the load — which now runs on the disconnected render — must
      # surface the setup banner. The previously-gated behavior left
      # `show_setup_banner?` at its mount default (false) on the static
      # render and flashed an incomplete page. `get/2` exercises the first
      # render the browser paints.
      html = conn |> get(~p"/settings") |> html_response(200)

      assert html =~ "Setup is incomplete",
             "load-derived state must render on the disconnected first paint"
    end

    test "dismiss event hides the banner for the session", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings")

      assert render_after_async_load(view) =~ "Setup is incomplete"

      view |> element("button[phx-click='setup:dismiss_banner']") |> render_click()

      refute render(view) =~ "Setup is incomplete"
    end
  end

  describe "media import — artwork resolution" do
    setup do
      # Config.update mutates the global :persistent_term map (not rolled back
      # by the sandbox), so snapshot and restore it around each test.
      config = :persistent_term.get({MediaCentaur.Config, :config})
      on_exit(fn -> :persistent_term.put({MediaCentaur.Config, :config}, config) end)
      :ok
    end

    test "saving the media-import form persists the artwork resolution", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=import")

      view
      |> form("form[phx-submit=save_import]", %{
        "extras_dirs" => "",
        "skip_dirs" => "",
        "image_resolution" => "1080p"
      })
      |> render_submit()

      assert MediaCentaur.Config.image_resolution() == "1080p"
    end

    test "changing the resolution starts a backdrop re-fetch", %{conn: conn} do
      MediaCentaur.Config.update(:image_resolution, "4k")
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=import")

      html =
        view
        |> form("form[phx-submit=save_import]", %{
          "extras_dirs" => "",
          "skip_dirs" => "",
          "image_resolution" => "1080p"
        })
        |> render_submit()

      assert html =~ "Re-fetching backdrops"
    end

    test "saving without changing the resolution does not start a re-fetch", %{conn: conn} do
      MediaCentaur.Config.update(:image_resolution, "1080p")
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=import")

      html =
        view
        |> form("form[phx-submit=save_import]", %{
          "extras_dirs" => "",
          "skip_dirs" => "",
          "image_resolution" => "1080p"
        })
        |> render_submit()

      refute html =~ "Re-fetching backdrops"
      assert html =~ "Media import settings saved"
    end

    test "the retired ?section=pipeline address lands on Media Import", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=pipeline")

      assert has_element?(
               view,
               "[data-nav-zone='sections'] a.menu-item-active[href='/settings?section=import']"
             )
    end

    test "saving persists the auto-approve threshold", %{conn: conn} do
      MediaCentaur.Config.update(:image_resolution, "1080p")
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=import")

      view
      |> form("form[phx-submit=save_import]", %{
        "extras_dirs" => "",
        "skip_dirs" => "",
        "auto_approve_threshold" => "0.72",
        "image_resolution" => "1080p"
      })
      |> render_submit()

      assert MediaCentaur.Config.get(:auto_approve_threshold) == 0.72
    end

    test "the completion message reports the re-queued count", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=maintenance")

      send(
        view.pid,
        {:backdrop_refetch_complete, %{enqueued: 2, queue_reused: 2, queue_rebuilt: 0, skipped: 0}}
      )

      assert render(view) =~ "Re-queued 2 backdrops"
    end

    test "the manual maintenance button starts a re-fetch", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=maintenance")

      html = view |> element("button[phx-click=refetch_backdrops]") |> render_click()
      assert html =~ "Re-fetching backdrops"
    end
  end

  test "receives cross-tab spoiler_free sync via PubSub", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, ~p"/settings")

    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      MediaCentaur.Topics.settings_updates(),
      {:setting_changed, "spoiler_free_mode", %{"enabled" => true}}
    )

    # Wait for the broadcast to be processed by the LiveView
    _ = render(view)

    # The LiveView should have updated its spoiler_free assign
    assert view |> element("[data-page-behavior]") |> render() =~ "settings"
  end

  test "receives watcher state changes via PubSub", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, ~p"/settings")

    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      MediaCentaur.Topics.dir_state(),
      {:dir_state_changed, "/tmp/test", :media_dir, :unavailable}
    )

    # The LiveView should process the message without crashing
    _ = render(view)
    assert view |> element("[data-page-behavior]") |> render() =~ "settings"
  end

  describe "services section" do
    # "Scan now" lives on Library → Media directories, where the surrounding
    # copy gives it context. Services holds only the process toggles — the
    # same action must not appear in two sections (settings-coherence).
    test "holds only service toggles — no scan trigger", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=services")

      refute has_element?(view, "[phx-click='scan']")
    end

    # Toggles are named for the user-facing task, not the internal process
    # (settings-coherence item 1): Watchers → File watching, Pipeline →
    # Media import, Image Pipeline → Artwork downloads.
    test "toggles carry task-facing names", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, ~p"/settings?section=services")

      assert html =~ "File watching"
      assert html =~ "Media import"
      assert html =~ "Artwork downloads"
      refute html =~ "Watchers"
      refute html =~ "Image Pipeline"
    end

    test "the scan trigger remains on the Library section", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=library")

      assert has_element?(view, "[phx-click='scan']")
    end
  end

  describe "directory-ignore naming" do
    # Excluded directories (Library) are absolute paths in your library
    # layout; Skip/Extras (Media Import) are folder names found within
    # incoming content. The card names carry that distinction
    # (settings-coherence item 4): name-based cards say "folder names".
    test "Media Import cards are named for folder names, not directories", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, ~p"/settings?section=import")

      assert html =~ "Extras folder names"
      assert html =~ "Ignored folder names"
      refute html =~ "Extras directories"
      refute html =~ "Skip directories"
    end

    test "the Excluded directories card cross-links name-based ignores", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, ~p"/settings?section=library")

      assert html =~ "Excluded directories"
      assert html =~ "Ignored folder names"
    end
  end

  describe "release tracking folded into Acquisition" do
    # One number input doesn't earn a nav item; release tracking feeds
    # auto-grab, so its refresh interval lives on the Acquisition section
    # (settings-coherence). The retired section id keeps a legacy redirect.
    test "there is no Release Tracking nav entry", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings")

      refute has_element?(
               view,
               "[data-nav-zone='sections'] a[href='/settings?section=release_tracking']"
             )
    end

    test "the retired ?section=release_tracking address lands on Acquisition", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=release_tracking")

      assert has_element?(
               view,
               "[data-nav-zone='sections'] a.menu-item-active[href='/settings?section=acquisition']"
             )
    end

    test "saving the refresh interval from Acquisition persists it", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=acquisition")

      view
      |> form("form[phx-submit=save_release_tracking]", %{"refresh_interval_hours" => "12"})
      |> render_submit()

      assert MediaCentaur.Config.get(:release_tracking_refresh_interval_hours) == 12
    end
  end

  describe "save_tmdb retry hook" do
    # Saving a new TMDB key should re-emit `:file_detected` for any
    # `Library.FilePresence` row that has no library link yet — recovery
    # from the silent-drop bug where a transient TMDB auth failure left
    # files stranded between watcher detection and pipeline ingestion.
    alias MediaCentaur.Library.FilePresence
    alias MediaCentaur.Topics

    test "re-emits file_detected for stranded files when key is updated", %{conn: conn} do
      # `rescan_unlinked/0` only re-emits presence rows that still exist on
      # disk (a deleted title leaves the same presence-without-link shape,
      # with nothing to recover) — the fixture needs a real file, not just a
      # stamped path.
      media_dir =
        Path.join(System.tmp_dir!(), "settings_live_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(media_dir)
      on_exit(fn -> File.rm_rf!(media_dir) end)

      stranded_path = Path.join(media_dir, "save-tmdb-stranded.mkv")
      File.write!(stranded_path, "stranded")
      FilePresence.stamp(stranded_path, media_dir)

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.pipeline_input())

      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=tmdb")

      view
      |> form("form[phx-submit='save_tmdb']", %{
        "tmdb_api_key" => "freshly-rotated-key-123"
      })
      |> render_submit()

      assert_receive {:file_detected, %{path: ^stranded_path, media_dir: ^media_dir}}, 1_500
    end

    test "no re-emit when the key field is left blank (no value change)", %{conn: conn} do
      stranded_path = "/tmp/test/save-tmdb-noop.mkv"
      media_dir = "/tmp/test"
      FilePresence.stamp(stranded_path, media_dir)

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.pipeline_input())

      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=tmdb")

      view
      |> form("form[phx-submit='save_tmdb']", %{
        "tmdb_api_key" => ""
      })
      |> render_submit()

      refute_receive {:file_detected, _}, 500
    end
  end

  describe "image repair button" do
    alias MediaCentaur.Library

    test "renders disabled with no badge when nothing is missing", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, ~p"/settings?section=maintenance")

      assert html =~ "Repair missing images"
      assert html =~ "All image files are present on disk"
      # Button is disabled (attr order is component-dependent — match the
      # whole tag and assert both attributes are present on it).
      [button_tag] =
        Regex.run(~r/<button[^>]*phx-click="repair_missing_images"[^>]*>/, html) || [""]

      assert button_tag =~ "disabled"
    end

    test "renders enabled with badge when images are missing", %{conn: conn} do
      movie = Library.Containers.create!(:movie, %{name: "Lost Posters", position: 0})

      Library.Images.create!(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=maintenance")

      # `missing_images_summary` is fetched inside the deferred
      # `start_async_settings_load/1` task; wait for the result.
      html = render_after_async_load(view)

      assert html =~ "Repair missing images"
      assert html =~ "1 missing"
      assert html =~ "Finds 1 image file"
    end

    test "dispatch flips to 'Repairing…' and completes with a flash", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=maintenance")

      # Hand the LiveView a completion message directly — we don't need the
      # background Task.Supervisor path to prove the state-transition wiring.
      send(
        view.pid,
        {:image_repair_complete, %{enqueued: 0, queue_reused: 0, queue_rebuilt: 0, skipped: 0}}
      )

      html = render(view)
      assert html =~ "No missing images — nothing to repair."
    end
  end

  describe "detect download client from Prowlarr" do
    # Prowlarr returns URLs exactly as configured inside Prowlarr. Those
    # hostnames (typically Docker service names like `qbittorrent`) are
    # rarely reachable from the host running media-centaur. The detect
    # flow must therefore pre-fill the form without persisting — the user
    # reviews the URL and confirms with Save. See ADR-037.
    alias MediaCentaur.Config

    test "pre-fills form with detected values but does not persist until save",
         %{conn: conn} do
      # Capture the saved URL before detection so we can assert it is
      # untouched afterwards.
      saved_url_before = Config.get(:download_client_url)

      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=acquisition")

      detected = %{
        name: "qBittorrent",
        type: "qbittorrent",
        url: "http://qbittorrent:8080",
        username: "admin",
        enabled: true
      }

      send(view.pid, {:download_client_detect_result, {:ok, [detected]}})

      html = render(view)

      # Form shows the detected URL as the input value.
      assert html =~ ~s(value="http://qbittorrent:8080")
      assert html =~ ~s(value="admin")

      # Config is NOT updated — the user hasn't clicked Save.
      assert Config.get(:download_client_url) == saved_url_before

      # A flash instructs the user to review and save.
      assert html =~ "review" or html =~ "Review"
    end

    test "empty result shows no clients configured", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=acquisition")

      send(view.pid, {:download_client_detect_result, {:ok, []}})

      html = render(view)
      assert html =~ "no download clients" or html =~ "No download clients"
    end

    test "error result shows connection failure", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=acquisition")

      send(view.pid, {:download_client_detect_result, {:error, :timeout}})

      html = render(view)
      assert html =~ "Couldn&#39;t reach Prowlarr" or html =~ "couldn&#39;t reach Prowlarr"
    end
  end
end
