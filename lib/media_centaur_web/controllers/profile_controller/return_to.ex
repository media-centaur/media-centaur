defmodule MediaCentaurWeb.ProfileController.ReturnTo do
  @moduledoc """
  The one guard on where the activate route sends the browser next: a
  path on this app, never a URL, never the picker itself (which would
  ask the question that was just answered).
  """

  @spec local_path(term()) :: String.t()
  def local_path("/profiles" <> _rest), do: "/"
  def local_path(<<"/", next, _::binary>> = path) when next != ?/ and next != ?\\, do: path
  def local_path(_other), do: "/"
end
