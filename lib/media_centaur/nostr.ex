defmodule MediaCentaur.Nostr do
  use Boundary, deps: [], exports: [Keys]

  @moduledoc """
  Nostr protocol, nothing else: keys (`Keys`), events (`Event`) and
  subscription filters (`Filter`). Pure functions over binaries and
  maps — no persistence, no network, no knowledge of what an event
  means. The relay connection process lives beside these
  (`Connection`, next layer); the recommendations domain that gives
  events meaning is `MediaCentaur.Recommendations`.

  Crypto is `bitcoinex` (pure Elixir): secp256k1 keys, BIP-340 Schnorr
  signatures, bech32 for NIP-19. Secret keys are `MediaCentaur.Secret`
  everywhere except the signing call.
  """
end
