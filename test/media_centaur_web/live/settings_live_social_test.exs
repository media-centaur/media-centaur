defmodule MediaCentaurWeb.SettingsLiveSocialTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Social
  alias MediaCentaur.Social.Events
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Secret
  alias MediaCentaurWeb.SettingsLive.SocialSection

  @section "/settings?section=social"

  describe "identity" do
    test "opening the section generates an identity and shows the npub with a copy control", %{
      conn: conn
    } do
      refute Identity.present?()
      {:ok, view, _html} = live_async!(conn, @section)

      assert Identity.present?()
      assert has_element?(view, "#identity-npub", Identity.npub())
      assert has_element?(view, "#copy-npub[data-copy-text='#{Identity.npub()}']")
      refute render(view) =~ Identity.export_nsec()
    end

    test "other sections do not mint an identity", %{conn: conn} do
      {:ok, _view, _html} = live_async!(conn, "/settings?section=tmdb")
      refute Identity.present?()
    end

    test "the secret key is revealed only on request", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, @section)
      nsec = Identity.export_nsec()

      refute render(view) =~ nsec
      view |> element("#reveal-nsec") |> render_click()
      assert has_element?(view, "#identity-nsec", nsec)
      assert has_element?(view, "#copy-nsec[data-copy-text='#{nsec}']")

      view |> element("#hide-nsec") |> render_click()
      refute render(view) =~ nsec
    end

    test "importing a secret key replaces the identity after a second click", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, @section)
      before = Identity.pubkey()
      nsec = Keys.to_nsec(Secret.wrap(String.duplicate("0", 63) <> "3"))

      view |> form("#import-nsec-form", %{"nsec" => nsec}) |> render_submit()
      assert has_element?(view, "#import-nsec-submit", "Click again to replace")
      assert has_element?(view, "#import-nsec", nsec)
      assert Identity.pubkey() == before

      view |> form("#import-nsec-form", %{"nsec" => nsec}) |> render_submit()
      assert Identity.pubkey() == "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
      assert render(view) =~ "Identity replaced"
      assert has_element?(view, "#identity-npub", Identity.npub())
      refute has_element?(view, "#import-nsec", nsec)
    end

    test "replacing the identity in another tab clears the revealed key and the arm", %{conn: conn} do
      {:ok, tab_a, _html} = live_async!(conn, @section)
      {:ok, tab_b, _html} = live_async!(conn, @section)

      old_nsec = Identity.export_nsec()
      tab_a |> element("#reveal-nsec") |> render_click()
      assert has_element?(tab_a, "#identity-nsec", old_nsec)

      tab_a |> form("#import-nsec-form", %{"nsec" => old_nsec}) |> render_submit()
      assert has_element?(tab_a, "#import-nsec-submit", "Click again to replace")

      replacement = Keys.to_nsec(Secret.wrap(String.duplicate("0", 63) <> "3"))
      tab_b |> form("#import-nsec-form", %{"nsec" => replacement}) |> render_submit()
      tab_b |> form("#import-nsec-form", %{"nsec" => replacement}) |> render_submit()

      render_until(tab_a, fn _html -> not has_element?(tab_a, "#identity-nsec", old_nsec) end)
      assert has_element?(tab_a, "#import-nsec-submit", "Replace identity")
      refute has_element?(tab_a, "#import-nsec", old_nsec)
    end

    test "an invalid secret key is refused with a flash", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, @section)
      before = Identity.pubkey()

      view |> form("#import-nsec-form", %{"nsec" => "nsec1nope"}) |> render_submit()
      view |> form("#import-nsec-form", %{"nsec" => "nsec1nope"}) |> render_submit()

      assert render(view) =~ "That is not a valid secret key"
      assert has_element?(view, "#import-nsec-submit", "Replace identity")
      assert Identity.pubkey() == before
    end
  end

  describe "relays" do
    @relay_url "wss://relay.example/"

    defp relay_row, do: "#" <> SocialSection.relay_dom_id(@relay_url)

    test "lists relays with their connection state, adds by URL, and removes", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, @section)

      view |> form("#add-relay-form", %{"url" => "wss://relay.example"}) |> render_submit()
      assert has_element?(view, relay_row(), @relay_url)
      assert has_element?(view, relay_row(), "Not connected")
      assert [%{url: @relay_url}] = Social.list_relays()

      view |> element(relay_row() <> " button", "Remove") |> render_click()
      refute has_element?(view, relay_row())
      assert Social.list_relays() == []
    end

    test "an invalid relay address is refused with a flash", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, @section)
      view |> form("#add-relay-form", %{"url" => "https://relay.example"}) |> render_submit()
      assert render(view) =~ "Relay addresses start with wss:// or ws://"
      assert Social.list_relays() == []
    end

    test "connection state updates live and lights the section's status dot", %{conn: conn} do
      {:ok, _relay} = Social.add_relay(@relay_url)
      {:ok, view, _html} = live_async!(conn, @section)
      assert has_element?(view, relay_row(), "Not connected")
      assert has_element?(view, "#settings-social [aria-label='Not configured']")

      # The owner is not started under :test — stand in for its re-broadcast.
      Events.broadcast_connection(@relay_url, :connected)
      render_until(view, fn _html -> has_element?(view, relay_row(), "Connected") end)
      assert has_element?(view, "#settings-social [aria-label='Configured']")

      Events.broadcast_connection(@relay_url, {:auth, {:failed, "not on the allowlist"}})
      render_until(view, fn _html -> has_element?(view, relay_row(), "Rejected") end)
      assert has_element?(view, relay_row(), "not on the allowlist")
    end
  end
end
