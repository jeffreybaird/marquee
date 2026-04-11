defmodule BobineWeb.Components.AdminComponents do
  @moduledoc """
  Reusable components for the admin dashboard.

  Keeps UI pieces that are shared across several admin LiveViews in
  one place. Today that's just `image_upload_field/1`; grow as needed.
  """

  use BobineWeb, :html

  alias Bobine.Storage

  @doc """
  Renders a drop-in image upload control for admin forms.

  The control wraps a file input + a live preview + a hidden input
  that carries the uploaded image's public URL into the surrounding
  form. All state lives in the LiveView via a single `url` assign;
  when the LiveView updates it after an upload completes, the hidden
  input re-serialises to the new value and the preview swaps.

  The file picker is wired up through the `SpacesUploader` TS hook,
  which mirrors the direct-to-Mux pattern: selecting a file triggers
  the hook to request a presigned URL from the server, PUT the bytes
  directly to the bucket, and report completion via `spaces_upload_complete`.

  ## Attributes

    * `name` — the form field name, e.g. `"series[cover_image_url]"`
    * `kind` — a short identifier forwarded to the server with every
      upload event (used to derive the bucket path). Examples:
      `"series_cover"`, `"season_cover"`, `"collection_cover"`,
      `"video_thumbnail"`.
    * `target_id` — optional, opaque caller id used when one LiveView
      hosts several upload slots (e.g. the series edit modal for the
      currently-edited series). Defaults to the `kind` when omitted.
    * `url` — the current public URL. Rendered as the preview and
      the hidden input's value.
    * `label` — the display label above the control. Defaults to
      `"Image"`.
    * `help` — optional help text below the control.
    * `status` — one of `:idle | :uploading | :error`. The caller
      toggles this in response to `spaces_upload_progress`, `_complete`
      or `_error` events. Progress is displayed when `percent` is set.
    * `percent` — integer 0..100, rendered as a bar when uploading.
    * `error` — error string to surface when `status == :error`.

  The component never fires direct phx events itself — all of the
  hook/LiveView communication happens through the `SpacesUploader`
  hook inside the wrapper element.
  """
  attr :name, :string, required: true
  attr :kind, :string, required: true
  attr :target_id, :string, default: nil
  attr :url, :string, default: nil
  attr :label, :string, default: "Image"
  attr :help, :string, default: nil
  attr :status, :atom, default: :idle, values: [:idle, :uploading, :error]
  attr :percent, :integer, default: 0
  attr :error, :string, default: nil

  def image_upload_field(assigns) do
    assigns =
      assigns
      |> assign_new(:resolved_target_id, fn -> assigns.target_id || assigns.kind end)
      |> assign_new(:accept_attr, fn ->
        Storage.allowed_image_content_types() |> Enum.join(",")
      end)
      |> assign_new(:hook_id, fn ->
        "spaces-uploader-#{assigns.kind}-#{assigns.target_id || "default"}"
      end)

    ~H"""
    <div class="sv-image-upload" data-test={"image-upload-#{@kind}"}>
      <label class="label">{@label}</label>

      <div class="sv-image-upload-preview" data-test={"image-upload-preview-#{@kind}"}>
        <%= if @url && @url != "" do %>
          <img src={@url} alt="" loading="lazy" />
        <% else %>
          <div class="sv-image-upload-placeholder">
            <.icon name="hero-photo" class="size-8" aria-hidden="true" />
            <p>No image yet</p>
          </div>
        <% end %>
      </div>

      <%!--
        The hook host is the *only* element that needs phx-update="ignore"
        — the file input must survive LV re-renders so in-progress uploads
        don't lose their XHR binding. The preview, progress, error, and
        hidden value above are re-rendered normally by the LV on every
        state change.
      --%>
      <div
        id={@hook_id}
        phx-hook="SpacesUploader"
        phx-update="ignore"
        data-upload-kind={@kind}
        data-target-id={@resolved_target_id}
        class="sv-image-upload-controls"
      >
        <label class="btn btn-sm btn-outline sv-image-upload-btn">
          <.icon name="hero-arrow-up-tray" class="size-4 mr-1" aria-hidden="true" /> Choose file
          <input
            type="file"
            accept={@accept_attr}
            class="sv-image-upload-file-input"
            data-test={"image-upload-input-#{@kind}"}
          />
        </label>
      </div>

      <input
        type="hidden"
        name={@name}
        value={@url || ""}
        data-test={"image-upload-value-#{@kind}"}
      />

      <div :if={@status == :uploading} class="sv-image-upload-progress">
        <div class="sv-image-upload-progress-bar" style={"width: #{@percent}%"}></div>
        <span>{@percent}%</span>
      </div>

      <p
        :if={@status == :error && @error}
        class="sv-image-upload-error"
        data-test={"image-upload-error-#{@kind}"}
      >
        {@error}
      </p>
      <p :if={@help} class="sv-image-upload-help">{@help}</p>
    </div>
    """
  end
end
