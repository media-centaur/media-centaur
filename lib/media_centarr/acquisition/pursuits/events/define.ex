defmodule MediaCentarr.Acquisition.Pursuits.Events.Define do
  @moduledoc """
  Macro for declaring a typed pursuit-event struct module.

  Each event struct carries three envelope fields — `pursuit_id`,
  `pursuit_title`, `occurred_at` — plus any kind-specific keys named in
  `payload_keys`. The macro generates the `defstruct`, type, and the
  three `EventBehaviour` callbacks (`kind/0`, `to_payload/1`,
  `from_payload/1`) so each event module reduces to a few lines.

  ## Usage

      defmodule MediaCentarr.Acquisition.Pursuits.Events.PursuitStarted do
        use MediaCentarr.Acquisition.Pursuits.Events.Define,
          kind: "pursuit_started",
          payload_keys: [:origin]
      end

  Payload serialization converts atom struct-keys to string map-keys (the
  `payload` column is JSONB-shaped, which round-trips strings cleanly).
  Override `to_payload/1` and `from_payload/1` in the using module if a
  kind needs custom encoding (e.g. ISO datetimes).
  """

  defmacro __using__(opts) do
    kind = Keyword.fetch!(opts, :kind)
    payload_keys = Keyword.get(opts, :payload_keys, [])
    envelope_keys = [:pursuit_id, :pursuit_title, :occurred_at]
    all_keys = envelope_keys ++ payload_keys

    quote bind_quoted: [kind: kind, payload_keys: payload_keys, all_keys: all_keys] do
      @behaviour MediaCentarr.Acquisition.Pursuits.Events.EventBehaviour

      @kind kind
      @payload_keys payload_keys

      defstruct all_keys

      @type t :: %__MODULE__{}

      @impl true
      def kind, do: @kind

      @impl true
      def to_payload(%__MODULE__{} = event) do
        Map.new(@payload_keys, fn key -> {Atom.to_string(key), Map.fetch!(event, key)} end)
      end

      @impl true
      def from_payload(payload) when is_map(payload) do
        struct(
          __MODULE__,
          Enum.map(@payload_keys, fn key -> {key, Map.get(payload, Atom.to_string(key))} end)
        )
      end

      defoverridable to_payload: 1, from_payload: 1
    end
  end
end
