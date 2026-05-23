defmodule MediaCentaur.Platform.WatcherEventsTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Platform.WatcherEvents

  describe "normalize/1 — Linux (inotify) input is identity" do
    test ":created stays :created" do
      assert WatcherEvents.normalize([:created]) == [:created]
    end

    test ":modified stays :modified" do
      assert WatcherEvents.normalize([:modified]) == [:modified]
    end

    test ":deleted stays :deleted" do
      assert WatcherEvents.normalize([:deleted]) == [:deleted]
    end

    test ":unmounted stays :unmounted" do
      assert WatcherEvents.normalize([:unmounted]) == [:unmounted]
    end

    test "the typical inotify create event (created + modified) preserves both" do
      assert WatcherEvents.normalize([:created, :modified]) == [:created, :modified]
    end
  end

  describe "normalize/1 — macOS (FSEvents) translation" do
    test ":removed maps to :deleted" do
      assert WatcherEvents.normalize([:removed]) == [:deleted]
    end

    test ":unmount maps to :unmounted" do
      assert WatcherEvents.normalize([:unmount]) == [:unmounted]
    end

    test ":rootchanged maps to :unmounted (the watched root went away)" do
      assert WatcherEvents.normalize([:rootchanged]) == [:unmounted]
    end

    test ":renamed maps to :scan_required (atomic rename on macOS)" do
      assert WatcherEvents.normalize([:renamed]) == [:scan_required]
    end

    test ":mustscansubdirs maps to :scan_required" do
      assert WatcherEvents.normalize([:mustscansubdirs]) == [:scan_required]
    end

    test ":userdropped maps to :scan_required (dropped events)" do
      assert WatcherEvents.normalize([:userdropped]) == [:scan_required]
    end

    test ":kerneldropped maps to :scan_required (dropped events)" do
      assert WatcherEvents.normalize([:kerneldropped]) == [:scan_required]
    end

    test ":eventidswrapped maps to :scan_required (event-ID rollover)" do
      assert WatcherEvents.normalize([:eventidswrapped]) == [:scan_required]
    end
  end

  describe "normalize/1 — FSEvents noise atoms are filtered" do
    # These atoms are emitted by FSEvents but carry no domain meaning to
    # Watcher: type markers, metadata-only changes, mount notices, and the
    # "we caused this" loop-avoidance marker. They must not appear in the
    # normalized output.

    test ":mount is filtered out" do
      assert WatcherEvents.normalize([:mount]) == []
    end

    test ":historydone is filtered out" do
      assert WatcherEvents.normalize([:historydone]) == []
    end

    test ":isfile / :isdir / :issymlink type markers are filtered out" do
      assert WatcherEvents.normalize([:isfile]) == []
      assert WatcherEvents.normalize([:isdir]) == []
      assert WatcherEvents.normalize([:issymlink]) == []
    end

    test ":inodemetamod / :finderinfomod / :xattrmod / :changeowner metadata changes are filtered out" do
      assert WatcherEvents.normalize([:inodemetamod]) == []
      assert WatcherEvents.normalize([:finderinfomod]) == []
      assert WatcherEvents.normalize([:xattrmod]) == []
      assert WatcherEvents.normalize([:changeowner]) == []
    end

    test ":ownevent (we caused this) is filtered out" do
      assert WatcherEvents.normalize([:ownevent]) == []
    end
  end

  describe "normalize/1 — compositional behaviour" do
    test "a domain event mixed with noise returns just the domain event" do
      assert WatcherEvents.normalize([:created, :isfile]) == [:created]
    end

    test "the realistic FSEvents create event (created + isfile + ownevent) normalizes to [:created]" do
      assert WatcherEvents.normalize([:created, :isfile, :ownevent]) == [:created]
    end

    test "two noise atoms collapse to []" do
      assert WatcherEvents.normalize([:isfile, :ownevent]) == []
    end

    test "removed + isfile (typical FSEvents delete) normalizes to [:deleted]" do
      assert WatcherEvents.normalize([:removed, :isfile]) == [:deleted]
    end

    test "duplicate domain atoms collapse to a single occurrence" do
      assert WatcherEvents.normalize([:scan_required, :scan_required]) == [:scan_required]
    end

    test "two advisory atoms both meaning :scan_required collapse" do
      assert WatcherEvents.normalize([:userdropped, :kerneldropped]) == [:scan_required]
    end

    test "empty input returns empty output" do
      assert WatcherEvents.normalize([]) == []
    end
  end

  describe "normalize/1 — unknown atoms" do
    # Unknown atoms (future file_system release adds a new event, or a
    # backend not yet supported emits something we haven't mapped) are
    # silently dropped. The Watcher's pattern-match on the domain
    # vocabulary would ignore them anyway; explicit drop keeps the
    # contract clean.

    test "unknown atom is filtered out" do
      assert WatcherEvents.normalize([:something_new_in_the_future]) == []
    end

    test "unknown atom mixed with a known one keeps only the known one" do
      assert WatcherEvents.normalize([:created, :something_new_in_the_future]) == [:created]
    end
  end

  describe "normalize/1 — full coverage of both backend vocabularies" do
    # If the file_system library adds a new atom to either known_events/0
    # list, the campaign rule says the normalizer must explicitly handle
    # it (map or drop). These tests enumerate the lists from
    # FSInotify and FSMac so an upstream addition surfaces here.

    @fs_inotify_atoms [:created, :modified, :deleted, :unmounted]

    @fs_mac_atoms [
      :mustscansubdirs,
      :userdropped,
      :kerneldropped,
      :eventidswrapped,
      :historydone,
      :rootchanged,
      :mount,
      :unmount,
      :created,
      :removed,
      :inodemetamod,
      :renamed,
      :modified,
      :finderinfomod,
      :changeowner,
      :xattrmod,
      :isfile,
      :isdir,
      :issymlink,
      :ownevent
    ]

    test "every FSInotify atom round-trips through normalize/1 without crashing" do
      for atom <- @fs_inotify_atoms do
        result = WatcherEvents.normalize([atom])
        assert is_list(result), "normalize/1 must return a list for #{inspect(atom)}"
      end
    end

    test "every FSMac atom round-trips through normalize/1 without crashing" do
      for atom <- @fs_mac_atoms do
        result = WatcherEvents.normalize([atom])
        assert is_list(result), "normalize/1 must return a list for #{inspect(atom)}"
      end
    end

    test "every output atom is from the domain vocabulary" do
      domain = [:created, :modified, :deleted, :unmounted, :scan_required]

      for atom <- @fs_inotify_atoms ++ @fs_mac_atoms do
        result = WatcherEvents.normalize([atom])

        for output_atom <- result do
          assert output_atom in domain,
                 "normalize/1 returned #{inspect(output_atom)} (not in domain vocabulary) for input #{inspect(atom)}"
        end
      end
    end
  end
end
