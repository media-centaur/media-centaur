defmodule MediaCentaur.Nostr.Filter do
  @moduledoc """
  A NIP-01 subscription filter — what a `REQ` asks a relay for. Built
  from keyword options; `to_map/1` yields the wire map (only the keys
  set), with tag filters as `"#<name>"` entries.
  """

  defstruct ids: nil, authors: nil, kinds: nil, since: nil, until: nil, limit: nil, tags: %{}

  @type t :: %__MODULE__{
          ids: [String.t()] | nil,
          authors: [String.t()] | nil,
          kinds: [non_neg_integer()] | nil,
          since: non_neg_integer() | nil,
          until: non_neg_integer() | nil,
          limit: pos_integer() | nil,
          tags: %{optional(String.t()) => [String.t()]}
        }

  @keys [:ids, :authors, :kinds, :since, :until, :limit, :tags]
  @scalar_keys [:ids, :authors, :kinds, :since, :until, :limit]

  @doc "Builds a filter; raises `KeyError` on an unknown option."
  @spec new(keyword()) :: t()
  def new(opts) do
    Enum.reduce(opts, %__MODULE__{}, fn {key, value}, filter ->
      if key in @keys, do: Map.put(filter, key, value), else: raise(KeyError, key: key, term: opts)
    end)
  end

  @doc "The wire map for `[\"REQ\", sub_id, filter]`."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = filter) do
    base =
      @scalar_keys
      |> Enum.reject(&is_nil(Map.get(filter, &1)))
      |> Map.new(&{Atom.to_string(&1), Map.get(filter, &1)})

    Enum.reduce(filter.tags, base, fn {name, values}, acc -> Map.put(acc, "#" <> name, values) end)
  end
end
