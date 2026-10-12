defmodule Marquee.Content.AspectRatioTest do
  use ExUnit.Case, async: true

  alias Marquee.Content.AspectRatio

  describe "parse/1" do
    test "parses Mux width:height ratios into integer tuples" do
      assert AspectRatio.parse("9:16") == {:ok, {9, 16}}
      assert AspectRatio.parse("16:9") == {:ok, {16, 9}}
      assert AspectRatio.parse("1:1") == {:ok, {1, 1}}
      assert AspectRatio.parse("4:5") == {:ok, {4, 5}}
    end

    test "rejects malformed, zero, negative and missing ratios" do
      for value <- [nil, "", "abc", "9", "9:", ":16", "9/16", "9:16:1", "0:16", "9:0", "-9:16"] do
        assert AspectRatio.parse(value) == :error, "expected #{inspect(value)} to be rejected"
      end
    end

    test "rejects non-string values" do
      assert AspectRatio.parse(916) == :error
      assert AspectRatio.parse({9, 16}) == :error
    end
  end

  describe "normalize/1" do
    test "returns the canonical ratio string for valid ratios" do
      assert AspectRatio.normalize("9:16") == "9:16"
      assert AspectRatio.normalize("16:9") == "16:9"
      assert AspectRatio.normalize("1:1") == "1:1"
    end

    test "returns nil for garbage or missing ratios" do
      assert AspectRatio.normalize(nil) == nil
      assert AspectRatio.normalize("") == nil
      assert AspectRatio.normalize("garbage") == nil
      assert AspectRatio.normalize("0:16") == nil
    end
  end

  describe "orientation/1" do
    test "classifies taller-than-wide ratios as portrait" do
      assert AspectRatio.orientation("9:16") == :portrait
      assert AspectRatio.orientation("4:5") == :portrait
    end

    test "classifies wider-than-tall ratios as landscape" do
      assert AspectRatio.orientation("16:9") == :landscape
      assert AspectRatio.orientation("4:3") == :landscape
    end

    test "classifies equal sides as square" do
      assert AspectRatio.orientation("1:1") == :square
    end

    test "returns :unknown for missing or malformed ratios" do
      assert AspectRatio.orientation(nil) == :unknown
      assert AspectRatio.orientation("bad") == :unknown
    end
  end

  describe "css_ratio/1" do
    test "renders a CSS aspect-ratio value for a known ratio" do
      assert AspectRatio.css_ratio("9:16") == "9 / 16"
      assert AspectRatio.css_ratio("16:9") == "16 / 9"
      assert AspectRatio.css_ratio("1:1") == "1 / 1"
    end

    test "falls back to the 9 / 16 stage ratio when unknown" do
      assert AspectRatio.css_ratio(nil) == "9 / 16"
      assert AspectRatio.css_ratio("bad") == "9 / 16"
    end
  end
end
