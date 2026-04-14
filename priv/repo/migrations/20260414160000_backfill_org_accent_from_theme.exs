defmodule Bobine.Repo.Migrations.BackfillOrgAccentFromTheme do
  use Ecto.Migration

  @moduledoc """
  Wave B migration: the accent color is now owned by Organization
  (as oklch variants). Back-fill Organization.accent_color_base from
  Theme.brand_primary for any org that has a theme color set but no
  tenant accent yet, so no tenant loses their existing visual identity.

  We keep the Theme.brand_primary column in place for now — this is a
  data-only migration, not a schema drop. Values stop being edited
  through the Branding UI but remain available for rollback.

  Hex values stay as hex (e.g. "#E50914"); they render fine in CSS.
  Browser-level CSS aliases map --sv-accent onto --color-accent so the
  viewer CSS keeps resolving in either mode.
  """

  def up do
    execute("""
    UPDATE organizations o
    SET accent_color_base = t.brand_primary
    FROM themes t
    WHERE t.organization_id = o.id
      AND t.brand_primary IS NOT NULL
      AND t.brand_primary <> ''
      AND (o.accent_color_base IS NULL OR o.accent_color_base = '');
    """)

    execute("""
    UPDATE organizations o
    SET accent_color_hover = t.brand_primary_hover
    FROM themes t
    WHERE t.organization_id = o.id
      AND t.brand_primary_hover IS NOT NULL
      AND t.brand_primary_hover <> ''
      AND (o.accent_color_hover IS NULL OR o.accent_color_hover = '');
    """)
  end

  def down do
    # Backfill is one-way. Rolling this migration back does not restore
    # the prior empty-string state because we don't track which rows were
    # filled by this migration vs manually. No-op.
    :ok
  end
end
