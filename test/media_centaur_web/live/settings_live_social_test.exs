defmodule MediaCentaurWeb.SettingsLiveSocialTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TmpDataDir
  import Phoenix.LiveViewTest

  alias MediaCentaur.Social
  alias MediaCentaur.Social.AvatarStore
  alias MediaCentaur.Social.Events
  alias MediaCentaur.Social.Hue
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Secret
  alias MediaCentaur.Settings.Preferences.ShareWatchlist
  alias MediaCentaur.Settings.Preferences.ShareWatched
  alias MediaCentaurWeb.SettingsLive.SocialSection

  @section "/settings?section=social"

  describe "profile" do
    # The avatar master lands under `{data_dir}/images/social/`.
    setup :setup_tmp_data_dir

    test "opening Social mints nothing; Create profile mints the identity and shows the other cards",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, @section)
      refute Identity.present?()
      assert has_element?(view, "#profile-form button", "Create profile")
      refute has_element?(view, "#identity-npub")
      refute has_element?(view, "#add-relay-form")
      refute has_element?(view, "#social-sharing")

      view |> form("#profile-form", %{"name" => "   "}) |> render_submit()
      assert render(view) =~ "Your profile needs a name"
      refute Identity.present?()

      # The input's maxlength stops this in a browser; a crafted submit must not crash the view.
      view |> form("#profile-form", %{"name" => String.duplicate("x", 51)}) |> render_submit()
      assert render(view) =~ "Names are at most 50 characters"
      refute Identity.present?()

      view |> form("#profile-form", %{"name" => "Sample Name"}) |> render_submit()
      assert Identity.present?()
      assert render(view) =~ "Profile saved"
      assert has_element?(view, "#identity-npub", Identity.npub())
      assert has_element?(view, "#copy-npub[data-copy-text='#{Identity.npub()}']")
      assert has_element?(view, "#add-relay-form")
      assert has_element?(view, "#social-sharing")
      assert has_element?(view, "#profile-form input[name='name'][value='Sample Name']")
      assert has_element?(view, "#profile-form button", "Save")
      assert %{name: "Sample Name"} = Social.own_profile()
    end

    test "an identity without a profile shows both cards, the name empty", %{conn: conn} do
      Identity.ensure()
      {:ok, view, _html} = live_async!(conn, @section)
      assert has_element?(view, "#identity-npub")
      assert has_element?(view, "#profile-form input[name='name']:not([value])")
      assert has_element?(view, "#profile-form button", "Save")
    end

    test "a profile saved in another tab shows here", %{conn: conn} do
      Identity.ensure()
      {:ok, tab_a, _html} = live_async!(conn, @section)
      {:ok, tab_b, _html} = live_async!(conn, @section)

      tab_b |> form("#profile-form", %{"name" => "Sample Name"}) |> render_submit()

      render_until(tab_a, fn _html ->
        has_element?(tab_a, "#profile-form input[name='name'][value='Sample Name']")
      end)
    end

    test "other sections do not mint an identity", %{conn: conn} do
      {:ok, _view, _html} = live_async!(conn, "/settings?section=tmdb")
      refute Identity.present?()
    end

    test "choosing a picture and saving publishes a 256×256 WebP avatar; Remove clears it",
         %{conn: conn} do
      Identity.ensure()
      {:ok, view, _html} = live_async!(conn, @section)
      {:ok, img} = Image.new(400, 300, color: :blue)
      {:ok, png} = Image.write(img, :memory, suffix: ".png")

      upload =
        file_input(view, "#profile-form", :avatar, [
          %{name: "me.png", content: png, type: "image/png"}
        ])

      assert render_upload(upload, "me.png") =~ "me.png"
      view |> form("#profile-form", %{"name" => "Sample Name"}) |> render_submit()

      me = Identity.pubkey()
      assert %{avatar_type: "image/webp"} = Social.own_profile()
      {:ok, bytes} = AvatarStore.read(me, "image/webp")
      {:ok, back} = Image.from_binary(bytes)
      assert {256, 256, _bands} = Image.shape(back)
      assert has_element?(view, "#profile-form [data-component='identity-tile'][data-mark='avatar']")
      assert has_element?(view, "#remove-avatar")

      view |> element("#remove-avatar") |> render_click()
      assert has_element?(view, "#profile-form [data-component='identity-tile'][data-mark='letter']")
      assert %{avatar_type: "image/webp"} = Social.own_profile()

      view |> form("#profile-form", %{"name" => "Sample Name"}) |> render_submit()
      assert %{avatar_type: nil} = Social.own_profile()
      assert AvatarStore.read(me, "image/webp") == {:error, :enoent}
      assert has_element?(view, "#profile-form [data-component='identity-tile'][data-mark='letter']")
      refute has_element?(view, "#remove-avatar")
    end

    test "a file that is not an image is refused before anything is saved", %{conn: conn} do
      Identity.ensure()
      {:ok, view, _html} = live_async!(conn, @section)

      upload =
        file_input(view, "#profile-form", :avatar, [
          %{name: "notes.txt", content: "hello", type: "text/plain"}
        ])

      assert {:error, [[_ref, :not_accepted]]} = render_upload(upload, "notes.txt")
      assert Social.own_profile() == nil
    end

    test "a picture the app cannot read is consumed and refused; nothing is saved", %{conn: conn} do
      Identity.ensure()
      {:ok, view, _html} = live_async!(conn, @section)

      upload =
        file_input(view, "#profile-form", :avatar, [
          %{name: "x.png", content: "hello", type: "image/png"}
        ])

      assert render_upload(upload, "x.png") =~ "x.png"
      html = view |> form("#profile-form", %{"name" => "Sample Name"}) |> render_submit()

      assert html =~ "That file is not a picture we can read"
      # The consumed entry drops on the channel's next pass, after the reply.
      refute render(view) =~ "x.png"
      assert Social.own_profile() == nil
    end

    test "a name error leaves the chosen picture pending for the next save", %{conn: conn} do
      Identity.ensure()
      {:ok, view, _html} = live_async!(conn, @section)
      {:ok, img} = Image.new(64, 64, color: :red)
      {:ok, png} = Image.write(img, :memory, suffix: ".png")

      upload =
        file_input(view, "#profile-form", :avatar, [
          %{name: "me.png", content: png, type: "image/png"}
        ])

      assert render_upload(upload, "me.png") =~ "me.png"
      html = view |> form("#profile-form", %{"name" => "   "}) |> render_submit()
      assert html =~ "Your profile needs a name"
      assert html =~ "me.png"
      assert Social.own_profile() == nil

      view |> form("#profile-form", %{"name" => "Sample Name"}) |> render_submit()
      assert %{avatar_type: "image/webp"} = Social.own_profile()
    end

    test "Remove steps aside while a picture is chosen", %{conn: conn} do
      Identity.ensure()
      {:ok, img} = Image.new(64, 64, color: :red)
      {:ok, png} = Image.write(img, :memory, suffix: ".png")
      {:ok, _profile} = Social.save_profile("Sample Name", {:new, png_to_webp(png)}, nil)
      {:ok, view, _html} = live_async!(conn, @section)
      assert has_element?(view, "#remove-avatar")

      upload =
        file_input(view, "#profile-form", :avatar, [
          %{name: "next.png", content: png, type: "image/png"}
        ])

      assert render_upload(upload, "next.png") =~ "next.png"
      refute has_element?(view, "#remove-avatar")
    end

    test "a new profile's form starts on a palette hue; a swatch or the slider changes it; Save publishes it",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, @section)
      tile = "#profile-form [data-component='identity-tile']"

      [seed] =
        view |> element(tile) |> render() |> LazyHTML.from_fragment() |> LazyHTML.attribute("data-hue")

      assert String.to_integer(seed) in Enum.map(Hue.palette(), &elem(&1, 1))
      assert has_element?(view, "#profile-hues button[data-hue='#{seed}'][aria-pressed='true']")

      view |> element("#profile-hues button[data-hue='195']") |> render_click()
      assert has_element?(view, tile <> "[data-hue='195']")
      assert has_element?(view, "#profile-hues input[name='hue'][value='195']")

      view |> form("#profile-form", %{"hue" => "100"}) |> render_change(%{"_target" => ["hue"]})
      assert has_element?(view, tile <> "[data-hue='100']")
      refute has_element?(view, "#profile-hues button[aria-pressed='true']")

      view |> form("#profile-form", %{"name" => "Sample Name"}) |> render_submit()
      assert %{hue: 100} = Social.own_profile()
      assert has_element?(view, tile <> "[data-hue='100']")
    end

    test "a saved hue loads as saved; a profile saved before hues seeds one for the form only", %{
      conn: conn
    } do
      {:ok, _profile} = Social.save_profile("Sample Name", :keep, 290)
      {:ok, view, _html} = live_async!(conn, @section)
      assert has_element?(view, "#profile-form [data-component='identity-tile'][data-hue='290']")
      assert has_element?(view, "#profile-hues button[data-hue='290'][aria-pressed='true']")

      {:ok, _profile} = Social.save_profile("Sample Name", :keep, nil)
      {:ok, view, _html} = live_async!(conn, @section)
      assert has_element?(view, "#profile-form [data-component='identity-tile'][data-hue]")
      assert %{hue: nil} = Social.own_profile()
    end

    test "the name field is 16rem with Save beside it, not the card's width", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, @section)
      assert has_element?(view, "#profile-form input[name='name'].max-w-64")
      refute has_element?(view, "#profile-form input[name='name'].flex-1")
    end
  end

  defp png_to_webp(png) do
    {:ok, img} = Image.from_binary(png)
    {:ok, webp} = Image.write(img, :memory, suffix: ".webp")
    webp
  end

  describe "identity" do
    setup do
      Identity.ensure()
      :ok
    end

    test "the npub shows with a copy control; the secret key does not", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, @section)

      assert has_element?(view, "#identity-npub", Identity.npub())
      assert has_element?(view, "#copy-npub[data-copy-text='#{Identity.npub()}']")
      refute render(view) =~ Identity.export_nsec()
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

    test "importing a secret key replaces the identity after a second click and forgets the old profile",
         %{conn: conn} do
      {:ok, _profile} = Social.save_profile("Sample Name", :keep, nil)
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
      assert Social.own_profile() == nil
      assert has_element?(view, "#profile-form input[name='name']:not([value])")
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

    setup do
      Identity.ensure()
      :ok
    end

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

    test "connection state updates live; the row's dot follows it", %{conn: conn} do
      {:ok, _relay} = Social.add_relay(@relay_url)
      {:ok, view, _html} = live_async!(conn, @section)
      assert has_element?(view, relay_row(), "Not connected")
      assert has_element?(view, relay_row() <> " .bg-error")

      # The owner is not started under :test — stand in for its re-broadcast.
      Events.broadcast_connection(@relay_url, :connected)
      render_until(view, fn _html -> has_element?(view, relay_row(), "Connected") end)
      assert has_element?(view, relay_row() <> " .bg-success")

      Events.broadcast_connection(@relay_url, {:auth, {:failed, "not on the allowlist"}})
      render_until(view, fn _html -> has_element?(view, relay_row(), "Rejected") end)
      assert has_element?(view, relay_row() <> " .bg-error")
      assert has_element?(view, relay_row(), "not on the allowlist")
    end

    test "the section is four cards, Your profile first", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, @section)

      for title <- ["Your profile", "Your identity", "Relays", "Sharing"] do
        assert has_element?(view, "#settings-social h3", title)
      end

      assert has_element?(view, "#settings-social > div:first-child h3", "Your profile")
    end
  end

  describe "sharing" do
    setup do
      Identity.ensure()
      :ok
    end

    test "both toggles start off and flip their preference", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, @section)
      refute ShareWatched.enabled?()
      refute ShareWatchlist.enabled?()
      refute has_element?(view, "#social-sharing [phx-click='toggle_share_watched'] input:checked")
      refute has_element?(view, "#social-sharing [phx-click='toggle_share_watchlist'] input:checked")

      view |> element("#social-sharing [phx-click='toggle_share_watched']") |> render_click()
      assert ShareWatched.enabled?()
      refute ShareWatchlist.enabled?()
      assert has_element?(view, "#social-sharing [phx-click='toggle_share_watched'] input:checked")

      view |> element("#social-sharing [phx-click='toggle_share_watchlist']") |> render_click()
      assert ShareWatchlist.enabled?()
      assert has_element?(view, "#social-sharing [phx-click='toggle_share_watchlist'] input:checked")

      view |> element("#social-sharing [phx-click='toggle_share_watched']") |> render_click()
      refute ShareWatched.enabled?()
      refute has_element?(view, "#social-sharing [phx-click='toggle_share_watched'] input:checked")
    end

    test "the toggles are named for what they share", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, @section)
      assert has_element?(view, "#social-sharing", "Share what you watch")
      assert has_element?(view, "#social-sharing", "Share your watchlist")
      assert has_element?(view, "#social-sharing", "A title you list is shared with your friends")
      refute render(view) =~ "Share what you track"
    end

    test "a stored preference renders as on", %{conn: conn} do
      ShareWatchlist.set(true)
      {:ok, view, _html} = live_async!(conn, @section)
      assert has_element?(view, "#social-sharing [phx-click='toggle_share_watchlist'] input:checked")
      refute has_element?(view, "#social-sharing [phx-click='toggle_share_watched'] input:checked")
    end
  end
end
