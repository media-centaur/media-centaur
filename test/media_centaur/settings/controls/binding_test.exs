defmodule MediaCentaur.Settings.Controls.BindingTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Settings.Controls.Binding

  test "struct carries id, category, name and defaults" do
    binding = %Binding{
      id: :navigate_up,
      category: :navigation,
      name: "Move up",
      description: "Focus the item above",
      default_key: "ArrowUp",
      default_button: 12
    }

    assert binding.id == :navigate_up
    assert binding.category == :navigation
    assert binding.default_key == "ArrowUp"
  end

  test "default_key and default_button may be nil (unbound default)" do
    binding = %Binding{
      id: :fake,
      category: :playback,
      name: "Fake",
      description: "No defaults",
      default_key: nil,
      default_button: nil
    }

    assert binding.default_key == nil
    assert binding.default_button == nil
  end
end
