defmodule MediaCentaur.Downloads.Wiring.Proposal do
  @moduledoc """
  What accepting a wiring would change, as a person is shown it: the
  connections that differ from the saved settings, each with its address
  and the fields that change, and the stack's completed directory. It
  holds no credential. `digest` identifies the wiring's values, and is
  what `Wiring.accept/1` and `Wiring.decline/1` take.
  """

  alias MediaCentaur.Capabilities

  @enforce_keys [:digest, :connections]
  defstruct [:digest, :connections, :completed_dir, :completed_dir_watched?]

  @type connection :: %{
          id: Capabilities.subject(),
          url: String.t(),
          new?: boolean(),
          changes: [atom()]
        }

  @type t :: %__MODULE__{
          digest: String.t(),
          connections: [connection(), ...],
          completed_dir: String.t() | nil,
          completed_dir_watched?: boolean() | nil
        }
end
