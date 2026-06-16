defmodule MediaCentaurWeb.Storybook.Guide.Markdown do
  @moduledoc """
  Reading typography for the in-app guide (`/guide`). `GuideMarkdown.prose/1`
  renders a chapter's markdown body to HEEx, styled by the `.guide-prose` CSS
  block. Variations pin each element family (prose, tables, callouts, code) so
  the typography is iterable in isolation, inside the same glass reading card the
  page uses.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.GuideMarkdown.prose/1
  def render_source, do: :function
  def layout, do: :one_column

  def template do
    """
    <div class="glass-surface rounded-xl px-8 py-7 max-w-[44rem]">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :prose,
        description: "Headings, paragraphs, a list, a link, inline code.",
        attributes: %{
          markdown: """
          ## How identification works

          When a file is detected it's processed through the **ingestion pipeline**:
          it parses the name, searches TMDB, and adds a match. The more standard the
          name (`Show S01E05.mkv`), the better it does.

          - Movies: `Title (2024).mkv`
          - Episodes: `Show S01E05.mkv`
          - Quality tags and release-group suffixes are stripped automatically

          See [the review queue](/guide/the-review-queue) for what happens when a
          match isn't confident.

          ### A sub-section

          Sub-headings stay calm and well-spaced for a comfortable reading column.
          """
        }
      },
      %Variation{
        id: :table,
        description: "A GFM table — quiet header, zebra rows.",
        attributes: %{
          markdown: """
          | Step | Required? | Unlocks |
          |---|---|---|
          | Media directories | Yes | File discovery |
          | TMDB | Yes | Identification, artwork |
          | mpv | No | Playback |
          | ffprobe | No | Track detection |
          """
        }
      },
      %Variation{
        id: :callouts,
        description: "All four callout kinds — note/tip calm, warning/important carry color.",
        attributes: %{
          markdown: """
          > [!NOTE]
          > A note reads calm — no decorative color, just a quiet icon.

          > [!TIP]
          > A tip surfaces an under-used capability without shouting.

          > [!WARNING]
          > A warning earns amber, because here color is a signal.

          > [!IMPORTANT]
          > Something important gets the primary accent.
          """
        }
      },
      %Variation{
        id: :code_block,
        description: "A fenced code block in a glass-inset panel.",
        attributes: %{
          markdown: """
          Raise the inotify watch limit and persist it:

          ```sh
          sudo sysctl fs.inotify.max_user_watches=524288
          echo 'fs.inotify.max_user_watches=524288' | sudo tee /etc/sysctl.d/40-media-centaur.conf
          ```
          """
        }
      }
    ]
  end
end
