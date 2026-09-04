defmodule MediaCentaur.ErrorReports.BucketTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.ErrorReports.Bucket
  alias MediaCentaur.ErrorReports.Incident

  defp incident(attrs) do
    struct!(
      %Incident{
        fingerprint: "abc123",
        component: "system",
        message: "** (RuntimeError) boom",
        display_title: "[System] ** (RuntimeError) boom",
        severity: :error,
        count: 3,
        first_seen: ~U[2026-06-12 10:00:00Z],
        last_seen: ~U[2026-06-12 11:00:00Z]
      },
      attrs
    )
  end

  describe "from_incident/2" do
    test "derives a human headline from the normalized message, not the stored title" do
      bucket =
        Bucket.from_incident(
          incident(message: "** (Phoenix.Ecto.PendingMigrationError) migrations are pending"),
          []
        )

      assert bucket.headline == "PendingMigrationError: migrations are pending"
    end

    test "headline falls back to the stored display title when the incident has no message" do
      bucket = Bucket.from_incident(incident(message: nil), [])

      assert bucket.headline == "[System] ** (RuntimeError) boom"
    end
  end

  describe "from_incident/2 component" do
    test "resolves a log component from the console taxonomy" do
      assert Bucket.from_incident(incident(component: "nostr"), []).component == :nostr
    end

    test "resolves a subsystem component the console taxonomy does not list" do
      assert Bucket.from_incident(incident(component: "self_update"), []).component ==
               :self_update
    end

    test "a component outside both taxonomies lands under :system even when the atom exists" do
      # The atom exists (this line mints it); membership, not atom-table
      # presence, is what makes a component a bucket key.
      _ = :not_a_media_centaur_component

      assert Bucket.from_incident(incident(component: "not_a_media_centaur_component"), []).component ==
               :system
    end
  end
end
