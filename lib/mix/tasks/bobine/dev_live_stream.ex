defmodule Mix.Tasks.Bobine.DevLiveStream do
  use Mix.Task

  @shortdoc "Starts a dev live stream — provisions Mux, transitions to live, pushes test RTMP."

  @moduledoc """
  Creates a live event, provisions a Mux live stream, transitions it to live,
  and pushes a test video pattern via ffmpeg.

  Requires `MUX_TOKEN_ID` and `MUX_TOKEN_SECRET` env vars. Use `--fake` to
  skip Mux and use a test playback ID instead (player shows "stream unavailable"
  but the full UI and chat work).

      mix bobine.dev_live_stream                   # uses first org in DB
      mix bobine.dev_live_stream --org my-org      # uses specific org by slug
      mix bobine.dev_live_stream --no-ffmpeg       # print credentials, don't run ffmpeg
      mix bobine.dev_live_stream --fake            # skip Mux, no RTMP needed

  When ffmpeg runs, Ctrl+C stops the push. The event stays live — use the
  super admin dashboard or `Streaming.transition_event/3` in iex to end it.

  Mux webhooks (`video.live_stream.active`) would normally trigger the
  live transition in production. This task does it directly so you don't
  need ngrok wired up for basic UI testing.
  """

  alias Bobine.Accounts
  alias Bobine.Accounts.Scope
  alias Bobine.Repo
  alias Bobine.Streaming
  alias Bobine.Streaming.LiveEvent

  @fake_playback_id "DS00Spx1CV902MCtPj5WknGlR102V5HFkDe"
  @switches [org: :string, no_ffmpeg: :boolean, fake: :boolean]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    org = find_org!(opts[:org])
    fake = opts[:fake] || false

    info("Org: #{org.name} (#{org.slug})")

    event = provision_event!(org, fake)

    info("""

    Event ready:
      Title:    #{event.title}
      Slug:     #{event.slug}
      Status:   #{event.status}
      Viewer:   http://#{org.slug}.localhost:4000/events/#{event.slug}
      Admin:    http://#{org.slug}.localhost:4000/admin/live-events/#{event.id}
    """)

    if fake do
      info("Fake mode — no RTMP. Playback ID: #{event.mux_live_playback_id}")
    else
      creds = fetch_credentials!(event)
      print_credentials(creds)
      unless opts[:no_ffmpeg], do: run_ffmpeg!(creds)
    end
  end

  # ---------------------------------------------------------------------------
  # Org resolution
  # ---------------------------------------------------------------------------

  defp find_org!(nil) do
    case Accounts.fetch_any_organization() do
      {:ok, org} ->
        org

      {:error, :not_found} ->
        Mix.raise("No organizations found. Run `mix bobine.seed_demo_orgs` first.")
    end
  end

  defp find_org!(slug) do
    case Accounts.get_organization_by_slug(slug) do
      {:ok, org} -> org
      {:error, :not_found} -> Mix.raise("Org not found: #{inspect(slug)}")
    end
  end

  # ---------------------------------------------------------------------------
  # Event creation + transitions
  # ---------------------------------------------------------------------------

  defp provision_event!(org, fake) do
    event = create_event!(org, fake)
    info("Created event #{event.id} (status: #{event.status})")
    transition_through_to_live!(org, event)
  end

  defp create_event!(org, false) do
    scope = %Scope{organization: org}

    attrs = %{
      title: "Dev Live Stream",
      slug: "dev-stream-#{System.system_time(:second)}",
      description: "Created by mix bobine.dev_live_stream.",
      scheduled_start_at: DateTime.utc_now() |> DateTime.truncate(:second),
      access_type: "public",
      organization_id: org.id
    }

    info("Provisioning Mux live stream…")

    case Streaming.create_live_event(scope, attrs) do
      {:ok, event} ->
        event

      {:error, :mux_error, details} ->
        Mix.raise(
          "Mux API error: #{inspect(details)}\n\n" <>
            "Check MUX_TOKEN_ID and MUX_TOKEN_SECRET, or use --fake."
        )

      {:error, :validation, changeset} ->
        Mix.raise("Validation error: #{inspect(changeset.errors)}")
    end
  end

  defp create_event!(org, true) do
    attrs = %{
      title: "Dev Live Stream (fake)",
      slug: "dev-stream-#{System.system_time(:second)}",
      description: "Created by mix bobine.dev_live_stream --fake.",
      scheduled_start_at: DateTime.utc_now() |> DateTime.truncate(:second),
      access_type: "public",
      organization_id: org.id
    }

    %LiveEvent{}
    |> LiveEvent.changeset(attrs)
    |> LiveEvent.mux_changeset(%{
      mux_live_playback_id: @fake_playback_id,
      mux_rtmp_url: "rtmps://global-live.mux.com:443/app"
    })
    |> Ecto.Changeset.put_change(:status, "scheduled")
    |> Repo.insert!()
  end

  # create_live_event creates in draft status; walk the state machine to live.
  defp transition_through_to_live!(org, %{status: "draft"} = event) do
    event = do_transition!(org, event, "scheduled")
    do_transition!(org, event, "live")
  end

  defp transition_through_to_live!(org, %{status: "scheduled"} = event) do
    do_transition!(org, event, "live")
  end

  defp transition_through_to_live!(_org, %{status: "live"} = event), do: event

  defp transition_through_to_live!(_org, event) do
    Mix.raise("Cannot transition #{event.status} to live.")
  end

  defp do_transition!(org, event, to_status) do
    scope = %Scope{organization: org}

    case Streaming.transition_event(scope, event, to_status) do
      {:ok, updated} ->
        info("Transitioned #{event.status} → #{to_status}")
        updated

      {:error, :invalid_transition} ->
        Mix.raise("Invalid transition: #{event.status} → #{to_status}")

      error ->
        Mix.raise("Transition failed: #{inspect(error)}")
    end
  end

  # ---------------------------------------------------------------------------
  # Credentials + ffmpeg
  # ---------------------------------------------------------------------------

  defp fetch_credentials!(event) do
    case Streaming.get_stream_credentials(event) do
      {:ok, creds} ->
        creds

      error ->
        Mix.raise("Could not fetch Mux stream credentials: #{inspect(error)}")
    end
  end

  defp print_credentials(%{rtmp_url: rtmp_url, stream_key: key}) do
    Mix.shell().info("""

    RTMP credentials:
      URL:        #{rtmp_url}
      Stream key: #{key}
      Full target: #{rtmp_url}/#{key}

    To push manually:
      ffmpeg -re \\
        -f lavfi -i "testsrc=size=1280x720:rate=30,format=yuv420p" \\
        -f lavfi -i anullsrc \\
        -c:v libx264 -preset veryfast -b:v 2M \\
        -c:a aac -ar 44100 -b:a 128k \\
        -f flv "#{rtmp_url}/#{key}"
    """)
  end

  defp run_ffmpeg!(%{rtmp_url: rtmp_url, stream_key: key}) do
    case System.find_executable("ffmpeg") do
      nil ->
        Mix.shell().info("ffmpeg not found in PATH — run the command above manually.")

      ffmpeg ->
        info("Starting ffmpeg push… (Ctrl+C to stop)")

        System.cmd(
          ffmpeg,
          [
            "-re",
            "-f",
            "lavfi",
            "-i",
            "testsrc=size=1280x720:rate=30,format=yuv420p",
            "-f",
            "lavfi",
            "-i",
            "anullsrc",
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-b:v",
            "2M",
            "-c:a",
            "aac",
            "-ar",
            "44100",
            "-b:a",
            "128k",
            "-f",
            "flv",
            "#{rtmp_url}/#{key}"
          ],
          into: IO.stream(:stdio, :line),
          stderr_to_stdout: true
        )
    end
  end

  defp info(msg), do: Mix.shell().info(msg)
end
