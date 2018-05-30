defmodule Freddy.Utils.MultikeyMapTest do
  use ExUnit.Case, async: true

  import Freddy.Utils.MultikeyMap

  test "pop/3 returns value and removes all associated keys" do
    map =
      new()
      |> put([:a1, :a2], :a_value)
      |> put([:b1, :b2], :b_value)

    assert {:a_value, new_map} = pop(map, :a1)
    assert {:a_value, ^new_map} = pop(map, :a2)

    refute has_key?(new_map, :a1)
    refute has_key?(new_map, :a2)

    assert has_key?(new_map, :b1)
    assert has_key?(new_map, :b2)
  end

  test "pop/3 leaves map intact if a key is missing" do
    map = new() |> put([:a1, :a2], :a_value)

    assert {nil, ^map} = pop(map, :b)
    assert {:default, ^map} = pop(map, :b, :default)
  end
end
