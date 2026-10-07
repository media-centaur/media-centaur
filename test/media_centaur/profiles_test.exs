defmodule MediaCentaur.ProfilesTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TmpDataDir

  alias MediaCentaur.Profiles
  alias MediaCentaur.Profiles.Events
  alias MediaCentaur.Profiles.PictureStore
  alias MediaCentaur.Profiles.Profile

  setup :setup_tmp_data_dir

  test "the upgrade left one owner profile named Me" do
    assert [%Profile{name: "Me", hue: nil, picture_at: nil}] = Profiles.list()
    assert Profiles.count() == 1
  end

  test "add trims and checks the name, orders by creation, caps at eight, and broadcasts" do
    Profiles.subscribe()
    assert {:ok, %Profile{name: "Ana"} = ana} = Profiles.add("  Ana ")
    assert_receive {:profile_added, %Events.ProfileAdded{profile: %Profile{id: id}}}
    assert id == ana.id
    assert ["Me", "Ana"] = Enum.map(Profiles.list(), & &1.name)

    assert {:error, :name_required} = Profiles.add("   ")
    assert {:error, :name_too_long} = Profiles.add(String.duplicate("x", 51))

    for n <- 3..8, do: assert({:ok, _} = Profiles.add("Person #{n}"))
    assert {:error, :too_many_profiles} = Profiles.add("One too many")
    assert Profiles.count() == 8
  end

  test "get takes an id, and answers nil for an unknown or malformed one" do
    [me] = Profiles.list()
    assert %Profile{name: "Me"} = Profiles.get(me.id)
    assert Profiles.get(Ecto.UUID.generate()) == nil
    assert Profiles.get("not-a-uuid") == nil
  end

  test "rename and set_hue save on the act and broadcast; a bad hue is refused" do
    [me] = Profiles.list()
    Profiles.subscribe()

    assert {:ok, %Profile{name: "Sample Name"}} = Profiles.rename(me, " Sample Name ")
    assert_receive {:profile_changed, %Events.ProfileChanged{profile: %Profile{name: "Sample Name"}}}
    assert {:error, :name_required} = Profiles.rename(me, "")

    assert {:ok, %Profile{hue: 195}} = Profiles.set_hue(me, 195)
    assert_receive {:profile_changed, %Events.ProfileChanged{profile: %Profile{hue: 195}}}
    assert {:ok, %Profile{hue: nil}} = Profiles.set_hue(me, nil)
    assert {:error, :invalid_hue} = Profiles.set_hue(me, 360)
  end

  test "a picture is one file per profile; the URL carries the row's version; none removes it",
       %{data_dir: data_dir} do
    [me] = Profiles.list()
    assert Profiles.picture_url(me) == nil

    assert {:ok, %Profile{picture_at: %DateTime{} = at} = with_picture} =
             Profiles.set_picture(me, {:new, "webp-bytes"})

    assert File.read!(Path.join(data_dir, "images/profiles/#{me.id}.webp")) == "webp-bytes"

    assert Profiles.picture_url(with_picture) ==
             "/media-images/images/profiles/#{me.id}.webp?v=#{DateTime.to_unix(at)}"

    assert {:ok, %Profile{picture_at: nil} = without} = Profiles.set_picture(with_picture, :none)
    refute File.exists?(Path.join(data_dir, "images/profiles/#{me.id}.webp"))
    assert Profiles.picture_url(without) == nil
  end

  test "remove refuses the last profile, otherwise deletes the row and the picture and broadcasts",
       %{data_dir: data_dir} do
    [me] = Profiles.list()
    assert {:error, :last_profile} = Profiles.remove(me)

    {:ok, ana} = Profiles.add("Ana")
    {:ok, ana} = Profiles.set_picture(ana, {:new, "webp-bytes"})
    Profiles.subscribe()

    assert :ok = Profiles.remove(ana)
    assert_receive {:profile_removed, %Events.ProfileRemoved{id: id}}
    assert id == ana.id
    assert Profiles.get(ana.id) == nil
    refute File.exists?(Path.join(data_dir, "images/profiles/#{ana.id}.webp"))
    assert PictureStore.url(ana.id, 1) == nil
  end

  test "the social profiles table kept its rows and its unique key" do
    assert MediaCentaur.Social.Profile.__schema__(:source) == "social_profiles"
  end
end
