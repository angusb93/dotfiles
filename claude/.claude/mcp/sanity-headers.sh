#!/usr/bin/env bash
# headersHelper for the Sanity MCP server (Exhibition Co, project 1vyh4bbf).
# Reads the robot token from 1Password at connect time, so it never sits in
# ~/.claude.json. Claude Code expects a JSON object of headers on stdout.
set -euo pipefail
PATH="$PATH:/run/current-system/sw/bin:/opt/homebrew/bin"
export OP_SERVICE_ACCOUNT_TOKEN="$(<"$HOME/.config/op/service-account-token")"
token="$(op read --no-newline "op://6ozvud25wxpywiml26e3a53hxu/ire7f2pdvpeknbhqbaudbf3loq/credential")"
printf '{"Authorization":"Bearer %s"}\n' "$token"
