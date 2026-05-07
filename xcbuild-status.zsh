#!/usr/bin/env zsh
# xcbuild-status — emits a tmux status-right fragment summarizing xcbuild state.
# Counts in-flight builds and recent successes / failures from the last hour.
# Meant to be invoked from `status-right` via `#(…)`; emits nothing when
# there's nothing interesting to show.

emulate -L zsh
setopt LOCAL_OPTIONS NULL_GLOB PIPE_FAIL

XCBUILD_RUNS_DIR="${HOME}/.cache/xcbuild/runs"
XCBUILD_STATUS_WINDOW=${XCBUILD_STATUS_WINDOW:-3600}   # seconds

# Catppuccin Mocha palette — matches the theme set in .tmux.conf.
local color_running='#f9e2af'   # yellow
local color_success='#a6e3a1'   # green
local color_failed='#f38ba8'    # red
local color_dim='#6c7086'       # overlay 0

local -a metas
metas=( "$XCBUILD_RUNS_DIR"/*/meta.json(N) )
(( ${#metas[@]} == 0 )) && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Snapshot live tmux window ids so we can distinguish a genuinely running build
# from one whose window died (session killed, machine rebooted, etc.). If tmux
# isn't available here the set is empty and every "running" row is treated as
# dead.
local alive
alive=$(tmux list-windows -a -F '#{window_id}' 2>/dev/null)

local cutoff
cutoff=$(( $(date -u +%s) - XCBUILD_STATUS_WINDOW ))

# One jq pass over every meta.json: emit a single-column classification per
# relevant run (running / success / failed). Dead-running entries whose tmux
# window no longer exists fall into "failed" when they started recently —
# otherwise they're silently ignored as stale.
local rows
rows=$(jq -rs \
    --arg cutoff "$cutoff" \
    --arg alive "$alive" '
    ($alive | split("\n") | map(select(. != ""))) as $aliveset
    | ($cutoff | tonumber) as $cutoff_num
    | map(
        . as $r
        | ($r.status // "unknown") as $s
        | ($r.tmux_window_id // "") as $wid
        | ($r.started_at | if (. // "") == "" then 0
                           else (try fromdateiso8601 catch 0) end) as $started
        | ($r.ended_at   | if (. // null) == null then 0
                           else (try fromdateiso8601 catch 0) end) as $ended
        | if $s == "running" and ($aliveset | index($wid)) != null then
            "running"
          elif $s == "running" and $started >= $cutoff_num then
            "failed"
          elif $s == "success" and $ended >= $cutoff_num then
            "success"
          elif $s == "failed" and $ended >= $cutoff_num then
            "failed"
          else null end
      )
    | map(select(. != null))
    | .[]
' "${metas[@]}" 2>/dev/null)

local running=0 success=0 failed=0
local kind
while IFS= read -r kind; do
    [[ -z "$kind" ]] && continue
    case "$kind" in
        running) (( running++ )) ;;
        success) (( success++ )) ;;
        failed)  (( failed++ )) ;;
    esac
done <<<"$rows"

local -a segments
(( running > 0 )) && segments+=( "#[fg=${color_running}]● ${running}#[fg=default]" )
(( success > 0 )) && segments+=( "#[fg=${color_success}]✓ ${success}#[fg=default]" )
(( failed  > 0 )) && segments+=( "#[fg=${color_failed}]✗ ${failed}#[fg=default]" )

(( ${#segments[@]} == 0 )) && exit 0

# Join with two spaces, and append a trailing separator so we're visually
# detached from whatever tmux draws to the right (e.g. the AI-assistant
# status panel). The single space tmux inserts between `#(…)` substitutions
# in status-right pads the other side of the separator.
local IFS='  '
print -n -- "${segments[*]} #[fg=${color_dim}]│#[fg=default]"
