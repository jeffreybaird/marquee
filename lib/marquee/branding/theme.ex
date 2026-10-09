defmodule Marquee.Branding.Theme do
  use Ecto.Schema
  import Ecto.Changeset

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
      iex> String.ends_with?(css, "; --color-accent: #ABCDEF; --color-accent-hover: #ABCDEF; --font-display: 'Playfair Display', Georgia, serif")
      true

      iex> theme = %Marquee.Branding.Theme{background: "#123456"}
      iex> Marquee.Branding.Theme.build_preview_css_vars(%{theme: theme, accent_color_base: nil, display_font: nil}) ==
      ...>   Marquee.Branding.Theme.build_css_vars(theme)
      true

  """
  def build_preview_css_vars(%{theme: %__MODULE__{} = theme} = draft) do
    [
      build_css_vars(theme),
      accent_override(Map.get(draft, :accent_color_base)),
      display_font_override(Map.get(draft, :display_font))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("; ")
  end

  defp accent_override(accent) when is_binary(accent) and accent != "",
    do: "--color-accent: #{accent}; --color-accent-hover: #{accent}"

  defp accent_override(_accent), do: nil

  defp display_font_override(font) when is_binary(font) and font != "",
    do: "--font-display: '#{font}', Georgia, serif"

  defp display_font_override(_font), do: nil

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
