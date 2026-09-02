defmodule MediaCentaur.Nostr do
  use Boundary, deps: [], exports: [Connection, Event, Filter, Keys]

  @moduledoc """
  Nostr protocol, nothing else: keys (`Keys`), events (`Event`),
  subscription filters (`Filter`) and one relay WebSocket per URL
  (`Connection`). The first three are pure functions over binaries and
  maps; `Connection` adds the wire, and speaks NIP-01 frames plus the
  NIP-42 `AUTH` handshake. Nothing here knows what an event means —
  the domain that gives them meaning is
  `MediaCentaur.Recommendations`; the relay list and the connections
  keyed by it are `MediaCentaur.Social`.

  Crypto is `bitcoinex` (pure Elixir): secp256k1 keys, BIP-340 Schnorr
  signatures, bech32 for NIP-19. Secret keys are `MediaCentaur.Secret`
  everywhere except the signing call.
  """
end
