defmodule MediaCentaur.Acquisition.Pursuits.Commands.TerminalCommandsTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Pursuits.{Event, Pursuit, Units}
  alias MediaCentaur.Acquisition.Pursuits.Commands.{Cancel, Exhaust, Satisfy}

  alias MediaCentaur.Acquisition.Pursuits.Events.{
    PursuitCancelled,
    PursuitExhausted,
    PursuitSatisfied
  }

  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Topics

  defp insert_active_pursuit(state \\ "active") do
    create_pursuit(%{state: state})
  end

  describe "Satisfy.execute/1" do
    test "transitions an active pursuit to satisfied and records the event" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.acquisition_updates())
      pursuit = insert_active_pursuit()
      grab_id = Ecto.UUID.generate()

      assert {:ok, %Pursuit{state: "satisfied"} = closed} =
               Satisfy.execute(%{
                 pursuit_id: pursuit.id,
                 final_target_id: grab_id,
                 final_release_title: "Sample.Movie.2010.1080p"
               })

      assert closed.id == pursuit.id

      [event] = Repo.all(Event)
      assert event.kind == "pursuit_satisfied"
      assert event.payload["final_target_id"] == grab_id
      assert event.payload["final_release_title"] == "Sample.Movie.2010.1080p"

      assert_receive %PursuitSatisfied{}
    end

    test "rejects already-terminal pursuit" do
      pursuit = insert_active_pursuit("satisfied")

      assert {:error, :not_eligible} =
               Satisfy.execute(%{
                 pursuit_id: pursuit.id,
                 final_target_id: Ecto.UUID.generate(),
                 final_release_title: "X"
               })
    end

    test "returns :not_found for missing pursuit" do
      assert {:error, :not_found} =
               Satisfy.execute(%{
                 pursuit_id: Ecto.UUID.generate(),
                 final_target_id: Ecto.UUID.generate(),
                 final_release_title: "X"
               })
    end

    test "promotes final target to succeeded and cancels in-flight siblings" do
      # Reproduces the Project Hail Mary scenario: a satisfied pursuit
      # left in-flight `seeking` / `acquired` siblings alive, and their
      # snoozed PursueTarget workers later grabbed duplicate releases.
      {pursuit, final_target} = create_pursuit_with_target(%{status: "acquired"})

      {:ok, sibling_seeking} =
        %Target{}
        |> Ecto.Changeset.change(
          pursuit_id: pursuit.id,
          title: pursuit.title,
          origin: pursuit.origin,
          status: "seeking"
        )
        |> Repo.insert()

      {:ok, sibling_acquired} =
        %Target{}
        |> Ecto.Changeset.change(
          pursuit_id: pursuit.id,
          title: pursuit.title,
          origin: pursuit.origin,
          status: "acquired"
        )
        |> Repo.insert()

      assert {:ok, %Pursuit{state: "satisfied"}} =
               Satisfy.execute(%{
                 pursuit_id: pursuit.id,
                 final_target_id: final_target.id,
                 final_release_title: "Sample.Movie.2026.1080p"
               })

      assert Repo.get!(Target, final_target.id).status == "succeeded"

      assert Repo.get!(Target, sibling_seeking.id).status == "cancelled"
      assert Repo.get!(Target, sibling_seeking.id).cancelled_reason == "pursuit_satisfied"

      assert Repo.get!(Target, sibling_acquired.id).status == "cancelled"
      assert Repo.get!(Target, sibling_acquired.id).cancelled_reason == "pursuit_satisfied"
    end

    test "cancels in-flight targets even when final_target_id is nil" do
      # LibraryReconciler may call Satisfy without a known final target
      # (the file landed via watcher import, not via a pursuit grab).
      {pursuit, seeking} = create_pursuit_with_target(%{status: "seeking"})

      assert {:ok, %Pursuit{state: "satisfied"}} =
               Satisfy.execute(%{
                 pursuit_id: pursuit.id,
                 final_target_id: nil,
                 final_release_title: "Sample.Movie.2026.1080p"
               })

      assert Repo.get!(Target, seeking.id).status == "cancelled"
      assert Repo.get!(Target, seeking.id).cancelled_reason == "pursuit_satisfied"
    end
  end

  describe "Exhaust.execute/1" do
    test "transitions to exhausted and records the event" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.acquisition_updates())
      pursuit = insert_active_pursuit()

      assert {:ok, %Pursuit{state: "exhausted"}} =
               Exhaust.execute(%{
                 pursuit_id: pursuit.id,
                 reason: :max_attempts
               })

      [event] = Repo.all(Event)
      assert event.kind == "pursuit_exhausted"
      assert event.payload["reason"] == "max_attempts"

      assert_receive %PursuitExhausted{}
    end

    test "exhausting an awaiting-decision pursuit clears the unit's awaiting flag" do
      pursuit = create_pursuit(%{awaiting_decision_at: DateTime.utc_now(:second)})

      assert {:ok, %Pursuit{state: "exhausted"}} =
               Exhaust.execute(%{
                 pursuit_id: pursuit.id,
                 reason: :no_alternatives
               })

      unit = Units.single!(pursuit.id)
      assert unit.state == "exhausted"
      assert unit.awaiting_decision_at == nil
    end

    test "cancels in-flight targets" do
      {pursuit, seeking} = create_pursuit_with_target(%{status: "seeking"})

      assert {:ok, %Pursuit{state: "exhausted"}} =
               Exhaust.execute(%{pursuit_id: pursuit.id, reason: :max_attempts})

      assert Repo.get!(Target, seeking.id).status == "cancelled"
      assert Repo.get!(Target, seeking.id).cancelled_reason == "pursuit_exhausted"
    end
  end

  describe "Cancel.execute/1 — stopping client downloads" do
    # Cancelling a pursuit takes its in-flight downloads out of the
    # client (user-settled 2026-06-11, campaign
    # pursuit-identity-and-lifecycle) — cancel must not mint orphans.
    # Client I/O is post-transaction and best-effort: a failure is
    # logged, never blocks the cancel (the orphan zone is the net).

    alias MediaCentaur.Downloads.DownloadClient.QBittorrent

    defp with_qbit_client(test_pid) do
      config = :persistent_term.get({MediaCentaur.Config, :config})

      :persistent_term.put(
        {MediaCentaur.Config, :config},
        Map.merge(config, %{
          download_client_type: "qbittorrent",
          download_client_url: "http://qbit.test"
        })
      )

      qbit_client = Req.new(plug: {Req.Test, :qbittorrent}, retry: false, base_url: "http://qbit.test")
      :persistent_term.put({QBittorrent, :client}, qbit_client)
      Req.Test.stub(:qbittorrent, fn conn -> Req.Test.json(conn, %{}) end)

      ExUnit.Callbacks.on_exit(fn ->
        :persistent_term.put({MediaCentaur.Config, :config}, config)
        QBittorrent.invalidate_client()
      end)

      Req.Test.allow(:qbittorrent, test_pid, self())
      :ok
    end

    test "cancelling deletes the pursuit's in-flight downloads from the client" do
      with_qbit_client(self())
      test_pid = self()

      Req.Test.stub(:qbittorrent, fn conn ->
        if conn.request_path == "/api/v2/torrents/delete" do
          {:ok, body, _conn} = Plug.Conn.read_body(conn)
          send(test_pid, {:qbit_delete, URI.decode_query(body)})
        end

        Req.Test.json(conn, %{})
      end)

      {pursuit, _target} =
        create_pursuit_with_target(%{status: "acquired", torrent_hash: "feedbeef00"})

      assert {:ok, cancelled} =
               Cancel.execute(%{pursuit_id: pursuit.id, cancelled_by: :user, reason: "user_cancelled"})

      assert cancelled.state == "cancelled"
      assert_receive {:qbit_delete, %{"hashes" => "feedbeef00", "deleteFiles" => "true"}}
    end

    test "a never-grabbed target (no hash) sends nothing to the client" do
      with_qbit_client(self())
      test_pid = self()

      Req.Test.stub(:qbittorrent, fn conn ->
        send(test_pid, {:qbit_request, conn.request_path})
        Req.Test.json(conn, %{})
      end)

      {pursuit, _target} = create_pursuit_with_target(%{status: "seeking", torrent_hash: nil})

      assert {:ok, cancelled} =
               Cancel.execute(%{pursuit_id: pursuit.id, cancelled_by: :user, reason: "user_cancelled"})

      assert cancelled.state == "cancelled"
      refute_receive {:qbit_request, _path}, 100
    end

    test "an unconfigured download client never blocks the cancel" do
      # Default test config has no download_client_type — the removal
      # step must degrade to a no-op, not an error.
      {pursuit, _target} =
        create_pursuit_with_target(%{status: "acquired", torrent_hash: "feedbeef00"})

      assert {:ok, cancelled} =
               Cancel.execute(%{pursuit_id: pursuit.id, cancelled_by: :user, reason: "user_cancelled"})

      assert cancelled.state == "cancelled"
    end
  end

  describe "Cancel.execute/1" do
    test "transitions to cancelled and records the event" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.acquisition_updates())
      pursuit = insert_active_pursuit()

      assert {:ok, %Pursuit{state: "cancelled"}} =
               Cancel.execute(%{
                 pursuit_id: pursuit.id,
                 cancelled_by: :user,
                 reason: "user_request"
               })

      [event] = Repo.all(Event)
      assert event.kind == "pursuit_cancelled"
      assert event.payload["cancelled_by"] == "user"
      assert event.payload["reason"] == "user_request"

      assert_receive %PursuitCancelled{}
    end

    test "cancels in-flight targets" do
      {pursuit, seeking} = create_pursuit_with_target(%{status: "seeking"})

      assert {:ok, %Pursuit{state: "cancelled"}} =
               Cancel.execute(%{
                 pursuit_id: pursuit.id,
                 cancelled_by: :user,
                 reason: "user_request"
               })

      assert Repo.get!(Target, seeking.id).status == "cancelled"
      assert Repo.get!(Target, seeking.id).cancelled_reason == "pursuit_cancelled"
    end
  end
end
