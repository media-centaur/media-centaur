defmodule MediaCentaur.ErrorReports.Headline do
  @moduledoc """
  Derives the short, human-readable title an incident row shows from a
  Redactor-normalized error message.

  The input is one collapsed line (the Redactor folds newlines), so the
  grammar keys on the rigid textual shapes OTP and Elixir put in front
  of errors rather than on line boundaries:

    * `GenServer <name> terminating ** (Mod) msg …` — the *process* is
      the identity: `<name> crashed — Mod: msg`
    * `** (Mod) msg …` — the exception headlines: `Mod: msg`
    * anything else passes through, clamped.

  Stack-frame chatter after the message (`(ecto_sql 3.13.5) lib/…`) is
  cut at the first well-known dependency-frame marker. Display-only:
  fingerprint keys and the stored `display_title` (which feeds GitHub
  issue titles) are untouched.
  """

  @max_length 160

  @genserver_re ~r/^GenServer (?<name>.+?) terminating \*\* \((?<mod>[^)]+)\) (?<rest>.+)$/u
  # Unanchored: wrappers prefix the exception ("an exception was
  # raised: ** (KeyError) …") and the exception is still the headline.
  @exception_re ~r/\*\* \((?<mod>[^)]+)\) (?<rest>.+)$/u

  @frame_re ~r/ \((?:elixir|stdlib|kernel|media_centaur|ecto|ecto_sql|exqlite|db_connection|phoenix|phoenix_live_view|phoenix_pubsub|bandit|oban|broadway|req|finch|mint)[ )]/u

  # Last segments that identify nothing on their own — keep one parent
  # segment for context ("App.Error", not "Error").
  @generic_segments ~w(Error Exception)

  @spec derive(binary()) :: binary()
  def derive(message) when is_binary(message) do
    clamp(
      cond do
        captures = Regex.named_captures(@genserver_re, message) ->
          "#{process_name(captures["name"])} crashed — " <>
            "#{short_module(captures["mod"])}: #{trim_frames(captures["rest"])}"

        captures = Regex.named_captures(@exception_re, message) ->
          "#{short_module(captures["mod"])}: #{trim_frames(captures["rest"])}"

        true ->
          message
      end
    )
  end

  # Registered module names read well shortened; pid-ish names don't
  # survive redaction as anything a human can use.
  defp process_name(name) do
    if String.contains?(name, ["#", "<"]) do
      "GenServer"
    else
      name
      |> String.replace_prefix("Elixir.", "")
      |> String.replace_prefix("MediaCentaur.", "")
    end
  end

  defp short_module(module) do
    segments = String.split(module, ".")

    case Enum.reverse(segments) do
      [last, parent | _] when length(segments) > 2 and last in @generic_segments ->
        "#{parent}.#{last}"

      [last | _] when length(segments) > 2 ->
        last

      _ ->
        module
    end
  end

  defp trim_frames(rest) do
    rest
    |> String.split(@frame_re, parts: 2)
    |> hd()
    |> String.trim()
  end

  defp clamp(text) do
    if String.length(text) <= @max_length do
      text
    else
      String.slice(text, 0, @max_length) <> "…"
    end
  end
end
