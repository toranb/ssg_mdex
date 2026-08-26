defmodule Mix.Tasks.Grf.Server do
  @shortdoc "Generates a static website and listens for changes."

  @moduledoc """
  Starts up a local development server using Bandit.
  The local server watches for file changes and re-runs grf.build
  on file change, then live-reloads the page in the browser.
  This server is NOT meant to be run in production.
  """
  use Mix.Task

  @requirements ["app.config", "grf.build"]
  @default_port "4123"

  @switches [
    port: :integer
  ]

  @aliases [
    p: :port
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _parsed} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    opts = Map.new(opts)

    # load code and start dependencies, including bandit
    {:ok, _} = Application.ensure_all_started([:ssg_mdex])

    port = http_port(opts)

    input_directories =
      [
        Application.get_env(:ssg_mdex, :input, "src"),
        Application.get_env(:ssg_mdex, :layouts, "lib/layouts")
      ] ++ Application.get_env(:ssg_mdex, :additional_watch_directories, [])

    on_file_change_callback = fn ->
      # Can we do more clever builds here? (e.g. building only changed files)
      Mix.Tasks.Grf.Build.run([])
    end

    children = [
      {Bandit, plug: GriffinSSG.Web.Plug, scheme: :http, port: port},
      {GriffinSSG.Filesystem.Watcher, [input_directories, on_file_change_callback]}
    ]

    # keep the console readable during development
    Logger.configure(level: :info)

    Mix.shell().info("Starting webserver on http://localhost:#{port}")
    Supervisor.start_link(children, strategy: :one_for_one, name: Grf.Server.Supervisor)

    Process.sleep(:infinity)
  end

  # refactor: consider having a centralized place for reading configuration values
  # that are overridable in different ways.
  def http_port(opts) do
    Map.get(opts, :port) || Application.get_env(:ssg_mdex, :http_port) ||
      parse_int(System.get_env("GRIFFIN_HTTP_PORT", @default_port))
  end

  defp parse_int(string) do
    {integer, _remainder} = Integer.parse(string)
    integer
  end
end
