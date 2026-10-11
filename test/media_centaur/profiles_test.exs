defmodule MediaCentaur.ProfilesTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TmpDataDir

  alias MediaCentaur.Library.ProgressRecords
  alias MediaCentaur.Profiles
  alias MediaCentaur.Profiles.Events
  alias MediaCentaur.Profiles.PictureStore
  alias MediaCentaur.Profiles.Profile

  setup :setup_tmp_data_dir

  describe "owner/0" do
    test "owner is the oldest profile" do
      [me] = Profiles.list()
      {:ok, _ana} = Profiles.add("Ana")
      assert Profiles.owner().id == me.id
    end
  end

  test "the upgrade left one owner profile named Me, in Blue" do
    assert [%Profile{name: "Me", hue: 250, picture_at: nil}] = Profiles.list()
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

  test "a profile is born with the first palette hue no one holds; the owner's Blue is skipped" do
    [me] = Profiles.list()
    assert {:ok, %Profile{hue: 12}} = Profiles.add("Ana")
    assert {:ok, %Profile{hue: 45}} = Profiles.add("Bea")
    # A hue changed by hand frees its swatch for the next person.
    assert {:ok, _} = Profiles.set_hue(me, 195)
    assert {:ok, %Profile{hue: 80}} = Profiles.add("Cas")
    assert {:ok, %Profile{hue: 150}} = Profiles.add("Dee")
    assert {:ok, %Profile{hue: 250}} = Profiles.add("Eve")
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

    assert {:ok, %Profile{name: "Sample Name"} = renamed} = Profiles.rename(me, " Sample Name ")
    assert_receive {:profile_changed, %Events.ProfileChanged{profile: %Profile{name: "Sample Name"}}}
    assert {:ok, %Profile{name: "Sample Name"}} = Profiles.rename(renamed, "Sample Name")
    refute_receive {:profile_changed, _}, 50
    assert {:error, :name_required} = Profiles.rename(me, "")

    assert {:ok, %Profile{hue: 195}} = Profiles.set_hue(me, 195)
    assert_receive {:profile_changed, %Events.ProfileChanged{profile: %Profile{hue: 195}}}
    # A profile always has a hue: none is not a choice.
    assert {:error, :invalid_hue} = Profiles.set_hue(me, nil)
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
             "/media-images/images/profiles/#{me.id}.webp?v=#{DateTime.to_unix(at, :microsecond)}"

    assert {:ok, %Profile{picture_at: nil} = without} = Profiles.set_picture(with_picture, :none)
    refute File.exists?(Path.join(data_dir, "images/profiles/#{me.id}.webp"))
    assert Profiles.picture_url(without) == nil
  end

  test "picture_url answers nil when the row has a picture time but the file is missing",
       %{data_dir: data_dir} do
    [me] = Profiles.list()
    {:ok, with_picture} = Profiles.set_picture(me, {:new, "webp-bytes"})
    File.rm!(Path.join(data_dir, "images/profiles/#{me.id}.webp"))
    assert Profiles.picture_url(with_picture) == nil
  end

  test "removing the picture of a profile that has none leaves no file", %{data_dir: data_dir} do
    [me] = Profiles.list()
    assert {:ok, %Profile{picture_at: nil}} = Profiles.set_picture(me, :none)
    refute File.exists?(Path.join(data_dir, "images/profiles/#{me.id}.webp"))
  end

  test "removing an already removed profile answers ok and broadcasts nothing" do
    {:ok, ana} = Profiles.add("Ana")
    Profiles.subscribe()

    assert :ok = Profiles.remove(ana)
    assert_receive {:profile_removed, %Events.ProfileRemoved{}}
    assert :ok = Profiles.remove(ana)
    refute_receive {:profile_removed, _}, 50
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

  test "remove takes the profile's watching rows with it and leaves the other profile's" do
    movie = create_standalone_movie(%{name: "Sample Movie"})
    [me] = Profiles.list()
    {:ok, ana} = Profiles.add("Ana")

    create_watch_progress(%{profile_id: ana.id, movie_id: movie.id, position_seconds: 10.0})
    create_watch_progress(%{profile_id: me.id, movie_id: movie.id, position_seconds: 20.0})
    create_watch_event(%{profile_id: ana.id, movie_id: movie.id, title: "Sample Movie"})
    extra = create_extra(%{movie_id: movie.id, name: "Behind the Scenes"})
    create_extra_progress(%{profile_id: ana.id, extra_id: extra.id, position_seconds: 5.0})

    {:ok, _} =
      MediaCentaur.Library.MediaTrackOverrides.upsert(ana.id, :movie, movie.id, %{audio_lang: "fra"})

    assert :ok = Profiles.remove(ana)

    assert {:error, :not_found} =
             ProgressRecords.fetch_for_container(ana.id, :movie, movie.id)

    assert ProgressRecords.fetch_for_extra(ana.id, extra.id) ==
             {:error, :not_found}

    assert {:ok, %{position_seconds: 20.0}} =
             ProgressRecords.fetch_for_container(me.id, :movie, movie.id)

    assert MediaCentaur.WatchHistory.list_events(ana.id) == []
    assert MediaCentaur.Library.MediaTrackOverrides.get(ana.id, :movie, movie.id) == nil
  end

  test "the social profile schema reads social_profiles and the table carries its unique key" do
    assert MediaCentaur.Social.Profile.__schema__(:source) == "social_profiles"

    %{columns: columns, rows: rows} = Repo.query!("PRAGMA index_list('social_profiles')")
    indexes = Enum.map(rows, &Map.new(Enum.zip(columns, &1)))

    assert [%{"name" => "social_profiles_pubkey_index"}] =
             Enum.filter(indexes, &(&1["unique"] == 1 and &1["origin"] != "pk"))

    %{columns: columns, rows: rows} = Repo.query!("PRAGMA index_info('social_profiles_pubkey_index')")
    assert ["pubkey"] = Enum.map(rows, &Map.new(Enum.zip(columns, &1))["name"])
  end
end
