defmodule MediaCentarrWeb.SettingsLive.WatchDirsLogic do
  @moduledoc """
  Pure helpers for the Settings watch-dirs card and dialog.

  ADR-030: keep LiveView logic small by extracting reusable transformations
  and text formatting into this pure module. Tested with `async: true`.
  """

  @spec new_entry() :: map()
  def new_entry do
    %{"id" => Ecto.UUID.generate(), "dir" => "", "images_dir" => nil, "name" => nil}
  end

  @spec display_label(map()) :: String.t()
  def display_label(%{"name" => name, "dir" => dir}) do
    case name do
      n when is_binary(n) and n != "" -> n
      _ -> dir
    end
  end

  @spec upsert([map()], map()) :: [map()]
  def upsert(list, %{"id" => id} = entry) do
    if Enum.any?(list, &(&1["id"] == id)) do
      Enum.map(list, fn e -> if e["id"] == id, do: entry, else: e end)
    else
      list ++ [entry]
    end
  end

  @spec remove([map()], String.t()) :: [map()]
  def remove(list, id), do: Enum.reject(list, &(&1["id"] == id))

  @doc """
  Returns a human-readable hint for the default images directory given the
  current `dir` value in the dialog. Used below the `images_dir` input so
  users see exactly where artwork will land if they leave the field blank.
  """
  @spec default_images_dir_hint(String.t() | nil) :: String.t()
  def default_images_dir_hint(dir) when is_binary(dir) and dir != "" do
    Path.join(dir, ".media-centarr/images")
  end

  def default_images_dir_hint(_), do: "<watch dir>/.media-centarr/images"

  @spec saveable?(map()) :: boolean()
  def saveable?(%{errors: errors}), do: errors == []

  @spec error_message({atom(), atom()} | {atom(), atom(), any()}) :: String.t()
  def error_message({:dir, :not_found}), do: "Path not found on this host."
  def error_message({:dir, :not_a_directory}), do: "Path is not a directory."
  def error_message({:dir, :not_readable}), do: "Path is not readable by the app."
  def error_message({:dir, :duplicate}), do: "This directory is already configured."
  def error_message({:dir, :nested}), do: "This directory is nested inside another configured directory."

  def error_message({:dir, :contains_existing}),
    do: "This directory contains another configured directory."

  def error_message({:dir, :unmounted, mount}), do: "Warning: #{mount} is not currently mounted."

  def error_message({:images_dir, :unwritable}),
    do: "Images directory is not writable and cannot be created."

  def error_message({:name, :too_long}), do: "Name must be 60 characters or fewer."
  def error_message({:name, :duplicate}), do: "Another directory already uses this name."
end
