defmodule MarqueeWeb.Admin.PodcastsLive do
  @moduledoc """
  Operator interface for premium podcast shows. Index lists every show
  for the org. The same screen flips into a create or edit form when
  the operator picks an action.

  Events: new_show, edit_show, validate, save_show, delete_show,
  toggle_published, sync_now.

  Route: /admin/podcasts
  """

  use MarqueeWeb, :live_view

  alias Marquee.Billing
  alias Marquee.Podcasts
  alias Marquee.Podcasts.Show
  alias Marquee.Workers.PodcastFeedSync

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    %{results: shows} = Podcasts.list_shows(org, per_page: 100)
    %{results: plans} = Billing.list_plans(org, per_page: 100)

    {:ok,
     socket
     |> assign(:page_title, "Podcasts")
     |> assign(:demo?, org.demo_kind == :admin_sandbox)
     |> assign(:shows, shows)
     |> assign(:plans, plans)
     |> assign(:show_form, false)
     |> assign(:editing_show, nil)
     |> assign_form(Show.changeset(%Show{}, %{}))}
  end

  @impl true
  def handle_event("new_show", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_show, nil)
     |> assign_form(Show.changeset(%Show{access_mode: "any_active"}, %{}))}
  end

  def handle_event("edit_show", %{"id" => id}, socket) do
    case Podcasts.get_show(socket.assigns.organization, id) do
      {:ok, show} ->
        show = Podcasts.with_access_plans(show)

        {:noreply,
         socket
         |> assign(:show_form, true)
         |> assign(:editing_show, show)
         |> assign_form(Show.changeset(show, %{}))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Show not found.")}
    end
  end

  def handle_event("cancel_form", _params, socket) do
    {:noreply, assign(socket, show_form: false, editing_show: nil)}
  end

  def handle_event("validate", %{"show" => attrs}, socket) do
    base = socket.assigns.editing_show || %Show{}

    changeset =
      base
      |> Show.changeset(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save_show", %{"show" => attrs}, socket) do
    scope = socket.assigns.current_scope
    attrs = normalize_attrs(attrs)

    result =
      case socket.assigns.editing_show do
        nil -> Podcasts.create_show(scope, attrs)
        show -> Podcasts.update_show(scope, show, attrs)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:show_form, false)
         |> assign(:editing_show, nil)
         |> reload_shows()
         |> put_flash(:info, "Show saved.")}

      {:error, :validation, changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not save show: #{inspect(reason)}")}
    end
  end

  def handle_event("delete_show", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    with {:ok, show} <- Podcasts.get_show(socket.assigns.organization, id),
         {:ok, _} <- Podcasts.soft_delete_show(scope, show) do
      {:noreply,
       socket
       |> reload_shows()
       |> put_flash(:info, "Show deleted.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not delete show.")}
    end
  end

  def handle_event("toggle_published", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    with {:ok, show} <- Podcasts.get_show(socket.assigns.organization, id),
         {:ok, _} <- Podcasts.update_show(scope, show, %{published: !show.published}) do
      {:noreply, reload_shows(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not toggle.")}
    end
  end

  def handle_event("sync_now", _params, %{assigns: %{demo?: true}} = socket),
    do:
      {:noreply,
       put_flash(
         socket,
         :info,
         "Feed sync is disabled in the demo. You can edit show details locally."
       )}

  def handle_event("sync_now", %{"id" => id}, socket) do
    case Podcasts.get_show(socket.assigns.organization, id) do
      {:ok, %Show{source_type: "feed_import"} = show} ->
        PodcastFeedSync.enqueue_for_show(show)
        {:noreply, put_flash(socket, :info, "Sync enqueued.")}

      {:ok, _} ->
        {:noreply, put_flash(socket, :error, "Sync only applies to feed-import shows.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Show not found.")}
    end
  end

  defp reload_shows(socket) do
    %{results: shows} = Podcasts.list_shows(socket.assigns.organization, per_page: 100)
    assign(socket, :shows, shows)
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "show"))

  defp normalize_attrs(attrs) do
    attrs
    |> Map.update("tier_plan_ids", [], &List.wrap/1)
    |> Map.update("explicit", false, &truthy?/1)
    |> Map.update("published", false, &truthy?/1)
  end

  defp truthy?("true"), do: true
  defp truthy?(true), do: true
  defp truthy?(_), do: false

  @impl true
  def render(assigns) do
    ~H"""
    <MarqueeWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      trial_status={@trial_status}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
      flash={@flash}
    >
      <MarqueeWeb.Components.AdminUI.admin_panel
        title="Podcasts"
        subtitle="Premium audio shows delivered through tokenized RSS feeds."
      >
        <:actions>
          <MarqueeWeb.Components.AdminUI.admin_button
            :if={!@show_form}
            phx-click="new_show"
            size={:sm}
            data-test="new-show-btn"
          >
            New show
          </MarqueeWeb.Components.AdminUI.admin_button>
        </:actions>

        <p :if={@demo?} class="mb-4 text-admin-muted">
          Sample podcast shows. Edit details and publishing status here. Audio uploads, imported feeds and distribution are disabled.
        </p>
        <.show_form
          :if={@show_form}
          form={@form}
          editing={@editing_show}
          plans={@plans}
          demo?={@demo?}
        />

        <MarqueeWeb.Components.AdminUI.admin_empty
          :if={!@show_form and @shows == []}
          title="No podcasts yet"
          description="Create your first show to publish audio to subscribers."
          data_test="shows-empty"
        />

        <div :if={!@show_form and @shows != []} class="space-y-3" data-test="shows-list">
          <.show_row :for={show <- @shows} show={show} />
        </div>
      </MarqueeWeb.Components.AdminUI.admin_panel>
    </MarqueeWeb.Components.AdminLayout.admin_layout>
    """
  end

  attr :show, :map, required: true

  defp show_row(assigns) do
    ~H"""
    <div
      class={[
        "rounded-lg border border-admin-border bg-admin-card p-4 flex items-center justify-between gap-4",
        !@show.published && "opacity-60"
      ]}
      data-test={"show-row-#{@show.id}"}
    >
      <div class="min-w-0">
        <div class="flex items-center gap-2">
          <span class="font-display font-semibold text-admin-fg truncate">{@show.title}</span>
          <span class="font-mono text-xs text-admin-muted">{@show.slug}</span>
        </div>
        <div class="mt-1 flex flex-wrap items-center gap-2 text-xs text-admin-muted">
          <span data-test={"show-source-#{@show.id}"}>{source_label(@show.source_type)}</span>
          <span aria-hidden="true">·</span>
          <span>{access_label(@show.access_mode)}</span>
          <span :if={!@show.published} class="text-warning">(unpublished)</span>
          <span
            :if={@show.source_type == "feed_import" && @show.remote_last_sync_error}
            class="text-danger"
            data-test={"show-sync-error-#{@show.id}"}
          >
            sync error
          </span>
        </div>
      </div>
      <div class="flex flex-shrink-0 gap-1">
        <MarqueeWeb.Components.AdminUI.admin_button
          :if={@show.source_type == "feed_import"}
          variant={:ghost}
          size={:sm}
          phx-click="sync_now"
          phx-value-id={@show.id}
          data-test={"sync-show-#{@show.id}"}
        >
          Sync now
        </MarqueeWeb.Components.AdminUI.admin_button>
        <MarqueeWeb.Components.AdminUI.admin_button
          variant={:ghost}
          size={:sm}
          phx-click="toggle_published"
          phx-value-id={@show.id}
          data-test={"toggle-published-#{@show.id}"}
        >
          {if @show.published, do: "Unpublish", else: "Publish"}
        </MarqueeWeb.Components.AdminUI.admin_button>
        <MarqueeWeb.Components.AdminUI.admin_button
          variant={:ghost}
          size={:sm}
          phx-click="edit_show"
          phx-value-id={@show.id}
          data-test={"edit-show-#{@show.id}"}
        >
          Edit
        </MarqueeWeb.Components.AdminUI.admin_button>
        <MarqueeWeb.Components.AdminUI.admin_button
          variant={:danger}
          size={:sm}
          phx-click="delete_show"
          phx-value-id={@show.id}
          data-confirm="Delete this show? Active feed tokens will be revoked."
          data-test={"delete-show-#{@show.id}"}
        >
          Delete
        </MarqueeWeb.Components.AdminUI.admin_button>
      </div>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :editing, :any, default: nil
  attr :plans, :list, default: []
  attr :demo?, :boolean, default: false

  defp show_form(assigns) do
    ~H"""
    <form
      phx-change="validate"
      phx-submit="save_show"
      class="space-y-4"
      data-test="show-form"
    >
      <div class="grid gap-3 sm:grid-cols-2">
        <label class="block">
          <span class="text-xs font-medium text-admin-muted">Title</span>
          <input
            type="text"
            name="show[title]"
            value={Phoenix.HTML.Form.input_value(@form, :title)}
            required
            class="mt-1 w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
            data-test="show-title-input"
          />
        </label>
        <label class="block">
          <span class="text-xs font-medium text-admin-muted">Slug</span>
          <input
            type="text"
            name="show[slug]"
            value={Phoenix.HTML.Form.input_value(@form, :slug)}
            required
            pattern="[a-z0-9\-]+"
            class="mt-1 w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
            data-test="show-slug-input"
          />
        </label>
      </div>

      <label class="block">
        <span class="text-xs font-medium text-admin-muted">Description</span>
        <textarea
          name="show[description]"
          rows="3"
          class="mt-1 w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
        >{Phoenix.HTML.Form.input_value(@form, :description)}</textarea>
      </label>

      <div class="grid gap-3 sm:grid-cols-2">
        <label class="block">
          <span class="text-xs font-medium text-admin-muted">Author</span>
          <input
            type="text"
            name="show[author]"
            value={Phoenix.HTML.Form.input_value(@form, :author)}
            class="mt-1 w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
          />
        </label>
        <label class="block">
          <span class="text-xs font-medium text-admin-muted">Owner email</span>
          <input
            type="email"
            name="show[owner_email]"
            value={Phoenix.HTML.Form.input_value(@form, :owner_email)}
            class="mt-1 w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
          />
        </label>
      </div>

      <fieldset class="space-y-2">
        <legend class="text-xs font-medium text-admin-muted">Source</legend>
        <div class="flex gap-4">
          <label class="flex items-center gap-2">
            <input
              type="radio"
              name="show[source_type]"
              value="direct_upload"
              checked={Phoenix.HTML.Form.input_value(@form, :source_type) in [nil, "direct_upload"]}
              disabled={!is_nil(@editing)}
              data-test="source-direct"
            />
            <span class="text-sm text-admin-fg">Direct upload</span>
          </label>
          <label class="flex items-center gap-2">
            <input
              type="radio"
              name="show[source_type]"
              value="feed_import"
              checked={Phoenix.HTML.Form.input_value(@form, :source_type) == "feed_import"}
              disabled={@demo? or !is_nil(@editing)}
              data-test="source-feed"
            />
            <span class="text-sm text-admin-fg">Import from feed URL</span>
          </label>
        </div>
        <p :if={!is_nil(@editing)} class="text-xs text-admin-muted">
          Source type is fixed after creation.
        </p>
      </fieldset>

      <label
        :if={Phoenix.HTML.Form.input_value(@form, :source_type) == "feed_import"}
        class="block"
      >
        <span class="text-xs font-medium text-admin-muted">Remote feed URL</span>
        <input
          type="url"
          name="show[remote_feed_url]"
          value={Phoenix.HTML.Form.input_value(@form, :remote_feed_url)}
          class="mt-1 w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
          data-test="show-remote-feed-input"
        />
      </label>

      <fieldset class="space-y-2">
        <legend class="text-xs font-medium text-admin-muted">Access mode</legend>
        <div class="flex flex-wrap gap-3">
          <label class="flex items-center gap-2">
            <input
              type="radio"
              name="show[access_mode]"
              value="any_active"
              checked={Phoenix.HTML.Form.input_value(@form, :access_mode) in [nil, "any_active"]}
              data-test="access-any"
            />
            <span class="text-sm text-admin-fg">Any active subscription</span>
          </label>
          <label class="flex items-center gap-2">
            <input
              type="radio"
              name="show[access_mode]"
              value="specific_tiers"
              checked={Phoenix.HTML.Form.input_value(@form, :access_mode) == "specific_tiers"}
              disabled={@demo?}
              data-test="access-tiers"
            />
            <span class="text-sm text-admin-fg">Specific tiers</span>
          </label>
          <label class="flex items-center gap-2">
            <input
              type="radio"
              name="show[access_mode]"
              value="audio_only_plan"
              checked={Phoenix.HTML.Form.input_value(@form, :access_mode) == "audio_only_plan"}
              disabled={@demo?}
              data-test="access-audio-only"
            />
            <span class="text-sm text-admin-fg">Audio-only plan</span>
          </label>
        </div>
      </fieldset>

      <fieldset
        :if={Phoenix.HTML.Form.input_value(@form, :access_mode) == "specific_tiers"}
        class="space-y-2"
        data-test="tier-picker"
      >
        <legend class="text-xs font-medium text-admin-muted">Allowed tiers</legend>
        <div :for={plan <- @plans} class="flex items-center gap-2">
          <input
            type="checkbox"
            name="show[tier_plan_ids][]"
            value={plan.id}
            checked={tier_checked?(@editing, plan.id)}
            data-test={"tier-checkbox-#{plan.id}"}
          />
          <span class="text-sm text-admin-fg">{plan.name}</span>
        </div>
      </fieldset>

      <label
        :if={Phoenix.HTML.Form.input_value(@form, :access_mode) == "audio_only_plan"}
        class="block"
      >
        <span class="text-xs font-medium text-admin-muted">Audio-only plan</span>
        <select
          name="show[audio_only_plan_id]"
          class="mt-1 w-full rounded-md border border-admin-border bg-admin-card px-3 py-2 font-body text-sm text-admin-fg focus:border-admin-accent focus:outline-none"
          data-test="audio-only-plan-select"
        >
          <option value="">— select a plan —</option>
          <option
            :for={plan <- @plans}
            value={plan.id}
            selected={Phoenix.HTML.Form.input_value(@form, :audio_only_plan_id) == plan.id}
          >
            {plan.name}
          </option>
        </select>
      </label>

      <div class="flex items-center gap-3">
        <label class="flex items-center gap-2">
          <input
            type="checkbox"
            name="show[explicit]"
            value="true"
            checked={Phoenix.HTML.Form.input_value(@form, :explicit) == true}
          />
          <span class="text-sm text-admin-fg">Explicit content</span>
        </label>
        <label class="flex items-center gap-2">
          <input
            type="checkbox"
            name="show[published]"
            value="true"
            checked={Phoenix.HTML.Form.input_value(@form, :published) == true}
            data-test="show-published-checkbox"
          />
          <span class="text-sm text-admin-fg">Published</span>
        </label>
      </div>

      <div class="flex gap-2">
        <MarqueeWeb.Components.AdminUI.admin_button
          type="submit"
          size={:sm}
          data-test="save-show-btn"
        >
          {if @editing, do: "Save changes", else: "Create show"}
        </MarqueeWeb.Components.AdminUI.admin_button>
        <MarqueeWeb.Components.AdminUI.admin_button
          type="button"
          variant={:ghost}
          size={:sm}
          phx-click="cancel_form"
        >
          Cancel
        </MarqueeWeb.Components.AdminUI.admin_button>
      </div>
    </form>
    """
  end

  defp tier_checked?(nil, _plan_id), do: false

  defp tier_checked?(%Show{access_plans: plans}, plan_id) when is_list(plans),
    do: Enum.any?(plans, &(&1.id == plan_id))

  defp tier_checked?(_, _), do: false

  defp source_label("direct_upload"), do: "Direct upload"
  defp source_label("feed_import"), do: "Feed import"
  defp source_label(other), do: other

  defp access_label("any_active"), do: "Any active subscription"
  defp access_label("specific_tiers"), do: "Specific tiers"
  defp access_label("audio_only_plan"), do: "Audio-only plan"
  defp access_label(other), do: other
end
