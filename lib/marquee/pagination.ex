defmodule Marquee.Pagination do
  @moduledoc """
  Pagination helper for list queries.

  Accepts a query and options, returns a map with results and pagination metadata.
  """

  import Ecto.Query

  @max_per_page 100
  @default_per_page 25

  @doc """
  Paginates a query and returns results with metadata.

  Options:
  - `:page` — page number (default 1, minimum 1)
  - `:per_page` — results per page (default 25, maximum 100)

      iex> Marquee.Pagination.normalize_opts(page: 0, per_page: 200)
      {1, 100}

      iex> Marquee.Pagination.normalize_opts([])
      {1, 25}
  """
  def paginate(query, opts) do
    {page, per_page} = normalize_opts(opts)

    results =
      query
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> Marquee.Repo.all()

    total = Marquee.Repo.aggregate(query, :count)

    %{
      results: results,
      page: page,
      per_page: per_page,
      total: total,
      total_pages: max(ceil(total / per_page), 1)
    }
  end

  @doc """
  Normalizes pagination options to valid page and per_page values.

      iex> Marquee.Pagination.normalize_opts(page: 3, per_page: 50)
      {3, 50}

      iex> Marquee.Pagination.normalize_opts(page: -1, per_page: 999)
      {1, 100}
  """
  def normalize_opts(opts) do
    page = max(Keyword.get(opts, :page, 1), 1)
    per_page = opts |> Keyword.get(:per_page, @default_per_page) |> min(@max_per_page) |> max(1)
    {page, per_page}
  end
end
