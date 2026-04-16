defmodule BobineWeb.Components.AdminUI do
  @moduledoc """
  Unified admin UI primitives. All operator-facing admin views render
  through these components so they inherit the same semantic tokens
  (`bg-surface`, `bg-elevated`, `border-border`, `text-text-primary`,
  `bg-accent`) and the same content-creation pattern (side sheet,
  never a centered modal or inline toggle).

  Components:
    * `admin_panel/1`   — page shell: titled header with optional action slot + body
    * `admin_section/1` — grouped sub-region inside a panel
    * `admin_sheet/1`   — right-side slide-in drawer for create/edit forms
    * `admin_button/1`  — accent/secondary/ghost/danger buttons backed by tokens
    * `admin_empty/1`   — empty-state block

  All components live on semantic tokens only. daisyUI `base-*`,
  `btn-primary`, and raw hex values must not appear in admin templates.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :data_test, :string, default: nil
  slot :actions
  slot :inner_block, required: true

  @doc """
  Page-level shell: title, optional subtitle, action slot, then body.

  ## Example

      <.admin_panel title="Plans" subtitle="Viewer subscription tiers">
        <:actions>
          <.admin_button phx-click="new_plan">New plan</.admin_button>
        </:actions>
        ...rows...
      </.admin_panel>
  """
  def admin_panel(assigns) do
    ~H"""
    <section class="space-y-6" data-test={@data_test}>
      <header class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <h1 class="font-display text-2xl font-semibold tracking-tight text-text-primary">
            {@title}
          </h1>
          <p :if={@subtitle} class="mt-1 font-body text-sm text-text-secondary">
            {@subtitle}
          </p>
        </div>
        <div :if={@actions != []} class="flex shrink-0 items-center gap-2">
          {render_slot(@actions)}
        </div>
      </header>

      <div class="font-body text-text-primary">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  attr :title, :string, default: nil
  attr :description, :string, default: nil
  attr :data_test, :string, default: nil
  slot :inner_block, required: true

  @doc """
  Grouped sub-region inside an `admin_panel`. Use for logical clusters
  inside a long view (e.g. "Typography" within Appearance).
  """
  def admin_section(assigns) do
    ~H"""
    <section
      class="rounded-lg border border-border bg-surface p-6 space-y-4"
      data-test={@data_test}
    >
      <div :if={@title} class="space-y-1">
        <h2 class="font-display text-lg font-semibold text-text-primary">{@title}</h2>
        <p :if={@description} class="font-body text-sm text-text-secondary">{@description}</p>
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :id, :string, required: true
  attr :open, :boolean, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil

  attr :on_close, :string,
    required: true,
    doc: "Server event name dispatched when the user closes the sheet"

  attr :data_test, :string, default: nil
  slot :inner_block, required: true
  slot :footer

  @doc """
  Right-side slide-in drawer. Single unified create/edit surface for
  every admin view. Preserves list context (no route change) and keeps
  narrow forms (one column) comfortable.

  Triggered open by the parent assigning `@open = true`. Closes via:
    * backdrop click
    * Escape key
    * explicit Cancel button inside the sheet

  All three dispatch the server event named in `:on_close`.
  """
  def admin_sheet(assigns) do
    ~H"""
    <div
      :if={@open}
      id={@id}
      class="fixed inset-0 z-50"
      role="dialog"
      aria-modal="true"
      aria-labelledby={@id <> "-title"}
      data-test={@data_test}
      phx-window-keydown={JS.push(@on_close)}
      phx-key="escape"
    >
      <div
        class="absolute inset-0 bg-bg/70 backdrop-blur-sm"
        phx-click={JS.push(@on_close)}
        aria-hidden="true"
      />
      <aside class="absolute inset-y-0 right-0 flex w-full max-w-xl flex-col border-l border-border bg-surface shadow-2xl">
        <header class="flex items-start justify-between gap-4 border-b border-border px-6 py-4">
          <div class="min-w-0">
            <h2
              id={@id <> "-title"}
              class="font-display text-lg font-semibold text-text-primary"
            >
              {@title}
            </h2>
            <p :if={@subtitle} class="mt-1 font-body text-sm text-text-secondary">
              {@subtitle}
            </p>
          </div>
          <button
            type="button"
            phx-click={JS.push(@on_close)}
            class="rounded-md p-1 text-text-secondary hover:bg-elevated hover:text-text-primary focus-visible:outline-2 focus-visible:outline-accent"
            aria-label="Close"
            data-test={(@data_test && @data_test <> "-close") || nil}
          >
            <BobineWeb.CoreComponents.icon name="hero-x-mark" class="size-5" />
          </button>
        </header>

        <div class="flex-1 overflow-y-auto px-6 py-5 font-body text-text-primary">
          {render_slot(@inner_block)}
        </div>

        <footer
          :if={@footer != []}
          class="flex items-center justify-end gap-2 border-t border-border bg-elevated px-6 py-4"
        >
          {render_slot(@footer)}
        </footer>
      </aside>
    </div>
    """
  end

  attr :type, :string, default: "button"
  attr :variant, :atom, values: [:accent, :secondary, :ghost, :danger], default: :accent
  attr :size, :atom, values: [:sm, :md], default: :md
  attr :class, :any, default: nil

  attr :rest, :global,
    include:
      ~w(phx-click phx-value-id phx-value-name phx-disable-with disabled href navigate patch form name value data-confirm)

  slot :inner_block, required: true

  @doc """
  Single admin button. Variants map to token-backed color pairs so
  operator branding flows through (`accent` uses the tenant accent).
  """
  def admin_button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "inline-flex items-center justify-center gap-1.5 rounded-md font-ui font-medium transition-colors",
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent",
        "disabled:cursor-not-allowed disabled:opacity-50",
        size_class(@size),
        variant_class(@variant),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp size_class(:sm), do: "px-3 py-1.5 text-sm"
  defp size_class(:md), do: "px-4 py-2 text-sm"

  defp variant_class(:accent),
    do: "bg-accent text-accent-text hover:bg-accent-hover active:bg-accent-active"

  defp variant_class(:secondary),
    do: "bg-elevated text-text-primary border border-border hover:border-border-strong"

  defp variant_class(:ghost),
    do: "text-text-secondary hover:bg-elevated hover:text-text-primary"

  defp variant_class(:danger),
    do: "bg-error text-accent-text hover:opacity-90"

  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :data_test, :string, default: nil
  slot :actions

  @doc """
  Empty-state block. Centered message with optional action button slot.
  """
  def admin_empty(assigns) do
    ~H"""
    <div
      class="rounded-lg border border-dashed border-border bg-surface px-6 py-12 text-center"
      data-test={@data_test}
    >
      <p class="font-display text-base font-semibold text-text-primary">{@title}</p>
      <p :if={@description} class="mt-1 font-body text-sm text-text-secondary">
        {@description}
      </p>
      <div :if={@actions != []} class="mt-4 flex items-center justify-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end
end
