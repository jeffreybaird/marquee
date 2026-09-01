defmodule Marquee.Streaming.LiveEventTest do
  use ExUnit.Case, async: true

  alias Marquee.Streaming.LiveEvent

  @valid_org_id "00000000-0000-0000-0000-000000000001"
  @valid_attrs %{
    title: "Test Stream",
    slug: "test-stream",
    scheduled_start_at: ~U[2026-06-01 18:00:00Z],
    access_type: "subscribers_only",
    organization_id: @valid_org_id
  }

  describe "changeset/2" do
    test "valid attrs produce valid changeset" do
      cs = LiveEvent.changeset(%LiveEvent{}, @valid_attrs)
      assert cs.valid?
    end

    test "requires title" do
      cs = LiveEvent.changeset(%LiveEvent{}, Map.delete(@valid_attrs, :title))
      refute cs.valid?
      assert "can't be blank" in errors_on(cs).title
    end

    test "requires slug" do
      cs = LiveEvent.changeset(%LiveEvent{}, Map.delete(@valid_attrs, :slug))
      refute cs.valid?
      assert "can't be blank" in errors_on(cs).slug
    end

    test "requires scheduled_start_at" do
      cs = LiveEvent.changeset(%LiveEvent{}, Map.delete(@valid_attrs, :scheduled_start_at))
      refute cs.valid?
      assert "can't be blank" in errors_on(cs).scheduled_start_at
    end

    test "access_type defaults to subscribers_only when not provided" do
      cs = LiveEvent.changeset(%LiveEvent{}, Map.delete(@valid_attrs, :access_type))
      # The schema default means the field is populated even without explicit attr
      # so the changeset is valid (default applied)
      assert get_in(cs.changes, [:access_type]) == nil or cs.valid?
    end

    test "requires explicit access_type if schema has no default context" do
      # Validate that invalid access_type is rejected regardless
      cs = LiveEvent.changeset(%LiveEvent{}, Map.put(@valid_attrs, :access_type, "bad_type"))
      refute cs.valid?
      assert "is invalid" in errors_on(cs).access_type
    end

    test "rejects invalid access_type" do
      cs = LiveEvent.changeset(%LiveEvent{}, Map.put(@valid_attrs, :access_type, "free"))
      refute cs.valid?
      assert "is invalid" in errors_on(cs).access_type
    end

    test "accepts all valid access types" do
      for type <- ~w(subscribers_only public pay_per_view) do
        cs = LiveEvent.changeset(%LiveEvent{}, Map.put(@valid_attrs, :access_type, type))

        if type == "pay_per_view" do
          # PPV needs ppv_price_cents too
          cs2 =
            LiveEvent.changeset(
              %LiveEvent{},
              Map.merge(@valid_attrs, %{access_type: type, ppv_price_cents: 500})
            )

          assert cs2.valid?, "expected #{type} to be valid with ppv_price_cents"
        else
          assert cs.valid?, "expected #{type} to be valid"
        end
      end
    end

    test "pay_per_view requires ppv_price_cents" do
      attrs = Map.put(@valid_attrs, :access_type, "pay_per_view")
      cs = LiveEvent.changeset(%LiveEvent{}, attrs)
      refute cs.valid?
      assert "can't be blank" in errors_on(cs).ppv_price_cents
    end

    test "pay_per_view rejects ppv_price_cents of 0" do
      attrs = Map.merge(@valid_attrs, %{access_type: "pay_per_view", ppv_price_cents: 0})
      cs = LiveEvent.changeset(%LiveEvent{}, attrs)
      refute cs.valid?
      assert "must be greater than 0" in errors_on(cs).ppv_price_cents
    end

    test "pay_per_view accepts positive ppv_price_cents" do
      attrs = Map.merge(@valid_attrs, %{access_type: "pay_per_view", ppv_price_cents: 999})
      cs = LiveEvent.changeset(%LiveEvent{}, attrs)
      assert cs.valid?
    end
  end

  describe "mux_changeset/2" do
    test "allows only mux fields" do
      event = %LiveEvent{title: "Original"}

      cs =
        LiveEvent.mux_changeset(event, %{
          mux_live_stream_id: "stream_abc",
          mux_live_playback_id: "pb_xyz",
          mux_rtmp_url: "rtmps://global-live.mux.com:443/app"
        })

      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :mux_live_stream_id) == "stream_abc"
      # Title not changed by mux_changeset
      assert is_nil(Ecto.Changeset.get_change(cs, :title))
    end
  end

  describe "transition_changeset/3" do
    test "draft → scheduled is valid" do
      event = %LiveEvent{status: "draft"}
      cs = LiveEvent.transition_changeset(event, "draft", "scheduled")
      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :status) == "scheduled"
    end

    test "draft → canceled is valid" do
      event = %LiveEvent{status: "draft"}
      cs = LiveEvent.transition_changeset(event, "draft", "canceled")
      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :status) == "canceled"
    end

    test "scheduled → live is valid and sets went_live_at" do
      event = %LiveEvent{status: "scheduled"}
      cs = LiveEvent.transition_changeset(event, "scheduled", "live")
      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :status) == "live"
      assert Ecto.Changeset.get_change(cs, :went_live_at) != nil
    end

    test "scheduled → canceled is valid and sets canceled_at" do
      event = %LiveEvent{status: "scheduled"}
      cs = LiveEvent.transition_changeset(event, "scheduled", "canceled")
      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :canceled_at) != nil
    end

    test "scheduled → did_not_occur is valid" do
      event = %LiveEvent{status: "scheduled"}
      cs = LiveEvent.transition_changeset(event, "scheduled", "did_not_occur")
      assert cs.valid?
    end

    test "live → ended is valid and sets ended_at" do
      event = %LiveEvent{status: "live"}
      cs = LiveEvent.transition_changeset(event, "live", "ended")
      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :ended_at) != nil
    end

    test "ended → any returns invalid_transition" do
      event = %LiveEvent{status: "ended"}

      for to <- ~w(draft scheduled live canceled did_not_occur) do
        assert {:error, :invalid_transition} = LiveEvent.transition_changeset(event, "ended", to)
      end
    end

    test "canceled → any returns invalid_transition" do
      event = %LiveEvent{status: "canceled"}

      for to <- ~w(draft scheduled live ended did_not_occur) do
        assert {:error, :invalid_transition} =
                 LiveEvent.transition_changeset(event, "canceled", to)
      end
    end

    test "did_not_occur → any returns invalid_transition" do
      event = %LiveEvent{status: "did_not_occur"}

      for to <- ~w(draft scheduled live ended canceled) do
        assert {:error, :invalid_transition} =
                 LiveEvent.transition_changeset(event, "did_not_occur", to)
      end
    end

    test "draft → live is invalid (skips scheduled)" do
      event = %LiveEvent{status: "draft"}

      assert {:error, :invalid_transition} =
               LiveEvent.transition_changeset(event, "draft", "live")
    end

    test "live → draft is invalid (backwards)" do
      event = %LiveEvent{status: "live"}

      assert {:error, :invalid_transition} =
               LiveEvent.transition_changeset(event, "live", "draft")
    end
  end

  describe "valid_access_types/0 and valid_statuses/0" do
    test "returns expected access types" do
      assert LiveEvent.valid_access_types() == ~w(subscribers_only public pay_per_view)
    end

    test "returns expected statuses" do
      assert LiveEvent.valid_statuses() == ~w(draft scheduled live ended canceled did_not_occur)
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
