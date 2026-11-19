defmodule MediaCentaurWeb.Components.Settings.WiringProposal do
  @moduledoc """
  The card for connection settings `prowlarr-stack` wrote on this
  computer (`MediaCentaur.Downloads.Wiring`): the connections that differ
  from the saved ones, each a connection row in its not-saved state, the
  stack's completed directory, and Accept and Decline. A wiring that
  cannot be used is the same card with the reason and no actions.

  The host renders it while `Wiring.proposal/0` is not `:none` and handles
  `accept_wiring` and `decline_wiring`, both carrying `digest`.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings
  import MediaCentaurWeb.Components.Settings.ConnectionRow

  alias MediaCentaur.Downloads.Wiring.Proposal

  attr :wiring, :any,
    required: true,
    doc: "`{:proposal, %Wiring.Proposal{}}` or `{:error, reason}` from `Wiring.proposal/0`."

  @doc "The proposal card, or the reason the stack's wiring cannot be used."
  def wiring_proposal(%{wiring: {:proposal, %Proposal{} = proposal}} = assigns) do
    assigns = assign(assigns, :proposal, proposal)

    ~H"""
    <.settings_card
      id="wiring-proposal"
      title="prowlarr-stack"
      description="prowlarr-stack on this computer has connection settings that are not saved here. Nothing changes until you accept."
    >
      <:action>
        <div class="flex items-center gap-2">
          <.button
            id="wiring-decline"
            variant="dismiss"
            size="xs"
            phx-click="decline_wiring"
            phx-value-digest={@proposal.digest}
            data-nav-item
            tabindex="0"
          >
            Decline
          </.button>
          <.button
            id="wiring-accept"
            variant="action"
            size="xs"
            phx-click="accept_wiring"
            phx-value-digest={@proposal.digest}
            data-nav-item
            tabindex="0"
          >
            Accept and test
          </.button>
        </div>
      </:action>
      <ul>
        <.connection_row
          :for={connection <- @proposal.connections}
          id={"wiring-#{connection.id}"}
          name={name(connection.id)}
          kind={kind(connection.id)}
          state={:detected}
          state_label={if connection.new?, do: "New", else: "Changes"}
          address={connection.url}
          detail={if !connection.new?, do: change_summary(connection.changes)}
        />
      </ul>
      <p :if={@proposal.completed_dir} id="wiring-completed-dir" class="text-xs text-base-content/60">
        Finished downloads land in <span class="font-mono">{@proposal.completed_dir}</span>, {completed_dir_clause(
          @proposal.completed_dir_watched?
        )}
        <.link
          :if={!@proposal.completed_dir_watched?}
          navigate={~p"/settings?section=library"}
          class="link"
          data-nav-item
          tabindex="0"
        >
          Media directories
        </.link>
      </p>
    </.settings_card>
    """
  end

  def wiring_proposal(%{wiring: {:error, reason}} = assigns) do
    assigns = assign(assigns, :message, error_message(reason))

    ~H"""
    <.settings_card id="wiring-proposal" title="prowlarr-stack">
      <p id="wiring-error" class="text-sm text-base-content/70 max-w-[60ch]">{@message}</p>
    </.settings_card>
    """
  end

  @doc """
  The fields a changed connection's line names, in words: "Changes:
  address, API key".
  """
  @spec change_summary([atom()]) :: String.t()
  def change_summary(changes) do
    "Changes: " <> Enum.map_join(changes, ", ", &field_word/1)
  end

  @doc "Why a wiring cannot be used, as the card states it."
  @spec error_message(MediaCentaur.Downloads.Wiring.reason()) :: String.t()
  def error_message({:unknown_format, format}),
    do:
      "prowlarr-stack wrote its connection settings in a format this version of Media Centaur does not read (format #{inspect(format)}). Update Media Centaur, then open this page again. Nothing was changed."

  def error_message(:malformed),
    do:
      "The connection settings prowlarr-stack wrote cannot be read. Run ./setup in the stack's directory to write them again. Nothing was changed."

  def error_message({:unsupported_client, type}),
    do:
      "prowlarr-stack names a download client Media Centaur has no driver for (#{type}). Nothing was changed."

  def error_message(:writable_by_others),
    do:
      "The file prowlarr-stack wrote can be changed by other users of this computer, so it is not used. Run ./setup in the stack's directory to write it again."

  def error_message({:unreadable, posix}),
    do:
      "The connection settings prowlarr-stack wrote could not be opened (#{posix}). Nothing was changed."

  defp field_word(key) do
    cond do
      suffix?(key, "_url") -> "address"
      suffix?(key, "_type") -> "client"
      suffix?(key, "_username") -> "username"
      suffix?(key, "_password") -> "password"
      suffix?(key, "_api_key") -> "API key"
    end
  end

  defp suffix?(key, suffix), do: String.ends_with?(Atom.to_string(key), suffix)

  defp completed_dir_clause(true), do: "which is inside a media directory."

  defp completed_dir_clause(_not_watched),
    do: "which is not inside a media directory, so they are not imported."

  defp name(:prowlarr), do: "Prowlarr"
  defp name(:download_client), do: "qBittorrent"
  defp name(:usenet_download_client), do: "SABnzbd"

  defp kind(:prowlarr), do: nil
  defp kind(:download_client), do: "torrent"
  defp kind(:usenet_download_client), do: "usenet"
end
