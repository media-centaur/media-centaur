defmodule MediaCentaur.Downloads.WiringStackAgreementTest do
  @moduledoc """
  The file `prowlarr-stack` writes is a file `Wiring` reads. The stack's own
  `write_wiring` runs against a sample install, and its output goes through
  `Wiring.read/1` and `Wiring.proposal/0`, so a field renamed on either side
  fails here before a release carries it.

  The stack's checkout is `PROWLARR_STACK_DIR`, or the sibling directory
  `../prowlarr-stack`. CI checks it out at its `main`.
  """

  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Downloads.Wiring
  alias MediaCentaur.Secret

  @moduletag :tmp_dir

  @write_wiring ~S"""
  set -eu
  source ./scripts/lib/common
  write_wiring "$1" "v0.0.0"
  wiring_path
  """

  setup %{tmp_dir: tmp_dir} do
    stack_dir = System.get_env("PROWLARR_STACK_DIR") || Path.expand("../prowlarr-stack")

    if !File.exists?(Path.join(stack_dir, "scripts/lib/common")) do
      flunk("""
      No prowlarr-stack checkout at #{stack_dir}. Clone
      https://github.com/media-centaur/prowlarr-stack beside this repository,
      or set PROWLARR_STACK_DIR to a checkout.
      """)
    end

    install = Path.join(tmp_dir, "install")
    File.mkdir_p!(Path.join(install, "config/prowlarr"))

    File.write!(Path.join(install, ".env"), """
    QBITTORRENT_PASSWORD=sample-password
    SABNZBD_API_KEY=0123456789abcdef0123456789abcdef
    COMPLETED_DIR=/mnt/sample/completed
    """)

    File.write!(
      Path.join(install, "config/prowlarr/config.xml"),
      "<Config><ApiKey>abcdef0123456789abcdef0123456789</ApiKey></Config>\n"
    )

    {output, 0} =
      System.cmd("bash", ["-c", @write_wiring, "bash", install],
        cd: stack_dir,
        env: [{"XDG_STATE_HOME", Path.join(tmp_dir, "state")}],
        stderr_to_stdout: true
      )

    path = output |> String.split("\n", trim: true) |> List.last()
    Application.put_env(:media_centaur, :stack_wiring_path, path)
    %{path: path}
  end

  test "the stack's file reads as a wiring with every connection", %{path: path} do
    assert {:ok, %Wiring{} = wiring} = Wiring.read(path)

    assert wiring.stack_version == "v0.0.0"
    assert wiring.prowlarr.url == "http://127.0.0.1:9696"
    assert Secret.expose(wiring.prowlarr.api_key) == "abcdef0123456789abcdef0123456789"

    assert %{type: "qbittorrent", url: "http://127.0.0.1:8080", username: "admin"} = wiring.torrent
    assert Secret.expose(wiring.torrent.password) == "sample-password"

    assert %{type: "sabnzbd", url: "http://127.0.0.1:8085"} = wiring.usenet
    assert Secret.expose(wiring.usenet.api_key) == "0123456789abcdef0123456789abcdef"

    assert wiring.completed_dir == "/mnt/sample/completed"
  end

  test "the stack's file is proposed and accepted whole", %{path: _path} do
    assert {:proposal, proposal} = Wiring.proposal()

    assert [:prowlarr, :download_client, :usenet_download_client] =
             Enum.map(proposal.connections, & &1.id)

    assert {:ok, [:prowlarr, :download_client, :usenet_download_client]} =
             Wiring.accept(proposal.digest)

    assert Wiring.proposal() == :none
  end
end
