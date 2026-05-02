defmodule MediaCentarrWeb.Storybook.Composites.ModalShell do
  @moduledoc """
  Centered overlay shell for the DetailPanel.

  The modal is **always present in the DOM** — `open` toggles a
  `data-state` attribute that drives CSS visibility/opacity, so the
  browser's `backdrop-filter` compositing layer stays warm and there's
  no first-frame blur jank on open.

  Visibility uses the Elixir-controlled recipe from the storybook
  skill: each variation passes `open: true|false` directly. Variations
  that start closed pair with a `psb-assign` trigger button; variations
  that start open wire `on_close` to the same event so closing the
  modal updates the variation's assigns rather than walking it out of
  the DOM.

  All fixtures are minimally-shaped movie maps — TV-series and
  movie-series stories belong with `DetailPanel` (Phase 5), where the
  full season/episode contract lives.
  """

  use PhoenixStorybook.Story, :component

  alias Phoenix.LiveView.JS

  def function, do: &MediaCentarrWeb.Components.ModalShell.modal_shell/1
  def render_source, do: :function
  def layout, do: :one_column

  # Each variation renders a real `position: fixed` overlay, so they
  # would otherwise stack on top of each other in a shared DOM and
  # only the last would be visible. Iframing isolates them.
  def container, do: {:iframe, style: "min-height: 480px; width: 100%;"}

  def template do
    """
    <div>
      <button
        type="button"
        class="btn btn-sm btn-primary"
        phx-click={JS.push("psb-assign", value: %{open: true})}
        psb-code-hidden
      >
        Open modal
      </button>
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :closed,
        description:
          "Closed state — modal is in the DOM but visually hidden via " <>
            "`data-state=\"closed\"`. Click *Open modal* above to flip the " <>
            "assigns and exercise the open transition.",
        attributes: %{open: false, entity: nil}
      },
      %Variation{
        id: :open_movie,
        description:
          "Open — movie entity with backdrop placeholder, full metadata row, and a Play action.",
        attributes: %{
          open: true,
          entity: sample_movie(),
          on_close: close_event(:open_movie)
        }
      },
      %Variation{
        id: :open_movie_no_progress,
        description:
          "Open — same movie, no playback progress yet. The PlayCard renders without a remaining-time strip.",
        attributes: %{
          open: true,
          entity: sample_movie(),
          progress: nil,
          on_close: close_event(:open_movie_no_progress)
        }
      },
      %Variation{
        id: :open_movie_unavailable,
        description:
          "Open — `available={false}` (storage offline / file missing). The Hero suppresses backdrop, " <>
            "shows the film placeholder icon, and the Play action greys out.",
        attributes: %{
          open: true,
          entity: sample_movie(),
          available: false,
          on_close: close_event(:open_movie_unavailable)
        }
      },
      %Variation{
        id: :open_long_description,
        description:
          "Open — movie with a very long description and no metadata clamp, to verify the modal-panel " <>
            "scroll surface (single scroll container, close button pinned, atmospheric scrim covers " <>
            "the full scroll height).",
        attributes: %{
          open: true,
          entity: long_description_movie(),
          on_close: close_event(:open_long_description)
        }
      }
    ]
  end

  # --- Fixtures ----------------------------------------------------------

  defp close_event(variation_id) do
    {:eval, ~s|JS.push("psb-assign", value: %{variation_id: #{inspect(variation_id)}, open: false})|}
  end

  defp sample_movie do
    %{
      id: "movie-fixture-1",
      type: :movie,
      name: "Sample Movie",
      description:
        "A short placeholder description used for the storybook. " <>
          "It has enough text to exercise the four-line clamp without " <>
          "spilling into the metadata grid below.",
      tagline: "A demonstrative tagline",
      date_published: "2024-01-15",
      duration: "PT2H8M",
      director: "A. Director",
      original_language: "en",
      studio: "Sample Pictures",
      country_code: "US",
      content_rating: "PG-13",
      genres: ["Drama", "Adventure"],
      aggregate_rating_value: 7.8,
      vote_count: 1234,
      content_url: "/library/Movies/Sample.Movie.2024.1080p.mkv",
      status: :released,
      images: [],
      extras: []
    }
  end

  defp long_description_movie do
    description =
      Enum.map_join(1..12, " ", fn n ->
        "Paragraph #{n} of placeholder copy for the long-description variation, " <>
          "written long enough to overflow the modal panel and exercise the scroll surface."
      end)

    %{sample_movie() | description: description, name: "Sample Movie — Director's Cut"}
  end
end
