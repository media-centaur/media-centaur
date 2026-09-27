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
  """

  alias MediaCentaur.Nostr.Event

  @kind 12_160
  @content_version 1
  @max_name_length 50

  @type attrs :: %{
          pubkey: String.t(),
          name: String.t() | nil,
          raw_event: map(),
          created_at: non_neg_integer()
        }

  @doc "The profile's kind number."
  @spec kind() :: 12_160
  def kind, do: @kind

  @doc "The name cap in characters; the Settings form and the protocol page mirror it."
  @spec max_name_length() :: 50
  def max_name_length, do: @max_name_length

  @doc "An unsigned profile event for `pubkey` at `created_at`; a nil name is left off the wire."
  @spec to_event(String.t() | nil, String.t(), non_neg_integer()) :: Event.t()
  def to_event(name, pubkey, created_at) do
    content = if name, do: %{"v" => @content_version, "name" => name}, else: %{"v" => @content_version}

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
         {:ok, name} <- read_name(content) do
      {:ok,
       %{pubkey: event.pubkey, name: name, raw_event: Event.to_map(event), created_at: event.created_at}}
    end
  end

  def from_event(%Event{}), do: {:error, :wrong_kind}

  defp decode(content) do
    case Jason.decode(content) do
      {:ok, %{} = map} -> {:ok, map}
      _other -> {:error, :bad_content}
    end
  end

  defp check_version(%{"v" => version}) when version in [nil, @content_version], do: :ok
  defp check_version(%{"v" => _other}), do: {:error, :unsupported_version}
  defp check_version(_content), do: :ok

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
end
