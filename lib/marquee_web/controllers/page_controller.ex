defmodule MarqueeWeb.PageController do
  use MarqueeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
