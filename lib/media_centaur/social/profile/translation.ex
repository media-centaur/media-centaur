defmodule MediaCentaur.Social.Profile.Translation do
  @moduledoc """
  The profile's wire shape, both ways, pure (ADR-073;
  `docs/social-protocol.md` § Profile). Kind 12160, the first kind of
  the replaceable block: one record per signer, no tags. Content is
  `{"v": 1, "name": <string>}`; an absent `v` means 1, and an absent or
  blank name means the key gives none. A name is capped at 50
  characters. Anything malformed is dropped whole: an unknown `v`,
  content that is not a JSON object, a name that is not a string or is
  over the cap. Unknown fields are ignored, so fields can be added
  without a version bump.

  The avatar is the optional field `"avatar": {"type": <type>, "data":
  <base64>}`, absent or null when the key gives none. The type is one
  of `image/webp`, `image/jpeg`, `image/png`; the decoded bytes are
  capped at 64 KB inclusive and must open with the type's signature
  (`RIFF` at 0 and `WEBP` at 8; the eight-byte PNG signature;
  `FF D8 FF`). An unknown type, bad base64, bytes over the cap, a
  signature mismatch or any other shape drops the whole profile. A
  reader never decodes an avatar: `from_event/1` hands the bytes on as
  `avatar_bytes`, and they go to a file, never to a column; the row's
  `raw_event` still carries the wire form, avatar included, for
  republish.

  The hue is the optional integer field `"hue"`, 0–359 (`Social.Hue`),
  absent or null when the key gives none; a float, a string or an
  integer out of range drops the whole profile.
  """

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Social.Hue

  @kind 12_160
  @content_version 1
  @max_name_length 50
  # Each accepted type: its file extension and the marks its bytes must
  # carry, as `{offset, magic}`.
  @avatar_types %{
    "image/webp" => {"webp", [{0, "RIFF"}, {8, "WEBP"}]},
    "image/png" => {"png", [{0, <<0x89, "PNG\r\n", 0x1A, 0x0A>>}]},
    "image/jpeg" => {"jpg", [{0, <<0xFF, 0xD8, 0xFF>>}]}
  }
  @max_avatar_bytes 64 * 1024

  @type avatar :: %{type: String.t(), bytes: binary()}
  @typedoc "The content a sender gives, one map: a nil or absent field is left off the wire."
  @type fields :: %{
          optional(:name) => String.t() | nil,
          optional(:avatar) => avatar() | nil,
          optional(:hue) => Hue.t() | nil
        }
  @type attrs :: %{
          pubkey: String.t(),
          name: String.t() | nil,
          avatar_type: String.t() | nil,
          avatar_bytes: binary() | nil,
          hue: Hue.t() | nil,
          raw_event: map(),
          created_at: non_neg_integer()
        }

  @doc "The profile's kind number."
  @spec kind() :: 12_160
  def kind, do: @kind

  @doc "The name cap in characters; the Settings form and the protocol page mirror it."
  @spec max_name_length() :: 50
  def max_name_length, do: @max_name_length

  @doc "The file extension for an accepted avatar type; raises on any other."
  @spec avatar_extension(String.t()) :: String.t()
  def avatar_extension(type), do: @avatar_types |> Map.fetch!(type) |> elem(0)

  @doc "The decoded avatar cap in bytes; the protocol page mirrors it."
  @spec max_avatar_bytes() :: pos_integer()
  def max_avatar_bytes, do: @max_avatar_bytes

  @doc "The type of the master this app publishes (`ImageFiles.square_webp/4`); one of the three."
  @spec master_type() :: String.t()
  def master_type, do: "image/webp"

  @doc "An unsigned profile event for `pubkey` at `created_at` carrying `fields`; a nil or absent field is left off the wire."
  @spec to_event(fields(), String.t(), non_neg_integer()) :: Event.t()
  def to_event(fields, pubkey, created_at) when is_map(fields) do
    content =
      %{"v" => @content_version}
      |> put_present("name", fields[:name])
      |> put_present("avatar", encode_avatar(fields[:avatar]))
      |> put_present("hue", fields[:hue])

    Event.new(%{
      pubkey: pubkey,
      created_at: created_at,
      kind: @kind,
      tags: [],
      content: Jason.encode!(content)
    })
  end

  @doc "The attrs a verified profile event carries, or why it is dropped."
  @spec from_event(Event.t()) ::
          {:ok, attrs()} | {:error, :wrong_kind | :bad_content | :unsupported_version}
  def from_event(%Event{kind: @kind} = event) do
    with {:ok, content} <- decode(event.content),
         :ok <- check_version(content),
         {:ok, name} <- read_name(content),
         {:ok, avatar} <- read_avatar(content),
         {:ok, hue} <- read_hue(content) do
      {:ok,
       %{
         pubkey: event.pubkey,
         name: name,
         avatar_type: avatar && avatar.type,
         avatar_bytes: avatar && avatar.bytes,
         hue: hue,
         raw_event: Event.to_map(event),
         created_at: event.created_at
       }}
    end
  end

  def from_event(%Event{}), do: {:error, :wrong_kind}

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp encode_avatar(nil), do: nil
  defp encode_avatar(avatar), do: %{"type" => avatar.type, "data" => Base.encode64(avatar.bytes)}

  defp decode(content) do
    case Jason.decode(content) do
      {:ok, %{} = map} -> {:ok, map}
      _other -> {:error, :bad_content}
    end
  end

  # An absent `v` means 1; an explicit null is not absent, as for activities.
  defp check_version(%{"v" => @content_version}), do: :ok
  defp check_version(%{"v" => _other}), do: {:error, :unsupported_version}
  defp check_version(_absent), do: :ok

  defp read_name(%{"name" => name}) when is_binary(name) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" -> {:ok, nil}
      String.length(trimmed) <= @max_name_length -> {:ok, trimmed}
      true -> {:error, :bad_content}
    end
  end

  defp read_name(%{"name" => nil}), do: {:ok, nil}
  defp read_name(%{"name" => _not_a_string}), do: {:error, :bad_content}
  defp read_name(_absent), do: {:ok, nil}

  # A reader never decodes an avatar: the type must be one of three, the
  # bytes must decode from base64, fit the cap and open with the type's
  # signature. Anything else drops the whole profile.
  defp read_avatar(%{"avatar" => %{"type" => type, "data" => data}})
       when is_binary(type) and is_binary(data) do
    with {:ok, {_ext, marks}} <- Map.fetch(@avatar_types, type),
         {:ok, bytes} <- Base.decode64(data),
         true <- byte_size(bytes) <= @max_avatar_bytes,
         true <- signature?(bytes, marks) do
      {:ok, %{type: type, bytes: bytes}}
    else
      _bad -> {:error, :bad_content}
    end
  end

  defp read_avatar(%{"avatar" => nil}), do: {:ok, nil}
  defp read_avatar(%{"avatar" => _wrong_shape}), do: {:error, :bad_content}
  defp read_avatar(_absent), do: {:ok, nil}

  # An integer angle on the ring, or none. Jason gives `195.0` as a float,
  # which is not an integer and drops the profile like a string would.
  defp read_hue(%{"hue" => hue}) when is_integer(hue),
    do: if(Hue.valid?(hue), do: {:ok, hue}, else: {:error, :bad_content})

  defp read_hue(%{"hue" => nil}), do: {:ok, nil}
  defp read_hue(%{"hue" => _not_an_angle}), do: {:error, :bad_content}
  defp read_hue(_absent), do: {:ok, nil}

  # Every mark of the type sits at its offset.
  defp signature?(bytes, marks) do
    Enum.all?(marks, fn {at, magic} ->
      size = byte_size(magic)
      byte_size(bytes) >= at + size and binary_part(bytes, at, size) == magic
    end)
  end
end
