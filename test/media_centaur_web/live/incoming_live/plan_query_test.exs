defmodule MediaCentaurWeb.IncomingLive.PlanQueryTest do
  @moduledoc """
  The plan modal's address: two shapes (the board, the picker), built and
  parsed by one module so every link, patch and navigate agrees on them.
  """
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.IncomingLive.PlanQuery

  @plan_id "9f4f5e0e-0d1a-4b5c-8e2f-3a1b2c3d4e5f"

  describe "board/1 and picker/3 — the two shapes" do
    test "the board is the plan id alone" do
      assert PlanQuery.board("abc") == %{"plan" => "abc"}
    end

    test "the picker names the title, the id as a string" do
      assert PlanQuery.picker(246_810, "tv") ==
               %{"plan" => "new", "tmdb_id" => "246810", "tmdb_type" => "tv"}
    end

    test "the picker carries a mode only when given one" do
      assert PlanQuery.picker("550", "movie", :auto_select_best_release) ==
               %{
                 "plan" => "new",
                 "tmdb_id" => "550",
                 "tmdb_type" => "movie",
                 "mode" => "auto_select_best_release"
               }

      refute Map.has_key?(PlanQuery.picker("550", "movie", nil), "mode")
    end

    test "the picker refuses a type Incoming cannot target" do
      assert_raise FunctionClauseError, fn -> PlanQuery.picker("1", "book") end
    end
  end

  describe "path/1 — a query as a path to Incoming" do
    test "renders the board" do
      assert PlanQuery.path(PlanQuery.board("abc")) == "/incoming?plan=abc"
    end

    test "renders the picker with every param" do
      "/incoming?" <> query = PlanQuery.path(PlanQuery.picker("246810", "tv", :manually_select_release))

      assert URI.decode_query(query) == %{
               "plan" => "new",
               "tmdb_id" => "246810",
               "tmdb_type" => "tv",
               "mode" => "manually_select_release"
             }
    end
  end

  describe "parse/1 — Incoming's params" do
    test "no plan param is closed" do
      assert PlanQuery.parse(%{}) == :closed
      assert PlanQuery.parse(%{"zone" => "history"}) == :closed
    end

    test "a plan id is its board" do
      assert PlanQuery.parse(%{"plan" => @plan_id}) == {:board, @plan_id}
    end

    test "a plan id that is not a UUID is malformed, not a board to fetch" do
      assert PlanQuery.parse(%{"plan" => "abc"}) == {:error, :malformed}
      assert PlanQuery.parse(%{"plan" => ""}) == {:error, :malformed}
    end

    test "new with a title is the picker, mode nil when absent" do
      assert PlanQuery.parse(%{"plan" => "new", "tmdb_id" => "246810", "tmdb_type" => "tv"}) ==
               {:picker, "246810", "tv", nil}
    end

    test "new with a mode carries it as the atom" do
      assert PlanQuery.parse(%{
               "plan" => "new",
               "tmdb_id" => "550",
               "tmdb_type" => "movie",
               "mode" => "auto_select_best_release"
             }) == {:picker, "550", "movie", :auto_select_best_release}
    end

    test "round-trips what it builds" do
      assert PlanQuery.parse(PlanQuery.board(@plan_id)) == {:board, @plan_id}
      assert PlanQuery.parse(PlanQuery.picker("1", "tv")) == {:picker, "1", "tv", nil}

      assert PlanQuery.parse(PlanQuery.picker("1", "tv", :manually_select_release)) ==
               {:picker, "1", "tv", :manually_select_release}
    end

    test "a bad mode, a bad type, a missing id or a non-string plan is malformed" do
      assert PlanQuery.parse(%{"plan" => "new", "tmdb_id" => "1", "tmdb_type" => "tv", "mode" => "grab"}) ==
               {:error, :malformed}

      assert PlanQuery.parse(%{"plan" => "new", "tmdb_id" => "1", "tmdb_type" => "book"}) ==
               {:error, :malformed}

      assert PlanQuery.parse(%{"plan" => "new", "tmdb_type" => "tv"}) == {:error, :malformed}
      assert PlanQuery.parse(%{"plan" => ["abc"]}) == {:error, :malformed}
    end
  end
end
