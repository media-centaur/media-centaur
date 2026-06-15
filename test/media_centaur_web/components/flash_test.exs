defmodule MediaCentaurWeb.Components.FlashTest do
  @moduledoc """
  Scopes the toast auto-dismiss to user-action flashes only. The
  connection-state toasts (client-error / server-error / update-applying)
  reflect an ongoing condition and must persist — they must never mount the
  `FlashAutoDismiss` hook.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MediaCentaurWeb.Layouts

  defp count(html, substr), do: html |> String.split(substr) |> length() |> Kernel.-(1)

  describe "flash_group auto-dismiss" do
    test "a visible :info flash arms the auto-dismiss hook with a delay" do
      html = render_component(&Layouts.flash_group/1, %{flash: %{"info" => "Saved"}})

      # Exactly one element auto-dismisses: the user :info toast. The three
      # connection-state toasts also render (hidden) but carry no hook.
      assert count(html, ~s(phx-hook="FlashAutoDismiss")) == 1
      assert html =~ ~s(data-dismiss-after=)
      assert html =~ "Saved"
    end

    test "a visible :error flash also auto-dismisses" do
      html = render_component(&Layouts.flash_group/1, %{flash: %{"error" => "It broke"}})

      assert count(html, ~s(phx-hook="FlashAutoDismiss")) == 1
      assert html =~ "It broke"
    end

    test "connection-state toasts never mount the hook" do
      # No user flash present — only the persistent connection toasts render.
      html = render_component(&Layouts.flash_group/1, %{flash: %{}})

      refute html =~ ~s(phx-hook="FlashAutoDismiss")
      # Sanity: the connection toasts are in fact present in this render.
      assert html =~ ~s(id="client-error")
    end
  end
end
