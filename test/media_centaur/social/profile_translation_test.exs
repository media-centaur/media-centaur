defmodule MediaCentaur.Social.Profile.TranslationTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Secret
  alias MediaCentaur.Social.Profile.Translation

  @secret Secret.wrap(String.duplicate("0", 63) <> "3")
  @pubkey Keys.pubkey(@secret)

  @webp <<"RIFF", 0, 0, 0, 0, "WEBPVP8 ", 0, 0, 0, 0>>
  @png <<0x89, "PNG\r\n", 0x1A, 0x0A, 0, 0, 0, 0>>
  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0>>

  defp avatar_json(type, bytes), do: Jason.encode!(%{"type" => type, "data" => Base.encode64(bytes)})

  defp signed(content, created_at \\ 1_700_000_000) do
    Event.sign(
      Event.new(%{pubkey: @pubkey, created_at: created_at, kind: 12_160, tags: [], content: content}),
      @secret
    )
  end

  test "kind/0 is 12160, the first of the replaceable block" do
    assert Translation.kind() == 12_160
  end

  test "to_event/4 builds an unsigned profile with the name and version, no tags" do
    event = Translation.to_event("Sample Name", nil, @pubkey, 1_700_000_000)

    assert %Event{kind: 12_160, tags: [], pubkey: @pubkey, created_at: 1_700_000_000} = event
    assert Jason.decode!(event.content) == %{"v" => 1, "name" => "Sample Name"}
  end

  test "to_event/4 leaves an absent name off the wire" do
    assert Jason.decode!(Translation.to_event(nil, nil, @pubkey, 1).content) == %{"v" => 1}
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
    assert {:error, :unsupported_version} = Translation.from_event(signed(~s({"v":null,"name":"x"})))
    assert {:ok, %{name: "x"}} = Translation.from_event(signed(~s({"name":"x"})))
  end

  test "an unknown field is ignored and a name at the cap passes" do
    name = String.duplicate("x", 50)

    assert {:ok, %{name: ^name}} =
             Translation.from_event(signed(~s({"v":1,"name":"#{name}","later":true})))
  end

  test "to_event/4 carries the avatar as base64 with its type; nil leaves it off" do
    event = Translation.to_event("Sample Name", %{type: "image/webp", bytes: @webp}, @pubkey, 1)
    assert %{"avatar" => %{"type" => "image/webp", "data" => data}} = Jason.decode!(event.content)
    assert Base.decode64!(data) == @webp
    refute Map.has_key?(Jason.decode!(Translation.to_event("x", nil, @pubkey, 1).content), "avatar")
  end

  test "from_event/1 reads a well-formed avatar of each type and hands the bytes on undecoded" do
    for {type, bytes} <- [{"image/webp", @webp}, {"image/png", @png}, {"image/jpeg", @jpeg}] do
      content = ~s({"v":1,"name":"x","avatar":#{avatar_json(type, bytes)}})
      assert {:ok, %{avatar_type: ^type, avatar_bytes: ^bytes}} = Translation.from_event(signed(content))
    end

    assert {:ok, %{avatar_type: nil, avatar_bytes: nil}} =
             Translation.from_event(signed(~s({"v":1,"name":"x"})))

    assert {:ok, %{avatar_type: nil, avatar_bytes: nil}} =
             Translation.from_event(signed(~s({"v":1,"avatar":null})))
  end

  test "a malformed avatar drops the whole profile: unknown type, bad base64, over the cap, signature mismatch, wrong shape" do
    bad = [
      ~s({"v":1,"avatar":#{avatar_json("image/gif", @png)}}),
      ~s({"v":1,"avatar":{"type":"image/png","data":"@@@"}}),
      ~s({"v":1,"avatar":#{avatar_json("image/png", @png <> :binary.copy(<<0>>, 64 * 1024))}}),
      ~s({"v":1,"avatar":#{avatar_json("image/png", @webp)}}),
      ~s({"v":1,"avatar":"not an object"}),
      ~s({"v":1,"avatar":{"type":"image/png"}})
    ]

    for content <- bad do
      assert {:error, :bad_content} = Translation.from_event(signed(content)), content
    end
  end

  test "the decoded cap is 64 KB inclusive" do
    at_cap = @png <> :binary.copy(<<0>>, 64 * 1024 - byte_size(@png))

    assert {:ok, %{avatar_bytes: ^at_cap}} =
             Translation.from_event(signed(~s({"v":1,"avatar":#{avatar_json("image/png", at_cap)}})))
  end
end
