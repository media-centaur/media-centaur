defmodule MediaCentaur.Nostr.EventTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Secret

  @secret Secret.wrap(String.duplicate("0", 63) <> "3")
  @pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  defp unsigned(overrides \\ %{}) do
    Event.new(
      Map.merge(
        %{
          pubkey: @pubkey,
          created_at: 1_700_000_000,
          kind: 1,
          tags: [["d", "sample"]],
          content: "hello"
        },
        overrides
      )
    )
  end

  describe "serialize/1 (NIP-01 canonical form)" do
    test "is the compact JSON array [0, pubkey, created_at, kind, tags, content]" do
      assert Event.serialize(unsigned()) ==
               ~s([0,"#{@pubkey}",1700000000,1,[["d","sample"]],"hello"])
    end

    test "escapes exactly the NIP-01 set and leaves UTF-8 verbatim" do
      content = "q\"b\\n\nr\rt\tb\bf\fé😀/"
      serialized = Event.serialize(unsigned(%{content: content}))
      assert String.ends_with?(serialized, ~s(,"q\\"b\\\\n\\nr\\rt\\tb\\bf\\fé😀/"]))
    end

    test "other control characters become lowercase \\u00xx like JSON.stringify" do
      serialized = Event.serialize(unsigned(%{content: <<1, 0x1F>>}))
      assert String.ends_with?(serialized, ~s(,"\\u0001\\u001f"]))
    end

    test "agrees with Jason for ordinary content" do
      event =
        unsigned(%{
          content: "plain text — with punctuation, quotes \" and slashes /",
          tags: [["p", "x"], ["t", "a b"]]
        })

      assert Event.serialize(event) ==
               Jason.encode!([0, event.pubkey, event.created_at, event.kind, event.tags, event.content])
    end
  end

  describe "id/1" do
    test "is the lowercase sha256 hex of the serialization" do
      event = unsigned()
      expected = Base.encode16(:crypto.hash(:sha256, Event.serialize(event)), case: :lower)
      assert Event.id(event) == expected
    end
  end

  describe "sign/2 and verify/1" do
    test "signs with the secret, sets pubkey/id/sig, and verifies" do
      event = Event.new(%{created_at: 1_700_000_000, kind: 1, tags: [], content: "hello"})
      signed = Event.sign(event, @secret)

      assert signed.pubkey == @pubkey
      assert signed.id == Event.id(signed)
      assert signed.sig =~ ~r/^[0-9a-f]{128}$/
      assert Event.verify(signed) == :ok
    end

    test "a signature is always 64 bytes even when r or s has leading zeros" do
      # Sign many events; every sig must be exactly 128 hex chars.
      for index <- 1..64 do
        event = Event.new(%{created_at: index, kind: 1, tags: [], content: "n#{index}"})
        signed = Event.sign(event, @secret)
        assert byte_size(signed.sig) == 128
        assert Event.verify(signed) == :ok
      end
    end

    test "verify rejects a tampered id, a tampered content, a wrong signature, and a malformed event" do
      signed = Event.sign(Event.new(%{created_at: 1, kind: 1, tags: [], content: "hello"}), @secret)

      assert Event.verify(%{signed | id: String.duplicate("0", 64)}) == {:error, :bad_id}
      assert Event.verify(%{signed | content: "bye"}) == {:error, :bad_id}
      assert Event.verify(%{signed | sig: String.duplicate("0", 128)}) == {:error, :bad_signature}
      assert Event.verify(%{signed | sig: "zz"}) == {:error, :malformed}
      assert Event.verify(%{signed | pubkey: "not-hex"}) == {:error, :malformed}
    end

    test "verify rejects a signature made by a different key" do
      other = Keys.generate()
      signed = Event.sign(Event.new(%{created_at: 1, kind: 1, tags: [], content: "hello"}), other)
      forged = %{signed | pubkey: @pubkey, id: Event.id(%{signed | pubkey: @pubkey})}
      assert Event.verify(forged) == {:error, :bad_signature}
    end
  end

  describe "to_map/1 and from_map/1 (wire form)" do
    test "round-trips through JSON" do
      event =
        Event.new(%{created_at: 1, kind: 32_160, tags: [["d", "tmdb:movie:603"]], content: "{}"})

      signed = Event.sign(event, @secret)
      json = signed |> Event.to_map() |> Jason.encode!()

      assert {:ok, decoded} = json |> Jason.decode!() |> Event.from_map()
      assert decoded == signed
      assert Event.verify(decoded) == :ok
    end

    test "from_map rejects wrong shapes" do
      assert {:error, :malformed} = Event.from_map(%{"id" => 1})

      assert {:error, :malformed} =
               Event.from_map(%{
                 "id" => "a",
                 "pubkey" => "b",
                 "created_at" => "x",
                 "kind" => 1,
                 "tags" => [],
                 "content" => "",
                 "sig" => "c"
               })

      assert {:error, :malformed} =
               Event.from_map(%{
                 "id" => "a",
                 "pubkey" => "b",
                 "created_at" => 1,
                 "kind" => 1,
                 "tags" => [["ok"], "notalist"],
                 "content" => "",
                 "sig" => "c"
               })

      assert {:error, :malformed} = Event.from_map("nope")
    end
  end

  describe "tag helpers" do
    test "tag_value/2 returns the first value of the first matching tag" do
      event = unsigned(%{tags: [["d", "one"], ["p", "pk"], ["d", "two"]]})
      assert Event.tag_value(event, "d") == "one"
      assert Event.tag_value(event, "p") == "pk"
      assert Event.tag_value(event, "e") == nil
    end
  end
end
