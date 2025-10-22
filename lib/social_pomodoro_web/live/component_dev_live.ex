defmodule SocialPomodoroWeb.ComponentDevLive do
  use SocialPomodoroWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       comment: %{
         author: "Casey",
         body:
           "This is a placeholder comment. Change styles, swap text, and experiment with the layout right here.",
         timestamp: "2 minutes ago"
       },
       sample_participant: %{
         user_id: "thumbs_demo_456",
         username: "Taylor",
         status_emoji: "1F4AA",
         ready_for_next: false,
         todos: [
           %{text: "Complete landing page design", completed: true},
           %{text: "Review pull requests", completed: true},
           %{text: "Update documentation", completed: false},
           %{text: "Fix responsive layout bugs", completed: false}
         ],
         chat_messages: [
           %{text: "Making great progress on the UI!"},
           %{text: "Almost done with this task"}
         ]
       }
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-12 p-8">
      <section aria-labelledby="comment-preview" class="space-y-6">
        <div class="flex items-center gap-3">
          <span class="size-2 rounded-full bg-secondary" />
          <h2 id="comment-preview" class="text-lg font-semibold text-base-content">
            Comment bubble
          </h2>
        </div>
        <div class="rounded-3xl border border-base-300/60 bg-base-200/40 p-8">
          <.comment_bubble>
            <:body>
              <div class="flex items-center gap-3 mb-3">
                <div
                  class="size-12 shrink-0 rounded-full bg-secondary-content/20 shadow-inner"
                  aria-hidden="true"
                >
                </div>
                <div>
                  <p class="text-sm font-semibold">{@comment.author}</p>
                  <p class="text-xs text-secondary-content/70">{@comment.timestamp}</p>
                </div>
              </div>
              <p class="text-sm leading-relaxed">{@comment.body}</p>
            </:body>
          </.comment_bubble>
        </div>
      </section>

      <section aria-labelledby="participant-card-preview" class="space-y-6">
        <div class="flex items-center gap-3">
          <span class="size-2 rounded-full bg-secondary" />
          <h2 id="participant-card-preview" class="text-lg font-semibold text-base-content">
            Participant card
          </h2>
        </div>
        <div class="rounded-3xl border border-base-300/60 bg-base-200/40 p-8 space-y-6">
          <div class="space-y-2">
            <p class="text-xs font-semibold text-base-content/60">isBreak=false</p>
            <div class="flex-shrink-0 max-w-2xl">
              <SocialPomodoroWeb.SessionParticipantComponents.participant_display
                participant={@sample_participant}
                is_break={false}
              />
            </div>
          </div>
          <div class="space-y-2">
            <p class="text-xs font-semibold text-base-content/60">isBreak=true</p>
            <div class="flex-shrink-0 max-w-2xl">
              <SocialPomodoroWeb.SessionParticipantComponents.participant_display
                participant={@sample_participant}
                is_break={true}
              />
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end
end
