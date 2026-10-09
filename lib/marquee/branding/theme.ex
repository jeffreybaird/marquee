defmodule Marquee.Branding.Theme do
  use Ecto.Schema
  import Ecto.Changeset

  alias Marquee.Accounts.Organization

  # Wave B: brand_primary / brand_primary_hover / accent still live on the
  # schema so presets and backfills keep working, but the Branding UI
  # hides them — the tenant accent is authoritative on Organization now.
  @castable_fields [
    :brand_primary,
    :brand_secondary,
    :background,
    :surface,
    :elevated,
    :text_primary,
    :text_secondary,
    :text_on_accent,
    :accent,
    :brand_primary_hover,
    :font_heading,
    :font_body,
    :border_radius,
    :card_border_radius,
    :border_color,
    :divider_color,
    :nav_background,
    :card_background,
    :overlay_color,
    :logo_url,
    :favicon_url,
    :login_background_image_url,
    :form_text,
    :form_placeholder,
    :organization_id
  ]

  @default_viewer_theme %{
    background: "#0F0F0F",
    surface: "#1A1A1A",
    elevated: "#252525",
    text_primary: "#FFFFFF",
    text_secondary: "#A0A0A0",
    text_on_accent: "#FFFFFF",
    brand_primary: "#E50914",
    brand_primary_hover: "#F6121D",
    font_heading: "Inter",
    font_body: "Inter",
    border_color: "rgba(255, 255, 255, 0.08)",
    divider_color: "rgba(255, 255, 255, 0.05)",
    nav_background: "rgba(0, 0, 0, 0.85)",
    card_background: "#1A1A1A",
    overlay_color: "rgba(0, 0, 0, 0.7)",
    form_text: "#FFFFFF",
    form_placeholder: "#8A8A8A"
  }

  # Named starter themes offered to operators at signup. Each preset is a
  # complete set of color values that can be applied directly via
  # `create_theme/1`. The `:label` and `:description` are presentation-only
  # metadata for the chooser UI and are stripped by `preset_attrs/1`.
  @theme_presets %{
    "midnight" => %{
      label: "Midnight",
      description: "Cinema-dark with bold red accents.",
      background: "#0F0F0F",
      surface: "#1A1A1A",
      elevated: "#252525",
      text_primary: "#FFFFFF",
      text_secondary: "#A0A0A0",
      text_on_accent: "#FFFFFF",
      brand_primary: "#E50914",
      brand_primary_hover: "#F6121D",
      font_heading: "Inter",
      font_body: "Inter",
      border_radius: "0.5rem",
      card_border_radius: "0.75rem",
      border_color: "rgba(255, 255, 255, 0.08)",
      divider_color: "rgba(255, 255, 255, 0.05)",
      nav_background: "rgba(0, 0, 0, 0.85)",
      card_background: "#1A1A1A",
      overlay_color: "rgba(0, 0, 0, 0.7)",
      form_text: "#FFFFFF",
      form_placeholder: "#8A8A8A"
    },
    "daybreak" => %{
      label: "Daybreak",
      description: "Bright and minimal with calm blue accents.",
      background: "#FFFFFF",
      surface: "#F5F5F7",
      elevated: "#FFFFFF",
      text_primary: "#111827",
      text_secondary: "#6B7280",
      text_on_accent: "#FFFFFF",
      brand_primary: "#2563EB",
      brand_primary_hover: "#1D4ED8",
      font_heading: "Inter",
      font_body: "Inter",
      border_radius: "0.5rem",
      card_border_radius: "0.75rem",
      border_color: "rgba(17, 24, 39, 0.08)",
      divider_color: "rgba(17, 24, 39, 0.05)",
      nav_background: "rgba(255, 255, 255, 0.92)",
      card_background: "#FFFFFF",
      overlay_color: "rgba(17, 24, 39, 0.5)",
      form_text: "#111827",
      form_placeholder: "#9CA3AF"
    }
  }

  @default_preset_key "midnight"

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "themes" do
    field :brand_primary, :string
    field :brand_secondary, :string
    field :background, :string
    field :surface, :string
    field :elevated, :string
    field :text_primary, :string
    field :text_secondary, :string
    field :text_on_accent, :string
    field :accent, :string
    field :brand_primary_hover, :string
    field :font_heading, :string
    field :font_body, :string
    field :border_radius, :string
    field :card_border_radius, :string
    field :border_color, :string
    field :divider_color, :string
    field :nav_background, :string
    field :card_background, :string
    field :overlay_color, :string
    field :logo_url, :string
    field :favicon_url, :string
    field :login_background_image_url, :string
    field :form_text, :string
    field :form_placeholder, :string

    belongs_to :organization, Marquee.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the default viewer theme values.

  ## Examples

      iex> defaults = Marquee.Branding.Theme.default_viewer_theme()
      iex> defaults.background
      "#0F0F0F"
      iex> defaults.form_text
      "#FFFFFF"
      iex> defaults.form_placeholder
      "#8A8A8A"

  """
  def default_viewer_theme, do: @default_viewer_theme

  @doc """
  Returns the map of named starter theme presets offered to new operators
  at signup.

  ## Examples

      iex> presets = Marquee.Branding.Theme.presets()
      iex> Map.keys(presets) |> Enum.sort()
      ["daybreak", "midnight"]
      iex> presets["midnight"].label
      "Midnight"

  """
  def presets, do: @theme_presets

  @doc """
  Returns the list of valid preset keys.

  ## Examples

      iex> Enum.sort(Marquee.Branding.Theme.preset_keys())
      ["daybreak", "midnight"]

  """
  def preset_keys, do: Map.keys(@theme_presets)

  @doc """
  Returns the default preset key used when none is supplied at signup.

  ## Examples

      iex> Marquee.Branding.Theme.default_preset_key()
      "midnight"

  """
  def default_preset_key, do: @default_preset_key

  @doc """
  Looks up a preset by key, returning the full presentation map (label,
  description, and color values) or `nil` when the key is unknown.

  ## Examples

      iex> Marquee.Branding.Theme.preset("daybreak").background
      "#FFFFFF"

      iex> Marquee.Branding.Theme.preset("nope")
      nil

  """
  def preset(key) when is_binary(key), do: Map.get(@theme_presets, key)

  @doc """
  Returns just the theme attribute map for a preset, with presentation
  metadata stripped — suitable for passing to `Marquee.Branding.create_theme/1`.

  ## Examples

      iex> attrs = Marquee.Branding.Theme.preset_attrs("midnight")
      iex> attrs.background
      "#0F0F0F"
      iex> Map.has_key?(attrs, :label)
      false

      iex> Marquee.Branding.Theme.preset_attrs("nope")
      nil

  """
  def preset_attrs(key) when is_binary(key) do
    case preset(key) do
      nil -> nil
      preset -> Map.drop(preset, [:label, :description])
    end
  end

  @doc """
  Builds a CSS custom property string from theme values, applying defaults for missing fields.

  ## Examples

      iex> theme = %Marquee.Branding.Theme{background: "#000000", brand_primary: "#FF0000"}
      iex> css = Marquee.Branding.Theme.build_css_vars(theme)
      iex> css =~ "--sv-bg-primary: #000000"
      true
      iex> css =~ "--sv-accent: var(--color-accent, #FF0000)"
      true
      iex> css =~ "--sv-live-indicator-bg: #D4183D"
      true

  """
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def build_css_vars(%__MODULE__{} = theme) do
    defaults = @default_viewer_theme

    [
      {"--sv-bg-primary", theme.background || defaults.background},
      {"--sv-bg-secondary", theme.surface || defaults.surface},
      {"--sv-bg-elevated", theme.elevated || defaults.elevated},
      {"--sv-text-primary", theme.text_primary || defaults.text_primary},
      {"--sv-text-secondary", theme.text_secondary || defaults.text_secondary},
      {"--sv-text-on-accent", theme.text_on_accent || defaults.text_on_accent},
      # --sv-accent / --sv-accent-hover now alias to the tenant accent tokens
      # owned by Organization.accent_color_*. See app.css for the alias rule.
      # Hex defaults remain as a last-resort fallback for legacy theme rows.
      {"--sv-accent", "var(--color-accent, #{theme.brand_primary || defaults.brand_primary})"},
      {"--sv-accent-hover",
       "var(--color-accent-hover, #{theme.brand_primary_hover || defaults.brand_primary_hover})"},
      {"--sv-font-heading",
       "#{theme.font_heading || defaults.font_heading}, system-ui, sans-serif"},
      {"--sv-font-body", "#{theme.font_body || defaults.font_body}, system-ui, sans-serif"},
      {"--sv-border", theme.border_color || defaults.border_color},
      {"--sv-divider", theme.divider_color || defaults.divider_color},
      {"--sv-nav-bg", theme.nav_background || defaults.nav_background},
      {"--sv-card-bg", theme.card_background || defaults.card_background},
      {"--sv-overlay", theme.overlay_color || defaults.overlay_color},
      {"--sv-form-text", theme.form_text || defaults.form_text},
      {"--sv-form-placeholder", theme.form_placeholder || defaults.form_placeholder},
      {"--sv-radius-sm", "4px"},
      {"--sv-radius-md", "8px"},
      {"--sv-radius-lg", "12px"},
      # Semantic "liveness" indicator — used for LIVE badges and error surfaces
      # on live pages. Distinct from brand accent so streaming signals remain
      # recognizable regardless of tenant color choice.
      {"--sv-live-indicator-bg", "#D4183D"},
      {"--sv-live-indicator-fg", "#FFFFFF"}
    ]
    |> Enum.map_join("; ", fn {var, val} -> "#{var}: #{val}" end)
  end

  @doc """
  Builds the inline style for an unsaved appearance draft: the theme's CSS
  custom properties followed by the organization-level accent and display
  font overrides, when present.

  The editor's preview frame and the viewer site both render drafts through
  this function so the two surfaces cannot drift.

  ## Examples

      iex> theme = %Marquee.Branding.Theme{background: "#123456"}
      iex> css = Marquee.Branding.Theme.build_preview_css_vars(%{
      ...>   theme: theme,
      ...>   accent_color_base: "#ABCDEF",
      ...>   display_font: "Playfair Display"
      ...> })
      iex> String.starts_with?(css, "--sv-bg-primary: #123456")
      true
      iex> String.ends_with?(css, "; --color-accent: #ABCDEF; --color-accent-hover: #ABCDEF; --color-accent-active: #ABCDEF; --color-accent-subtle: #ABCDEF; --font-display: 'Playfair Display', Georgia, serif")
      true

      iex> theme = %Marquee.Branding.Theme{background: "#123456"}
      iex> Marquee.Branding.Theme.build_preview_css_vars(%{theme: theme, accent_color_base: nil, display_font: nil}) ==
      ...>   Marquee.Branding.Theme.build_css_vars(theme)
      true

  """
  def build_preview_css_vars(%{theme: %__MODULE__{} = theme} = draft) do
    branding =
      draft
      |> Map.drop([:theme])
      |> preview_params(:organization)
      |> derive_accent_variants()

    safe_theme =
      struct(__MODULE__, theme |> Map.from_struct() |> preview_params(:theme) |> atomize_params())

    [
      build_css_vars(safe_theme),
      accent_overrides(branding),
      display_font_override(branding["display_font"])
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("; ")
  end

  defp accent_overrides(branding) do
    [
      {"accent_color_base", "--color-accent"},
      {"accent_color_hover", "--color-accent-hover"},
      {"accent_color_active", "--color-accent-active"},
      {"accent_color_subtle", "--color-accent-subtle"}
    ]
    |> Enum.flat_map(fn {field, token} ->
      case branding[field] do
        value when is_binary(value) and value != "" -> ["#{token}: #{value}"]
        _ -> []
      end
    end)
    |> case do
      [] -> nil
      values -> Enum.join(values, "; ")
    end
  end

  defp display_font_override(font) when is_binary(font) and font != "",
    do: "--font-display: '#{font}', Georgia, serif"

  defp display_font_override(_font), do: nil

  @doc """
  Keeps only supported, safe values for an unsaved theme or organization preview.

      iex> Marquee.Branding.Theme.preview_params(%{"background" => "#123456", "surface" => "red; color: red"}, :theme)
      %{"background" => "#123456"}
      iex> Marquee.Branding.Theme.preview_params(%{"display_font" => "Playfair Display", "accent_color_base" => "#ABCDEF"}, :organization)
      %{"display_font" => "Playfair Display", "accent_color_base" => "#ABCDEF"}
  """
  def preview_params(params, kind) do
    params
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Enum.filter(fn {key, value} -> safe_preview_value?(kind, key, value) end)
    |> Map.new()
  end

  @preview_color_fields ~w(brand_primary brand_secondary background surface elevated text_primary text_secondary text_on_accent accent brand_primary_hover border_color divider_color nav_background card_background overlay_color form_text form_placeholder)
  @preview_accent_fields ~w(accent_color_base accent_color_hover accent_color_active accent_color_subtle)
  @preview_asset_fields ~w(logo_url favicon_url login_background_image_url)
  @color_number "(?:[0-9]+(?:\\.[0-9]+)?|\\.[0-9]+)"
  @preview_color ~r/\A(?:\#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?|\#[0-9a-fA-F]{8}|oklch\(\s*#{@color_number}\s+#{@color_number}\s+#{@color_number}\s*\)|rgba?\(\s*#{@color_number}\s*,\s*#{@color_number}\s*,\s*#{@color_number}(?:\s*,\s*#{@color_number})?\s*\))\z/

  defp safe_preview_value?(:organization, "display_font", value),
    do: value in [nil, "" | Organization.approved_display_fonts()]

  defp safe_preview_value?(:organization, field, value) when field in @preview_accent_fields,
    do: safe_preview_color?(value)

  defp safe_preview_value?(:theme, field, value) when field in @preview_color_fields,
    do: safe_preview_color?(value)

  defp safe_preview_value?(:theme, "font_heading", value),
    do:
      value in [
        nil,
        ""
        | Organization.approved_display_fonts() ++
            Organization.approved_body_fonts()
      ]

  defp safe_preview_value?(:theme, "font_body", value),
    do: value in [nil, "" | Organization.approved_body_fonts()]

  defp safe_preview_value?(:theme, field, value) when field in @preview_asset_fields,
    do:
      is_nil(value) or
        (is_binary(value) and
           (value == "" or String.starts_with?(value, ["https://", "http://", "/"])))

  defp safe_preview_value?(:theme, field, value)
       when field in ~w(border_radius card_border_radius),
       do:
         is_nil(value) or
           (is_binary(value) and
              Regex.match?(~r/\A(?:[0-9]+(?:\.[0-9]+)?(?:px|rem|em|%)?|)\z/, value))

  defp safe_preview_value?(_, _, _), do: false

  defp safe_preview_color?(value) when value in [nil, ""], do: true

  defp safe_preview_color?(value) when is_binary(value),
    do: byte_size(value) <= 100 and Regex.match?(@preview_color, value)

  defp safe_preview_color?(_), do: false

  defp atomize_params(params),
    do: Map.new(params, fn {key, value} -> {String.to_existing_atom(key), value} end)

  @doc """
  Fills blank accent variants using the same values for preview and persistence.

      iex> Marquee.Branding.Theme.derive_accent_variants(%{"accent_color_base" => "oklch(0.6 0.2 30)"})
      %{"accent_color_base" => "oklch(0.6 0.2 30)", "accent_color_hover" => "oklch(0.660 0.200 30.000)", "accent_color_active" => "oklch(0.540 0.200 30.000)", "accent_color_subtle" => "oklch(0.28 0.100 30.000)"}
  """
  def derive_accent_variants(%{"accent_color_base" => base} = params)
      when is_binary(base) and base != "" do
    params
    |> put_if_blank("accent_color_hover", shift_lightness(base, +0.06))
    |> put_if_blank("accent_color_active", shift_lightness(base, -0.06))
    |> put_if_blank("accent_color_subtle", subtle_from(base))
  end

  def derive_accent_variants(params), do: params

  @doc """
  Derives changed accent values against the organization's current branding.

  Unchanged explicit variants are preserved, and a cleared variant derives from
  the effective base. Only actual changes are returned for persistence.

      iex> org = %Marquee.Accounts.Organization{accent_color_base: "#112233", accent_color_hover: "#223344", accent_color_active: "#334455", accent_color_subtle: "#445566"}
      iex> Marquee.Branding.Theme.derive_accent_variants(%{"accent_color_base" => "#AABBCC"}, org)
      %{"accent_color_base" => "#AABBCC"}
      iex> Marquee.Branding.Theme.derive_accent_variants(%{"accent_color_hover" => nil}, org)
      %{"accent_color_hover" => "#112233"}
  """
  def derive_accent_variants(params, org) do
    if Enum.any?(@preview_accent_fields, &Map.has_key?(params, &1)) do
      org
      |> Map.from_struct()
      |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
      |> Map.take(@preview_accent_fields)
      |> Map.merge(params)
      |> derive_accent_variants()
      |> then(&Organization.branding_changeset(org, &1))
      |> Map.fetch!(:changes)
      |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
    else
      params
    end
  end

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
      {:ok, _l, c, h} -> "oklch(0.28 #{format_number(c / 2)} #{format_number(h)})"
      :error -> oklch
    end
  end

  defp parse_oklch(str) do
    case Regex.run(
           ~r/\Aoklch\(\s*(#{@color_number})\s+(#{@color_number})\s+(#{@color_number})\s*\)\z/,
           str
         ) do
      [_, l, c, h] -> {:ok, parse_number(l), parse_number(c), parse_number(h)}
      _ -> :error
    end
  end

  defp parse_number(s) do
    {number, ""} = Float.parse(if String.starts_with?(s, "."), do: "0" <> s, else: s)
    number
  end

  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)
  defp format_number(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 3)

  @doc """
  Returns the castable theme attributes of `draft` that differ from `saved`,
  keyed by string so they can seed a changeset or form.

  ## Examples

      iex> saved = %Marquee.Branding.Theme{background: "#000000", surface: "#111111"}
      iex> draft = %Marquee.Branding.Theme{background: "#123456", surface: "#111111"}
      iex> Marquee.Branding.Theme.changed_attrs(draft, saved)
      %{"background" => "#123456"}

      iex> theme = %Marquee.Branding.Theme{background: "#000000"}
      iex> Marquee.Branding.Theme.changed_attrs(theme, theme)
      %{}

  """
  def changed_attrs(%__MODULE__{} = draft, %__MODULE__{} = saved) do
    @castable_fields
    |> Enum.reject(fn field -> Map.get(draft, field) == Map.get(saved, field) end)
    |> Map.new(fn field -> {Atom.to_string(field), Map.get(draft, field)} end)
  end

  @doc """
  Builds CSS custom property string from the default theme preset.

  ## Examples

      iex> css = Marquee.Branding.Theme.build_default_css_vars()
      iex> css =~ "--sv-bg-primary: #0F0F0F"
      true

  """
  def build_default_css_vars do
    build_css_vars(%__MODULE__{})
  end

  @doc false
  def changeset(theme, attrs) do
    theme
    |> cast(attrs, @castable_fields)
    |> validate_required([:organization_id])
  end
end
