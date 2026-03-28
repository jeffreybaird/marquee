defmodule BobineWeb.PageController do
  use BobineWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
