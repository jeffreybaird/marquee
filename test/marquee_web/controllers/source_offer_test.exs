defmodule MarqueeWeb.SourceOfferTest do
  use MarqueeWeb.ConnCase, async: true

  test "anonymous visitors can find source and licensing without signing in", %{conn: conn} do
    conn
    |> get(~p"/users/log-in")
    |> html_response(200)
    |> assert_source_offer()
  end

  test "public tenant pages expose the same source and license offer", %{conn: conn} do
    org = insert(:organization)

    conn
    |> Map.put(:host, "#{org.slug}.localhost")
    |> get(~p"/")
    |> html_response(200)
    |> assert_source_offer()
  end

  test "operators can find the offer on their dashboard" do
    membership = insert(:membership, role: :owner)

    membership
    |> conn_for()
    |> get(~p"/admin")
    |> html_response(200)
    |> assert_source_offer()
  end

  test "signed-in viewers can find the offer on their account page" do
    :viewer
    |> insert()
    |> conn_for_viewer()
    |> get(~p"/account")
    |> html_response(200)
    |> assert_source_offer()
  end

  test "super admins can find the offer on the platform dashboard" do
    :user
    |> insert(is_super_admin: true)
    |> conn_for_super_admin()
    |> get(~p"/super")
    |> html_response(200)
    |> assert_source_offer()
  end

  defp assert_source_offer(html) do
    document = Floki.parse_document!(html)

    for {selector, href, label} <- [
          {"source-code", "https://github.com/jeffreybaird/marquee", "Source code"},
          {"license", "https://github.com/jeffreybaird/marquee/blob/main/LICENSE", "AGPL-3.0"}
        ] do
      links = Floki.find(document, "a[data-test='#{selector}']")
      assert length(links) == 1
      assert Floki.attribute(links, "href") == [href]
      assert Floki.text(links) =~ label
      assert Floki.attribute(links, "hidden") == []
      refute Floki.attribute(links, "aria-hidden") == ["true"]
      refute Floki.attribute(links, "tabindex") == ["-1"]
    end
  end
end
