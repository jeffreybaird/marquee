defmodule Bobine.Branding.Theme do
  use Ecto.Schema
  import Ecto.Changeset

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
    overlay_color: "rgba(0, 0, 0, 0.7)"
  }

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

    belongs_to :organization, Bobine.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the default viewer theme values.

  ## Examples

      iex> Bobine.Branding.Theme.default_viewer_theme()
      %{background: "#0F0F0F", surface: "#1A1A1A", elevated: "#252525", text_primary: "#FFFFFF", text_secondary: "#A0A0A0", text_on_accent: "#FFFFFF", brand_primary: "#E50914", brand_primary_hover: "#F6121D", font_heading: "Inter", font_body: "Inter", border_color: "rgba(255, 255, 255, 0.08)", divider_color: "rgba(255, 255, 255, 0.05)", nav_background: "rgba(0, 0, 0, 0.85)", card_background: "#1A1A1A", overlay_color: "rgba(0, 0, 0, 0.7)"}

  """
  def default_viewer_theme, do: @default_viewer_theme

  @doc """
  Builds a CSS custom property string from theme values, applying defaults for missing fields.

  ## Examples

      iex> theme = %Bobine.Branding.Theme{background: "#000000", brand_primary: "#FF0000"}
      iex> css = Bobine.Branding.Theme.build_css_vars(theme)
      iex> css =~ "--sv-bg-primary: #000000"
      true
      iex> css =~ "--sv-accent: #FF0000"
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
      {"--sv-accent", theme.brand_primary || defaults.brand_primary},
      {"--sv-accent-hover", theme.brand_primary_hover || defaults.brand_primary_hover},
      {"--sv-font-heading",
       "#{theme.font_heading || defaults.font_heading}, system-ui, sans-serif"},
      {"--sv-font-body", "#{theme.font_body || defaults.font_body}, system-ui, sans-serif"},
      {"--sv-border", theme.border_color || defaults.border_color},
      {"--sv-divider", theme.divider_color || defaults.divider_color},
      {"--sv-nav-bg", theme.nav_background || defaults.nav_background},
      {"--sv-card-bg", theme.card_background || defaults.card_background},
      {"--sv-overlay", theme.overlay_color || defaults.overlay_color},
      {"--sv-radius-sm", "4px"},
      {"--sv-radius-md", "8px"},
      {"--sv-radius-lg", "12px"}
    ]
    |> Enum.map_join("; ", fn {var, val} -> "#{var}: #{val}" end)
  end

  @doc """
  Builds CSS custom property string from the default theme preset.

  ## Examples

      iex> css = Bobine.Branding.Theme.build_default_css_vars()
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
