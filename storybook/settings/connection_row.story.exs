defmodule MediaCentaurWeb.Storybook.Settings.ConnectionRow do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Settings.ConnectionRow.connection_row/1
  def render_source, do: :function

  # Rows are `<li>`s: the story wraps each in the list the section renders.
  def template, do: ~s|<ul><.psb-variation/></ul>|

  @tested ~U[2026-05-18 09:00:00Z]

  @test_and_edit ~s|<:actions><button class="btn btn-soft btn-xs">Test</button><button class="btn btn-ghost btn-xs">Edit</button></:actions>|

  def variations do
    [
      %Variation{
        id: :connected,
        description:
          "The steady state: address as a link, credential presence in words, the test's age.",
        attributes: %{
          id: "connection-prowlarr",
          name: "Prowlarr",
          state: :ok,
          state_label: "Connected",
          tested_at: @tested,
          address: "http://localhost:9696",
          detail: "API key set"
        },
        slots: [@test_and_edit]
      },
      %Variation{
        id: :connected_client,
        description: "A download client carries its protocol as a kind tag.",
        attributes: %{
          id: "connection-download_client",
          name: "qBittorrent",
          kind: "torrent",
          state: :ok,
          state_label: "Connected",
          tested_at: @tested,
          address: "http://localhost:8080",
          detail: "admin · password set"
        },
        slots: [@test_and_edit]
      },
      %Variation{
        id: :pending,
        description: "A verify in flight: spinner beside the state word.",
        attributes: %{
          id: "connection-prowlarr-pending",
          name: "Prowlarr",
          state: :pending,
          state_label: "Testing…",
          address: "http://localhost:9696",
          detail: "API key set"
        },
        slots: [@test_and_edit]
      },
      %Variation{
        id: :unreachable,
        description: "The last test failed, in the integration's own words.",
        attributes: %{
          id: "connection-usenet_download_client",
          name: "SABnzbd",
          kind: "usenet",
          state: :error,
          state_label: "Unreachable or bad API key",
          tested_at: @tested,
          address: "http://192.168.68.67:8085",
          detail: "API key set"
        },
        slots: [@test_and_edit]
      },
      %Variation{
        id: :not_tested,
        description: "Configured, never tested — the state after a save.",
        attributes: %{
          id: "connection-prowlarr-not-tested",
          name: "Prowlarr",
          state: :not_tested,
          state_label: "Not tested",
          address: "http://localhost:9696",
          detail: "API key set"
        },
        slots: [@test_and_edit]
      },
      %Variation{
        id: :not_configured,
        description:
          "Nothing configured: the detail line says what the connection does; the one action is Set up.",
        attributes: %{
          id: "connection-usenet-empty",
          name: "Usenet client",
          state: :not_configured,
          state_label: "Not configured",
          detail: "SABnzbd. Repairs and unpacks; the finished file imports like any other download."
        },
        slots: [
          ~s|<:actions><button class="btn btn-soft btn-primary text-base-content btn-xs">Set up</button></:actions>|
        ]
      },
      %Variation{
        id: :detected,
        description: "Detect from Prowlarr found values that are not saved.",
        attributes: %{
          id: "connection-download_client-detected",
          name: "qBittorrent",
          kind: "torrent",
          state: :detected,
          state_label: "Detected from Prowlarr, not saved",
          address: "http://qbittorrent:8080"
        },
        slots: [
          ~s|<:actions><button class="btn btn-soft btn-primary text-base-content btn-xs">Review</button><button class="btn btn-ghost btn-xs">Dismiss</button></:actions>|
        ]
      },
      %Variation{
        id: :editing,
        description: "The edit state: the form beneath the row, under a hairline.",
        attributes: %{
          id: "connection-prowlarr-editing",
          name: "Prowlarr",
          state: :ok,
          state_label: "Connected",
          tested_at: @tested,
          address: "http://localhost:9696",
          detail: "API key set",
          editing: true
        },
        slots: [
          """
          <:edit>
            <form class="space-y-4">
              <div class="py-3.5"><div class="text-sm font-medium">Address</div><input class="input input-bordered w-full font-mono text-sm mt-2" value="http://localhost:9696" /></div>
              <div class="py-3.5"><div class="text-sm font-medium">API key</div><input type="password" class="input input-bordered w-full font-mono text-sm mt-2" placeholder="Leave blank to keep the current key" /></div>
              <div class="flex items-center justify-end gap-2 pt-1">
                <button type="button" class="btn btn-ghost btn-sm">Cancel</button>
                <button type="button" class="btn btn-soft btn-sm">Save and test</button>
                <button type="button" class="btn btn-soft btn-primary text-base-content btn-sm">Save</button>
              </div>
            </form>
          </:edit>
          """
        ]
      },
      %Variation{
        id: :relay,
        description: "A relay: monospace name, no kind, no edit; Remove is the one action.",
        attributes: %{
          id: "relay-wss-relay-example",
          name: "wss://relay.example",
          monospace_name: true,
          state: :ok,
          state_label: "Synced"
        },
        slots: [~s|<:actions><button class="btn btn-ghost btn-xs">Remove</button></:actions>|]
      },
      %Variation{
        id: :relay_rejected,
        description: "A relay that refused the connection, with its last error on the detail line.",
        attributes: %{
          id: "relay-wss-relay-example-net",
          name: "wss://relay.example.net",
          monospace_name: true,
          state: :error,
          state_label: "Rejected",
          detail: "auth-required: this relay requires authentication"
        },
        slots: [~s|<:actions><button class="btn btn-ghost btn-xs">Remove</button></:actions>|]
      }
    ]
  end
end
