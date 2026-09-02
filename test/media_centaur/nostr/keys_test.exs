defmodule MediaCentaur.Nostr.KeysTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Secret

  # BIP-340 test vector 0 (bitcoin/bips bip-0340/test-vectors.csv):
  # secret key 3, its x-only public key.
  @vector0_secret_hex String.duplicate("0", 63) <> "3"
  @vector0_pubkey_hex "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  describe "generate/0" do
    test "returns a wrapped 64-hex secret whose pubkey derives deterministically" do
      secret = Keys.generate()
      assert %Secret{} = secret
      assert Secret.expose(secret) =~ ~r/^[0-9a-f]{64}$/
      assert Keys.pubkey(secret) == Keys.pubkey(secret)
      assert Keys.pubkey(secret) =~ ~r/^[0-9a-f]{64}$/
    end

    test "two generations differ" do
      refute Secret.expose(Keys.generate()) == Secret.expose(Keys.generate())
    end
  end

  describe "pubkey/1" do
    test "derives the x-only public key of BIP-340 vector 0" do
      assert Keys.pubkey(Secret.wrap(@vector0_secret_hex)) == @vector0_pubkey_hex
    end
  end

  describe "valid_secret?/1" do
    test "rejects zero, the curve order, non-hex, and wrong length" do
      refute Keys.valid_secret?(String.duplicate("0", 64))
      refute Keys.valid_secret?("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141")
      refute Keys.valid_secret?("zz")
      refute Keys.valid_secret?(String.duplicate("a", 63))
      assert Keys.valid_secret?(@vector0_secret_hex)
      assert Keys.valid_secret?("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140")
    end
  end

  describe "npub / nsec" do
    test "round-trips the secret through nsec" do
      secret = Secret.wrap(@vector0_secret_hex)
      nsec = Keys.to_nsec(secret)
      assert String.starts_with?(nsec, "nsec1")
      assert String.length(nsec) == 63
      assert {:ok, back} = Keys.from_nsec(nsec)
      assert Secret.expose(back) == @vector0_secret_hex
    end

    test "round-trips the pubkey through npub" do
      npub = Keys.to_npub(@vector0_pubkey_hex)
      assert String.starts_with?(npub, "npub1")
      assert String.length(npub) == 63
      assert Keys.from_npub(npub) == {:ok, @vector0_pubkey_hex}
    end

    test "rejects the wrong prefix, a bad checksum, and garbage" do
      npub = Keys.to_npub(@vector0_pubkey_hex)
      assert {:error, _} = Keys.from_nsec(npub)
      assert {:error, _} = Keys.from_npub(Keys.to_nsec(Secret.wrap(@vector0_secret_hex)))
      assert {:error, _} = Keys.from_npub(String.slice(npub, 0..-2//1) <> "x")
      assert {:error, _} = Keys.from_npub("hello")
    end
  end

  describe "parse_pubkey/1" do
    test "accepts an npub or 64-hex and normalizes to lowercase hex" do
      npub = Keys.to_npub(@vector0_pubkey_hex)
      assert Keys.parse_pubkey(npub) == {:ok, @vector0_pubkey_hex}
      assert Keys.parse_pubkey(String.upcase(@vector0_pubkey_hex)) == {:ok, @vector0_pubkey_hex}
      assert {:error, _} = Keys.parse_pubkey("npub1notreal")
      assert {:error, _} = Keys.parse_pubkey("12")
    end
  end
end
