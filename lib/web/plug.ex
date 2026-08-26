defmodule GriffinSSG.Web.Plug do
  @moduledoc """
  Defines a simple HTTP server with live reload. Spawned from the `grf.server` task.
  Serves the generated static site from the output directory and injects a small
  live-reload client script into HTML responses. The client connects to a Bandit
  WebSocket (`GriffinSSG.Web.LiveReload`) that pushes reload events when the
  output directory changes.
  """
  use Plug.Router
  use Plug.ErrorHandler

  @reload_path "/grf_live_reload/socket"

  plug(:match)
  plug(:dispatch)

  get "/grf_live_reload/socket" do
    conn
    |> WebSockAdapter.upgrade(GriffinSSG.Web.LiveReload, [], timeout: :infinity)
    |> halt()
  end

  match "*path" do
    expanded_path =
      [output_dir() | path]
      |> Path.join()
      |> Path.expand()

    if File.exists?(expanded_path) and File.dir?(expanded_path) do
      send_file(conn, Path.join(expanded_path, "index.html"))
    else
      send_file(conn, expanded_path)
    end
  end

  defp send_file(conn, path) do
    case File.read(path) do
      {:ok, file} ->
        content_type = MIME.from_path(path)

        body =
          if String.starts_with?(content_type, "text/html") do
            inject_reloader(file)
          else
            file
          end

        conn
        |> put_resp_content_type(content_type)
        |> send_resp(200, body)

      {:error, :enoent} ->
        send_resp(conn, 404, "not found")
    end
  end

  defp inject_reloader(html) do
    if String.contains?(html, "</body>") do
      String.replace(html, "</body>", reloader_script() <> "</body>", global: false)
    else
      html <> reloader_script()
    end
  end

  defp reloader_script do
    """
    <script>
    (function () {
      var socket = new WebSocket("ws://" + location.host + "#{@reload_path}");
      socket.addEventListener("message", function (event) {
        if (event.data === "css") {
          document.querySelectorAll("link[rel=stylesheet]").forEach(function (link) {
            if (!link.href) return;
            var url = link.href.replace(/[?&]vsn=\\d*/, "");
            link.href = url + (url.indexOf("?") >= 0 ? "&" : "?") + "vsn=" + Date.now();
          });
        } else {
          location.reload();
        }
      });
    })();
    </script>
    """
  end

  @impl Plug.ErrorHandler
  def handle_errors(conn, _) do
    send_resp(conn, conn.status, "internal server error")
  end

  defp output_dir do
    Application.get_env(:ssg_mdex, :output, "_site")
  end
end
