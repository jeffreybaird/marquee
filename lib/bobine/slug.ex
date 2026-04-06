defmodule Bobine.Slug do
  @moduledoc """
  URL-safe slug generation from titles.
  """

  @doc """
  Generates a URL-safe slug from a title string.

      iex> Bobine.Slug.generate("My Awesome Series!")
      "my-awesome-series"

      iex> Bobine.Slug.generate("  Spaces  and---dashes  ")
      "spaces-and-dashes"

      iex> Bobine.Slug.generate("")
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
