defmodule MediaCentarrWeb.Components.ComingUpMarqueeTest do
  use MediaCentarrWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias MediaCentarrWeb.Components.ComingUpMarquee
  alias MediaCentarrWeb.Components.ComingUpMarquee.{Item, Marquee}

  defp item(name, opts \\ []) do
    %Item{
      id: name,
      entity_id: Keyword.get(opts, :entity_id, "entity-" <> name),
      name: name,
      eyebrow: Keyword.get(opts, :eyebrow, "Tonight · S05E04"),
      badge: Keyword.get(opts, :badge, %{label: "Scheduled", variant: :default}),
      backdrop_url: Keyword.get(opts, :backdrop_url, "/img/" <> name <> "/backdrop.jpg"),
      logo_url: Keyword.get(opts, :logo_url, "/img/" <> name <> "/logo.png"),
      rollup: Keyword.get(opts, :rollup),
      sub: Keyword.get(opts, :sub)
    }
  end

  describe "coming_up_marquee/1" do
    test "renders hero with logo image when logo_url is present" do
      marquee = %Marquee{
        hero: item("Sample Show Sixteen", logo_url: "/img/hacks/logo.png"),
        secondaries: []
      }

      html = render_component(&ComingUpMarquee.coming_up_marquee/1, marquee: marquee)

      assert html =~ "/img/hacks/logo.png"
      assert html =~ "Sample Show Sixteen"
    end

    test "renders hero with typography fallback when logo_url is nil" do
      marquee = %Marquee{
        hero: item("Foundation", logo_url: nil),
        secondaries: []
      }

      html = render_component(&ComingUpMarquee.coming_up_marquee/1, marquee: marquee)

      assert html =~ "Foundation"
      refute html =~ "<img src=\"/img/Foundation/logo.png"
    end

    test "renders eyebrow, badge label, and rollup line on hero" do
      marquee = %Marquee{
        hero:
          item("Sample Show Sixteen",
            eyebrow: "Tonight · S05E04",
            badge: %{label: "Grabbed", variant: :success},
            rollup: "+ 6 more this season"
          ),
        secondaries: []
      }

      html = render_component(&ComingUpMarquee.coming_up_marquee/1, marquee: marquee)

      assert html =~ "Tonight"
      assert html =~ "S05E04"
      assert html =~ "Grabbed"
      assert html =~ "6 more"
    end

    test "renders all secondary tiles" do
      marquee = %Marquee{
        hero: item("Sample Show Sixteen"),
        secondaries: [
          item("Severance", eyebrow: "Tomorrow · 9 PM", sub: "S02E08"),
          item("Doc Now", eyebrow: "Sun · May 12", sub: "S04E01"),
          item("The Pitt", eyebrow: "Thu · May 09", sub: "+ 7 more")
        ]
      }

      html = render_component(&ComingUpMarquee.coming_up_marquee/1, marquee: marquee)

      assert html =~ "Severance"
      assert html =~ "Doc Now"
      assert html =~ "The Pitt"
      assert html =~ "Tomorrow"
      assert html =~ "Sun"
      assert html =~ "Thu"
    end

    test "sparse mode renders only the hero (no data-card='secondary' tiles)" do
      marquee = %Marquee{hero: item("Sample Show Sixteen"), secondaries: []}

      html = render_component(&ComingUpMarquee.coming_up_marquee/1, marquee: marquee)

      assert html =~ "data-card=\"hero\""
      refute html =~ "data-card=\"secondary\""
    end

    test "empty marquee (no hero) renders nothing" do
      marquee = %Marquee{hero: nil, secondaries: []}

      html = render_component(&ComingUpMarquee.coming_up_marquee/1, marquee: marquee)

      refute html =~ "data-component=\"coming-up-marquee\""
    end

    test "Item struct enforces all keys" do
      assert_raise ArgumentError, fn ->
        struct!(Item, %{id: 1, name: "X"})
      end
    end

    test "Marquee struct enforces hero and secondaries keys" do
      assert_raise ArgumentError, fn ->
        struct!(Marquee, %{hero: nil})
      end
    end
  end
end
