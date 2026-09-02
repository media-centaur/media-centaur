defmodule MediaCentaur.Social.IdentityTest do
  # Writes a Config key → :persistent_term; GlobalStateSandbox restores only for async: false.
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Social
  alias MediaCentaur.Social.Events.IdentityChanged
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Secret
  alias MediaCentaur.Settings.Config

  @vector0_secret_hex String.duplicate("0", 63) <> "3"
  @vector0_pubkey_hex "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  describe "ensure/0" do
    test "generates once and is stable afterwards" do
      refute Identity.present?()
      assert %Secret{} = Identity.ensure()
      assert Identity.present?()
      first = Identity.pubkey()
      assert %Secret{} = Identity.ensure()
      assert Identity.pubkey() == first
      assert Identity.npub() == Keys.to_npub(first)
    end

    test "broadcasts identity_changed only when it generates" do
      Social.subscribe()
      Identity.ensure()
      assert_receive {:identity_changed, %IdentityChanged{pubkey: pubkey}}, 500
      assert pubkey == Identity.pubkey()
      Identity.ensure()
      refute_receive {:identity_changed, _}, 100
    end
  end

  describe "export_nsec/0 and import_nsec/1" do
    test "exports the current secret; import replaces it and broadcasts" do
      Identity.ensure()
      Social.subscribe()

      nsec = Keys.to_nsec(Secret.wrap(@vector0_secret_hex))
      assert :ok = Identity.import_nsec(nsec)
      assert Identity.pubkey() == @vector0_pubkey_hex
      assert Identity.export_nsec() == nsec
      assert_receive {:identity_changed, %IdentityChanged{pubkey: @vector0_pubkey_hex}}, 500

      # stored wrapped, not bare
      assert %Secret{} = Config.get(:nostr_secret_key)
    end

    test "rejects an invalid nsec and keeps the identity" do
      Identity.ensure()
      before = Identity.pubkey()
      assert {:error, :invalid_secret} = Identity.import_nsec("nsec1nope")
      assert {:error, :invalid_secret} = Identity.import_nsec(Identity.npub())
      assert Identity.pubkey() == before
    end

    test "trims pasted whitespace" do
      Identity.ensure()
      nsec = Keys.to_nsec(Secret.wrap(@vector0_secret_hex))
      assert :ok = Identity.import_nsec("  " <> nsec <> "\n")
      assert Identity.pubkey() == @vector0_pubkey_hex
    end
  end

  test "pubkey/0, npub/0, export_nsec/0 are nil without an identity" do
    refute Identity.present?()
    assert Identity.pubkey() == nil
    assert Identity.npub() == nil
    assert Identity.export_nsec() == nil
  end
end
