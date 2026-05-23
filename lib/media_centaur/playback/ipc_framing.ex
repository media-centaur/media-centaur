defmodule MediaCentaur.Playback.IpcFraming do
  @moduledoc """
  Newline framing for the mpv JSON-IPC byte stream.

  mpv emits newline-delimited JSON over its IPC socket. A single message
  — notably `track-list` for files with many audio/subtitle tracks — can
  exceed the socket's read buffer and arrive split across several
  `{:tcp, _, chunk}` deliveries, or several small messages can arrive in
  one chunk. Decoding a chunk in isolation raises `Jason.DecodeError`
  (the classic "partial JSON" failure).

  `feed/2` reassembles whole lines: hand it the buffer carried from the
  previous call plus the new chunk, and it returns the lines that are
  complete (newline-terminated in the stream, with the newline stripped)
  and the unterminated remainder to carry into the next call. The caller
  owns the buffer; this module is pure.

  Pairs with `:gen_tcp` opened in `packet: :raw` mode — `packet: :line`
  silently truncates lines longer than the read buffer, which is the bug
  this module exists to avoid.
  """

  @doc """
  Splits `buffer <> data` on newlines.

  Returns `{complete_lines, remainder}` where `complete_lines` are the
  newline-terminated segments (newline removed) and `remainder` is the
  trailing bytes not yet terminated by a newline.
  """
  @spec feed(binary(), binary()) :: {[binary()], binary()}
  def feed(buffer, data) when is_binary(buffer) and is_binary(data) do
    parts = String.split(buffer <> data, "\n")
    {complete, [remainder]} = Enum.split(parts, -1)
    {complete, remainder}
  end
end
