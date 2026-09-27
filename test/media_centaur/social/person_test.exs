defmodule MediaCentaur.Social.PersonTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Format
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Social.Person

  @friend "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
  @other "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"

  describe "people/0" do
    test "the roster as people: the reader's name, no avatar" do
      {:ok, friend} = Social.add_friend(@friend, "Nick")
      {:ok, _friend} = Social.add_friend(@other, "Cleo")

      people = Social.people()

      assert map_size(people) == 2

      assert %Person{
               pubkey: @friend,
               name_override: "Nick",
               published_name: nil,
               avatar_url: nil,
               own?: false
             } = people[@friend]

      assert people[@friend].short_npub == Social.short_npub(@friend)
      assert people[@friend].added_on == DateTime.to_date(friend.inserted_at)
      assert %Person{name_override: "Cleo", own?: false} = people[@other]
    end

    test "the reader is in the map once an identity exists, and is their own" do
      refute Enum.any?(Social.people(), fn {_pubkey, person} -> person.own? end)

      Identity.ensure()
      me = Identity.pubkey()

      assert %Person{pubkey: ^me, own?: true, name_override: nil, added_on: nil} = Social.people()[me]
      assert Social.people()[me].short_npub == Social.short_npub(me)
      assert Social.people()[me].published_name == nil

      {:ok, _profile} = Social.save_profile("Me")
      assert Social.people()[me].published_name == "Me"
      assert Social.own_person().published_name == "Me"
    end
  end

  describe "own_person/0" do
    test "speaks as the reader before and after an identity exists" do
      assert %Person{pubkey: nil, own?: true, short_npub: nil} = Social.own_person()

      Identity.ensure()
      assert %Person{pubkey: pubkey, own?: true} = Social.own_person()
      assert pubkey == Identity.pubkey()
    end
  end

  test "Format.person_name/1 says You for the reader and the reader's name for a friend" do
    assert Format.person_name(%Person{pubkey: "me", own?: true}) == "You"
    assert Format.person_name(%Person{pubkey: @friend, name_override: "Nick"}) == "Nick"
  end

  test "Person.name/1 is the override, else the published name, else nil" do
    assert Person.name(%Person{pubkey: @friend, name_override: "Nick", published_name: "Nicholas"}) ==
             "Nick"

    assert Person.name(%Person{pubkey: @friend, published_name: "Nicholas"}) == "Nicholas"
    assert Person.name(%Person{pubkey: @friend}) == nil
  end

  test "Format.person_name/1 says You, the name, or Unnamed" do
    assert Format.person_name(%Person{pubkey: "me", own?: true}) == "You"

    assert Format.person_name(%Person{
             pubkey: @friend,
             name_override: "Nick",
             published_name: "Nicholas"
           }) == "Nick"

    assert Format.person_name(%Person{pubkey: @friend, published_name: "Nicholas"}) == "Nicholas"
    assert Format.person_name(%Person{pubkey: @friend}) == "Unnamed"
  end

  test "short_npub/1 elides the middle" do
    short = Social.short_npub(@friend)

    npub = Social.to_npub(@friend)

    assert String.starts_with?(short, String.slice(npub, 0, 9))
    assert String.contains?(short, "…")
    assert String.ends_with?(short, String.slice(npub, -4..-1//1))
    assert String.length(short) == 14
  end
end
