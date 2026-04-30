defmodule MediaCentarr.Credo.Checks.TypedComponentAttrsTest do
  use Credo.Test.Case, async: true

  alias MediaCentarr.Credo.Checks.TypedComponentAttrs

  describe "scope" do
    test "ignores files outside lib/media_centarr_web/" do
      """
      defmodule MediaCentarr.SomeContext do
        attr :items, :list, required: true
      end
      """
      |> to_source_file("lib/media_centarr/some_context.ex")
      |> run_check(TypedComponentAttrs)
      |> refute_issues()
    end

    test "applies to files under lib/media_centarr_web/" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :items, :list, required: true
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(TypedComponentAttrs)
      |> assert_issue()
    end
  end

  describe "non-violations (negative cases)" do
    test "scalar types are not flagged" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :name, :string, required: true
        attr :count, :integer, default: 0
        attr :active, :boolean, default: false
        attr :status, :atom, default: nil
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(TypedComponentAttrs)
      |> refute_issues()
    end

    test "struct/schema types are not flagged" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :movie, MediaCentarr.Library.Movie, required: true
        attr :facet, Facet, required: true
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(TypedComponentAttrs)
      |> refute_issues()
    end

    test ":list with a doc: waiver is allowed" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :items, :list, required: true, doc: "list of `Item.t()`"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(TypedComponentAttrs)
      |> refute_issues()
    end

    test ":map with a doc: waiver is allowed" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :entity, :map, required: true, doc: "polymorphic library entity"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(TypedComponentAttrs)
      |> refute_issues()
    end

    test ":any with a doc: waiver is allowed" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :delete_confirm, :any, default: nil, doc: "transient confirm flag"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(TypedComponentAttrs)
      |> refute_issues()
    end

    test "multi-line doc waiver is allowed" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :facets, :list,
          default: [],
          doc: "list of Facet.t() structs"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(TypedComponentAttrs)
      |> refute_issues()
    end

    test "concatenated doc string is allowed" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :items, :list,
          required: true,
          doc: "list of " <> "Item.t()"
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(TypedComponentAttrs)
      |> refute_issues()
    end

    test "non-attr code is not flagged" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        def foo(), do: :list
        @attrs [:list, :map]
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(TypedComponentAttrs)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test ":list without doc: is flagged" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :items, :list, required: true
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(TypedComponentAttrs)
      |> assert_issue()
    end

    test ":map without doc: is flagged" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :entity, :map, required: true
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(TypedComponentAttrs)
      |> assert_issue()
    end

    test ":any without doc: is flagged" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :delete_confirm, :any, default: nil
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(TypedComponentAttrs)
      |> assert_issue()
    end

    test ":global without doc: is flagged" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :rest, :global, default: %{}
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(TypedComponentAttrs)
      |> assert_issue()
    end

    test "two-arg attr (no opts) is flagged for loose type" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :items, :list
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(TypedComponentAttrs)
      |> assert_issue()
    end

    test "empty doc string is not a valid waiver" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :items, :list, required: true, doc: ""
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(TypedComponentAttrs)
      |> assert_issue()
    end

    test "whitespace-only doc string is not a valid waiver" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :items, :list, required: true, doc: "   "
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(TypedComponentAttrs)
      |> assert_issue()
    end

    test "multiple violations in one module are all reported" do
      """
      defmodule MediaCentarrWeb.Components.Sample do
        attr :items, :list, required: true
        attr :entity, :map, required: true
        attr :flag, :any, default: nil
      end
      """
      |> to_source_file("lib/media_centarr_web/components/sample.ex")
      |> run_check(TypedComponentAttrs)
      |> assert_issues(fn issues -> length(issues) == 3 end)
    end
  end
end
