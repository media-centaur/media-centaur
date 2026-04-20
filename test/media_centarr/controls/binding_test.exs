defmodule MediaCentarr.Controls.BindingTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Controls.Binding

  test "struct requires id, category, name, scope" do
    binding = %Binding{
      id: :navigate_up,
      category: :navigation,
      name: "Move up",
      description: "Focus the item above",
      default_key: "ArrowUp",
      default_button: 12,
      scope: :input_system
    }

    assert binding.id == :navigate_up
    assert binding.category == :navigation
    assert binding.scope == :input_system
  end

  test "default_key and default_button may be nil (unbound default)" do
    binding = %Binding{
      id: :fake,
      category: :system,
      name: "Fake",
      description: "No defaults",
      default_key: nil,
      default_button: nil,
      scope: :global
    }

    assert binding.default_key == nil
    assert binding.default_button == nil
  end
end
