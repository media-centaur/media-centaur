defmodule MediaCentaur.Credo.Checks.PubSubTransportTest do
  use Credo.Test.Case, async: true

  alias MediaCentaur.Credo.Checks.PubSubTransport

  describe "clean code (negative cases)" do
    test "publishing through the Topics seam is allowed" do
      ~S'''
      defmodule MediaCentaur.Review.Intake do
        alias MediaCentaur.Topics

        def announce(id) do
          Topics.publish(Topics.review_updates(), {:file_added, id})
        end
      end
      '''
      |> to_source_file("lib/media_centaur/review/intake.ex")
      |> run_check(PubSubTransport)
      |> refute_issues()
    end

    test "subscribing through the Topics seam is allowed" do
      ~S'''
      defmodule MediaCentaur.Review do
        alias MediaCentaur.Topics

        def subscribe, do: Topics.subscribe(Topics.review_updates())
      end
      '''
      |> to_source_file("lib/media_centaur/review.ex")
      |> run_check(PubSubTransport)
      |> refute_issues()
    end

    test "topics.ex itself may call Phoenix.PubSub — it is the seam" do
      ~S'''
      defmodule MediaCentaur.Topics do
        @pubsub MediaCentaur.PubSub

        def publish(topic, message), do: Phoenix.PubSub.broadcast(@pubsub, topic, message)
        def subscribe(topic), do: Phoenix.PubSub.subscribe(@pubsub, topic)
        def unsubscribe(topic), do: Phoenix.PubSub.unsubscribe(@pubsub, topic)
      end
      '''
      |> to_source_file("lib/media_centaur/topics.ex")
      |> run_check(PubSubTransport)
      |> refute_issues()
    end

    test "the application child spec naming the server is not a call site" do
      ~S'''
      defmodule MediaCentaur.Application do
        def start(_type, _args) do
          children = [{Phoenix.PubSub, name: MediaCentaur.PubSub}]
          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end
      '''
      |> to_source_file("lib/media_centaur/application.ex")
      |> run_check(PubSubTransport)
      |> refute_issues()
    end

    test "test files may drive PubSub directly" do
      ~S'''
      defmodule MediaCentaur.ReviewTest do
        use MediaCentaur.DataCase

        test "broadcasts" do
          Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "review:updates")
        end
      end
      '''
      |> to_source_file("test/media_centaur/review_test.exs")
      |> run_check(PubSubTransport)
      |> refute_issues()
    end
  end

  describe "violations (positive cases)" do
    test "Phoenix.PubSub.broadcast outside the seam is reported" do
      ~S'''
      defmodule MediaCentaur.Review.Intake do
        alias MediaCentaur.Topics

        def announce(id) do
          Phoenix.PubSub.broadcast(MediaCentaur.PubSub, Topics.review_updates(), {:file_added, id})
        end
      end
      '''
      |> to_source_file("lib/media_centaur/review/intake.ex")
      |> run_check(PubSubTransport)
      |> assert_issue()
    end

    test "Phoenix.PubSub.subscribe outside the seam is reported" do
      ~S'''
      defmodule MediaCentaur.Status.Views.Overview do
        def start do
          Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "review:updates")
        end
      end
      '''
      |> to_source_file("lib/media_centaur/status/views/overview.ex")
      |> run_check(PubSubTransport)
      |> assert_issue()
    end

    test "Phoenix.PubSub.unsubscribe outside the seam is reported" do
      ~S'''
      defmodule MediaCentaur.Watcher do
        def stop_watching(topic) do
          Phoenix.PubSub.unsubscribe(MediaCentaur.PubSub, topic)
        end
      end
      '''
      |> to_source_file("lib/media_centaur/watcher.ex")
      |> run_check(PubSubTransport)
      |> assert_issue()
    end

    test "each direct call in a module is reported separately" do
      ~S'''
      defmodule MediaCentaur.Config do
        def churn(topic, message) do
          Phoenix.PubSub.subscribe(MediaCentaur.PubSub, topic)
          Phoenix.PubSub.broadcast(MediaCentaur.PubSub, topic, message)
        end
      end
      '''
      |> to_source_file("lib/media_centaur/config.ex")
      |> run_check(PubSubTransport)
      |> assert_issues(fn issues -> assert length(issues) == 2 end)
    end
  end
end
