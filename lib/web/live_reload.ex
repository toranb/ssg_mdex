defmodule GriffinSSG.Web.LiveReload do
  @moduledoc """
  Bandit WebSocket handler for live reload. Watches the output directory and
  pushes a message to the browser when files change so the page reloads.
  Spawned from `GriffinSSG.Web.Plug` during `mix grf.server`.
  """
  @behaviour WebSock

  require Logger

  @impl WebSock
  def init(_opts) do
    output = Application.get_env(:ssg_mdex, :output, "_site")

    case FileSystem.start_link(dirs: [Path.absname(output)]) do
      {:ok, pid} ->
        FileSystem.subscribe(pid)
        {:ok, %{}}

      other ->
        Logger.warning("live reload could not watch #{output}: #{inspect(other)}")
        {:ok, %{}}
    end
  end

  @impl WebSock
  def handle_in(_frame, state), do: {:ok, state}

  @impl WebSock
  def handle_info({:file_event, _watcher_pid, {path, _events}}, state) do
    path = to_string(path)

    # ignore build artifacts; only the generated site should trigger reloads
    if String.match?(path, ~r{(^|/)_build/}) do
      {:ok, state}
    else
      Logger.debug("Live reload: #{Path.relative_to_cwd(path)}")
      {:push, {:text, reload_type(path)}, state}
    end
  end

  def handle_info(_message, state), do: {:ok, state}

  @impl WebSock
  def terminate(_reason, _state), do: :ok

  defp reload_type(path) do
    case Path.extname(path) do
      ".css" -> "css"
      _ -> "page"
    end
  end
end
