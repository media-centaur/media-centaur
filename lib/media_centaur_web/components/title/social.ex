defmodule MediaCentaurWeb.Components.Title.Social do
  @moduledoc """
  What people did with a title, on the title detail's hero: the social
  capsule and the social panel it opens.

  The **social capsule** is a dark pill in the hero's upper right
  holding the title's social glyphs — the flags a friend flew
  (`SocialWords.drawn_flags/1`), each at its grade (`Grade.for_title/1`),
  its sentence on hover — then a chevron. It names no one. It is a
  button: pressing it opens the **social panel**, a glass panel anchored
  beneath it over the backdrop, which lists every review on the title
  (the identity tile, the name, the review's glyph at its grade, how
  long ago, the words when there are any), then one sentence per drawn
  flag that carries no words ("Nick, Sam and you watched this"). The
  panel is the one place the modal says who did each act.

  `capsule?/1` says whether a title has a capsule at all: a friend did
  something with it. The reader alone draws nothing — the bookmark, the
  watched state and the Review control already say what the reader did.

  The open state is the host's (`ModalState.open_menu == :social`);
  the capsule pushes `on_toggle`, and a click outside and BACK push
  `on_close` — the glass menu's dismissal (`GlassMenu`). The wrapper is
  the capsule's nav zone; its BACK edge carries the close event only
  while the panel is open. The panel's entries are not controls.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaur.Activities
  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Discovery.IdentityTile
  alias MediaCentaurWeb.Components.Title.Flag
  alias MediaCentaurWeb.Components.Title.Grade
  alias MediaCentaurWeb.Components.Title.SocialGlyph
  alias MediaCentaurWeb.Components.Title.SocialWords

  @type review :: %{
          id: String.t(),
          author: Person.t(),
          flag: Flag.flag(),
          grade: Grade.t(),
          text: String.t() | nil,
          acted_at: DateTime.t()
        }

  @type act :: %{flag: Flag.flag(), grade: Grade.t(), sentence: String.t()}

  @doc "Whether a title's rows earn a capsule: a friend did something with it."
  @spec capsule?([Activities.activity_row()]) :: boolean()
  def capsule?(rows), do: SocialWords.drawn_flags(rows) != []

  @doc """
  The social panel's content for one title's rows (newest first): every
  review in the rows' order, then one sentence per drawn flag that
  carries no words — watched and listing — in order.
  """
  @spec panel([Activities.activity_row()]) :: %{reviews: [review()], acts: [act()]}
  def panel(rows) do
    grades = Grade.for_title(rows)
    sentences = SocialWords.sentences(rows)

    reviews =
      for %{activity: %{kind: :review} = activity, author: author} <- rows do
        flag = Flag.flag(activity)

        %{
          id: activity.id,
          author: author,
          flag: flag,
          grade: Map.fetch!(grades, flag),
          text: activity.text,
          acted_at: activity.acted_at
        }
      end

    acts =
      for flag <- SocialWords.drawn_flags(rows), flag in [:watched, :listing] do
        %{flag: flag, grade: Map.fetch!(grades, flag), sentence: Map.fetch!(sentences, flag)}
      end

    %{reviews: reviews, acts: acts}
  end

  attr :id, :string, required: true, doc: "the capsule button's id; the panel is `<id>-panel`"
  attr :rows, :list, required: true, doc: "the title's `Activities.activity_for/1` rows"
  attr :open, :boolean, required: true
  attr :zone, :string, required: true, doc: "the wrapper's `data-nav-zone`, declared in `config.js`"
  attr :on_toggle, :string, required: true, doc: "the event the capsule pushes"
  attr :on_close, :string, required: true, doc: "the event a click outside and BACK push while open"
  attr :now, DateTime, default: nil, doc: "anchors the reviews' ages; now when nil"

  @doc "The social capsule and, while open, the social panel beneath it."
  def social_capsule(assigns) do
    rows = assigns.rows

    assigns =
      assign(assigns,
        flags: SocialWords.drawn_flags(rows),
        grades: Grade.for_title(rows),
        sentences: SocialWords.sentences(rows)
      )

    ~H"""
    <div
      :if={@flags != []}
      class="social-capsule-anchor"
      data-nav-zone={@zone}
      data-nav-dismiss-event={@open && @on_close}
      phx-click-away={@open && @on_close}
    >
      <button
        id={@id}
        type="button"
        class="social-capsule"
        aria-label="What friends did"
        aria-haspopup="dialog"
        aria-expanded={to_string(@open)}
        aria-controls={@id <> "-panel"}
        phx-click={@on_toggle}
        data-nav-item
        tabindex="0"
      >
        <SocialGlyph.social_glyphs flags={@flags} grades={@grades} titles={@sentences} class="gap-3" />
        <span class={["social-capsule-chevron", @open && "rotate-180"]}>
          <.icon name="hero-chevron-down-mini" class="size-4" />
        </span>
      </button>
      <.social_panel :if={@open} id={@id <> "-panel"} rows={@rows} now={@now} />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true, doc: "the title's `Activities.activity_for/1` rows"
  attr :now, DateTime, default: nil, doc: "anchors the reviews' ages; now when nil"

  @doc "The social panel: every review on the title, then the sentences for the acts without words."
  def social_panel(assigns) do
    assigns =
      assigns
      |> assign(:content, panel(assigns.rows))
      |> assign(:now, assigns.now || DateTime.utc_now())

    ~H"""
    <div
      id={@id}
      class="social-panel glass-surface thin-scrollbar"
      role="dialog"
      aria-label="What friends did"
    >
      <div
        :for={review <- @content.reviews}
        id={@id <> "-review-" <> review.id}
        class="social-panel-review"
        data-role="review"
      >
        <IdentityTile.identity_tile person={review.author} size={32} />
        <div class="min-w-0 flex-1">
          <p class="flex items-center gap-2 text-[15px] leading-[22px]">
            <span class="font-semibold text-base-content/95">{Format.person_name(review.author)}</span>
            <SocialGlyph.social_glyph flag={review.flag} grade={review.grade} class="size-4" />
            <span class="ml-auto shrink-0 text-[13px] text-base-content/60">
              {Format.relative_ago(review.acted_at, now: @now, sub_minute: :just_now)}
            </span>
          </p>
          <p :if={review.text} class="mt-0.5 text-sm leading-[21px] text-base-content/80">
            {review.text}
          </p>
        </div>
      </div>
      <div :if={@content.acts != []} class="social-panel-acts">
        <p
          :for={act <- @content.acts}
          class="flex items-center gap-2.5 text-sm text-base-content/80"
          data-role="act"
          data-flag={act.flag}
        >
          <SocialGlyph.social_glyph flag={act.flag} grade={act.grade} class="size-4" />
          {act.sentence}
        </p>
      </div>
    </div>
    """
  end
end
