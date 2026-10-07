defmodule MediaCentaurWeb.SettingsLiveProfilesTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import MediaCentaur.TmpDataDir
  import Phoenix.LiveViewTest

  alias MediaCentaur.Profiles
  alias MediaCentaur.Profiles.PictureStore

  @section "/settings?section=profiles"

  # The picture master lands under `{data_dir}`.
  setup :setup_tmp_data_dir

  defp card(id), do: "#profile-card-#{id}"

  test "one card per profile, Remove disabled on the last one, and an Add card", %{conn: conn} do
    [me] = Profiles.list()
    {:ok, view, _html} = live_async!(conn, @section)
    assert has_element?(view, "#{card(me.id)} h3", "Me")
    assert has_element?(view, "#remove-profile-#{me.id}[disabled]")
    assert has_element?(view, "#add-profile")
  end

  test "Add adds a card; the hook keeps the list live", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, @section)
    view |> form("#settings-add-profile-form", %{"name" => "Ana"}) |> render_submit()
    assert render(view) =~ "Ana added"
    [_me, ana] = Profiles.list()
    render_until(view, fn _html -> has_element?(view, "#{card(ana.id)} h3", "Ana") end)
    refute has_element?(view, "#remove-profile-#{ana.id}[disabled]")
  end

  test "the name saves on blur and on Enter; a blank one is refused in words", %{conn: conn} do
    [me] = Profiles.list()
    {:ok, view, _html} = live_async!(conn, @section)

    view |> element("#profile-name-#{me.id}") |> render_blur(%{"value" => " Sample Name "})
    assert %{name: "Sample Name"} = Profiles.get(me.id)

    view
    |> element("#profile-name-#{me.id}")
    |> render_keydown(%{"key" => "Enter", "value" => "Ana"})

    assert %{name: "Ana"} = Profiles.get(me.id)

    # The name stands in no form: inside one, a blur debounce would hold
    # Enter until focus leaves, and Enter would submit the form (with the
    # picture field open, its Save). LiveViewTest exercises neither client
    # debounce nor implicit submission, so the shape is what is asserted.
    refute has_element?(view, "form #profile-name-#{me.id}")

    view |> element("#profile-name-#{me.id}") |> render_blur(%{"value" => "  "})
    assert render(view) =~ "A profile needs a name"
    assert %{name: "Ana"} = Profiles.get(me.id)
  end

  test "a swatch and the slider set the hue", %{conn: conn} do
    [me] = Profiles.list()
    {:ok, view, _html} = live_async!(conn, @section)

    view |> element("#profile-hues-#{me.id} button[data-hue='195']") |> render_click()
    assert %{hue: 195} = Profiles.get(me.id)

    view
    |> form("#profile-hue-form-#{me.id}")
    |> render_change(%{"_target" => ["hue"], "hue" => "12"})

    assert %{hue: 12} = Profiles.get(me.id)
  end

  test "a picture is chosen, cropped, saved, then removed", %{conn: conn, data_dir: data_dir} do
    [me] = Profiles.list()
    {:ok, view, _html} = live_async!(conn, @section)

    view |> element("#edit-profile-picture-#{me.id}") |> render_click()

    upload =
      file_input(view, "#profile-picture-form-#{me.id}", :profile_picture, [
        %{name: "me.png", content: sample_png(), type: "image/png"}
      ])

    assert render_upload(upload, "me.png") =~ "me.png"
    view |> form("#profile-picture-form-#{me.id}") |> render_submit()

    assert %{picture_at: %DateTime{}} = Profiles.get(me.id)

    {:ok, back} =
      Image.from_binary(File.read!(Path.join(data_dir, PictureStore.relative_path(me.id))))

    assert {256, 256, _bands} = Image.shape(back)
    assert has_element?(view, "#{card(me.id)} [data-component='identity-tile'][data-mark='avatar']")

    view |> element("#edit-profile-picture-#{me.id}") |> render_click()
    view |> element("#remove-profile-picture-#{me.id}") |> render_click()
    view |> form("#profile-picture-form-#{me.id}") |> render_submit()
    assert %{picture_at: nil} = Profiles.get(me.id)
    refute File.exists?(Path.join(data_dir, PictureStore.relative_path(me.id)))
  end

  test "Remove profile arms, then removes", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, @section)
    ana = create_profile(name: "Ana")
    render_until(view, fn _html -> has_element?(view, card(ana.id)) end)

    view |> element("#remove-profile-#{ana.id}") |> render_click()
    assert has_element?(view, "#remove-profile-#{ana.id}", "Click again to remove")
    assert Profiles.get(ana.id)

    view |> element("#remove-profile-#{ana.id}") |> render_click()
    assert Profiles.get(ana.id) == nil
    assert render(view) =~ "Ana removed"
    render_until(view, fn _html -> not has_element?(view, card(ana.id)) end)
  end

  test "one upload serves every card: opening another card drops the first card's file",
       %{conn: conn} do
    [me] = Profiles.list()
    {:ok, view, _html} = live_async!(conn, @section)
    ana = create_profile(name: "Ana")
    render_until(view, fn _html -> has_element?(view, card(ana.id)) end)

    view |> element("#edit-profile-picture-#{me.id}") |> render_click()
    choose_picture(view, me.id)

    view |> element("#edit-profile-picture-#{ana.id}") |> render_click()
    refute has_element?(view, "#profile-picture-form-#{me.id}")
    refute has_element?(view, "#profile-picture-form-#{ana.id} [data-role='pending-picture']")

    choose_picture(view, ana.id)
    view |> form("#profile-picture-form-#{ana.id}") |> render_submit()

    assert %{picture_at: %DateTime{}} = Profiles.get(ana.id)
    assert %{picture_at: nil} = Profiles.get(me.id)
  end

  defp choose_picture(view, id) do
    upload =
      file_input(view, "#profile-picture-form-#{id}", :profile_picture, [
        %{name: "me.png", content: sample_png(), type: "image/png"}
      ])

    assert render_upload(upload, "me.png") =~ "me.png"
  end

  defp sample_png do
    {:ok, img} = Image.new(400, 300, color: :blue)
    {:ok, png} = Image.write(img, :memory, suffix: ".png")
    png
  end
end
