defmodule MediaCentaur.Platform.LogSourceTest do
  use ExUnit.Case, async: false

  alias MediaCentaur.Platform.LogSource

  # async: false because we mutate Application env. Each test rolls
  # back its override in `on_exit` so the suite stays clean.

  defmodule FakeImpl do
    @behaviour MediaCentaur.Platform.LogSource

    @impl true
    def open_port(_unit), do: :fake_port_sentinel

    @impl true
    def available?(nil), do: false
    def available?(_unit), do: true
  end

  describe "facade dispatch" do
    setup do
      original = Application.get_env(:media_centaur, LogSource)
      Application.put_env(:media_centaur, LogSource, FakeImpl)

      on_exit(fn ->
        if original do
          Application.put_env(:media_centaur, LogSource, original)
        else
          Application.delete_env(:media_centaur, LogSource)
        end
      end)

      :ok
    end

    test "open_port/1 delegates to the configured impl" do
      assert LogSource.open_port("media-centaur.service") == :fake_port_sentinel
    end

    test "available?/1 returns true for a non-nil unit through the fake impl" do
      assert LogSource.available?("media-centaur.service") == true
    end

    test "available?/1 returns false for nil unit through the fake impl" do
      assert LogSource.available?(nil) == false
    end
  end

  describe "default impl (no Application env)" do
    test "defaults to Journal when no impl is configured" do
      original = Application.get_env(:media_centaur, LogSource)
      Application.delete_env(:media_centaur, LogSource)

      on_exit(fn ->
        if original, do: Application.put_env(:media_centaur, LogSource, original)
      end)

      # available?/1 with nil unit is the safe contract probe — neither
      # impl should attempt a shell-out for this.
      assert LogSource.available?(nil) == false
    end
  end
end
