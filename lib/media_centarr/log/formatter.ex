defmodule MediaCentarr.Log.Formatter do
  @moduledoc """
  Custom log formatter that renders component-tagged logs as
  `[level][component] message` and normal logs as `[level] message`.
  """

  def format(level, message, _timestamp, metadata) do
    case Keyword.get(metadata, :component) do
      nil -> "[#{level}] #{message}\n"
      component -> "[#{level}][#{component}] #{message}\n"
    end
  rescue
    _ -> "[#{level}] #{message}\n"
  end
end
