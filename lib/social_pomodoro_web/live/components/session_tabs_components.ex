defmodule SocialPomodoroWeb.SessionTabsComponents do
  use SocialPomodoroWeb, :html

  alias SocialPomodoroWeb.Icons

  attr :current_participant, :map, required: true
  attr :max_todos, :integer, required: true
  attr :placeholder, :string, default: "What are you working on?"

  def todo_list(assigns) do
    todos = Map.get(assigns.current_participant, :todos, [])
    todos_count = length(todos)
    at_max = todos_count >= assigns.max_todos

    assigns =
      assigns
      |> assign(:todos, todos)
      |> assign(:todos_count, todos_count)
      |> assign(:at_max, at_max)

    ~H"""
    <div class="flex flex-col gap-2 items-center w-full max-w-md mx-auto">
      <%= if @todos_count > 0 do %>
        <ul class="list bg-base-100 rounded-box shadow-md w-full max-w-xs mb-4">
          <%= for todo <- @todos do %>
            <li class="list-row" id={"todo-#{todo.id}"}>
              <div>
                <input
                  type="checkbox"
                  checked={todo.completed}
                  phx-click="toggle_todo"
                  phx-value-todo_id={todo.id}
                  class="checkbox checkbox-sm transition-transform duration-200"
                />
              </div>
              <div class="list-col-grow">
                <span class={
                  [
                    "text-sm transition-all duration-200",
                    if(todo.completed, do: "line-through opacity-50", else: "")
                  ]
                  |> Enum.join(" ")
                }>
                  {todo.text}
                </span>
              </div>
              <button
                phx-click="delete_todo"
                phx-value-todo_id={todo.id}
                phx-hook="MaintainWakeLock"
                id={"delete-todo-#{todo.id}"}
                class="btn btn-ghost btn-xs btn-square group"
              >
                <Icons.trash class="w-4 h-4 fill-neutral group-hover:fill-error" />
              </button>
            </li>
          <% end %>
        </ul>
      <% else %>
        <div class="flex flex-col items-center justify-center mb-4 opacity-50">
          <Icons.lightbulb class="w-12 h-12 fill-current mb-2" />
          <p class="text-sm text-center">Ready to focus?</p>
        </div>
      <% end %>

      <form
        id="todo-form"
        phx-submit="add_todo"
        phx-hook="ClearForm"
        class="flex gap-2 w-full justify-center"
      >
        <input
          type="text"
          name="text"
          placeholder={@placeholder}
          class="input input-bordered w-full max-w-xs text-base"
          maxlength="30"
          required
          disabled={@at_max}
        />
        <button
          type="submit"
          phx-hook="MaintainWakeLock"
          id="add-todo-button"
          class="btn btn-square btn-primary"
          disabled={@at_max}
        >
          <Icons.submit class="w-6 h-6 fill-current" />
        </button>
      </form>
      <%= if @at_max do %>
        <p class="text-xs opacity-50">Max {@max_todos} todos reached</p>
      <% end %>
    </div>
    """
  end

  attr :room_state, :map, required: true
  attr :selected_tab, :atom, required: true
  attr :current_participant, :map, required: true
  attr :placeholder, :string, default: "What are you working on?"
  attr :user_id, :string, required: true
  slot :avatar_card, required: true
  slot :left_controls

  def tabs_with_content(assigns) do
    ~H"""
    <div class="w-full">
      <div class="relative">
        <div class="absolute -left-2 -top-2 z-20 -rotate-3">
          {render_slot(@avatar_card)}
        </div>

        <div class={[
          "flex flex-col gap-2 md:flex-row md:items-end md:justify-end",
          @left_controls != [] && "md:pl-32"
        ]}>
          <%= if @left_controls != [] do %>
            <div class="flex justify-end md:justify-start md:mr-auto">
              <div class="md:-mt-2">
                {render_slot(@left_controls)}
              </div>
            </div>
          <% end %>

          <div
            role="tablist"
            class="flex justify-end relative z-10 gap-2"
          >
            <label class={[
              "px-4 py-2 gap-2 flex items-center cursor-pointer transition-all border-t border-x border-base-300 rounded-t-lg -mb-px",
              @selected_tab == :todo && "bg-base-100 border-b-base-100 z-10",
              @selected_tab != :todo && "bg-base-200 border-b-transparent hover:bg-base-300"
            ]}>
              <input
                type="radio"
                name="session-tabs"
                role="tab"
                id="session-tab-todo"
                aria-label="Todo"
                aria-controls="session-tab-panel-todo"
                phx-click="switch_tab"
                phx-value-tab="todo"
                checked={@selected_tab == :todo}
                class="hidden"
              />
              <Icons.todo class="w-4 h-4 fill-current" />
              <span class="font-semibold">Todo</span>
            </label>

            <label class={[
              "px-4 py-2 gap-2 flex items-center transition-all border-t border-x border-base-300 rounded-t-lg -mb-px",
              @selected_tab == :chat && "bg-base-100 border-b-base-100 z-10 cursor-pointer",
              @selected_tab != :chat && "bg-base-200 border-b-transparent",
              @room_state.status == :break && @selected_tab != :chat &&
                "hover:bg-base-300 cursor-pointer",
              @room_state.status != :break && "opacity-40 cursor-not-allowed"
            ]}>
              <input
                type="radio"
                name="session-tabs"
                role="tab"
                id="session-tab-chat"
                aria-label="Shout"
                aria-controls="session-tab-panel-chat"
                phx-click="switch_tab"
                phx-value-tab="chat"
                checked={@selected_tab == :chat}
                disabled={@room_state.status != :break}
                class="hidden"
              />
              <Icons.chat class="w-4 h-4 fill-current" />
              <span class="font-semibold">Shout</span>
            </label>
          </div>
        </div>
      </div>

      <div
        id="session-tab-panel-todo"
        role="tabpanel"
        aria-labelledby="session-tab-todo"
        class={[
          "bg-base-100 border-x border-b border-t border-base-300 p-6 rounded-b-lg rounded-tl-lg rounded-tr-lg min-h-48",
          @selected_tab == :todo && "block",
          @selected_tab != :todo && "hidden"
        ]}
      >
        <.todo_list
          current_participant={@current_participant}
          max_todos={SocialPomodoro.Config.max_todos_per_user()}
          placeholder={@placeholder}
        />
      </div>

      <div
        id="session-tab-panel-chat"
        role="tabpanel"
        aria-labelledby="session-tab-chat"
        class={[
          "bg-base-100 border-x border-b border-t border-base-300 p-6 rounded-b-lg rounded-tl-lg min-h-48",
          @selected_tab == :chat && "block",
          @selected_tab != :chat && "hidden"
        ]}
      >
        <div class="flex flex-col gap-2 items-center w-full max-w-md mx-auto">
          <% user_messages = Map.get(@room_state.chat_messages, @user_id, []) %>
          <%= if length(user_messages) > 0 do %>
            <div class="w-full mb-4 flex justify-center">
              <div class="chat chat-start max-w-xs">
                <div class="chat-bubble chat-bubble-secondary p-0">
                  <ul class="list">
                    <%= for message <- Enum.with_index(user_messages) do %>
                      <% {msg, index} = message %>
                      <li class={[
                        "list-row py-2 px-3",
                        index < length(user_messages) - 1 && "border-b border-base-content/10"
                      ]}>
                        <p class="text-sm">{msg.text}</p>
                      </li>
                    <% end %>
                  </ul>
                </div>
              </div>
            </div>
          <% else %>
            <div class="flex flex-col items-center justify-center mb-4 opacity-50">
              <Icons.bullhorn class="w-12 h-12 fill-current mb-2" />
              <p class="text-sm text-center">No shouts yet</p>
            </div>
          <% end %>

          <form
            id="chat-form"
            phx-submit="send_chat_message"
            phx-hook="ClearForm"
            class="flex gap-2 w-full justify-center"
          >
            <input
              type="text"
              name="text"
              placeholder="Say something..."
              class="input input-bordered w-full max-w-xs text-base"
              maxlength="50"
              required
            />
            <button
              type="submit"
              phx-hook="MaintainWakeLock"
              id="send-chat-button"
              class="btn btn-square btn-primary"
            >
              <Icons.submit class="w-6 h-6 fill-current" />
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
