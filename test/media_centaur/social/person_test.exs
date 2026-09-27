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

      assert %Person{pubkey: @friend, name_override: "Nick", avatar_url: nil, own?: false} =
               people[@friend]

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

  # A friend without a name is not a phase-1 Person; the clause is
  # unmatched on purpose. Phase 2 flips this test when it adds "Unnamed"
  # together with the optional name.
  test "Format.person_name/1 has no words yet for a friend without a name" do
    # Called dynamically: the compiler's type checker would otherwise
    # warn that no clause accepts the argument, which is the point.
    nameless = %Person{pubkey: @friend, name_override: nil}
    words = :person_name

    assert_raise FunctionClauseError, fn -> apply(Format, words, [nameless]) end
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
