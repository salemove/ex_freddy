defmodule Freddy.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Freddy.ConnHelper
      import Freddy.HistoryHelper
    end
  end
end
