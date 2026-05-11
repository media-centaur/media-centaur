defmodule MediaCentarr.Playback.DisplayEnv do
  @moduledoc """
  Resolves the display-server environment that mpv needs to open a window.

  The classic production failure: a systemd-user service starts before the
  graphical session has imported `WAYLAND_DISPLAY` / `DISPLAY` into its
  environment. mpv then aborts with status 1 and `--no-terminal` swallows
  the error message, leaving only the generic "mpv exited before playback
  started" classifier line.

  `resolve/1` produces an env list suitable for the `:env` option of
  `Port.open/2`. When the parent process already has display vars, they
  pass through. When neither is set, the resolver falls back to:

    * scanning `XDG_RUNTIME_DIR` for `wayland-N` sockets (lowest N wins)
    * scanning `/tmp/.X11-unix` for `XN` sockets (lowest N wins, mapped to
      `DISPLAY=:N`)

  If neither lookup yields a socket, `{:error, :no_display}` is returned and
  the caller should refuse to launch and surface a clear failure to the
  user — there is no GUI to render into.

  ## Why charlists

  Erlang ports take env tuples as `{key_charlist, value_charlist}`. The
  resolver returns the final shape so the caller can pass it straight
  through.
  """

  @type env_entry :: {charlist(), charlist()}

  @spec resolve(keyword()) :: {:ok, [env_entry]} | {:error, :no_display}
  def resolve(opts \\ []) do
    env = Keyword.get(opts, :env) || System.get_env()
    runtime_dir = Keyword.get(opts, :runtime_dir) || env["XDG_RUNTIME_DIR"]
    x11_dir = Keyword.get(opts, :x11_dir) || "/tmp/.X11-unix"

    wayland = env["WAYLAND_DISPLAY"] || find_wayland_socket(runtime_dir)
    display = env["DISPLAY"] || find_x11_display(x11_dir)

    case {wayland, display} do
      {nil, nil} ->
        {:error, :no_display}

      {wayland, display} ->
        {:ok, build_env(env, runtime_dir, wayland, display)}
    end
  end

  defp build_env(env, runtime_dir, wayland, display) do
    Enum.reject(
      [
        maybe_pair("WAYLAND_DISPLAY", wayland),
        maybe_pair("DISPLAY", display),
        maybe_pair("XDG_RUNTIME_DIR", runtime_dir || env["XDG_RUNTIME_DIR"]),
        maybe_pair("XDG_SESSION_TYPE", env["XDG_SESSION_TYPE"]),
        maybe_pair("XDG_CURRENT_DESKTOP", env["XDG_CURRENT_DESKTOP"])
      ],
      &is_nil/1
    )
  end

  defp maybe_pair(_key, nil), do: nil
  defp maybe_pair(key, value), do: {String.to_charlist(key), String.to_charlist(value)}

  defp find_wayland_socket(nil), do: nil

  defp find_wayland_socket(runtime_dir) do
    case File.ls(runtime_dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&wayland_socket?/1)
        |> Enum.sort_by(&socket_index/1)
        |> List.first()

      {:error, _reason} ->
        nil
    end
  end

  defp wayland_socket?(name) do
    String.match?(name, ~r/^wayland-\d+$/)
  end

  defp find_x11_display(x11_dir) do
    case File.ls(x11_dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&x11_socket?/1)
        |> Enum.sort_by(&socket_index/1)
        |> List.first()
        |> case do
          nil -> nil
          "X" <> n -> ":" <> n
        end

      {:error, _reason} ->
        nil
    end
  end

  defp x11_socket?(name) do
    String.match?(name, ~r/^X\d+$/)
  end

  defp socket_index(name) do
    name
    |> String.replace(~r/[^\d]/, "")
    |> String.to_integer()
  end
end
