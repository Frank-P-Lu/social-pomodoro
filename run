#!/bin/bash

# Load environment variables from .env file if it exists
if [ -f .env ]; then
  export $(cat .env | grep -v '^#' | xargs)
else
  echo "Warning: .env file not found. Copy .env.example to .env and configure it."
  exit 1
fi

# Start Phoenix server
mix phx.server
