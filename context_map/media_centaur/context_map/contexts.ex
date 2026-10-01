defmodule MediaCentaur.ContextMap.Contexts do
  @moduledoc """
  Reads the bounded contexts from the Boundary declarations the compiler
  already enforces. A context is a module named `MediaCentaur.<Name>` whose
  `use Boundary` is neither `classify_to` nor check-disabled tooling. Nested
  declarations (`MediaCentaur.Settings.Config`) fold into their parent by
  namespace. The web layer is `:web`, never a context.

  Shared-kernel membership is declared here (spec § 10), not detected.
  """

  alias MediaCentaur.ContextMap.Context

  @kernel [MediaCentaur.Library, MediaCentaur.TMDB]

  @doc "Every bounded context in the application, sorted by name."
  @spec all() :: [Context.t()]
  def all do
    {:ok, modules} = :application.get_key(:media_centaur, :modules)

    modules
    |> Enum.flat_map(fn module ->
      case context_opts(module) do
        {:ok, opts} -> [to_context(module, opts)]
        :error -> []
      end
    end)
    |> Enum.sort_by(&inspect(&1.name))
  end

  @doc "The context owning `module`, `:web` for the web layer, nil for anything else (Mix tasks, tooling)."
  @spec context_of(module()) :: module() | :web | nil
  def context_of(module) do
    case Module.split(module) do
      ["MediaCentaurWeb" | _] ->
        :web

      ["MediaCentaur", name | _] ->
        candidate = existing_module([MediaCentaur, name])
        if candidate && context_opts(candidate) != :error, do: candidate

      _ ->
        nil
    end
  end

  @doc "Whether `context` belongs to the shared kernel (declared, not detected)."
  @spec kernel?(module()) :: boolean()
  def kernel?(context), do: context in @kernel

  # The Boundary options of `module` when it is a context, `:error` otherwise.
  defp context_opts(module) do
    with ["MediaCentaur", _name] <- Module.split(module),
         {:ok, opts} <- boundary_opts(module),
         false <- Keyword.has_key?(opts, :classify_to),
         false <- tooling?(opts) do
      {:ok, opts}
    else
      _ -> :error
    end
  end

  defp boundary_opts(module) do
    with true <- Code.ensure_loaded?(module),
         [%{opts: opts}] <- Keyword.get(module.__info__(:attributes), Boundary) do
      {:ok, opts}
    else
      _ -> :error
    end
  end

  defp tooling?(opts) do
    check = Keyword.get(opts, :check, [])
    check[:in] == false and check[:out] == false
  end

  defp to_context(module, opts) do
    %Context{
      name: module,
      kernel?: kernel?(module),
      deps: opts |> Keyword.get(:deps, []) |> Enum.map(&dep_module/1) |> Enum.sort_by(&inspect/1),
      exports:
        opts
        |> Keyword.get(:exports, [])
        |> Enum.map(&export_module(module, &1))
        |> Enum.sort_by(&inspect/1)
    }
  end

  defp dep_module({module, _mode}), do: module
  defp dep_module(module), do: module

  defp export_module(context, {module, _except}), do: export_module(context, module)

  defp export_module(context, module) do
    if List.starts_with?(Module.split(module), Module.split(context)),
      do: module,
      else: Module.safe_concat(context, module)
  end

  defp existing_module(parts) do
    Module.safe_concat(parts)
  rescue
    ArgumentError -> nil
  end
end
