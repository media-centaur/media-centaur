defmodule MediaCentaurWeb.Components.PictureField do
  @moduledoc """
  The app's one picture field: a person chooses a picture, picks the
  region that shows at the master's fixed shape, and the save cuts the
  master from it (`ImageFiles.webp_master/4`, `jpeg_master/3`). The
  profile avatar is this at 1:1 (Settings → Social → Your profile); an
  app's banner at 460:215 (Apps → Manage, the manual form).

  The field sits inside the caller's form, over a LiveView upload made
  with `upload_options/0`. Its row: the `:current` slot (what is stored
  now — the identity tile, the banner), **Choose …**, and **Remove** while
  something is stored, nothing is chosen and no Remove is pending
  (`removable?`). While a file is chosen, the crop stage: the entry's
  `live_img_preview` under the `ImageCrop` hook (croppr, vendored), which
  draws a box locked to `aspect` over it — moved and resized by pointer,
  the resize being the scaling — and writes it into four hidden fields,
  `crop_x`, `crop_y`, `crop_width`, `crop_height`, in the picture's
  oriented pixels, that ride the form's submit (`crop_from_params/1`).
  Below the stage, the `:preview` slot: frames each holding a
  `<canvas data-role="preview">` the hook paints with the box, its width
  and height attributes in the master's shape — *How it will look*. Then
  the file's name, its errors and Cancel. The box has no keyboard path
  until the input system learns one (arrows on a focused element are
  navigation today).

  `rest` lands on the root: the profile's pending hue rides there, so it
  reaches the previews inside the hook's ignored subtree by inheritance.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1]

  alias Phoenix.LiveView.JS

  @doc """
  The upload's options, for `allow_upload/3`: one file, the three types a
  browser can preview and libvips can cut, capped well above any sensible
  source (every master is small).
  """
  @spec upload_options() :: keyword()
  def upload_options, do: [accept: ~w(.jpg .jpeg .png .webp), max_entries: 1, max_file_size: 10_000_000]

  @doc """
  Cancels the upload's rejected entries (wrong type, too large): they
  never upload, so `consume_uploaded_entries/3` refuses to run while one
  is listed. Called on save, before consuming; the field has already
  shown the entry's error.
  """
  @spec drop_rejected(Phoenix.LiveView.Socket.t(), atom()) :: Phoenix.LiveView.Socket.t()
  def drop_rejected(socket, name) do
    socket.assigns.uploads
    |> Map.fetch!(name)
    |> Map.fetch!(:entries)
    |> Enum.reject(& &1.valid?)
    |> Enum.reduce(socket, &Phoenix.LiveView.cancel_upload(&2, name, &1.ref))
  end

  @doc """
  The rectangle the person dragged over the picture, as the form's four
  fields; empty, missing or malformed is nil, the centred rectangle.
  """
  @spec crop_from_params(map()) :: MediaCentaur.ImageFiles.crop() | nil
  def crop_from_params(params) do
    with {x, ""} <- parse_crop_field(params, "crop_x"),
         {y, ""} <- parse_crop_field(params, "crop_y"),
         {width, ""} <- parse_crop_field(params, "crop_width"),
         {height, ""} <- parse_crop_field(params, "crop_height") do
      {x, y, width, height}
    else
      _empty_or_bad -> nil
    end
  end

  defp parse_crop_field(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) -> Integer.parse(value)
      _absent_or_not_a_string -> :error
    end
  end

  attr :id, :string,
    required: true,
    doc: "names the controls: `choose-<id>`, `remove-<id>`, `<id>-crop-<ref>`"

  attr :upload, Phoenix.LiveView.UploadConfig,
    required: true,
    doc: "the field's upload, made with `upload_options/0`"

  attr :aspect, :any,
    required: true,
    doc: "the master's shape as `{width, height}`; the crop box is locked to it"

  attr :label, :string,
    default: nil,
    doc:
      "a label over the field in core `.input`'s style, for a plain form; a Settings field brings its own"

  attr :noun, :string,
    default: "picture",
    doc: "the field's word for its file: Choose picture, One picture"

  attr :removable?, :boolean, required: true, doc: "something is stored and no Remove is pending"
  attr :remove_event, :string, required: true, doc: "pushed by Remove; the removal waits for the save"
  attr :cancel_event, :string, required: true, doc: "pushed by Cancel with the entry's `ref`"
  attr :rest, :global, doc: "on the root: a `style` the previews inherit"

  slot :current, required: true, doc: "what is stored now, beside Choose"

  slot :preview,
    required: true,
    doc: ~s|inside the crop stage: frames holding `<canvas data-role="preview">` in the master's shape|

  def picture_field(assigns) do
    ~H"""
    <div data-role="picture-field" class={@label && "fieldset mb-2"} {@rest}>
      <span :if={@label} class="label mb-1">{@label}</span>
      <div class="flex items-center gap-3">
        {render_slot(@current)}
        <.live_file_input upload={@upload} class="sr-only" />
        <.button
          id={"choose-#{@id}"}
          type="button"
          variant="neutral"
          size="sm"
          phx-click={JS.dispatch("click", to: "##{@upload.ref}")}
          data-nav-item
          tabindex="0"
        >
          Choose {@noun}
        </.button>
        <.button
          :if={@removable? && @upload.entries == []}
          id={"remove-#{@id}"}
          type="button"
          variant="dismiss"
          size="xs"
          phx-click={@remove_event}
          data-nav-item
          tabindex="0"
        >
          Remove
        </.button>
      </div>
      <p :for={err <- upload_errors(@upload)} class="mt-2 text-xs text-error">
        {error_words(err, @upload, @noun)}
      </p>
      <div :for={entry <- @upload.entries} class="mt-3 space-y-3" data-role="pending-picture">
        <div
          :if={entry.valid?}
          id={"#{@id}-crop-#{entry.ref}"}
          phx-hook="ImageCrop"
          phx-update="ignore"
          data-aspect={aspect_ratio(@aspect)}
          class="image-crop"
        >
          <div class="image-crop-stage">
            <.live_img_preview entry={entry} data-role="source" alt="" />
          </div>
          <input type="hidden" name="crop_x" value="" />
          <input type="hidden" name="crop_y" value="" />
          <input type="hidden" name="crop_width" value="" />
          <input type="hidden" name="crop_height" value="" />
          <div class="mt-3 flex items-center gap-3">
            {render_slot(@preview)}
            <span class="text-xs text-base-content/60">How it will look</span>
          </div>
        </div>
        <p class="flex items-center gap-2 text-xs text-base-content/60">
          <span class="truncate">{entry.client_name}</span>
          <span :for={err <- upload_errors(@upload, entry)} class="text-error">
            {error_words(err, @upload, @noun)}
          </span>
          <.button
            type="button"
            variant="dismiss"
            size="xs"
            phx-click={@cancel_event}
            phx-value-ref={entry.ref}
            data-nav-item
            tabindex="0"
          >
            Cancel
          </.button>
        </p>
      </div>
    </div>
    """
  end

  # croppr's ratio is the hook's to invert; the field carries width / height.
  defp aspect_ratio({width, height}), do: Float.to_string(width / height)

  # `Phoenix.Component.upload_errors/1,2`: the whole-upload error and the
  # two an entry can carry under the accept and size caps.
  defp error_words(:too_many_files, _upload, noun), do: "One #{noun}"

  defp error_words(:too_large, %{max_file_size: bytes}, _noun),
    do: "Larger than #{div(bytes, 1_000_000)} MB"

  defp error_words(:not_accepted, _upload, _noun), do: "Not a JPEG, PNG or WebP"
end
