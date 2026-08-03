defmodule MediaCentaurWeb.Storybook.Incoming.Ledger do
  @moduledoc """
  The History archive — the History tab's whole content, always open:
  lifecycle filter chips (All leading and default) + title/release
  search, the grouped terminal rows bucketed under date-section
  headers in the quiet ledger vocabulary (dot · title · outcome word ·
  relative time; sentences only for failures and partials), a Show
  older row when the archive extends past the window, and storage as
  the ambient foot line.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Acquisition.ViewModels.{CurrentAction, PursuitRow}
  alias MediaCentaurWeb.IncomingLive.HistoryLogic

  def function, do: &MediaCentaurWeb.Components.Incoming.Ledger.ledger/1
  def render_source, do: :function
  def layout, do: :one_column

  @gib 1_073_741_824

  defp drives do
    [
      %{
        mount_point: "/mnt/media",
        device: "/dev/sda",
        total_bytes: 4000 * @gib,
        used_bytes: 1200 * @gib,
        usage_percent: 30,
        roles: [%{label: "Media dir", path: "/mnt/media"}]
      }
    ]
  end

  defp row(id, title, opts) do
    %PursuitRow{
      id: id,
      title: title,
      state: Keyword.fetch!(opts, :state),
      status: %CurrentAction{
        verb: Keyword.fetch!(opts, :verb),
        description: Keyword.fetch!(opts, :description),
        severity: Keyword.fetch!(opts, :severity)
      },
      updated_at: DateTime.add(DateTime.utc_now(), -Keyword.fetch!(opts, :hours_ago), :hour),
      season_number: opts[:season],
      episode_number: opts[:episode],
      units_satisfied: opts[:units_satisfied] || 1,
      units_wanted: opts[:units_wanted] || 1
    }
  end

  defp terminal_mix do
    [
      {:single,
       row("ledger-demo-1", "Safety Last!",
         state: :satisfied,
         verb: "Done",
         description: "File landed and identity verified.",
         severity: :success,
         hours_ago: 2
       )},
      {:group,
       %{
         title: "Sample Show",
         state: :cancelled,
         awaiting?: false,
         count: 3,
         verb: "Cancelled",
         severity: :info,
         expanded?: false,
         vms:
           for episode <- 1..3 do
             row("ledger-demo-group-#{episode}", "Sample Show",
               state: :cancelled,
               verb: "Cancelled",
               description: "Pursuit cancelled.",
               severity: :info,
               season: 2,
               episode: episode,
               hours_ago: 26
             )
           end
       }},
      {:single,
       row("ledger-demo-2", "Sample Documentary",
         state: :satisfied,
         verb: "Done",
         description: "File landed and identity verified.",
         severity: :success,
         units_satisfied: 10,
         units_wanted: 10,
         hours_ago: 30
       )},
      {:single,
       row("ledger-demo-3", "A Trip to the Moon",
         state: :exhausted,
         verb: "Gave up",
         description: "Exhausted after 3 attempts.",
         severity: :error,
         hours_ago: 96
       )},
      {:single,
       row("ledger-demo-4", "The Cabinet of Dr. Caligari",
         state: :cancelled,
         verb: "Cancelled",
         description: "Pursuit cancelled.",
         severity: :info,
         hours_ago: 120
       )}
    ]
  end

  defp expanded_group_mix do
    Enum.map(terminal_mix(), fn
      {:group, data} -> {:group, %{data | expanded?: true}}
      entry -> entry
    end)
  end

  # Bucketed through the real helper so the story pins the exact shape
  # the app hands the component — labels included.
  defp sections(entries), do: HistoryLogic.section_entries(entries, Date.utc_today())

  def variations do
    [
      %Variation{
        id: :archive,
        description:
          "The open archive: chips with All active, search on the right, quiet rows " <>
            "bucketed under date-section headers — dot, title, composite \"N of M\" chip " <>
            "where one exists, one colored outcome word, relative time. Only the failure " <>
            "carries its diagnostic sentence; the episode cluster folds behind its " <>
            "disclosure row. Storage on the foot line.",
        attributes: %{
          sections: sections(terminal_mix()),
          filter: :all,
          search: "",
          storage_drives: drives()
        }
      },
      %Variation{
        id: :group_expanded,
        description: "The episode cluster opened — members inset under the disclosure row.",
        attributes: %{
          sections: sections(expanded_group_mix()),
          filter: :all,
          search: ""
        }
      },
      %Variation{
        id: :more_beyond_window,
        description:
          "The archive extends past the loaded window — the quiet Show older row " <>
            "widens it by a page.",
        attributes: %{
          sections: sections(terminal_mix()),
          filter: :all,
          search: "",
          has_older?: true
        }
      },
      %Variation{
        id: :empty_filter,
        description:
          "A filter that matches nothing — the filter-specific honest answer; the chips " <>
            "stay so widening the filter stays possible.",
        attributes: %{
          sections: [],
          filter: :cancelled,
          search: ""
        }
      },
      %Variation{
        id: :no_history_at_all,
        description: "Nothing on record yet — All's own empty state.",
        attributes: %{
          sections: [],
          filter: :all,
          search: ""
        }
      }
    ]
  end
end
