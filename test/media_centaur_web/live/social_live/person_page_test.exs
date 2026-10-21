defmodule MediaCentaurWeb.SocialLive.PersonPageTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.SocialRows, only: [person: 1, own_person: 0]

  alias MediaCentaur.Social
  alias MediaCentaurWeb.SocialLive.PersonPage

  @friend "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  defp people, do: Map.new([person("Nick"), own_person()], &{&1.pubkey, &1})

  test "path/1: you for the reader, the npub for anyone else" do
    assert PersonPage.path(own_person()) == "/social/friends/you"
    assert PersonPage.path(person("Nick")) == "/social/friends/" <> Social.to_npub(@friend)
  end

  test "find/2: you is the reader's own; an npub or hex key is that person; a bad key or a stranger is nil" do
    assert %{own?: true} = PersonPage.find("you", people())
    assert %{pubkey: @friend} = PersonPage.find(Social.to_npub(@friend), people())
    assert %{pubkey: @friend} = PersonPage.find(@friend, people())
    assert PersonPage.find("npub1nope", people()) == nil

    assert PersonPage.find(
             "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5",
             %{}
           ) == nil

    assert PersonPage.find("you", Map.delete(people(), own_person().pubkey)) == nil
  end
end
