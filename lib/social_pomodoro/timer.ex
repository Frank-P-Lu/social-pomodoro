defmodule SocialPomodoro.Timer do
  @moduledoc """
  A simple countdown timer.
  """

  defstruct [:duration, :remaining, :state]

  @type timer_state :: :running | :stopped | :done

  @type t :: %__MODULE__{
          duration: integer(),
          remaining: integer(),
          state: timer_state()
        }

  @doc """
  Creates a new timer with the given duration in seconds.
  """
  @spec new(integer()) :: t()
  def new(duration) do
    %__MODULE__{
      duration: duration,
      remaining: duration,
      state: :stopped
    }
  end

  @doc """
  Ticks the timer down by one second if it's running.
  Returns {:ok, timer} if there's still time remaining.
  Returns {:done, timer} if the timer has completed.
  """
  @spec tick(t()) :: {:ok, t()} | {:done, t()}
  def tick(%__MODULE__{remaining: remaining, state: :running} = timer) when remaining > 0 do
    {:ok, %{timer | remaining: remaining - 1}}
  end

  def tick(%__MODULE__{remaining: 0, state: :running} = timer) do
    {:done, %{timer | state: :done}}
  end

  def tick(timer), do: {:ok, timer}

  @doc """
  Starts the timer.
  """
  @spec start(t()) :: t()
  def start(%__MODULE__{} = timer), do: %{timer | state: :running}

  @doc """
  Stops the timer and resets remaining time to duration.
  """
  @spec stop(t()) :: t()
  def stop(%__MODULE__{duration: duration} = timer) do
    %{timer | state: :stopped, remaining: duration}
  end

  @doc """
  Returns true if the timer is running.
  """
  @spec running?(t()) :: boolean()
  def running?(%__MODULE__{state: :running}), do: true
  def running?(_), do: false

  @doc """
  Returns true if the timer is completed (state is :done).
  """
  @spec completed?(t()) :: boolean()
  def completed?(%__MODULE__{state: :done}), do: true
  def completed?(_), do: false
end
