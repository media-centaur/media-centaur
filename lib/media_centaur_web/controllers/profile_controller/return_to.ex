defmodule MediaCentaurWeb.ProfileController.ReturnTo do
  @moduledoc """
  The one guard on where the activate route sends the browser next: a
  path on this app, never a URL, never the picker itself (which would
  ask the question that was just answered). A value holding a control
  character or a backslash anywhere also goes home, since
  `Phoenix.Controller.redirect/2` or Plug's header check would raise on
  it. Plug has already decoded the parameter, so percent-encoded
  sequences are left alone.
  """

  @spec local_path(term()) :: String.t()
  def local_path("/profiles" <> _rest), do: "/"

  def local_path(<<"/", next, _::binary>> = path) when next != ?/ do
    if unsafe?(path), do: "/", else: path
  end

  def local_path(_other), do: "/"

  defp unsafe?(path),
    do: String.contains?(path, "\\") or Enum.any?(:binary.bin_to_list(path), &(&1 < 0x20))
end
