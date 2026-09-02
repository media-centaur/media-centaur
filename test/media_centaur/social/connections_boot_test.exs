defmodule MediaCentaur.Social.ConnectionsBootTest do
  # Boot order: `Connections.Owner` starts inside the supervision tree,
  # but the identity lives in the Settings database and reaches
  # `:persistent_term` only in `Application.post_supervisor_hooks/1`
  # (`Config.load_runtime_overrides/0`). The owner's first reconcile
  # therefore sees no identity and starts nothing; it must reconcile
  # again when the overlay lands.
  use MediaCentaur.DataCase, async: false

  @moduletag :capture_log

  alias MediaCentaur.Social
  alias MediaCentaur.Social.Connections
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Nostr.FakeRelay
  alias MediaCentaur.Settings.Config

  test "relays connect once the runtime config overlay delivers the identity" do
    Identity.ensure()
    relay = FakeRelay.start()
    {:ok, _row} = Social.add_relay(relay.url)

    # The boot-time term predates the database overlay: no identity yet.
    # (The sandbox restores the term after the test.)
    config = :persistent_term.get({Config, :config})
    :persistent_term.put({Config, :config}, Map.put(config, :nostr_secret_key, nil))
    refute Identity.present?()

    owner = start_supervised!({Connections.Owner, backoff_ms: 50})
    Connections.Owner.__sync_for_test__(owner)
    assert Connections.status() == %{}

    Social.subscribe_connections()
    :ok = Config.load_runtime_overrides()
    assert Identity.present?()

    url = relay.url
    assert_receive {:relay_connection, ^url, :connected}, 3_000
    assert %{^url => %{state: :connected}} = Connections.status()
  end
end
