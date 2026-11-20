defmodule MediaCentaur.Downloads.Wiring do
  @moduledoc """
  The wiring `prowlarr-stack` states for this computer: how a program on
  the host reaches Prowlarr and each download client, and with what
  credential (ADR-052, amended 2026-11-19).

  The stack writes it as one JSON document at the end of every `./setup`
  run, to `${XDG_STATE_HOME:-~/.local/state}/prowlarr-stack/wiring.json`,
  readable only by its user. Format 1:

      {
        "format": 1,
        "stack_version": "1.5.0",
        "prowlarr": {"url": "...", "api_key": "..."},
        "torrent":  {"type": "qbittorrent", "url": "...", "username": "...", "password": "..."},
        "usenet":   {"type": "sabnzbd", "url": "...", "api_key": "..."},
        "completed_dir": "/path"
      }

  `prowlarr` is required; a slot may be absent and is then left alone.
  The document is taken whole or not at all: an unknown format, a missing
  field, a client type with no driver, or a file another user can write
  is an error for all of it.

  Nothing here saves on its own. `proposal/0` compares the wiring with
  the saved connection settings by asking `Capabilities` what a save
  would change; `accept/1` saves through `Capabilities.save_integration/2`,
  the writer the Settings form uses; `decline/1` marks these values as
  declined so they are not proposed again. `completed_dir_status/0`
  says whether the completed directory of a wiring in use exists inside a
  media directory, for `Downloads.IncidentContext`. Trust is file ownership: there
  is no endpoint that stages or applies wiring.

  An instance in showcase mode reads no wiring: its Prowlarr and clients
  are stand-ins.
  """

  alias MediaCentaur.Capabilities
  alias MediaCentaur.Downloads.ClientConfig
  alias MediaCentaur.Downloads.Wiring.Proposal
  alias MediaCentaur.Secret
  alias MediaCentaur.Settings
  alias MediaCentaur.Settings.Config

  @format 1
  @declined_key "acquisition:wiring:declined"

  @enforce_keys [:prowlarr]
  defstruct [:stack_version, :prowlarr, :torrent, :usenet, :completed_dir]

  @type prowlarr :: %{url: String.t(), api_key: Secret.t()}
  @type torrent :: %{type: String.t(), url: String.t(), username: String.t(), password: Secret.t()}
  @type usenet :: %{type: String.t(), url: String.t(), api_key: Secret.t()}

  @type t :: %__MODULE__{
          stack_version: String.t() | nil,
          prowlarr: prowlarr(),
          torrent: torrent() | nil,
          usenet: usenet() | nil,
          completed_dir: String.t() | nil
        }

  @type reason ::
          {:unknown_format, term()}
          | :malformed
          | {:unsupported_client, String.t()}
          | :writable_by_others
          | {:unreadable, File.posix()}

  @doc """
  The file this instance reads, or nil in showcase mode. The
  `:stack_wiring_path` application setting replaces the default, which
  is how the test environment is kept off the real file.
  """
  @spec path() :: String.t() | nil
  def path do
    if !Config.get(:showcase_mode) do
      Application.get_env(:media_centaur, :stack_wiring_path) ||
        Path.join([
          System.get_env("XDG_STATE_HOME") || Path.expand("~/.local/state"),
          "prowlarr-stack",
          "wiring.json"
        ])
    end
  end

  @doc "Reads and validates the wiring file at `path`."
  @spec read(String.t() | nil) :: {:ok, t()} | :absent | {:error, reason()}
  def read(nil), do: :absent

  def read(path) do
    with {:ok, %File.Stat{mode: mode}} <- File.stat(path),
         :ok <- owner_only_writable(mode),
         {:ok, body} <- File.read(path) do
      parse(body)
    else
      {:error, :enoent} ->
        :absent

      {:error, posix} when is_atom(posix) and posix != :writable_by_others ->
        {:error, {:unreadable, posix}}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  What accepting the wiring would change, `:none` when there is no file,
  nothing differs, or these values were declined, or the reason the file
  cannot be used.
  """
  @spec proposal() :: :none | {:proposal, Proposal.t()} | {:error, reason()}
  def proposal do
    case read(path()) do
      :absent -> :none
      {:error, _reason} = error -> error
      {:ok, wiring} -> propose(wiring)
    end
  end

  @doc """
  Saves the wiring's connections, provided the file still holds the
  values the proposal with `digest` was built from; `:stale` otherwise.
  Returns the connections it carries, for the caller to verify.
  """
  @spec accept(String.t()) :: {:ok, [Capabilities.subject()]} | :stale
  def accept(digest) do
    with {:ok, wiring} <- read(path()),
         ^digest <- digest(wiring) do
      forms = forms(wiring)
      Enum.each(forms, fn {subject, params} -> Capabilities.save_integration(subject, params) end)
      {:ok, Enum.map(forms, &elem(&1, 0))}
    else
      _changed -> :stale
    end
  end

  @doc "Marks the values behind `digest` as declined."
  @spec decline(String.t()) :: :ok
  def decline(digest) when is_binary(digest) do
    Settings.find_or_create_entry!(%{key: @declined_key, value: %{"digest" => digest}})
    :ok
  end

  @doc """
  Whether finished downloads can be imported from where the stack puts
  them: `{:missing, dir}` when the completed directory does not exist,
  `{:not_watched, dir}` when it is outside every media directory. Judged
  only while the wiring is in use, meaning every connection it carries is
  saved as written; a wiring that is absent, unreadable, declined or only
  proposed is `:ok`.

  An unmounted directory that still exists as an empty mount point reads
  as present.
  """
  @spec completed_dir_status() :: :ok | {:missing, String.t()} | {:not_watched, String.t()}
  def completed_dir_status do
    with {:ok, %__MODULE__{completed_dir: dir} = wiring} when is_binary(dir) <- read(path()),
         true <- in_use?(wiring) do
      cond do
        not File.dir?(dir) -> {:missing, dir}
        not watched?(dir) -> {:not_watched, dir}
        true -> :ok
      end
    else
      _not_judged -> :ok
    end
  end

  defp in_use?(wiring) do
    Enum.all?(forms(wiring), fn {subject, params} ->
      Capabilities.integration_changes(subject, params) == []
    end)
  end

  defp propose(wiring) do
    digest = digest(wiring)

    connections =
      for {subject, params} <- forms(wiring),
          changes = Capabilities.integration_changes(subject, params),
          changes != [] do
        %{
          id: subject,
          url: params[url_field(subject)],
          new?: not Capabilities.configured?(subject),
          changes: changes
        }
      end

    if connections == [] or declined?(digest) do
      :none
    else
      {:proposal,
       %Proposal{
         digest: digest,
         connections: connections,
         completed_dir: wiring.completed_dir,
         completed_dir_watched?: watched?(wiring.completed_dir)
       }}
    end
  end

  # Each connection the wiring carries as the Settings form would submit
  # it, in the order the Acquisition section lists them.
  defp forms(%__MODULE__{} = wiring) do
    Enum.reject(
      [
        {:prowlarr,
         %{
           "prowlarr_url" => wiring.prowlarr.url,
           "prowlarr_api_key" => Secret.expose(wiring.prowlarr.api_key)
         }},
        wiring.torrent &&
          {:download_client,
           %{
             "download_client_type" => wiring.torrent.type,
             "download_client_url" => wiring.torrent.url,
             "download_client_username" => wiring.torrent.username,
             "download_client_password" => Secret.expose(wiring.torrent.password)
           }},
        wiring.usenet &&
          {:usenet_download_client,
           %{
             "usenet_download_client_type" => wiring.usenet.type,
             "usenet_download_client_url" => wiring.usenet.url,
             "usenet_download_client_api_key" => Secret.expose(wiring.usenet.api_key)
           }}
      ],
      &is_nil/1
    )
  end

  defp url_field(:prowlarr), do: "prowlarr_url"
  defp url_field(:download_client), do: "download_client_url"
  defp url_field(:usenet_download_client), do: "usenet_download_client_url"

  # Over the values only: a stack update that changes `stack_version` and
  # nothing else is the same wiring.
  defp digest(%__MODULE__{} = wiring) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary({forms(wiring), wiring.completed_dir}))
    |> Base.encode16(case: :lower)
  end

  defp declined?(digest) do
    match?(%{value: %{"digest" => ^digest}}, Settings.get_by_key(@declined_key))
  end

  defp watched?(nil), do: nil

  defp watched?(completed_dir) do
    completed = Path.split(Path.expand(completed_dir))

    Enum.any?(Config.get(:media_dirs) || [], fn media_dir ->
      List.starts_with?(completed, Path.split(Path.expand(media_dir)))
    end)
  end

  defp owner_only_writable(mode) when Bitwise.band(mode, 0o022) == 0, do: :ok
  defp owner_only_writable(_mode), do: {:error, :writable_by_others}

  defp parse(body) do
    case JSON.decode(body) do
      {:ok, %{"format" => @format} = document} -> build(document)
      {:ok, %{"format" => format}} -> {:error, {:unknown_format, format}}
      _other -> {:error, :malformed}
    end
  end

  defp build(document) do
    with {:ok, prowlarr} <- prowlarr(document["prowlarr"]),
         {:ok, torrent} <- slot(:torrent, document["torrent"]),
         {:ok, usenet} <- slot(:usenet, document["usenet"]),
         {:ok, completed_dir} <- optional_string(document["completed_dir"]),
         {:ok, stack_version} <- optional_string(document["stack_version"]) do
      {:ok,
       %__MODULE__{
         stack_version: stack_version,
         prowlarr: prowlarr,
         torrent: torrent,
         usenet: usenet,
         completed_dir: completed_dir
       }}
    end
  end

  defp prowlarr(%{"url" => url, "api_key" => api_key}) when is_binary(url) and is_binary(api_key),
    do: {:ok, %{url: url, api_key: Secret.wrap(api_key)}}

  defp prowlarr(_other), do: {:error, :malformed}

  defp slot(_protocol, nil), do: {:ok, nil}

  defp slot(protocol, %{"type" => type} = slot) when is_binary(type) do
    if ClientConfig.protocol_for_type(type) == protocol,
      do: credentials(protocol, slot),
      else: {:error, {:unsupported_client, type}}
  end

  defp slot(_protocol, _other), do: {:error, :malformed}

  defp credentials(:torrent, %{
         "type" => type,
         "url" => url,
         "username" => username,
         "password" => password
       })
       when is_binary(url) and is_binary(username) and is_binary(password),
       do: {:ok, %{type: type, url: url, username: username, password: Secret.wrap(password)}}

  defp credentials(:usenet, %{"type" => type, "url" => url, "api_key" => api_key})
       when is_binary(url) and is_binary(api_key),
       do: {:ok, %{type: type, url: url, api_key: Secret.wrap(api_key)}}

  defp credentials(_protocol, _slot), do: {:error, :malformed}

  defp optional_string(nil), do: {:ok, nil}
  defp optional_string(value) when is_binary(value), do: {:ok, value}
  defp optional_string(_other), do: {:error, :malformed}
end
