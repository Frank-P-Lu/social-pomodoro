defmodule SocialPomodoroWeb.Plugs.UserSession do
  @moduledoc """
  Manages persistent user identity with user_id and maps to usernames via UserRegistry.
  """
  import Plug.Conn

  @cookie_key "_social_pomodoro_user_id"
  # 1 year
  @max_age 60 * 60 * 24 * 365

  def init(_opts), do: %{}

  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    # Get or generate user_id
    user_id = get_session(conn, :user_id) || conn.cookies[@cookie_key] || generate_user_id()

    # Ensure user has a username in the registry
    username = SocialPomodoro.UserRegistry.get_username(user_id)

    if is_nil(username) do
      # Generate friendly username for new users
      new_username = generate_friendly_username()

      # Extract metadata for bot detection and analytics
      metadata = extract_connection_metadata(conn)

      SocialPomodoro.UserRegistry.register_or_update_user(user_id, new_username, metadata)
    end

    # Store user_id in session and cookie
    conn
    |> put_session(:user_id, user_id)
    |> assign(:user_id, user_id)
    |> put_resp_cookie(@cookie_key, user_id, max_age: @max_age, http_only: true)
  end

  defp extract_connection_metadata(conn) do
    %{
      user_agent: get_req_header(conn, "user-agent") |> List.first(),
      ip_address: get_client_ip(conn),
      referer: get_req_header(conn, "referer") |> List.first(),
      accept_language: get_req_header(conn, "accept-language") |> List.first()
    }
  end

  defp get_client_ip(conn) do
    # Check X-Forwarded-For first (for proxies/load balancers)
    case get_req_header(conn, "x-forwarded-for") do
      [forwarded_for | _] ->
        # Take the first IP in the chain (original client)
        forwarded_for |> String.split(",", parts: 2) |> List.first() |> String.trim()

      [] ->
        # Fall back to remote_ip
        format_ip_tuple(conn.remote_ip)
    end
  end

  defp format_ip_tuple({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  defp format_ip_tuple({a, b, c, d, e, f, g, h}) do
    [a, b, c, d, e, f, g, h]
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.join(":")
  end

  defp generate_user_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
  end

  defp generate_friendly_username do
    # Gfycat-style: AdjectiveAdjectiveAnimal
    adjectives = [
      "Serene",
      "Radiant",
      "Nimble",
      "Graceful",
      "Eager",
      "Spirited",
      "Vibrant",
      "Sturdy",
      "Witty",
      "Fierce",
      "Lively",
      "Patient",
      "Daring",
      "Steady",
      "Jolly",
      "Keen",
      "Merry",
      "Zesty",
      "Determined",
      "Valiant",
      "Audacious",
      "Cunning",
      "Wily",
      "Intrepid",
      "Placid",
      "Brazen",
      "Shrewd",
      "Languid",
      "Astute",
      "Mellow",
      "Crafty",
      "Sagacious",
      # Noir/mysterious vibes
      "Shadowy",
      "Smoky",
      "Mysterious",
      "Dangerous",
      "Sultry",
      "Ruthless",
      "Calculating",
      "Hardboiled",
      "Cynical",
      "Weathered",
      "Jaded",
      "Brooding",
      "Noir",
      "Gritty",
      "Sinister",
      "Weary",
      "Grizzled",
      "Haunted",
      "Treacherous",
      "Slick",
      "Cold",
      "Sharp",
      "Steel",
      "Bitter",
      "Lone",
      "Scarred",
      "Rough",
      "Dusty",
      "Stray",
      "Lonesome",
      "Ragged",
      "Crooked",
      "Sordid",
      "Bleak",
      "Worn",
      # Caffeinated energy
      "Caffeinated",
      "Unhinged",
      "Feral",
      "Chaotic",
      "Panicked",
      "Delirious",
      "Hyper",
      "Frazzled",
      "Zooming",
      "Vibrating",
      "Ferocious",
      # Confused/bewildered
      "Bewildered",
      "Discombobulated",
      "Flabbergasted",
      "Bamboozled",
      "Befuddled",
      "Boggled",
      "Flustered",
      "Rattled",
      "Gobsmacked",
      "Puzzled",
      "Muddled",
      "Addled",
      "Wobbly",
      "Wonky",
      "Scatterbrained"
    ]

    # Using "animals" loosely - includes animals, food, objects, and absurd things
    nouns = [
      # Classic animals
      "Panda",
      "Tiger",
      "Eagle",
      "Dolphin",
      "Phoenix",
      "Dragon",
      "Wolf",
      "Fox",
      "Bear",
      "Lion",
      "Lark",
      "Falcon",
      "Raven",
      "Otter",
      "Lynx",
      "Hawk",
      "Owl",
      "Deer",
      "Swan",
      "Crane",
      "Griffin",
      "Pegasus",
      "Sparrow",
      "Badger",
      # Australian animals (iconic, goofy, delightful)
      "Quokka",
      "Platypus",
      "Kookaburra",
      "Wombat",
      "Echidna",
      "Numbat",
      "Cassowary",
      "Bandicoot",
      "Potoroo",
      "Bilby",
      "Kangaroo",
      "Wallaby",
      "Dingo",
      # Dogs with maximum personality
      "Corgi",
      "Shiba",
      "Pug",
      "Dachshund",
      "Beagle",
      "Basset",
      "Husky",
      "Chihuahua",
      "Borzoi",
      "Bulldog",
      # Food items
      "Pickle",
      "Waffle",
      "Noodle",
      "Mango",
      "Pretzel",
      "Biscuit",
      "Dumpling",
      "Nugget",
      "Sprout",
      "Radish",
      "Turnip",
      "Kumquat",
      # Objectively funny animals (non-Australian)
      "Narwhal",
      "Axolotl",
      "Capybara",
      "Manatee",
      "Walrus",
      "Puffin",
      "Lemur",
      "Possum",
      "Shrimp",
      # Random objects with personality
      "Spatula",
      "Spoon",
      "Crayon",
      "Pencil",
      "Eraser",
      "Button",
      "Zipper",
      "Bucket",
      "Sponge",
      "Plunger",
      "Muffler",
      # Just absurd
      "Sneeze",
      "Hiccup",
      "Wiggle",
      "Bounce",
      "Wobble",
      "Squish",
      "Honk",
      "Blorp",
      "Bonk",
      # Lewis Carroll nonsense creatures
      "Jabberwock",
      "Bandersnatch",
      "Jubjub",
      "Borogove",
      "Rath",
      "Snark",
      "Boojum",
      # Noir/detective character types
      "Detective",
      "Gumshoe",
      "Dame",
      "Stranger",
      "Shadow",
      "Phantom",
      "Sleuth",
      "Prowler",
      "Drifter",
      "Outlaw",
      "Rogue",
      "Specter",
      "Wanderer",
      "Nomad",
      "Vagabond"
    ]

    # Ensure the two adjectives are different
    [adj1, adj2] = Enum.take_random(adjectives, 2)
    noun = Enum.random(nouns)

    "#{adj1}#{adj2}#{noun}"
  end
end
