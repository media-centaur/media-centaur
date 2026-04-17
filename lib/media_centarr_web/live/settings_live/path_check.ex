defmodule MediaCentarrWeb.Live.SettingsLive.PathCheck do
  @moduledoc """
  Pure helpers for checking the existence and kind of filesystem paths
  configured in Settings — used by the Overview section and inline
  `path_status` indicators.

  All functions return one of the following atoms so callers can render
  distinct feedback (icon, color, tooltip) per failure mode:

  - `:ok` — path exists and matches the requested kind
  - `:missing` — path is nil, empty, or does not exist
  - `:wrong_kind` — path exists but is not the requested kind
    (e.g. a file was requested but the path is a directory)
  - `:not_executable` — requested `:executable` exists but lacks the exec bit

  The check is synchronous and cheap (`File.stat/1`). Expect it to be called
  on every LiveView render, which is fine for the handful of paths shown
  on the Settings page.
  """

  @type kind :: :file | :directory | :executable
  @type result :: :ok | :missing | :wrong_kind | :not_executable

  @doc "Checks whether `path` exists and matches `kind`."
  @spec check(String.t() | nil, kind()) :: result()
  def check(path, kind) do
    case normalize(path) do
      nil -> :missing
      trimmed -> do_check(trimmed, kind)
    end
  end

  defp normalize(nil), do: nil

  defp normalize(path) when is_binary(path) do
    case String.trim(path) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp do_check(path, kind) do
    case File.stat(path) do
      {:ok, %File.Stat{type: type, mode: mode}} -> classify(kind, type, mode)
      {:error, _} -> :missing
    end
  end

  defp classify(:file, :regular, _mode), do: :ok
  defp classify(:file, _other, _mode), do: :wrong_kind

  defp classify(:directory, :directory, _mode), do: :ok
  defp classify(:directory, _other, _mode), do: :wrong_kind

  defp classify(:executable, :regular, mode) do
    # Any exec bit set (owner/group/other) is enough — matches how a user's
    # shell resolves the binary. Intentionally loose — we're helping the
    # user spot gross misconfiguration, not enforcing permissions.
    if Bitwise.band(mode, 0o111) == 0, do: :not_executable, else: :ok
  end

  defp classify(:executable, _other, _mode), do: :wrong_kind

  @doc "Returns `true` only when the result is `:ok`."
  @spec ok?(result()) :: boolean()
  def ok?(:ok), do: true
  def ok?(_), do: false

  @doc "Returns a short user-facing label for a check result."
  @spec label(result()) :: String.t()
  def label(:ok), do: "Found"
  def label(:missing), do: "Path not found"
  def label(:wrong_kind), do: "Path is the wrong kind"
  def label(:not_executable), do: "File is not executable"
end
