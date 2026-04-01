defmodule BobineWeb.Viewer.HeroItem do
  @moduledoc """
  Data structure representing a single hero carousel slide.

  Built from video or collection data by `Bobine.Catalog.build_hero_items/2`.
  """

  defstruct [
    :id,
    :background_image_url,
    :title,
    :brand_tag,
    :status_text,
    :metadata_text,
    :primary_cta_label,
    :primary_cta_path,
    :secondary_cta_label,
    :secondary_cta_path
  ]

  @type t :: %__MODULE__{
          id: binary(),
          background_image_url: String.t() | nil,
          title: String.t(),
          brand_tag: String.t() | nil,
          status_text: String.t() | nil,
          metadata_text: String.t() | nil,
          primary_cta_label: String.t(),
          primary_cta_path: String.t(),
          secondary_cta_label: String.t() | nil,
          secondary_cta_path: String.t() | nil
        }
end
