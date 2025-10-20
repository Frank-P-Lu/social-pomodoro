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

  def tabs_with_content(assigns) do
    ~H"""
    <div role="tablist" class="tabs tabs-lift tabs-lg tabs-bottom">
      <label class="tab">
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
        />
        <Icons.todo class="w-5 h-5 fill-current" />
        <span class="text-sm font-semibold">Todo</span>
      </label>
      <div
        id="session-tab-panel-todo"
        role="tabpanel"
        aria-labelledby="session-tab-todo"
        class="tab-content bg-base-100 border-base-300 p-6"
      >
        <.todo_list
          current_participant={@current_participant}
          max_todos={SocialPomodoro.Config.max_todos_per_user()}
          placeholder={@placeholder}
        />
      </div>

      <label class={[
        "tab",
        @room_state.status != :break && "opacity-40 cursor-not-allowed"
      ]}>
        <input
          type="radio"
          name="session-tabs"
          role="tab"
          id="session-tab-chat"
          aria-label="Chat"
          aria-controls="session-tab-panel-chat"
          phx-click="switch_tab"
          phx-value-tab="chat"
          checked={@selected_tab == :chat}
          disabled={@room_state.status != :break}
        />
        <Icons.chat class="w-5 h-5 fill-current" />
        <span class="text-sm font-semibold">Chat</span>
      </label>
      <div
        id="session-tab-panel-chat"
        role="tabpanel"
        aria-labelledby="session-tab-chat"
        class="tab-content bg-base-100 border-base-300 p-6"
      >
        <div class="flex flex-col gap-4 items-center w-full max-w-md mx-auto">
          <% user_messages = Map.get(@room_state.chat_messages, @user_id, []) %>
          <%= if length(user_messages) > 0 do %>
            <div class="w-full max-w-xs space-y-2 mb-4">
              <%= for message <- user_messages do %>
                <div class="chat chat-end">
                  <div class="chat-bubble chat-bubble-secondary">
                    {message.text}
                  </div>
                </div>
              <% end %>
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
