defmodule MediaCentarrWeb.AcquisitionReadyNavTest do
  @moduledoc """
  Closes the loop on the architectural fix that made the Downloads nav
  item appear in real time when capabilities become ready.

  Two pieces of behaviour are asserted:

    * **Real-time visibility.** A connected LiveView whose
      `:acquisition_ready` is initially false renders without the
      Downloads link; a `:capabilities_changed` broadcast (after the
      cache is flipped to ready) re-renders the page WITH the link, no
      reload required.
    * **Boot-order recovery.** Mounting after the persistent_term cache
      has been seeded `false` (the post-restart state before runtime
      config overlays have triggered a refresh) and AFTER a config
      change broadcast wakes the worker, the rendered nav contains the
      Downloads link — i.e. the `config_updates` reactivity edge closed
      the data dependency that used to require a manual Test click.
  """

  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentarr.Capabilities
  alias MediaCentarr.Config
  alias MediaCentarr.Topics

  @cache_key {Capabilities, :ready_flags}
  @ready_true %{tmdb: true, prowlarr: true, download_client: true, acquisition: true}
  @ready_false %{tmdb: false, prowlarr: false, download_client: false, acquisition: false}

  setup do
    config_backup = :persistent_term.get({Config, :config})
    cache_backup = :persistent_term.get(@cache_key, :__unset)

    on_exit(fn ->
      :persistent_term.put({Config, :config}, config_backup)

      case cache_backup do
        :__unset -> :persistent_term.erase(@cache_key)
        flags -> :persistent_term.put(@cache_key, flags)
      end
    end)

    :ok
  end

  test "Downloads nav appears in real time when :capabilities_changed flips the cache",
       %{conn: conn} do
    :persistent_term.put(@cache_key, @ready_false)

    {:ok, view, html} = live(conn, "/")
    refute html =~ "Downloads"

    :persistent_term.put(@cache_key, @ready_true)
    Phoenix.PubSub.broadcast(MediaCentarr.PubSub, Topics.capabilities_updates(), :capabilities_changed)

    assert render(view) =~ "Downloads"
  end

  test "boot-order race: empty cache + later config_updated yields visible nav after refresh",
       %{conn: conn} do
    Capabilities.save_test_result(:prowlarr, :ok)
    Capabilities.save_test_result(:download_client, :ok)

    Config.update(:prowlarr_url, "http://prowlarr.boot")
    Config.update(:prowlarr_api_key, "k-boot")
    Config.update(:download_client_type, "qbittorrent")
    Config.update(:download_client_url, "http://qbit.boot")

    :persistent_term.put(@cache_key, @ready_false)

    {:ok, view, html} = live(conn, "/")
    refute html =~ "Downloads"

    Capabilities.refresh_cache()

    Phoenix.PubSub.broadcast(MediaCentarr.PubSub, Topics.capabilities_updates(), :capabilities_changed)

    assert render(view) =~ "Downloads"
  end
end
