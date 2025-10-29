defmodule SocialPomodoroWeb.SessionTimerComponents do
  @moduledoc """
  Components for displaying session timers and countdowns.
  """
  use SocialPomodoroWeb, :html

  attr :id, :string, required: true
  attr :seconds_remaining, :integer, required: true
  attr :label, :string, required: true

  def timer_display(assigns) do
    assigns = assign(assigns, :countdown_segments, countdown_segments(assigns.seconds_remaining))

    ~H"""
    <div class="flex flex-col items-center gap-4">
      <div
        id={@id}
        class="flex justify-center gap-6"
        phx-hook="Timer"
        data-seconds-remaining={@seconds_remaining}
      >
        <%= for {unit, value} <- @countdown_segments do %>
          <div class="flex flex-col items-center gap-1" data-countdown-segment={Atom.to_string(unit)}>
            <span class="countdown font-mono text-5xl" data-timer-display>
              <span
                data-countdown-value
                style={"--value:#{value};"}
                aria-live="polite"
                aria-label={Integer.to_string(value)}
              >
                {value}
              </span>
            </span>
            <span class="text-xs font-semibold uppercase tracking-[0.35em] text-base-content/60">
              {countdown_label(unit)}
            </span>
          </div>
        <% end %>
      </div>
      <p class="text-sm uppercase tracking-[0.35em] text-base-content/50 text-center">{@label}</p>
    </div>
    """
  end

  defp countdown_segments(seconds) when is_integer(seconds) do
    safe_seconds = max(seconds, 0)
    minutes = div(safe_seconds, 60)
    secs = rem(safe_seconds, 60)

    [
      {:minutes, minutes},
      {:seconds, secs}
    ]
  end

  defp countdown_segments(_seconds) do
    [
      {:minutes, 0},
      {:seconds, 0}
    ]
  end

  defp countdown_label(:minutes), do: "Min"
  defp countdown_label(:seconds), do: "Sec"
end
