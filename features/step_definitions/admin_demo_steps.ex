defmodule MarqueeFeatures.Steps.AdminDemo do
  @moduledoc "Acceptance contract for independent private operator workspaces."
  use Cucumberex.DSL
  import ExUnit.Assertions
  import Ecto.Query
  alias Marquee.{AdminDemo, Content, Repo}
  alias Marquee.Content.Video

  when_("two Wanderlust visitors edit and reset separate private workspaces", fn world ->
    original = Application.fetch_env(:marquee, :admin_demo)

    path =
      Path.join(
        System.tmp_dir!(),
        "admin-demo-feature-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, Jason.encode!(Marquee.AdminDemoFixtures.catalog_manifest()))

    Application.put_env(:marquee, :admin_demo,
      enabled: true,
      host: "feature-demo.example.test",
      catalog_path: path
    )

    try do
      {:ok, _} = AdminDemo.configure_host("feature-demo.example.test")
      {:ok, first} = AdminDemo.start_session()
      {:ok, second} = AdminDemo.start_session()
      {:ok, %{scope: scope}} = AdminDemo.get_session(second.token)
      video = hd(Content.list_videos(second.organization).results)
      assert {:ok, _} = Content.update_video(scope, video, %{title: "Second visitor keeps this"})
      assert {:ok, replacement} = AdminDemo.reset_session(first.token)
      assert {:error, :revoked} = AdminDemo.get_session(first.token)
      assert {:ok, _} = AdminDemo.get_session(second.token)

      Map.merge(world, %{
        admin_demo_replacement: replacement.organization.id,
        admin_demo_second_video: video.id
      })
    after
      File.rm(path)

      case original do
        {:ok, value} -> Application.put_env(:marquee, :admin_demo, value)
        :error -> Application.delete_env(:marquee, :admin_demo)
      end
    end
  end)

  then_(
    "the reset visitor has a fresh catalog and the other visitor keeps their edits",
    fn world ->
      assert Repo.get!(Video, world.admin_demo_second_video).title == "Second visitor keeps this"

      titles =
        Repo.all(
          from v in Video,
            where: v.organization_id == ^world.admin_demo_replacement,
            select: v.title
        )

      assert "Travel fixture 1" in titles
      refute "Second visitor keeps this" in titles
      world
    end
  )
end
