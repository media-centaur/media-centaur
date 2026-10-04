defmodule MediaCentaurWeb.Storybook.CoreComponents.PictureField do
  use PhoenixStorybook.Story, :component

  alias Phoenix.LiveView.UploadConfig
  alias Phoenix.LiveView.UploadEntry

  def function, do: &MediaCentaurWeb.Components.PictureField.picture_field/1
  def render_source, do: :function
  def aliases, do: [MediaCentaurWeb.Components.AppCards]

  def template do
    ~s|<div class="max-w-md"><.psb-variation/></div>|
  end

  def variations do
    [
      %VariationGroup{
        id: :banner,
        description:
          "An app's banner at 460:215 (Apps → Manage, the manual form): nothing stored, " <>
            "a stored banner with Remove, and a chosen file with the crop stage and its preview in the card's frame. " <>
            "The chosen file's preview is the browser's own object URL, so it is blank here.",
        variations: [
          banner(:banner_empty, upload(:banner), nil),
          banner(:banner_stored, upload(:banner), "/media-images/images/apps/demo-1/banner.jpg"),
          banner(:banner_chosen, upload(:banner, [entry(:banner, "sample-banner.png")]), nil)
        ]
      },
      %VariationGroup{
        id: :avatar,
        description:
          "The profile picture at 1:1 (Settings → Social → Your profile), inside a Settings field, " <>
            "so no label of its own; the previews are the identity tile's rings.",
        variations: [
          avatar(:avatar_stored, upload(:avatar), true),
          avatar(:avatar_chosen, upload(:avatar, [entry(:avatar, "sample-picture.png")]), false)
        ]
      },
      %Variation{
        id: :rejected,
        description: "A file of the wrong type: the entry's error beside its name, and no crop stage.",
        attributes: %{
          id: "story-rejected",
          upload:
            upload(:banner, [%{entry(:banner, "notes.txt") | valid?: false}],
              errors: [{"0", :not_accepted}]
            ),
          aspect: {460, 215},
          label: "Banner",
          noun: "image",
          removable?: false,
          remove_event: "remove_banner",
          cancel_event: "cancel_banner"
        },
        slots: [banner_current(nil), banner_preview()]
      }
    ]
  end

  defp banner(id, upload, banner_url) do
    %Variation{
      id: id,
      attributes: %{
        id: "story-#{id}",
        upload: upload,
        aspect: {460, 215},
        label: "Banner",
        noun: "image",
        removable?: banner_url != nil,
        remove_event: "remove_banner",
        cancel_event: "cancel_banner"
      },
      slots: [banner_current(banner_url), banner_preview()]
    }
  end

  defp banner_current(banner_url) do
    """
    <:current>
      <AppCards.banner_art name="Sample App" banner_url={#{inspect(banner_url)}} class="w-32 shrink-0" />
    </:current>
    """
  end

  defp banner_preview do
    """
    <:preview>
      <AppCards.banner_art name="Sample App" class="w-32 shrink-0">
        <canvas data-role="preview" width="460" height="215" class="absolute inset-0 size-full"></canvas>
      </AppCards.banner_art>
    </:preview>
    """
  end

  defp avatar(id, upload, stored?) do
    %Variation{
      id: id,
      attributes: %{
        id: "story-#{id}",
        upload: upload,
        aspect: {1, 1},
        removable?: stored?,
        remove_event: "remove_avatar",
        cancel_event: "cancel_avatar"
      },
      slots: [
        """
        <:current>
          <span class="grid size-12 place-items-center rounded-full bg-base-content/10 text-lg font-semibold">S</span>
        </:current>
        """,
        """
        <:preview>
          <span class="identity-tile identity-tile-own identity-tile-avatar relative grid size-12 shrink-0 place-items-center overflow-hidden rounded-full">
            <canvas data-role="preview" width="48" height="48" class="size-full"></canvas>
          </span>
          <span class="identity-tile identity-tile-own identity-tile-avatar relative grid size-10 shrink-0 place-items-center overflow-hidden rounded-full">
            <canvas data-role="preview" width="40" height="40" class="size-full"></canvas>
          </span>
        </:preview>
        """
      ]
    }
  end

  # An upload as `allow_upload/3` with `PictureField.upload_options/0`
  # leaves it, with the entries a chosen file adds.
  defp upload(name, entries \\ [], extra \\ []) do
    struct(
      %UploadConfig{
        name: name,
        ref: "phx-story-#{name}",
        accept: ".jpg,.jpeg,.png,.webp",
        max_entries: 1,
        max_file_size: 10_000_000,
        allowed?: true,
        entries: entries
      },
      extra
    )
  end

  defp entry(name, client_name) do
    %UploadEntry{
      ref: "0",
      upload_ref: "phx-story-#{name}",
      upload_config: name,
      client_name: client_name,
      client_type: "image/png",
      valid?: true
    }
  end
end
