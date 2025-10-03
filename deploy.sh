#!/bin/bash
set -e
mix test
mix format --check-formatted
fly deploy