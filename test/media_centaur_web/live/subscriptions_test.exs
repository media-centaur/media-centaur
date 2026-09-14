defmodule MediaCentaurWeb.Live.SubscriptionsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Topics
  alias MediaCentaurWeb.Live.Subscriptions

  defp connected_socket, do: %Phoenix.LiveView.Socket{transport_pid: self()}

  test "a second subscribe to the same context by the same process is a no-op: one message arrives" do
    socket =
      connected_socket()
      |> Subscriptions.subscribe(MediaCentaur.Library)
      |> Subscriptions.subscribe(MediaCentaur.Library)

    assert MapSet.member?(socket.assigns.subscriptions, MediaCentaur.Library)

    :ok = Topics.publish(Topics.library_updates(), {:subscriptions_test_ping, self()})
    me = self()
    assert_receive {:subscriptions_test_ping, ^me}
    refute_receive {:subscriptions_test_ping, ^me}, 50
  end

  test "a context's other door is keyed by its function" do
    connected_socket()
    |> Subscriptions.subscribe({MediaCentaur.Acquisition, :subscribe_queue})
    |> Subscriptions.subscribe({MediaCentaur.Acquisition, :subscribe_queue})

    :ok = Topics.publish(Topics.acquisition_queue(), {:subscriptions_test_ping, self()})
    me = self()
    assert_receive {:subscriptions_test_ping, ^me}
    refute_receive {:subscriptions_test_ping, ^me}, 50
  end

  test "nothing subscribes on the dead render" do
    socket = Subscriptions.subscribe(%Phoenix.LiveView.Socket{}, MediaCentaur.Library)
    refute Map.has_key?(socket.assigns, :subscriptions)

    :ok = Topics.publish(Topics.library_updates(), {:subscriptions_test_ping, self()})
    me = self()
    refute_receive {:subscriptions_test_ping, ^me}, 50
  end
end
