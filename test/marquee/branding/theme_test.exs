defmodule Marquee.Branding.ThemeTest do
  use Marquee.DataCase, async: true

  alias Marquee.Branding.Theme

  describe "presets/0" do
    test "exposes exactly the midnight and daybreak starter themes" do
      assert Map.keys(Theme.presets()) |> Enum.sort() == ["daybreak", "midnight"]
    end

    test "every preset has a label, description, and the colors required by the changeset" do
      for {key, preset} <- Theme.presets() do
        assert is_binary(preset.label), "preset #{key} missing :label"
        assert is_binary(preset.description), "preset #{key} missing :description"

        for color <- [
              :background,
              :surface,
              :text_primary,
              :text_secondary,
              :brand_primary,
              :brand_primary_hover,
              :form_text,
              :form_placeholder
            ] do
          assert is_binary(Map.fetch!(preset, color)),
                 "preset #{key} missing color #{color}"
        end
      end
    end
  end

  describe "preset_attrs/1" do
    test "strips presentation metadata so the result is changeset-ready" do
      attrs = Theme.preset_attrs("daybreak")

      refute Map.has_key?(attrs, :label)
      refute Map.has_key?(attrs, :description)
      assert attrs.background == "#FFFFFF"
    end

    test "produces a valid theme changeset when paired with an organization_id" do
      org = insert(:organization)

      for key <- Theme.preset_keys() do
        attrs = Theme.preset_attrs(key) |> Map.put(:organization_id, org.id)
        changeset = Theme.changeset(%Theme{}, attrs)
        assert changeset.valid?, "preset #{key} did not produce a valid changeset"
      end
    end

    test "returns nil for an unknown preset key" do
      assert Theme.preset_attrs("nope") == nil
    end
  end

  describe "default_viewer_theme/0" do
    test "returns a map with all required default values" do
      defaults = Theme.default_viewer_theme()

      assert defaults.background == "#0F0F0F"
      assert defaults.surface == "#1A1A1A"
      assert defaults.elevated == "#252525"
      assert defaults.text_primary == "#FFFFFF"
      assert defaults.text_secondary == "#A0A0A0"
      assert defaults.text_on_accent == "#FFFFFF"
      assert defaults.brand_primary == "#E50914"
      assert defaults.brand_primary_hover == "#F6121D"
      assert defaults.font_heading == "Inter"
      assert defaults.font_body == "Inter"
      assert defaults.form_text == "#FFFFFF"
      assert defaults.form_placeholder == "#8A8A8A"
    end
  end

  describe "build_css_vars/1" do
    test "builds CSS variable string from a theme struct" do
      theme = %Theme{
        background: "#000000",
        brand_primary: "#FF0000",
        text_primary: "#FFFFFF"
      }

      css = Theme.build_css_vars(theme)

      assert css =~ "--sv-bg-primary: #000000"
      assert css =~ "--sv-accent: var(--color-accent, #FF0000)"
      assert css =~ "--sv-text-primary: #FFFFFF"
    end

    test "applies defaults for nil fields" do
      theme = %Theme{}
      css = Theme.build_css_vars(theme)

      assert css =~ "--sv-bg-primary: #0F0F0F"
      assert css =~ "--sv-accent: var(--color-accent, #E50914)"
      assert css =~ "--sv-font-heading: Inter, system-ui, sans-serif"
    end

    test "includes all required CSS custom properties" do
      css = Theme.build_default_css_vars()

      required_vars = [
        "--sv-bg-primary",
        "--sv-bg-secondary",
        "--sv-bg-elevated",
        "--sv-text-primary",
        "--sv-text-secondary",
        "--sv-text-on-accent",
        "--sv-accent",
        "--sv-accent-hover",
        "--sv-font-heading",
        "--sv-font-body",
        "--sv-border",
        "--sv-divider",
        "--sv-nav-bg",
        "--sv-card-bg",
        "--sv-overlay",
        "--sv-form-text",
        "--sv-form-placeholder",
        "--sv-radius-sm",
        "--sv-radius-md",
        "--sv-radius-lg"
      ]

      for var <- required_vars do
        assert css =~ var, "Missing CSS variable: #{var}"
      end
    end

    test "custom theme values override defaults" do
      theme = %Theme{
        background: "#112233",
        surface: "#445566",
        brand_primary: "#00FF00"
      }

      css = Theme.build_css_vars(theme)

      assert css =~ "--sv-bg-primary: #112233"
      assert css =~ "--sv-bg-secondary: #445566"
      assert css =~ "--sv-accent: var(--color-accent, #00FF00)"
    end
  end

  describe "build_preview_css_vars/1" do
    test "appends accent and display font overrides after the theme variables" do
      theme = %Theme{background: "#123456", surface: "#1A1A1A"}

      css =
        Theme.build_preview_css_vars(%{
          theme: theme,
          accent_color_base: "#ABCDEF",
          display_font: "Playfair Display"
        })

      assert css ==
               Theme.build_css_vars(theme) <>
                 "; --color-accent: #ABCDEF; --color-accent-hover: #ABCDEF" <>
                 "; --color-accent-active: #ABCDEF; --color-accent-subtle: #ABCDEF" <>
                 "; --font-display: 'Playfair Display', Georgia, serif"
    end

    test "adds nothing for nil accent and font" do
      theme = %Theme{background: "#123456"}

      assert Theme.build_preview_css_vars(%{
               theme: theme,
               accent_color_base: nil,
               display_font: nil
             }) == Theme.build_css_vars(theme)
    end

    test "adds nothing for empty-string accent and font" do
      theme = %Theme{background: "#123456"}

      assert Theme.build_preview_css_vars(%{
               theme: theme,
               accent_color_base: "",
               display_font: ""
             }) == Theme.build_css_vars(theme)
    end

    test "emits only the accent override when the font is absent" do
      theme = %Theme{}

      css =
        Theme.build_preview_css_vars(%{
          theme: theme,
          accent_color_base: "#ABCDEF",
          display_font: nil
        })

      assert css ==
               Theme.build_css_vars(theme) <>
                 "; --color-accent: #ABCDEF; --color-accent-hover: #ABCDEF" <>
                 "; --color-accent-active: #ABCDEF; --color-accent-subtle: #ABCDEF"

      refute css =~ "--font-display"
    end

    test "emits only the font override when the accent is absent" do
      theme = %Theme{}

      css =
        Theme.build_preview_css_vars(%{
          theme: theme,
          accent_color_base: nil,
          display_font: "Playfair Display"
        })

      assert css ==
               Theme.build_css_vars(theme) <>
                 "; --font-display: 'Playfair Display', Georgia, serif"

      refute css =~ "--color-accent:"
    end
  end

  test "preview honors explicit accent variants" do
    css =
      Theme.build_preview_css_vars(%{
        theme: %Theme{},
        accent_color_base: "#112233",
        accent_color_hover: "#223344",
        accent_color_active: "#334455",
        accent_color_subtle: "#445566"
      })

    assert css =~ "--color-accent: #112233"
    assert css =~ "--color-accent-hover: #223344"
    assert css =~ "--color-accent-active: #334455"
    assert css =~ "--color-accent-subtle: #445566"
  end

  test "preview rejects unapproved fonts and color declarations" do
    for font <- ["Lora", "Foo&family=Injected", "Foo'; --injected: yes; /*"] do
      css =
        Theme.build_preview_css_vars(%{
          theme: %Theme{},
          display_font: font,
          accent_color_base: "red; --injected: yes"
        })

      refute css =~ "--font-display"
      refute css =~ "--color-accent:"
      refute css =~ "--injected"
    end
  end

  describe "changeset/2" do
    test "allows all viewer theme fields" do
      org = insert(:organization)

      attrs = %{
        organization_id: org.id,
        brand_primary: "#FF0000",
        elevated: "#333333",
        text_on_accent: "#FFFFFF",
        brand_primary_hover: "#FF3333",
        border_color: "rgba(255,255,255,0.1)",
        divider_color: "rgba(255,255,255,0.05)",
        nav_background: "rgba(0,0,0,0.9)",
        card_background: "#222222",
        overlay_color: "rgba(0,0,0,0.7)"
      }

      changeset = Theme.changeset(%Theme{}, attrs)
      assert changeset.valid?
    end

    test "allows form_text and form_placeholder" do
      org = insert(:organization)

      attrs = %{
        organization_id: org.id,
        form_text: "#EEEEEE",
        form_placeholder: "#777777"
      }

      changeset = Theme.changeset(%Theme{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :form_text) == "#EEEEEE"
      assert Ecto.Changeset.get_change(changeset, :form_placeholder) == "#777777"
    end

    test "build_css_vars uses form_text and form_placeholder from the theme" do
      theme = %Theme{form_text: "#CCCCCC", form_placeholder: "#555555"}
      css = Theme.build_css_vars(theme)

      assert css =~ "--sv-form-text: #CCCCCC"
      assert css =~ "--sv-form-placeholder: #555555"
    end

    test "build_css_vars falls back to defaults for form colors when not set" do
      css = Theme.build_default_css_vars()

      assert css =~ "--sv-form-text: #FFFFFF"
      assert css =~ "--sv-form-placeholder: #8A8A8A"
    end

    test "allows login_background_image_url" do
      org = insert(:organization)

      attrs = %{
        organization_id: org.id,
        login_background_image_url: "https://cdn.example.com/login-bg.jpg"
      }

      changeset = Theme.changeset(%Theme{}, attrs)
      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :login_background_image_url) ==
               "https://cdn.example.com/login-bg.jpg"
    end
  end
end
