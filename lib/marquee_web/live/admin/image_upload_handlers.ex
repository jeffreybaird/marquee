defmodule MarqueeWeb.Admin.ImageUploadHandlers do
  @moduledoc """
  Shared Spaces upload event handlers for admin LiveViews.

  `use`-ing this module injects four `handle_event/3` clauses that
  handle the round-trip for the `SpacesUploader` JS hook:

    * `spaces_presign_requested` — the browser picked a file; ask
      `Marquee.Storage` for a presigned PUT URL and push
      `spaces_presign_ready` back.
    * `spaces_upload_progress` — forward the percent into socket
      assigns so the form can render a progress bar.
    * `spaces_upload_complete` — the direct-to-Spaces PUT finished;
      update the assigns so the upload control shows the new image
      and the hidden input carries the new URL on the next form submit.
    * `spaces_upload_error` — surface the error and reset state.

  The upload state is kept in a single assign (`:image_uploads`)
  keyed by `{kind, target_id}`. Helpers below let you read the
  resolved URL for a given slot, which is what the upload component
  renders and what your `save_*` handler reads when submitting the
  surrounding form.

  ## Required callbacks

  The using module must implement `allowed_upload_kind?/1` so we
  don't hand out presigned URLs for kinds a given LiveView has no
  business authorizing. Return `true` if the kind is allowed on this
  page, `false` otherwise.

  ## Required assigns

    * `:organization` — already on every admin socket
    * `:image_uploads` — injected by `on_mount`
  """

  require Marquee.Otel, as: Otel
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Marquee.Storage

  @doc """
  Returns true when the given upload kind is allowed on the calling
  LiveView. LiveViews implement this to lock down which kinds they're
  willing to presign for.
  """
  @callback allowed_upload_kind?(kind :: String.t()) :: boolean()

  defmacro __using__(_opts) do
    quote do
      @behaviour MarqueeWeb.Admin.ImageUploadHandlers
      alias MarqueeWeb.Admin.ImageUploadHandlers

      on_mount {ImageUploadHandlers, :assign_image_uploads}

      @impl true
      def handle_event("spaces_presign_requested", params, socket) do
        ImageUploadHandlers.handle_presign_requested(__MODULE__, params, socket)
      end

      @impl true
      def handle_event("spaces_upload_progress", params, socket) do
        ImageUploadHandlers.handle_upload_progress(params, socket)
      end

      @impl true
      def handle_event("spaces_upload_complete", params, socket) do
        ImageUploadHandlers.handle_upload_complete(params, socket)
      end

      @impl true
      def handle_event("spaces_upload_error", params, socket) do
        ImageUploadHandlers.handle_upload_error(params, socket)
      end
    end
  end

  @doc """
  Seeds the `:image_uploads` assign so templates never crash on a
  missing key. Runs as an `on_mount` callback, mirroring the
  `CardActions` pattern.
  """
  def on_mount(:assign_image_uploads, _params, _session, socket) do
    {:cont, Phoenix.Component.assign_new(socket, :image_uploads, fn -> %{} end)}
  end

  @doc """
  Returns the current upload state (`%{status:, percent:, url:, error:}`)
  for a given `{kind, target_id}` slot. Callers that need a single
  field — e.g. the public URL in the form — should use `upload_url/4`.

  Accepts either a full socket (the typical caller — the LiveView event
  handler has one handy) or the `:image_uploads` map directly (templates
  only receive pre-passed assigns, not a live socket).
  """
  def upload_state(%Phoenix.LiveView.Socket{} = socket, kind, target_id) do
    upload_state(socket.assigns.image_uploads, kind, target_id)
  end

  def upload_state(%{} = image_uploads, kind, target_id) do
    Map.get(image_uploads, slot_key(kind, target_id), %{
      status: :idle,
      percent: 0,
      url: nil,
      error: nil
    })
  end

  @doc """
  Returns the resolved URL for a slot, falling back to an explicit
  default. Used by the upload component's `url` attr and by form
  save handlers that need to read the URL out of the socket.

  Same overload as `upload_state/3`: accepts a `Phoenix.LiveView.Socket`
  or a bare `image_uploads` map.
  """
  def upload_url(source, kind, target_id, default \\ nil) do
    case upload_state(source, kind, target_id).url do
      nil -> default
      "" -> default
      url -> url
    end
  end

  @doc """
  Seeds the upload state for a slot with an existing URL (e.g. when
  opening an edit modal on a record that already has a cover image).
  """
  def put_initial_url(socket, kind, target_id, url) do
    update_slot(socket, kind, target_id, fn state -> %{state | url: url} end)
  end

  ## -----------------------------------------------------------------------
  ## Internal event handlers
  ## -----------------------------------------------------------------------

  @doc false
  def handle_presign_requested(using_module, params, socket) do
    %{
      "kind" => kind,
      "target_id" => target_id,
      "filename" => filename,
      "content_type" => content_type
    } = params

    org_id = socket.assigns.organization.id

    cond do
      not using_module.allowed_upload_kind?(kind) ->
        Logger.error("Spaces upload rejected: unauthorized kind",
          org_id: org_id,
          upload_kind: kind,
          target_id: target_id
        )

        {:noreply, fail_slot(socket, kind, target_id, "Uploads not allowed here")}

      not Storage.allowed_image_content_type?(content_type) ->
        Logger.error("Spaces upload rejected: unsupported content type",
          org_id: org_id,
          upload_kind: kind,
          target_id: target_id,
          content_type: content_type
        )

        {:noreply, fail_slot(socket, kind, target_id, "Unsupported file type")}

      true ->
        do_presign(socket, kind, target_id, filename, content_type)
    end
  end

  defp do_presign(socket, kind, target_id, filename, content_type) do
    org = socket.assigns.organization

    case Storage.presign_upload(org, kind,
           content_type: content_type,
           filename: filename
         ) do
      {:ok, presigned} ->
        socket =
          socket
          |> update_slot(kind, target_id, fn state ->
            %{state | status: :uploading, percent: 0, error: nil}
          end)
          |> Phoenix.LiveView.push_event("spaces_presign_ready", %{
            kind: kind,
            target_id: target_id,
            presigned_url: presigned.presigned_url,
            public_url: presigned.public_url,
            key: presigned.key,
            headers: presigned[:headers] || %{}
          })

        {:noreply, socket}

      {:error, reason} ->
        Logger.error("Spaces presign failed",
          org_id: org.id,
          upload_kind: kind,
          target_id: target_id,
          reason: inspect(reason)
        )

        {:noreply, fail_slot(socket, kind, target_id, "Could not start upload.")}
    end
  end

  @doc false
  def handle_upload_progress(params, socket) do
    %{"kind" => kind, "target_id" => target_id, "percent" => percent} = params
    percent = ensure_int(percent)

    socket =
      update_slot(socket, kind, target_id, fn state ->
        %{state | status: :uploading, percent: percent}
      end)

    {:noreply, socket}
  end

  @doc false
  def handle_upload_complete(params, socket) do
    %{
      "kind" => kind,
      "target_id" => target_id,
      "public_url" => public_url
    } = params

    socket =
      update_slot(socket, kind, target_id, fn state ->
        %{state | status: :idle, percent: 100, url: public_url, error: nil}
      end)

    {:noreply, socket}
  end

  @doc false
  def handle_upload_error(params, socket) do
    %{"kind" => kind, "target_id" => target_id, "error" => error} = params
    org_id = socket.assigns.organization.id

    Otel.with_span "marquee.admin.spaces_upload_error", %{
      "marquee.org.id" => org_id,
      "marquee.upload.kind" => kind,
      "marquee.upload.http_status" => params["http_status"],
      "marquee.upload.duration_ms" => params["duration_ms"],
      "marquee.upload.bytes_uploaded" => params["bytes_uploaded"],
      "marquee.upload.size" => params["size"],
      "marquee.upload.key" => params["key"]
    } do
      mark_span_error(error)

      Logger.error("Spaces upload failed",
        org_id: org_id,
        upload_kind: kind,
        target_id: target_id,
        error: error || "(empty)",
        http_status: params["http_status"],
        response_body: params["response_body"],
        bytes_uploaded: params["bytes_uploaded"],
        duration_ms: params["duration_ms"],
        filename: params["filename"],
        content_type: params["content_type"],
        size: params["size"],
        spaces_key: params["key"],
        raw_params: inspect(params, limit: :infinity, printable_limit: 2048)
      )

      {:noreply, fail_slot(socket, kind, target_id, error)}
    end
  end

  ## -----------------------------------------------------------------------
  ## Internal state helpers
  ## -----------------------------------------------------------------------

  defp update_slot(socket, kind, target_id, updater) do
    key = slot_key(kind, target_id)

    uploads =
      Map.update(
        socket.assigns.image_uploads,
        key,
        updater.(%{status: :idle, percent: 0, url: nil, error: nil}),
        updater
      )

    Phoenix.Component.assign(socket, :image_uploads, uploads)
  end

  defp fail_slot(socket, kind, target_id, message) do
    update_slot(socket, kind, target_id, fn state ->
      %{state | status: :error, error: message}
    end)
  end

  defp slot_key(kind, target_id), do: {to_string(kind), to_string(target_id || kind)}

  defp mark_span_error(reason) do
    Tracer.set_status(:error, to_string(reason))
  rescue
    UndefinedFunctionError -> :ok
  end

  defp ensure_int(v) when is_integer(v), do: v
  defp ensure_int(v) when is_binary(v), do: String.to_integer(v)
  defp ensure_int(v) when is_float(v), do: trunc(v)
end
