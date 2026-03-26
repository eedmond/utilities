#!/bin/zsh
# poll_github.sh — monitor a GitHub PR for updates
# Usage: ./poll_github.sh <PR_URL>
# Example: ./poll_github.sh https://github.com/Owner/Repo/pull/42

if [[ -z "$1" ]]; then
  echo "Usage: $0 <PR_URL>"
  echo "Example: $0 https://github.com/Owner/Repo/pull/42"
  exit 1
fi

# Parse URL: https://<host>/<owner>/<repo>/pull/<number>
if [[ ! "$1" =~ '^https://([^/]+)/([^/]+/[^/]+)/pull/([0-9]+)' ]]; then
  echo "Error: could not parse PR URL: $1"
  echo "Expected format: https://<host>/<owner>/<repo>/pull/<number>"
  exit 1
fi

HOSTNAME="${match[1]}"
REPO="${match[2]}"
PR="${match[3]}"
INTERVAL=$((5 * 60))

api() { GH_HOST="$HOSTNAME" gh api "$@" 2>/dev/null; }

get_pr()       { api "repos/$REPO/pulls/$PR" --jq '{title, state, sha: .head.sha, author: .user.login, base: .base.ref, head: .head.ref}'; }
get_sha()      { echo "$1" | jq -r '.sha'; }
get_reviews()  { api --paginate "repos/$REPO/pulls/$PR/reviews" --jq '.[] | {id, user: .user.login, state}' | jq -s '.'; }
get_comments() { api "repos/$REPO/issues/$PR/comments" --jq '[.[] | {id, updated_at}]'; }
get_checks()   { api "repos/$REPO/commits/$1/check-runs" --jq '[.check_runs[] | {name, status, conclusion}]'; }

checks_all_passed() {
  echo "$1" | jq -e '
    length > 0 and
    all(.[]; .status == "completed") and
    all(.[]; .conclusion == "success" or .conclusion == "skipped" or .conclusion == "neutral")
  ' > /dev/null 2>&1
}

