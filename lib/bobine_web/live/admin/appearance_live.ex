defmodule BobineWeb.Admin.AppearanceLive do
  @moduledoc """
  Operator appearance settings. Configures the homepage row layout
  (preset, row order, per-row card variant) and tenant branding
  (accent color, display font).

  Events:
    * `preview_preset`        — stage a preset preview (no save)
    * `apply_preset`          — reset layout rows to preset defaults
    * `move_row_up` / `move_row_down` — reorder + save
    * `update_row_variant`    — swap card variant for a row + save
    * `preview_branding`      — live-update accent swatch as operator types
    * `save_branding`         — persist accent colors + display font

  Route: /admin/appearance
  """

  use BobineWeb, :live_view

  alias Bobine.Accounts
  alias Bobine.Accounts.Organization
  alias Bobine.Catalog
  alias Bobine.Catalog.Presets

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    {:ok, layout} = Catalog.get_or_create_layout(org)

    branding_form =
      org
      |> Organization.branding_changeset(%{})
      |> to_form()

    {:ok,
     socket
     |> assign(:page_title, "Appearance")
     |> assign(:layout, layout)
     |> assign(:selected_preset, layout.preset_name)
     |> assign(:presets, Presets.list())
     |> assign(:branding_form, branding_form)
     |> assign(:accent_preview, org.accent_color_base)
     |> assign(:display_font_preview, org.display_font)
     |> assign(:display_fonts, Organization.approved_display_fonts())}
  end

  @impl true
  def handle_event("preview_preset", %{"name" => name}, socket) do
    {:noreply, assign(socket, :selected_preset, name)}
  end

  @impl true
  def handle_event("apply_preset", %{"name" => name}, socket) do
    org = socket.assigns.organization

    case Catalog.reset_layout_to_preset(org, name) do
      {:ok, layout} ->
        {:noreply,
         socket
         |> assign(:layout, layout)
         |> assign(:selected_preset, layout.preset_name)
         |> put_flash(:info, "Applied preset: #{name}")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Unknown preset.")}

      {:error, :validation, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not apply preset.")}
    end
  end

  @impl true
  def handle_event("move_row_up", %{"index" => idx_str}, socket) do
    reorder_rows(socket, String.to_integer(idx_str), :up)
  end

  @impl true
  def handle_event("move_row_down", %{"index" => idx_str}, socket) do
    reorder_rows(socket, String.to_integer(idx_str), :down)
  end

  @impl true
  def handle_event(
        "update_row_variant",
        %{"index" => idx_str, "variant" => variant},
        socket
      ) do
    idx = String.to_integer(idx_str)
    rows = socket.assigns.layout.rows

    new_rows =
      List.update_at(rows, idx, fn row -> Map.put(row, "card_variant", variant) end)

    save_rows(socket, new_rows)
  end

  @impl true
  def handle_event("preview_branding", %{"organization" => params}, socket) do
    {:noreply,
     socket
     |> assign(:accent_preview, Map.get(params, "accent_color_base") || "")
     |> assign(:display_font_preview, Map.get(params, "display_font") || "")
     |> assign(
       :branding_form,
       socket.assigns.organization
       |> Organization.branding_changeset(params)
       |> to_form()
     )}
  end

  @impl true
  def handle_event("save_branding", %{"organization" => params}, socket) do
    # Derive variants from base oklch if operator only supplies the base.
    params = maybe_derive_accent_variants(params)

    org = socket.assigns.organization

    case Accounts.update_organization_branding(org, params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:organization, updated)
         |> put_flash(:info, "Branding saved.")}

      {:error, :validation, changeset} ->
        {:noreply, assign(socket, :branding_form, to_form(changeset))}
    end
  end

  defp reorder_rows(socket, idx, direction) do
    rows = socket.assigns.layout.rows
    swap_with = if direction == :up, do: idx - 1, else: idx + 1

    if swap_with < 0 or swap_with >= length(rows) do
      {:noreply, socket}
    else
      a = Enum.at(rows, idx)
      b = Enum.at(rows, swap_with)

      new_rows =
        rows
        |> List.replace_at(idx, b)
        |> List.replace_at(swap_with, a)
        |> reindex_positions()

      save_rows(socket, new_rows)
    end
  end

  defp reindex_positions(rows) do
    rows
    |> Enum.with_index()
    |> Enum.map(fn {row, i} -> Map.put(row, "position", i) end)
  end

  defp save_rows(socket, new_rows) do
    case Catalog.update_layout(socket.assigns.layout, %{rows: new_rows}) do
      {:ok, layout} ->
        {:noreply, assign(socket, :layout, layout)}

      {:error, :validation, changeset} ->
        msg = format_row_errors(changeset)
        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  defp format_row_errors(changeset) do
    changeset.errors
    |> Enum.filter(fn {field, _} -> field == :rows end)
    |> Enum.map(fn {_, {msg, _}} -> msg end)
    |> Enum.join("; ")
    |> case do
      "" -> "Could not save layout."
      msg -> msg
    end
  end

  # When operator provides only the base oklch, auto-derive hover/active/subtle
  # by nudging the lightness channel. Keeps single-field UX while populating
  # all four stored variants.
  defp maybe_derive_accent_variants(%{"accent_color_base" => base} = params)
       when is_binary(base) and base != "" do
    params
    |> put_if_blank("accent_color_hover", shift_lightness(base, +0.06))
    |> put_if_blank("accent_color_active", shift_lightness(base, -0.06))
    |> put_if_blank("accent_color_subtle", subtle_from(base))
  end

  defp maybe_derive_accent_variants(params), do: params

  defp put_if_blank(params, key, value) do
    case Map.get(params, key) do
      v when is_binary(v) and v != "" -> params
      _ -> Map.put(params, key, value)
    end
  end

  defp shift_lightness(oklch, delta) do
    case parse_oklch(oklch) do
      {:ok, l, c, h} ->
        "oklch(#{format_number(clamp(l + delta, 0.0, 1.0))} #{format_number(c)} #{format_number(h)})"

      :error ->
        oklch
    end
  end

  defp subtle_from(oklch) do
    case parse_oklch(oklch) do
      {:ok, _l, c, h} ->
        "oklch(0.28 #{format_number(c / 2)} #{format_number(h)})"

      :error ->
        oklch
    end
  end

  defp parse_oklch(str) do
    case Regex.run(~r/oklch\(\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\)/, str) do
      [_, l, c, h] ->
        {:ok, String.to_float(ensure_dot(l)), String.to_float(ensure_dot(c)),
         String.to_float(ensure_dot(h))}

      _ ->
        :error
    end
  end

  defp ensure_dot(s), do: if(String.contains?(s, "."), do: s, else: s <> ".0")
  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)

  defp format_number(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 3)
  defp format_number(n), do: to_string(n)

  @impl true
  def render(assigns) do
    ~H"""
    <BobineWeb.Components.AdminLayout.admin_layout
      current_path={@current_path}
      organization={@organization}
      current_user={@current_user}
      impersonating={@impersonating}
    >
      <.header>
        Appearance
        <:subtitle>Homepage layout + tenant branding</:subtitle>
      </.header>

      <section class="mt-8" data-test="preset-picker">
        <h2 class="text-xl font-semibold mb-4">Presets</h2>
        <div class="grid gap-4 md:grid-cols-3">
          <button
            :for={preset <- @presets}
            type="button"
            phx-click="preview_preset"
            phx-value-name={preset.name}
            data-test={"preset-card-" <> preset.name}
            class={[
              "text-left rounded-lg border p-4 transition",
              preset_card_class(preset.name, @selected_preset, @layout.preset_name)
            ]}
          >
            <div class="font-semibold">{preset.display_name}</div>
            <p class="text-sm opacity-70 mt-1">{preset.description}</p>
            <div class="mt-3 text-xs opacity-60">
              {length(preset.rows)} rows · {preset.display_font}
            </div>
          </button>
        </div>

        <div :if={@selected_preset != @layout.preset_name} class="mt-4 flex gap-3 items-center">
          <span class="text-sm opacity-70">
            Previewing <strong>{@selected_preset}</strong>. Applying replaces your current rows.
          </span>
          <button
            type="button"
            phx-click="apply_preset"
            phx-value-name={@selected_preset}
            class="btn btn-primary btn-sm"
            data-test="apply-preset-btn"
          >
            Apply preset
          </button>
        </div>

        <div class="mt-4" data-test="preset-preview">
          <.preset_preview preset={preset_by_name(@presets, @selected_preset)} />
        </div>
      </section>

      <section class="mt-10" data-test="row-editor">
        <h2 class="text-xl font-semibold mb-4">Row order</h2>
        <ol class="space-y-2">
          <li
            :for={{row, idx} <- Enum.with_index(@layout.rows)}
            class="flex items-center gap-3 rounded-md border border-base-300 px-3 py-2"
            data-test={"layout-row-" <> to_string(idx)}
          >
            <span class="font-mono text-xs opacity-60 w-6">{idx + 1}.</span>
            <span class="flex-1 font-medium">{row["row_type"]}</span>
            <form phx-change="update_row_variant" class="flex items-center gap-2">
              <input type="hidden" name="index" value={idx} />
              <select
                name="variant"
                class="select select-sm select-bordered"
                data-test={"row-variant-" <> to_string(idx)}
              >
                <option
                  :for={variant <- compatible_variants(row["row_type"])}
                  value={to_string(variant)}
                  selected={to_string(variant) == row["card_variant"]}
                >
                  {variant}
                </option>
              </select>
            </form>
            <button
              type="button"
              phx-click="move_row_up"
              phx-value-index={idx}
              disabled={idx == 0}
              class="btn btn-ghost btn-xs"
              data-test={"move-up-" <> to_string(idx)}
              aria-label="Move row up"
            >
              ↑
            </button>
            <button
              type="button"
              phx-click="move_row_down"
              phx-value-index={idx}
              disabled={idx == length(@layout.rows) - 1}
              class="btn btn-ghost btn-xs"
              data-test={"move-down-" <> to_string(idx)}
              aria-label="Move row down"
            >
              ↓
            </button>
          </li>
        </ol>
      </section>

      <section class="mt-10" data-test="branding-editor">
        <h2 class="text-xl font-semibold mb-4">Brand</h2>
        <.form
          for={@branding_form}
          phx-change="preview_branding"
          phx-submit="save_branding"
          class="space-y-4 max-w-xl"
        >
          <div class="flex items-center gap-3">
            <.input
              field={@branding_form[:accent_color_base]}
              type="text"
              label="Accent color (oklch)"
              placeholder="oklch(0.72 0.14 68)"
            />
            <div
              class="w-10 h-10 rounded-full border border-base-300"
              style={"background-color: " <> (@accent_preview || "transparent")}
              data-test="accent-swatch"
              aria-hidden="true"
            >
            </div>
          </div>

          <div style={display_font_style(@display_font_preview)}>
            <.input
              field={@branding_form[:display_font]}
              type="select"
              label="Display font"
              options={[{"System default", ""} | Enum.map(@display_fonts, &{&1, &1})]}
            />
            <p class="text-3xl mt-2" data-test="display-font-preview">
              The quick brown fox
            </p>
          </div>

          <button type="submit" class="btn btn-primary" data-test="save-branding-btn">
            Save branding
          </button>
        </.form>
      </section>
    </BobineWeb.Components.AdminLayout.admin_layout>
    """
  end

  attr :preset, :map, default: nil

  defp preset_preview(assigns) do
    ~H"""
    <div :if={@preset} class="rounded-md bg-base-200 p-3 text-sm">
      <div class="font-semibold mb-2">{@preset.display_name} — row order</div>
      <ol class="list-decimal list-inside space-y-1">
        <li :for={row <- @preset.rows}>
          <span class="font-mono text-xs">{row.row_type}</span>
          <span class="opacity-60">·</span>
          <span>{row.card_variant}</span>
        </li>
      </ol>
    </div>
    """
  end

  defp preset_by_name(presets, name) do
    Enum.find(presets, &(&1.name == name))
  end

  defp compatible_variants(row_type_str) when is_binary(row_type_str) do
    row_type =
      Presets.row_types()
      |> Enum.find(&(Atom.to_string(&1) == row_type_str))

    if row_type, do: Presets.variants_for_row(row_type), else: []
  end

  defp compatible_variants(_), do: []

  defp preset_card_class(name, selected, active) do
    cond do
      name == active -> "border-primary ring-2 ring-primary/30"
      name == selected -> "border-accent"
      true -> "border-base-300 hover:border-base-content/40"
    end
  end

  defp display_font_style(nil), do: ""
  defp display_font_style(""), do: ""

  defp display_font_style(font) when is_binary(font),
    do: "font-family: '#{font}', Georgia, serif;"
end
