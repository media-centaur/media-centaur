defmodule MediaCentaurWeb.SettingsLive.LanguageLogic do
  @moduledoc """
  Pure helpers for the Settings → Language picker's working list of
  "understood languages" — an ordered list of canonical ISO 639-2/T
  codes, most-preferred first.

  The Settings LiveView keeps the draft list in assigns and routes the
  add / remove / reorder events through these functions. Extracting the
  ordering logic keeps the LiveView thin and makes the behaviour
  unit-testable without a socket or the DOM ([ADR-030]).
  """

  alias MediaCentaur.Playback.Iso639

  @doc "All selectable languages as `{code, name}`, sorted by name."
  @spec options() :: [{String.t(), String.t()}]
  def options, do: Iso639.all()

  @doc """
  Resolve `input` (a display name or any ISO form) to a canonical code
  and append it to `list`, unless it is unknown or already present.
  Returns the list unchanged when the input resolves to nothing.
  """
  @spec add([String.t()], String.t() | nil) :: [String.t()]
  def add(list, input) when is_list(list) do
    case Iso639.code_for_name(input) do
      nil -> list
      code -> if code in list, do: list, else: list ++ [code]
    end
  end

  @doc "Remove `code` from `list`, matching any ISO form."
  @spec remove([String.t()], String.t()) :: [String.t()]
  def remove(list, code) when is_list(list) do
    canon = Iso639.normalize(code)
    Enum.reject(list, &(Iso639.normalize(&1) == canon))
  end

  @doc "Swap `code` with the entry before it (no-op if first or absent)."
  @spec move_up([String.t()], String.t()) :: [String.t()]
  def move_up(list, code), do: swap(list, code, -1)

  @doc "Swap `code` with the entry after it (no-op if last or absent)."
  @spec move_down([String.t()], String.t()) :: [String.t()]
  def move_down(list, code), do: swap(list, code, +1)

  defp swap(list, code, delta) when is_list(list) do
    canon = Iso639.normalize(code)

    case Enum.find_index(list, &(Iso639.normalize(&1) == canon)) do
      nil -> list
      index -> do_swap(list, index, index + delta)
    end
  end

  defp do_swap(list, _index, target) when target < 0, do: list

  defp do_swap(list, index, target) do
    if target >= length(list) do
      list
    else
      moved = Enum.at(list, index)
      displaced = Enum.at(list, target)

      list
      |> List.replace_at(index, displaced)
      |> List.replace_at(target, moved)
    end
  end
end