# Full check breakdown for initial display.
print_checks_full() {
  local checks="$1"
  local failed passed running
  read -r failed passed running < <(echo "$checks" | jq -r '
    [
      ([.[] | select(.status == "completed" and (.conclusion == "failure" or .conclusion == "action_required" or .conclusion == "timed_out"))] | length),
      ([.[] | select(.status == "completed" and (.conclusion != "failure" and .conclusion != "action_required" and .conclusion != "timed_out"))] | length),
      ([.[] | select(.status != "completed")] | length)
    ] | map(tostring) | join(" ")
  ')
  printf '  Checks: %s ✗  %s ✓  %s running\n' "$failed" "$passed" "$running"
  if [[ "$failed" -gt 0 ]]; then
    echo "$checks" | jq -r '.[] | select(.status == "completed" and (.conclusion == "failure" or .conclusion == "action_required" or .conclusion == "timed_out")) | "    ✗ \(.name)"'
  fi
}

# Print only checks that newly completed since prev. Returns 0 if any, 1 if none.
# With do_notify=true, notifies on new failures or all-pass.
print_checks_diff() {
  local prev="$1" curr="$2" do_notify="${3:-false}"
  local newly_completed
  newly_completed=$(jq -n --argjson prev "$prev" --argjson curr "$curr" '
    ($prev | map(select(.status == "completed") | .name)) as $prev_done |
    [$curr[] | select(.status == "completed") | select(.name as $n | ($prev_done | any(. == $n)) | not)]
  ')
  [[ $(echo "$newly_completed" | jq 'length') -eq 0 ]] && return 1

  echo "$newly_completed" | jq -r '.[] | if (.conclusion == "failure" or .conclusion == "action_required" or .conclusion == "timed_out") then "  ✗ \(.name)" else "  ✓ \(.name)" end'

  if [[ "$do_notify" == true ]]; then
    local first_fail
    first_fail=$(echo "$newly_completed" | jq -r 'first(.[] | select(.conclusion == "failure" or .conclusion == "action_required" or .conclusion == "timed_out")) | .name // empty')
    if [[ -n "$first_fail" ]]; then
      notify "PR #$PR — Check Failed" "$first_fail"
    elif checks_all_passed "$curr"; then
      notify "PR #$PR — All Checks Passed" "$(echo "$curr" | jq 'length') checks passed"
    fi
  fi
  return 0
}

notify() { osascript -e "display notification \"$2\" with title \"$1\" subtitle \"$PR_URL\""; }

header() { printf '\n\033[2m%s  ─────────────────────────────\033[0m\n' "$(date '+%b %d %H:%M')"; }

print_pr_status() {
  local sha="$1" checks="$2" reviews="$3" comments="$4"
  echo "  SHA: ${sha[1,7]}"
  print_checks_full "$checks"
  local approved_names blocking_count
  approved_names=$(echo "$reviews" | jq -r '
    [group_by(.user)[] | sort_by(.id) | last | select(.state == "APPROVED") | .user] |
    if length == 0 then "none" else "\(length): \(join(", "))" end
  ')
  blocking_count=$(echo "$reviews" | jq '[group_by(.user)[] | sort_by(.id) | last | select(.state == "CHANGES_REQUESTED")] | length')
  printf '  Reviews: %s approved  —  %s blocking\n' "$approved_names" "$blocking_count"
  echo "  Comments: $(echo "$comments" | jq 'length')"
}

# ─── Init ────────────────────────────────────────────────────────────────────

echo "Monitoring $REPO#$PR — checking every 5 min"
echo "Started: $(date '+%b %d %H:%M')"

PREV_PR_JSON=$(get_pr)
if [[ -z "$PREV_PR_JSON" ]]; then
  echo "Error: could not fetch PR data (check 'gh auth status --hostname $HOSTNAME')"
  exit 1
fi
PREV_SHA=$(get_sha "$PREV_PR_JSON")
PREV_REVIEWS=$(get_reviews)
PREV_COMMENTS=$(get_comments)
PREV_CHECKS=$(get_checks "$PREV_SHA")

# ─── Initial Summary ─────────────────────────────────────────────────────────

header
print_pr_status "$PREV_SHA" "$PREV_CHECKS" "$PREV_REVIEWS" "$PREV_COMMENTS"

# ─── Loop ────────────────────────────────────────────────────────────────────

SPINNERS=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

countdown() {
  local total=$1 i=0 t m s
  for (( t=total; t>0; t-- )); do
    m=$(( t / 60 )) s=$(( t % 60 ))
    printf '\r\033[2K  %s  next check in %d:%02d' "${SPINNERS[$(( i % 10 + 1 ))]}" "$m" "$s"
    sleep 1
    (( i++ ))
  done
  printf '\r\033[2K'
}

NO_CHANGE_LINE=false

while true; do
  countdown $INTERVAL

  CURR_PR_JSON=$(get_pr)
  CURR_SHA=$(get_sha "$CURR_PR_JSON")
  CURR_REVIEWS=$(get_reviews)
  CURR_COMMENTS=$(get_comments)
  CURR_CHECKS=$(get_checks "$CURR_SHA")

  update_output=""

  # New commits pushed
  if [[ "$CURR_SHA" != "$PREV_SHA" ]]; then
    update_output+="  Commit pushed → ${CURR_SHA[1,7]}"$'\n'
    notify "PR #$PR — New Commits" "Head updated to ${CURR_SHA[1,7]}"
  fi

  # Checks: show newly completed; notify on new failures or all-pass
  if [[ "$CURR_CHECKS" != "$PREV_CHECKS" ]]; then
    check_diff=$(print_checks_diff "$PREV_CHECKS" "$CURR_CHECKS" true)
    [[ -n "$check_diff" ]] && update_output+="${check_diff}"$'\n'
  fi

  # Reviews: show newly approved or blocking reviewers
  if [[ "$CURR_REVIEWS" != "$PREV_REVIEWS" ]]; then
    review_lines=$(diff <(echo "$PREV_REVIEWS" | jq -r '.[] | "\(.id) \(.state) \(.user)"') \
                        <(echo "$CURR_REVIEWS" | jq -r '.[] | "\(.id) \(.state) \(.user)"') \
      | grep '^>' | sed 's/^> [^ ]* //' | while read -r state user; do
          case "$state" in
            APPROVED)           echo "  ✓ Approved by $user" ;;
            CHANGES_REQUESTED)  echo "  ✗ Changes requested by $user" ;;
          esac
        done)
    if [[ -n "$review_lines" ]]; then
      update_output+="${review_lines}"$'\n'
      notify "PR #$PR — Review Update" "New review activity"
    fi
  fi

  # Comments
  if [[ "$CURR_COMMENTS" != "$PREV_COMMENTS" ]]; then
    PREV_N=$(echo "$PREV_COMMENTS" | jq 'length')
    CURR_N=$(echo "$CURR_COMMENTS" | jq 'length')
    DELTA=$(( CURR_N - PREV_N ))
    if [[ $DELTA -gt 0 ]]; then
      update_output+="  Comments: +$DELTA new (total: $CURR_N)"$'\n'
    else
      update_output+="  Comments: updated (total: $CURR_N)"$'\n'
    fi
    notify "PR #$PR — New Comment" "$DELTA new comment(s)"
  fi

  if [[ -n "$update_output" ]]; then
    NO_CHANGE_LINE=false
    header
    printf '%s' "$update_output"
  else
    [[ "$NO_CHANGE_LINE" == true ]] && printf '\033[1A\r\033[2K'
    printf '  ○  no changes  (checked %s)\n' "$(date '+%H:%M')"
    NO_CHANGE_LINE=true
  fi

  PREV_SHA="$CURR_SHA"
  PREV_REVIEWS="$CURR_REVIEWS"
  PREV_COMMENTS="$CURR_COMMENTS"
  PREV_CHECKS="$CURR_CHECKS"
done

