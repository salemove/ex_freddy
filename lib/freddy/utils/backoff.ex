defmodule Freddy.Utils.Backoff do
  @moduledoc false

  @default_config [
    type: :jitter,
    start: 1000,
    max: 10000
  ]

  @opaque t ::
            {:mfa, {module, atom, [any]}, attempt}
            | {:func, function, attempt}
            | {:constant, non_neg_integer}
            | {:backoff, :backoff.backoff()}

  @type spec :: callback | config
  @type callback :: {module, atom, [any]} | (attempt -> interval)
  @type config :: [
          type: :constant | :normal | :jitter,
          start: interval,
          max: non_neg_integer | :infinity
        ]
  @type attempt :: pos_integer
  @type interval :: non_neg_integer

  @doc """
  Creates a new backoff functional structure.
  """
  @spec new(spec) :: t
  def new(spec)

  def new({mod, func, args}) do
    {:mfa, {mod, func, args}, 1}
  end

  def new(func) when is_function(func, 1) do
    {:func, func, 1}
  end

  def new(config) when is_list(config) do
    config = Keyword.merge(@default_config, config)
    type = Keyword.fetch!(config, :type)
    start = Keyword.fetch!(config, :start)
    max = Keyword.fetch!(config, :max)

    case type do
      :constant ->
        {:constant, start}

      type ->
        backoff = :backoff.init(start, max) |> :backoff.type(type)
        {:backoff, backoff}
    end
  end

  @doc """
  Mark an attempt as failed, which increments the backoff value for the next round.

  Returns current backoff interval and new backoff state.
  """
  @spec fail(t) :: {interval, t}
  def fail(backoff)

  def fail({:mfa, {mod, func, args} = callback, attempt}) do
    interval = apply(mod, func, args ++ [attempt])
    {interval, {:mfa, callback, attempt + 1}}
  end

  def fail({:func, func, attempt}) do
    interval = func.(attempt)
    {interval, {:func, func, attempt + 1}}
  end

  def fail({:constant, interval} = backoff) do
    {interval, backoff}
  end

  def fail({:backoff, backoff}) do
    interval = :backoff.get(backoff)
    {_new_interval, new_backoff} = :backoff.fail(backoff)
    {interval, {:backoff, new_backoff}}
  end

  @doc """
  Mark an attempt as successful, which resets the backoff value for the next round.
  """
  @spec succeed(t) :: t
  def succeed(backoff)

  def succeed({type, callback, _attempt}) when type in [:mfa, :func] do
    {type, callback, 1}
  end

  def succeed({:constant, _interval} = backoff) do
    backoff
  end

  def succeed({:backoff, backoff}) do
    {_start, new_backoff} = :backoff.succeed(backoff)
    {:backoff, new_backoff}
  end
end
