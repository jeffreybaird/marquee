defmodule Bobine.BrandingFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Bobine.Branding` context.
  """

  @doc """
  Generate a theme.
  """
  def theme_fixture(attrs \\ %{}) do
    {:ok, theme} =
      attrs
      |> Enum.into(%{
        accent: "some accent",
        background: "some background",
        border_radius: "some border_radius",
        brand_primary: "some brand_primary",
        brand_secondary: "some brand_secondary",
        card_border_radius: "some card_border_radius",
        favicon_url: "some favicon_url",
        font_body: "some font_body",
        font_heading: "some font_heading",
        logo_url: "some logo_url",
        surface: "some surface",
        text_primary: "some text_primary",
        text_secondary: "some text_secondary"
      })
      |> Bobine.Branding.create_theme()

    theme
  end
end
