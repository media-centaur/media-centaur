defmodule MediaCentaur.Credo.Checks.ActorAtTheEdgeTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.ActorAtTheEdge

  describe "clean code (negative cases)" do
    test "the web layer and playback may build an actor" do
      for path <- [
            "lib/media_centaur_web/live/profile_aware.ex",
            "lib/media_centaur/playback/progress_writer.ex"
          ] do
        ~S'''
        defmodule MediaCentaurWeb.Something do
          alias MediaCentaur.Profiles.Actor
          def actor(profile_id), do: Actor.new(profile_id)
        end
        '''
        |> to_source_file(path)
        |> run_check(ActorAtTheEdge)
        |> refute_issues()
      end
    end

    test "the core may match an actor and pass it on" do
      ~S'''
      defmodule MediaCentaur.Something do
        alias MediaCentaur.Profiles.Actor
        def share(%Actor{} = actor), do: actor.profile_id
      end
      '''
      |> to_source_file("lib/media_centaur/activities.ex")
      |> run_check(ActorAtTheEdge)
      |> refute_issues()
    end

    test "the module itself, and a test file, are exempt" do
      ~S'''
      defmodule MediaCentaur.Profiles.Actor do
        defstruct [:profile_id]
        def new(profile_id), do: %MediaCentaur.Profiles.Actor{profile_id: profile_id}
      end
      '''
      |> to_source_file("lib/media_centaur/profiles/actor.ex")
      |> run_check(ActorAtTheEdge)
      |> refute_issues()

      ~S'''
      defmodule MediaCentaur.SomethingTest do
        def actor, do: MediaCentaur.Profiles.Actor.new("p")
      end
      '''
      |> to_source_file("test/media_centaur/something_test.exs")
      |> run_check(ActorAtTheEdge)
      |> refute_issues()
    end
  end

  describe "violations" do
    test "a context, job or sweep building an actor" do
      ~S'''
      defmodule MediaCentaur.ReleaseTracking.Sweep do
        alias MediaCentaur.Profiles.Actor
        def run(title, profile_id), do: set_rung(title, :list, Actor.new(profile_id))
      end
      '''
      |> to_source_file("lib/media_centaur/release_tracking/sweep.ex")
      |> run_check(ActorAtTheEdge)
      |> assert_issue(%{trigger: "new"})
    end

    test "a struct literal, an update or struct/2 — even at the edge" do
      for body <- [
            "def forge(id), do: %Actor{profile_id: id}",
            "def forge(actor, id), do: %Actor{actor | profile_id: id}",
            "def forge(id), do: struct(Actor, profile_id: id)",
            "def forge(id), do: struct!(MediaCentaur.Profiles.Actor, profile_id: id)"
          ] do
        """
        defmodule MediaCentaurWeb.Forge do
          alias MediaCentaur.Profiles.Actor
          #{body}
        end
        """
        |> to_source_file("lib/media_centaur_web/forge.ex")
        |> run_check(ActorAtTheEdge)
        |> assert_issue()
      end
    end
  end
end
