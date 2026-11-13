defmodule MediaCentaur.SelfUpdate.DatabaseSnapshotTest do
  use MediaCentaur.Case, async: true

  alias Exqlite.Sqlite3
  alias MediaCentaur.SelfUpdate.DatabaseSnapshot

  @moduletag :tmp_dir

  defp create_database(path, titles) do
    {:ok, connection} = Sqlite3.open(path)
    :ok = Sqlite3.execute(connection, "PRAGMA journal_mode=WAL")
    :ok = Sqlite3.execute(connection, "CREATE TABLE movies (title TEXT)")

    for title <- titles do
      :ok = Sqlite3.execute(connection, "INSERT INTO movies (title) VALUES ('#{title}')")
    end

    connection
  end

  defp titles_in(path) do
    {:ok, connection} = Sqlite3.open(path)
    {:ok, statement} = Sqlite3.prepare(connection, "SELECT title FROM movies ORDER BY title")
    {:ok, rows} = Sqlite3.fetch_all(connection, statement)
    :ok = Sqlite3.release(connection, statement)
    :ok = Sqlite3.close(connection)
    List.flatten(rows)
  end

  describe "take!/3" do
    test "copies the database as it is now, while another connection holds it open", %{tmp_dir: tmp_dir} do
      database = Path.join(tmp_dir, "library.db")
      connection = create_database(database, ["Movie A", "Movie B"])

      snapshot = DatabaseSnapshot.take!(database, "2.17.0", ~U[2026-11-13 10:15:00Z])

      :ok = Sqlite3.execute(connection, "INSERT INTO movies (title) VALUES ('Movie C')")
      :ok = Sqlite3.close(connection)

      assert snapshot == Path.join([tmp_dir, "snapshots", "library-20261113T101500Z-before-2.17.0.db"])
      assert titles_in(snapshot) == ["Movie A", "Movie B"]
    end

    test "the copy is readable by its owner only — it holds the install's keys", %{tmp_dir: tmp_dir} do
      database = Path.join(tmp_dir, "library.db")
      :ok = database |> create_database(["Movie A"]) |> Sqlite3.close()

      snapshot = DatabaseSnapshot.take!(database, "2.17.0", ~U[2026-11-13 10:15:00Z])

      assert %File.Stat{mode: mode} = File.stat!(snapshot)
      assert Bitwise.band(mode, 0o777) == 0o600
    end

    test "raises when the copy cannot be written, so nothing migrates without one", %{tmp_dir: tmp_dir} do
      database = Path.join(tmp_dir, "library.db")
      :ok = database |> create_database(["Movie A"]) |> Sqlite3.close()
      File.write!(Path.join(tmp_dir, "snapshots"), "a file where the directory belongs")

      assert_raise File.Error, fn ->
        DatabaseSnapshot.take!(database, "2.17.0", ~U[2026-11-13 10:15:00Z])
      end
    end
  end

  describe "sweep/2" do
    test "keeps the newest snapshots and removes the rest", %{tmp_dir: tmp_dir} do
      names =
        for day <- 10..14 do
          name = "library-202611#{day}T101500Z-before-2.#{day}.0.db"
          File.write!(Path.join(tmp_dir, name), "")
          name
        end

      assert DatabaseSnapshot.sweep(tmp_dir, 3) == 2
      assert tmp_dir |> File.ls!() |> Enum.sort() == Enum.take(names, -3)
    end

    test "leaves files that are not snapshots alone", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "notes.txt"), "")

      assert DatabaseSnapshot.sweep(tmp_dir, 0) == 0
      assert File.ls!(tmp_dir) == ["notes.txt"]
    end

    test "a directory that does not exist has nothing to remove", %{tmp_dir: tmp_dir} do
      assert DatabaseSnapshot.sweep(Path.join(tmp_dir, "absent"), 3) == 0
    end
  end
end
