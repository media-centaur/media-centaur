defmodule MediaCentaurWeb.Components.Detail.CastPanelTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.Components.Detail.CastPanel

  # Rendering and variation coverage lives in
  # `storybook/detail/cast_panel.story.exs` (enforced by MC0009). This file
  # keeps the play-target membership lookup, which is pure list logic.

  defp series(seasons), do: %{type: :tv_series, seasons: seasons}

  defp episode(number, ids, content_url \\ "/tv/sample.mkv") do
    %{episode_number: number, cast_person_ids: ids, content_url: content_url}
  end

  describe "lead_cast_ids/2" do
    test "the resume-target episode's membership wins" do
      entity =
        series([
          %{season_number: 1, episodes: [episode(1, [10]), episode(2, [20])]},
          %{season_number: 2, episodes: [episode(1, [30])]}
        ])

      assert CastPanel.lead_cast_ids(entity, {2, 1}) == [30]
    end

    test "without a resume target, the first present episode is what Play would start" do
      entity =
        series([
          %{
            season_number: 1,
            episodes: [episode(1, [10], nil), episode(2, [20])]
          }
        ])

      assert CastPanel.lead_cast_ids(entity, nil) == [20]
    end

    test "no present episode at all falls back to empty membership" do
      entity = series([%{season_number: 1, episodes: [episode(1, [10], nil)]}])

      assert CastPanel.lead_cast_ids(entity, nil) == []
    end

    test "a resume key pointing at a missing episode falls back to the first present one" do
      entity = series([%{season_number: 1, episodes: [episode(1, [10])]}])

      assert CastPanel.lead_cast_ids(entity, {4, 9}) == [10]
    end

    test "an episode without membership data yields empty ids (single-list degrade)" do
      entity = series([%{season_number: 1, episodes: [episode(1, [])]}])

      assert CastPanel.lead_cast_ids(entity, {1, 1}) == []
    end

    test "movies and entities without seasons have no lead episode" do
      assert CastPanel.lead_cast_ids(%{type: :movie}, nil) == []
      assert CastPanel.lead_cast_ids(%{type: :tv_series, seasons: nil}, nil) == []
    end
  end
end
