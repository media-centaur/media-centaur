defmodule MediaCentarr.Controls do
  use Boundary,
    deps: [MediaCentarr.Settings],
    exports: [Binding, Catalog]

  @moduledoc """
  Facade for keyboard/gamepad binding configuration.

  Every binding is declared at compile time in `Controls.Catalog`. User
  overrides live in three `Settings.Entry` rows (see `Controls.Store`).
  `get/0` resolves the full map by overlaying overrides on catalog defaults.

  Writes go through `put/3` or `clear/2`, which handle conflict detection
  and (for put) auto-swap. Every successful write broadcasts
  `{:controls_changed, resolved_map}` on the `controls:updates` topic.
  """

  alias MediaCentarr.Controls.{Binding, Catalog, Store}
  alias MediaCentarr.Topics

  @type kind :: :keyboard | :gamepad
  @type resolved :: %{atom() => %{key: String.t() | nil, button: non_neg_integer() | nil}}

  @doc "Subscribe to controls change broadcasts."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.controls_updates())

  @doc """
  Returns a map keyed by binding id, each value `%{key: ..., button: ...}`.
  `key` and `button` may be `nil` if the user cleared the slot.
  """
  @spec get() :: resolved()
  def get do
    keyboard_overrides = Store.read_keyboard()
    gamepad_overrides = Store.read_gamepad()

    Catalog.all()
    |> Enum.map(fn %Binding{} = binding ->
      {binding.id,
       %{
         key: resolve(keyboard_overrides, Atom.to_string(binding.id), binding.default_key),
         button: resolve(gamepad_overrides, Atom.to_string(binding.id), binding.default_button)
       }}
    end)
    |> Map.new()
  end

  @doc "Returns the current glyph style (\"xbox\" or \"playstation\")."
  @spec glyph_style() :: String.t()
  def glyph_style, do: Store.read_glyph_style()

  @doc "Set the glyph style and broadcast."
  @spec set_glyph_style(String.t()) :: :ok
  def set_glyph_style(style) when style in ["xbox", "playstation"] do
    :ok = Store.write_glyph_style(style)
    broadcast()
    :ok
  end

  @doc """
  Bind an action to a key or button. If the value is already bound to
  another action (within the same kind), perform an auto-swap: the
  displaced action receives the *currently-resolved* value of the action
  being rebound (its override if any, otherwise the catalog default).
  """
  @spec put(atom(), kind(), String.t() | non_neg_integer()) ::
          {:ok, resolved()} | {:error, term()}
  def put(id, :keyboard, value) when is_atom(id) and is_binary(value) do
    do_put(id, :keyboard, value, &Store.read_keyboard/0, &Store.write_keyboard/1, & &1.key)
  end

  def put(id, :gamepad, value) when is_atom(id) and is_integer(value) and value >= 0 do
    do_put(id, :gamepad, value, &Store.read_gamepad/0, &Store.write_gamepad/1, & &1.button)
  end

  @doc "Clear a slot — user-intentional un-binding. Does not swap."
  @spec clear(atom(), kind()) :: :ok | {:error, :unknown_id}
  def clear(id, :keyboard), do: do_clear(id, &Store.read_keyboard/0, &Store.write_keyboard/1)
  def clear(id, :gamepad), do: do_clear(id, &Store.read_gamepad/0, &Store.write_gamepad/1)

  @doc "Remove every user override in a category; fall back to catalog defaults."
  @spec reset_category(atom()) :: :ok
  def reset_category(category) do
    ids = Catalog.by_category(category) |> Enum.map(&Atom.to_string(&1.id))

    :ok = Store.write_keyboard(Map.drop(Store.read_keyboard(), ids))
    :ok = Store.write_gamepad(Map.drop(Store.read_gamepad(), ids))
    broadcast()
    :ok
  end

  @doc "Remove every user override."
  @spec reset_all() :: :ok
  def reset_all do
    :ok = Store.write_keyboard(%{})
    :ok = Store.write_gamepad(%{})
    broadcast()
    :ok
  end

  # --- private ---

  defp do_put(id, _kind, value, reader, writer, extractor) do
    case Catalog.get(id) do
      nil ->
        {:error, :unknown_id}

      %Binding{} ->
        overrides = reader.()
        resolved_now = get()
        id_str = Atom.to_string(id)

        # Find the conflicting binding (if any) — different id, same resolved value.
        conflict =
          Enum.find(resolved_now, fn {other_id, slot} ->
            other_id != id and extractor.(slot) == value
          end)

        previous_value = extractor.(resolved_now[id])

        new_overrides =
          overrides
          |> Map.put(id_str, value)
          |> maybe_swap(conflict, previous_value)

        :ok = writer.(new_overrides)
        broadcast()
        {:ok, get()}
    end
  end

  defp maybe_swap(overrides, nil, _previous), do: overrides

  defp maybe_swap(overrides, {displaced_id, _slot}, previous_value) do
    Map.put(overrides, Atom.to_string(displaced_id), previous_value)
  end

  defp do_clear(id, reader, writer) do
    case Catalog.get(id) do
      nil ->
        {:error, :unknown_id}

      _ ->
        new = Map.put(reader.(), Atom.to_string(id), nil)
        :ok = writer.(new)
        broadcast()
        :ok
    end
  end

  defp resolve(overrides, id_str, default) do
    # Map.get/3 returns default only when the key is absent. An explicit
    # nil value (user-cleared) is preserved as-is.
    case Map.fetch(overrides, id_str) do
      {:ok, value} -> value
      :error -> default
    end
  end

  defp broadcast do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.controls_updates(),
      {:controls_changed, get()}
    )
  end
end
