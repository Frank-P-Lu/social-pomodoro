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
       },
       busy_participant: %{
         user_id: "busy_demo_789",
         username: "Jordan",
         status_emoji: "1F389",
         ready_for_next: false,
         todos: [
           %{
             text: "Refactor the entire authentication system to use OAuth 2.0 with PKCE flow",
             completed: true
           },
           %{
             text:
               "Write comprehensive unit tests for all edge cases in the payment processing module",
             completed: true
           },
           %{
             text:
               "Implement real-time websocket synchronization across multiple server instances with Redis pub/sub",
             completed: false
           },
           %{
             text:
               "Optimize database queries and add proper indexes to reduce page load time from 3s to under 500ms",
             completed: false
           },
           %{
             text: "Create detailed API documentation with examples for all 50+ endpoints",
             completed: false
           }
         ],
         chat_messages: [
           %{text: "This is taking longer than expected but making steady progress"},
           %{text: "Found a few edge cases we need to handle carefully"},
           %{text: "Almost there, just need to finish up the last few items"}
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
          <div class="space-y-2">
            <p class="text-xs font-semibold text-base-content/60">
              isBreak=true (3 comments, long todos)
            </p>
            <div class="flex-shrink-0 max-w-2xl">
              <SocialPomodoroWeb.SessionParticipantComponents.participant_display
                participant={@busy_participant}
                is_break={true}
              />
            </div>
          </div>
        </div>
      </section>

      <section aria-labelledby="participant-grid-preview" class="space-y-6">
        <div class="flex items-center gap-3">
          <span class="size-2 rounded-full bg-secondary" />
          <h2 id="participant-grid-preview" class="text-lg font-semibold text-base-content">
            Participant cards - Horizontal Layout
          </h2>
        </div>
        <div class="rounded-3xl border border-base-300/60 bg-base-200/40 p-8">
          <div class="flex flex-row gap-6 overflow-x-auto p-4 items-start">
            <SocialPomodoroWeb.SessionParticipantComponents.participant_display
              participant={@sample_participant}
              is_break={false}
            />

            <SocialPomodoroWeb.SessionParticipantComponents.participant_display
              participant={@busy_participant}
              is_break={true}
            />

            <SocialPomodoroWeb.SessionParticipantComponents.participant_display
              participant={@sample_participant}
              is_break={true}
            />

            <SocialPomodoroWeb.SessionParticipantComponents.participant_display
              participant={@busy_participant}
              is_break={false}
            />

            <SocialPomodoroWeb.SessionParticipantComponents.participant_display
              participant={@sample_participant}
              is_break={false}
            />

            <SocialPomodoroWeb.SessionParticipantComponents.participant_display
              participant={%{@sample_participant | ready_for_next: true}}
              is_break={false}
            />
          </div>
        </div>
      </section>
    </div>
    """
  end
end
