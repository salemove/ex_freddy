defmodule Freddy.Utils.BackoffTest do
  use ExUnit.Case, async: true

  import Freddy.Utils.Backoff

  describe "backoff specified with anonymous function" do
    test "fail/1 calls function with attempt number" do
      b0 = new(fn attempt -> attempt * 1000 end)

      assert {1000, b1} = fail(b0)
      assert {2000, _b2} = fail(b1)
    end

    test "succeed/1 resets attempts number" do
      b0 = new(fn attempt -> attempt * 1000 end)

      assert {1000, b1} = fail(b0)
      b2 = succeed(b1)
      assert {1000, _b3} = fail(b2)
    end
  end

  describe "backoff specified by {module, func, args}" do
    test "fail/1 calls function with attempt number" do
      b0 = new({__MODULE__, :backoff_func, [1000]})

      assert {1000, b1} = fail(b0)
      assert {2000, _b2} = fail(b1)
    end

    test "succeed/1 resets attempts number" do
      b0 = new({__MODULE__, :backoff_func, [1000]})

      assert {1000, b1} = fail(b0)
      b2 = succeed(b1)
      assert {1000, _b3} = fail(b2)
    end

    def backoff_func(mult, attempt) do
      mult * attempt
    end
  end

  describe "constant backoff" do
    test "fail/1 returns same number every time" do
      interval = :rand.uniform(1000)
      b0 = new(type: :constant, start: interval)

      assert {^interval, b1} = fail(b0)
      assert {^interval, b2} = fail(b1)
      assert {^interval, _b3} = fail(b2)
    end
  end

  describe "normal backoff" do
    test "fail/1 returns exponentially incrementing intervals" do
      b0 = new(type: :normal, start: 1000, max: 10000)

      assert {1000, b1} = fail(b0)
      assert {2000, b2} = fail(b1)
      assert {4000, b3} = fail(b2)
      assert {8000, b4} = fail(b3)
      assert {10000, b5} = fail(b4)
      assert {10000, _b6} = fail(b5)
    end

    test "succeed/1 resets the interval" do
      b0 = new(type: :normal, start: 1000)

      assert {1000, b1} = fail(b0)
      assert {2000, b2} = fail(b1)

      b3 = succeed(b2)

      assert {1000, b4} = fail(b3)
      assert {2000, _b5} = fail(b4)
    end
  end

  describe "backoff with jitter" do
    test "fail/1 returns exponentially incrementing intervals" do
      b0 = new(type: :jitter, start: 1000)

      assert {1000 = i1, b1} = fail(b0)
      assert {i2, b2} = fail(b1)
      assert interval_correct?(i1, i2)

      assert {i3, _b3} = fail(b2)
      assert interval_correct?(i2, i3)
    end

    test "succeed/1 resets the interval" do
      b0 = new(type: :jitter, start: 1000)

      assert {1000, b1} = fail(b0)
      assert {_i2, b2} = fail(b1)

      b3 = succeed(b2)

      assert {1000 = i4, b4} = fail(b3)
      assert {i5, _b5} = fail(b4)
      assert interval_correct?(i4, i5)
    end

    defp interval_correct?(prev_interval, next_interval) do
      next_interval >= prev_interval && next_interval <= prev_interval * 3
    end
  end
end
