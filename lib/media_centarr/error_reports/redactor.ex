defmodule MediaCentarr.ErrorReports.Redactor do
  @moduledoc """
  Strips sensitive and variable substrings from error text so that
  two users hitting the same bug produce the same fingerprint.

  Two passes:

  1. Active-config strip — exact-literal replacement of the TMDB API key
     and every configured external URL (Prowlarr, download client, etc.)
     with `<redacted:api_key>` / `<redacted:url>`.
  2. Regex substitutions — paths, UUIDs, IPs, emails, long digit runs.

  Unicode-aware; callers can assume input has been NFC-normalized.
  """

  alias MediaCentarr.Config
  alias MediaCentarr.Secret

  @min_secret_len 8

  @configured_url_keys [:prowlarr_url, :download_client_url]

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
    |> strip_active_config()
    |> apply_regex_rules()
    |> collapse_ws()
    |> String.trim()
  end

  @spec configured_urls() :: [binary()]
  def configured_urls do
    @configured_url_keys
    |> Enum.map(&Config.get/1)
    |> Enum.reject(&blank?/1)
  end

  defp strip_active_config(text) do
    text
    |> strip_api_key()
    |> strip_configured_urls()
  end

  defp strip_api_key(text) do
    value = Secret.expose(Config.get(:tmdb_api_key))

    if is_binary(value) and byte_size(value) >= @min_secret_len do
      String.replace(text, value, "<redacted:api_key>")
    else
      text
    end
  end

  defp strip_configured_urls(text) do
    Enum.reduce(configured_urls(), text, fn url, acc ->
      String.replace(acc, url, "<redacted:url>")
    end)
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

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end
