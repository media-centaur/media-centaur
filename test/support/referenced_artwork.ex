defmodule MediaCentaur.ReferencedArtwork do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Seeds the referenced artwork cache — `TmdbArtwork`'s files under
  `{data_dir}/images/tmdb/<type>-<id>/` — with placeholder bytes for a
  TMDB identity, for tests that read the cache through the real
  filesystem: `TmdbArtwork`'s own, and pages whose artwork walks
  `TitleArtwork`'s ladder. The caller points the config's `data_dir` at
  a temporary directory first (a `:persistent_term` write, legal in an
  `async: false` module and restored by the checkout).
  """

  @type role :: :poster | :backdrop | :logo

  @spec seed_referenced_artwork(String.t(), atom() | String.t(), integer(), [role()]) :: String.t()
  def seed_referenced_artwork(data_dir, type, id, roles) do
    dir = Path.join([data_dir, "images", "tmdb", "#{type}-#{id}"])
    File.mkdir_p!(dir)

    Enum.each(roles, fn role ->
      filename = if role == :logo, do: "logo.png", else: "#{role}.jpg"
      File.write!(Path.join(dir, filename), :binary.copy("x", 60_000))
    end)

    dir
  end
end
