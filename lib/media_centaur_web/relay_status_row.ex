defmodule MediaCentaurWeb.RelayStatusRow do
  @moduledoc """
  The words for one relay's status entry (`Social.Connections.entry/0`),
  shared by every surface that shows one: the Status drill-in's diagnostic
  rows and Settings → Social's relay list use the same `state_label/1`,
  so a relay is never "Synced" on one page and "Connected" on another.

  `build/3` is the drill-in row: host, label, and the details that apply
  to the state — how long it has been in it, the newest complaint, when
  the next attempt is, when the relay was last heard. Fields that do not
  apply are absent, not blank. Pure: takes `now` so a row is testable.
  """

  alias MediaCentaur.Format
  alias MediaCentaur.Social.Connections

  @type t :: %{host: String.t(), label: String.t(), details: [String.t()]}

  @doc "Builds the diagnostic row for `url`'s status entry as of `now`."
  @spec build(String.t(), Connections.entry(), DateTime.t()) :: t()
  def build(url, entry, now) do
    %{host: host(url), label: state_label(entry), details: details(entry, now)}
  end

  @doc "The relay URL as a user reads it: no scheme, no trailing slash, port only when it is not the default."
  @spec host(String.t()) :: String.t()
  def host(url) do
    uri = URI.parse(url)
    port = if uri.port && uri.port != URI.default_port(uri.scheme), do: ":#{uri.port}", else: ""
    path = if uri.path in [nil, "/"], do: "", else: uri.path
    "#{uri.host}#{port}#{path}"
  end

  @doc "One word per connection state; an absent entry reads as not connected."
  @spec state_label(Connections.entry() | nil) :: String.t()
  def state_label(%{state: :connecting}), do: "Connecting"
  def state_label(%{state: :connected}), do: "Connected"
  def state_label(%{state: :synced}), do: "Synced"
  def state_label(%{state: :auth_failed}), do: "Rejected"
  def state_label(_absent_or_disconnected), do: "Not connected"

  # Connecting has nothing to add: no failure yet, nothing heard yet.
  defp details(%{state: :connecting}, _now), do: []

  defp details(entry, now) do
    Enum.reject(
      [
        "for #{Format.elapsed(entry.since, now)}",
        entry.last_error,
        retry(entry, now),
        heard(entry, now)
      ],
      &is_nil/1
    )
  end

  defp retry(%{state: :disconnected, retry_at: %DateTime{} = at}, now),
    do: "retry #{Format.relative_in(at, now: now)}"

  defp retry(_entry, _now), do: nil

  defp heard(%{state: state, last_heard_at: %DateTime{} = at}, now) when state in [:connected, :synced],
    do: "heard #{Format.relative_ago(at, now: now)}"

  defp heard(_entry, _now), do: nil
end
