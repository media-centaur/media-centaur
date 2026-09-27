defmodule MediaCentaur.Social.Profile.TranslationTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Secret
  alias MediaCentaur.Social.Profile.Translation

  @secret Secret.wrap(String.duplicate("0", 63) <> "3")
  @pubkey Keys.pubkey(@secret)

  defp signed(content, created_at \\ 1_700_000_000) do
    Event.sign(
      Event.new(%{pubkey: @pubkey, created_at: created_at, kind: 12_160, tags: [], content: content}),
      @secret
    )
  end

  test "kind/0 is 12160, the first of the replaceable block" do
    assert Translation.kind() == 12_160
  end

  test "to_event/3 builds an unsigned profile with the name and version, no tags" do
    event = Translation.to_event("Sample Name", @pubkey, 1_700_000_000)

    assert %Event{kind: 12_160, tags: [], pubkey: @pubkey, created_at: 1_700_000_000} = event
    assert Jason.decode!(event.content) == %{"v" => 1, "name" => "Sample Name"}
  end

  test "to_event/3 leaves an absent name off the wire" do
    assert Jason.decode!(Translation.to_event(nil, @pubkey, 1).content) == %{"v" => 1}
  end

  test "from_event/1 reads the name, the raw event and the wire time; a missing name is nil" do
    event = signed(~s({"v":1,"name":"  Sample Name  "}))

    assert {:ok, %{pubkey: @pubkey, name: "Sample Name", created_at: 1_700_000_000, raw_event: raw}} =
             Translation.from_event(event)

    assert raw == Event.to_map(event)
    assert {:ok, %{name: nil}} = Translation.from_event(signed(~s({"v":1})))
    assert {:ok, %{name: nil}} = Translation.from_event(signed(~s({"v":1,"name":"   "})))
  end

  test "from_event/1 drops the malformed whole: wrong kind, bad JSON, a name over the cap, an unknown version" do
    other =
      Event.sign(
        Event.new(%{pubkey: @pubkey, created_at: 1, kind: 32_164, tags: [], content: "{}"}),
        @secret
      )

    assert {:error, :wrong_kind} = Translation.from_event(other)
    assert {:error, :bad_content} = Translation.from_event(signed("not json"))

    assert {:error, :bad_content} =
             Translation.from_event(signed(~s({"v":1,"name":"#{String.duplicate("x", 51)}"})))

    assert {:error, :bad_content} = Translation.from_event(signed(~s({"v":1,"name":7})))
    assert {:error, :unsupported_version} = Translation.from_event(signed(~s({"v":2,"name":"x"})))
  end

  test "an unknown field is ignored and a name at the cap passes" do
    name = String.duplicate("x", 50)

    assert {:ok, %{name: ^name}} =
             Translation.from_event(signed(~s({"v":1,"name":"#{name}","later":true})))
  end
end
