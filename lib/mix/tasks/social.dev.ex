defmodule Mix.Tasks.Social.Dev do
  @shortdoc "Act as a friend of the dev app against the dev relay"
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  The command line for the **dev friend**: a second Nostr identity, kept
  in `priv/dev-social/friend.nsec`, that publishes recommendations to the
  dev relay and reads back what the relay holds. It is how a Social
  feature gets "the other user" during development. `just social` prints
  the full setup walkthrough.

  Loads the app's config but never starts the app: nothing here opens the
  database or binds the dev port. Every relay exchange goes through
  `MediaCentaur.Nostr.OneShot`.

      mix social.dev npub
      mix social.dev recommend movie 603 --name "Sample Movie" --note "try it"
      mix social.dev feed
  """
  use Mix.Task

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.Filter
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Nostr.OneShot
  alias MediaCentaur.Recommendations.Translation
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.Format

  @default_relay "ws://127.0.0.1:2173"
  @default_dir "priv/dev-social"
  @kind 32_160

  @switches [
    dir: :string,
    relay: :string,
    name: :string,
    year: :string,
    poster_path: :string,
    overview: :string,
    note: :string
  ]

  @usage """
  mix social.dev — act as a friend of the dev app, against the dev relay

    mix social.dev npub
        Print the dev friend's npub (creating the key on first use).

    mix social.dev recommend <movie|tv_series> <tmdb_id> --name NAME [options]
        Publish a recommendation as the friend.
          --note TEXT           a note shown in the Feed
          --year YYYY           --poster-path /abc.jpg   --overview TEXT
          --relay URL           default #{@default_relay}
        Example:
          mix social.dev recommend movie 603 --name "Sample Movie" --note "try it"

    mix social.dev feed
        List every recommendation the dev relay holds, newest first.

  The friend's key lives in #{@default_dir}/friend.nsec (--dir to change).
  Run `just social` for the full setup walkthrough.
  """

  @impl true
  def run(args) do
    Mix.Task.run("app.config")

    Enum.each(
      [:bitcoinex, :mint_web_socket, :jason],
      &({:ok, _started} = Application.ensure_all_started(&1))
    )

    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)
    if invalid != [], do: fail("Unknown option: #{Enum.map_join(invalid, ", ", &elem(&1, 0))}")

    dispatch(positional, opts)
  end

  defp dispatch([], _opts), do: Mix.shell().info(@usage)
  defp dispatch(["help"], _opts), do: Mix.shell().info(@usage)

  defp dispatch(["npub"], opts),
    do: opts |> secret() |> Keys.pubkey() |> Keys.to_npub() |> Mix.shell().info()

  defp dispatch(["recommend", type, tmdb_id], opts), do: recommend(type, tmdb_id, opts)
  defp dispatch(["feed"], opts), do: feed(opts)
  defp dispatch(_other, _opts), do: fail("Unknown command.")

  # --- recommend ---------------------------------------------------------

  defp recommend(type, tmdb_id, opts) do
    media_type = parse_media_type(type)
    tmdb_id = parse_tmdb_id(tmdb_id)

    name =
      Keyword.get(opts, :name) ||
        fail("--name is required: the title's name as the Feed should show it.")

    secret = secret(opts)
    relay = Keyword.get(opts, :relay, @default_relay)

    title =
      Title.new!(%{
        tmdb_id: tmdb_id,
        media_type: media_type,
        name: name,
        year: opts[:year],
        poster_path: opts[:poster_path],
        overview: opts[:overview]
      })

    event = title |> Translation.to_event(opts[:note], Keys.pubkey(secret)) |> Event.sign(secret)

    case OneShot.publish(relay, event, signer(secret)) do
      :ok -> Mix.shell().info("Published #{Translation.address(title)} as the friend to #{relay}")
      {:error, reason} -> fail(relay_error(relay, reason))
    end
  end

  defp parse_media_type("movie"), do: :movie
  defp parse_media_type("tv_series"), do: :tv_series
  defp parse_media_type(other), do: fail("Media type must be movie or tv_series, got #{inspect(other)}.")

  defp parse_tmdb_id(text) do
    case Integer.parse(text) do
      {id, ""} when id > 0 -> id
      _other -> fail("TMDB id must be a positive integer, got #{inspect(text)}.")
    end
  end

  # --- feed --------------------------------------------------------------

  defp feed(opts) do
    secret = secret(opts)
    relay = Keyword.get(opts, :relay, @default_relay)
    own_pubkey = Keys.pubkey(secret)

    case OneShot.query(relay, [Filter.new(kinds: [@kind])], signer(secret)) do
      {:ok, []} ->
        Mix.shell().info("The relay holds no recommendations.")

      {:ok, events} ->
        events
        |> Enum.sort_by(& &1.created_at, :desc)
        |> Enum.map_join("\n", &feed_line(&1, own_pubkey))
        |> Mix.shell().info()

      {:error, reason} ->
        fail(relay_error(relay, reason))
    end
  end

  defp feed_line(%Event{} = event, own_pubkey) do
    author = if event.pubkey == own_pubkey, do: "friend", else: short_npub(event.pubkey)
    time = event.created_at |> DateTime.from_unix!() |> Format.relative_ago()

    case Translation.from_event(event) do
      {:ok, attrs} ->
        note = if attrs.note, do: "  — #{attrs.note}", else: ""
        "#{author}  #{Translation.address(attrs.title)}  #{inspect(attrs.title.name)}#{note}  (#{time})"

      {:error, reason} ->
        "#{author}  #{Event.tag_value(event, "d")}  <unreadable: #{reason}>  (#{time})"
    end
  end

  defp short_npub(pubkey), do: pubkey |> Keys.to_npub() |> String.slice(0, 12) |> Kernel.<>("…")

  # --- friend key --------------------------------------------------------

  defp secret(opts) do
    path = opts |> Keyword.get(:dir, @default_dir) |> Path.join("friend.nsec")

    case File.read(path) do
      {:ok, contents} -> contents |> String.trim() |> Keys.from_nsec() |> unwrap_secret(path)
      {:error, :enoent} -> create_secret(path)
      {:error, reason} -> fail("Could not read #{path}: #{:file.format_error(reason)}")
    end
  end

  defp unwrap_secret({:ok, secret}, _path), do: secret

  defp unwrap_secret({:error, _reason}, path),
    do: fail("#{path} does not hold a valid nsec. Delete it to start over.")

  defp create_secret(path) do
    secret = Keys.generate()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Keys.to_nsec(secret) <> "\n")
    File.chmod!(path, 0o600)
    secret
  end

  defp signer(secret), do: fn %Event{} = event -> Event.sign(event, secret) end

  # --- errors ------------------------------------------------------------

  defp relay_error(relay, {:disconnected, reason}),
    do: "Could not reach #{relay} (#{inspect(reason)}). Is the dev relay up? Try `just social-status`."

  defp relay_error(relay, {:auth_failed, reason}),
    do: "#{relay} rejected the friend's identity: #{reason}"

  defp relay_error(relay, :timeout), do: "#{relay} did not answer in time."

  defp relay_error(relay, reason) when is_binary(reason),
    do:
      "#{relay} refused: #{reason}\nIf the reason starts with restricted:, add the friend's npub to the relay: `just social-up`."

  @spec fail(String.t()) :: no_return()
  defp fail(message), do: Mix.raise(message <> "\n\n" <> @usage)
end
