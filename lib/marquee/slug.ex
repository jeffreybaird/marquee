defmodule Marquee.Slug do
  @moduledoc """
  URL-safe slug generation from titles.
  """

  @doc """
  Generates a URL-safe slug from a title string.

      iex> Marquee.Slug.generate("My Awesome Series!")
      "my-awesome-series"

      iex> Marquee.Slug.generate("  Spaces  and---dashes  ")
      "spaces-and-dashes"

      iex> Marquee.Slug.generate("")
      ""
  """
  def generate(title) when is_binary(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/[\s-]+/, "-")
    |> String.trim("-")
  end
end
