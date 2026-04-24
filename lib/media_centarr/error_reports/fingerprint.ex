defmodule MediaCentarr.ErrorReports.Fingerprint do
  @moduledoc """
  Computes a stable fingerprint for an error so that two users hitting
  the same bug produce the same bucket key and the same GitHub issue title.

  `fingerprint/2` returns `%{key, display_title, normalized_message}`:

    - `key` — 16 lowercase hex chars of `sha256(component || 0 || normalized)`.
    - `display_title` — `"[<Component>] <normalized message>"`, truncated to 200.
    - `normalized_message` — `Redactor.normalize/1` output.
  """

  alias MediaCentarr.ErrorReports.Redactor

  @title_limit 200

  @component_labels %{
    tmdb: "TMDB",
    library: "Library",
    pipeline: "Pipeline",
    watcher: "Watcher",
    playback: "Playback",
    phoenix: "Phoenix",
    ecto: "Ecto",
    live_view: "LiveView",
    system: "System"
  }

  @type result :: %{
          key: binary(),
          display_title: binary(),
          normalized_message: binary()
        }

  @spec fingerprint(atom(), binary()) :: result()
  def fingerprint(component, raw_message) when is_atom(component) and is_binary(raw_message) do
    normalized = Redactor.normalize(raw_message)
    key = compute_key(component, normalized)
    title = build_title(component, normalized)

    %{key: key, display_title: title, normalized_message: normalized}
  end

  defp compute_key(component, normalized) do
    :crypto.hash(:sha256, [Atom.to_string(component), 0, normalized])
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp build_title(component, normalized) do
    label = component_label(component)

    String.slice("[#{label}] #{normalized}", 0, @title_limit)
  end

  defp component_label(component) do
    Map.get_lazy(@component_labels, component, fn ->
      component |> Atom.to_string() |> String.capitalize()
    end)
  end
end
