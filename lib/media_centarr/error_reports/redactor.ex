defmodule MediaCentarr.ErrorReports.Redactor do
  @moduledoc """
  Strips sensitive and variable substrings from error text so that
  two users hitting the same bug produce the same fingerprint.

  Two passes:

  1. Active-config strip — exact-literal replacement of the TMDB API key
     and every configured external URL (Prowlarr, download client, etc.)
     with `<redacted:api_key>` / `<redacted:url>`. Added in a later task.
  2. Regex substitutions — paths, UUIDs, IPs, emails, long digit runs.

  Unicode-aware; callers can assume input has been NFC-normalized.
  """

  @path_re ~r|(?<![A-Za-z0-9_])/(?:[^\s/"']+/){1,}[^\s/"']*|u
  @uuid_re ~r/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/iu
  @ipv4_re ~r/\b(?:\d{1,3}\.){3}\d{1,3}\b/u
  @email_re ~r/\b[\w.+-]+@[\w.-]+\.\w{2,}\b/u
  @digits_re ~r/\b\d{3,}\b/u
  @ws_re ~r/\s+/u

  @spec normalize(binary()) :: binary()
  def normalize(message) when is_binary(message) do
    message
    |> :unicode.characters_to_nfc_binary()
    |> apply_regex_rules()
    |> collapse_ws()
    |> String.trim()
  end

  defp apply_regex_rules(text) do
    text
    |> then(&Regex.replace(@uuid_re, &1, "<uuid>"))
    |> then(&Regex.replace(@path_re, &1, "<path>"))
    |> then(&Regex.replace(@email_re, &1, "<email>"))
    |> then(&Regex.replace(@ipv4_re, &1, "<ip>"))
    |> then(&Regex.replace(@digits_re, &1, "<N>"))
  end

  defp collapse_ws(text), do: Regex.replace(@ws_re, text, " ")
end
