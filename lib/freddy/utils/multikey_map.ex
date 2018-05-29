defmodule Freddy.Utils.MultikeyMap do
  @moduledoc false
  # a map where values can be associated with multiple keys

  @opaque t :: map

  def new do
    %{}
  end

  def put(map, [key | rest] = _keys, value) do
    map
    |> Map.put(key, {:value, value, rest})
    |> associate(rest, key)
  end

  def pop(map, key, default \\ nil) do
    case map do
      %{^key => {:assoc, target}} ->
        pop(map, target, default)

      %{^key => {:value, value, associations}} ->
        {value, Map.drop(map, [key | associations])}

      _ ->
        {default, map}
    end
  end

  def has_key?(map, key) do
    Map.has_key?(map, key)
  end

  defp associate(map, keys, target) do
    Enum.reduce(keys, map, &Map.put(&2, &1, {:assoc, target}))
  end
end
