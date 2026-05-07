#!/usr/bin/env zsh
# xcbuild — fzf-driven Xcode build/deploy popup with persistent run history.
# Each build runs in its own window inside a shared tmux session ("xcbuild"),
# so closing the popup leaves it running. State lives at $XCBUILD_DIR.
#
# Public:  xcbuild — open the picker (intended for tmux popup `<leader>+B`).

XCBUILD_DIR="${HOME}/.cache/xcbuild"
XCBUILD_RUNS_DIR="${XCBUILD_DIR}/runs"
XCBUILD_RECENT="${XCBUILD_DIR}/recent.json"
XCBUILD_MAX_RUNS=20
XCBUILD_TMUX_SESSION="xcbuild"
# Captured at source time so the detached runner can re-source this file.
XCBUILD_LIB="${${(%):-%x}:A}"

xcbuild() {
    emulate -L zsh
    setopt LOCAL_OPTIONS PIPE_FAIL EXTENDED_GLOB

    local t
    for t in fzf jq xcodebuild tmux; do
        command -v "$t" >/dev/null 2>&1 || {
            print -u2 "xcbuild: $t not installed."
            return 1
        }
    done

    mkdir -p "$XCBUILD_RUNS_DIR"
    [[ -f "$XCBUILD_RECENT" ]] || print -- '[]' > "$XCBUILD_RECENT"

    # Optional: only required for `Configure new build…` and quick-builds
    # (those need a project to find). Browsing/re-running past runs works
    # from anywhere.
    local repo
    repo=$(git rev-parse --show-toplevel 2>/dev/null) || repo=""

    _xcbuild_prune

    local mode="main" detail_key=""

    # All loop-local variables are declared once up-front; redeclaring with
    # `local` inside the loop triggers a zsh quirk that prints the existing
    # value (`var=…`) on each subsequent iteration, which surfaces as terminal
    # spew between fzf renders.
    local result key sel menu_output prompt header fzf_rc
    local kind rest id vrc cfg mfile meta_file run_status run_repo

    while true; do
        if [[ "$mode" == "detail" ]]; then
            menu_output=$(_xcbuild_menu_detail "$detail_key")
            prompt='config history ▸ '
            header='enter=run · ctrl-v=view log · ctrl-x=delete · esc=back'
        else
            menu_output=$(_xcbuild_menu "$repo")
            prompt='xcbuild ▸ '
            header='enter=run · ctrl-v=view · ctrl-h=history · ctrl-x=delete · esc=quit'
        fi

        result=$(print -r -- "$menu_output" | fzf \
            --ansi \
            --with-nth='3..' \
            --delimiter=$'\t' \
            --prompt="$prompt" \
            --header="$header" \
            --layout=reverse \
            --no-multi --no-info \
            --pointer='▶' \
            --expect=ctrl-v,ctrl-x,ctrl-h)
        fzf_rc=$?

        if (( fzf_rc != 0 )); then
            # esc / cancel: detail mode pops back to main; main closes popup.
            if [[ "$mode" == "detail" ]]; then
                mode="main"; detail_key=""
                continue
            else
                return 0
            fi
        fi

        # `--expect` makes fzf print the pressed key on the first line and
        # the selection on the second (key is empty for plain Enter).
        key="${result%%$'\n'*}"
        sel="${result#*$'\n'}"

        kind="${sel%%$'\t'*}"
        rest="${sel#*$'\t'}"
        id="${rest%%$'\t'*}"

        case "$key" in
            ctrl-v)
                if [[ "$kind" == "run" ]]; then
                    _xcbuild_view "$id"; vrc=$?
                    (( vrc == 2 )) && return 0
                fi
                continue
                ;;
            ctrl-x)
                # Delete a run entry — kills its tmux window (aborting the
                # build if still active) and removes the run directory.
                [[ "$kind" == "run" ]] && _xcbuild_delete_run "$id"
                continue
                ;;
            ctrl-h)
                # Drill into all past runs for this run's config.
                if [[ "$kind" == "run" ]]; then
                    mfile="$XCBUILD_RUNS_DIR/$id/meta.json"
                    if [[ -f "$mfile" ]]; then
                        detail_key=$(_xcbuild_config_key "$mfile")
                        mode="detail"
                    fi
                fi
                continue
                ;;
        esac

        case "$kind" in
            new)
                [[ -z "$repo" ]] && {
                    print -u2 "xcbuild: 'Configure new build' requires a git repo."
                    continue
                }
                cfg=$(_xcbuild_wizard "$repo") || continue
                _xcbuild_launch "$repo" "$cfg"
                return 0
                ;;
            quick)
                [[ -z "$repo" ]] && continue
                cfg=$(_xcbuild_recent_for_repo "$repo" | jq -c ".[$id]")
                [[ -n "$cfg" && "$cfg" != "null" ]] || continue
                _xcbuild_launch "$repo" "$cfg"
                return 0
                ;;
            run)
                # Active run: jump into the live viewer. Done run: re-launch
                # using the saved config (works from any cwd, since the
                # original repo is recorded in meta.json).
                meta_file="$XCBUILD_RUNS_DIR/$id/meta.json"
                [[ -f "$meta_file" ]] || continue
                run_status=$(jq -r '.status' "$meta_file" 2>/dev/null)
                if [[ "$run_status" == "running" ]]; then
                    _xcbuild_view "$id"; vrc=$?
                    (( vrc == 2 )) && return 0
                else
                    run_repo=$(jq -r '.repo' "$meta_file")
                    cfg=$(jq -c '{project, project_flag, scheme,
                                  destination_id, destination_platform,
                                  destination_label, build_only}' "$meta_file")
                    _xcbuild_launch "$run_repo" "$cfg"
                    return 0
                fi
                ;;
        esac
    done
}

# ── Menu emission ───────────────────────────────────────────────────────────

_xcbuild_menu() {
    local repo="$1"

    # New / quick entries depend on knowing the current repo.
    if [[ -n "$repo" ]]; then
        printf 'new\t-\t  \e[36m▶\e[0m  Configure new build…\n'

        local i=0 entry label
        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            # Show scheme · project · destination so the user can disambiguate
            # quick-builds when a repo has multiple Xcode projects.
            label=$(jq -r --arg repo "$repo" '
                (.project | sub("^" + $repo + "/"; "")) as $proj
                | "\(.scheme)  ·  \($proj)  ·  \(.destination_label)"
            ' <<<"$entry")
            printf 'quick\t%d\t  \e[35m↻\e[0m  %s\n' "$i" "$label"
            (( i++ ))
        done < <(_xcbuild_recent_for_repo "$repo" | jq -c '.[0:5][]?' 2>/dev/null)
    fi

    # Recent runs across all repos — always shown so you can re-run anything
    # without first cd'ing into the original project. Deduped by config
    # (project + scheme + destination), showing only the newest run for
    # each. Ctrl-H drills into the full history for a config.
    typeset -A latest_dir run_count
    local -a config_order
    local run_dir k
    for run_dir in "$XCBUILD_RUNS_DIR"/*(N/On); do
        [[ -f "$run_dir/meta.json" ]] || continue
        k=$(_xcbuild_config_key "$run_dir/meta.json")
        if [[ -z "${latest_dir[$k]:-}" ]]; then
            latest_dir[$k]="$run_dir"
            config_order+=("$k")
        fi
        run_count[$k]=$(( ${run_count[$k]:-0} + 1 ))
    done

    for k in "${config_order[@]}"; do
        _xcbuild_emit_run_line "${latest_dir[$k]}" "${run_count[$k]}"
    done
}

_xcbuild_menu_detail() {
    # Show every run that matches the given config key (newest first), with
    # no dedup. Used when the user presses Ctrl-H on a deduped main entry.
    local detail_key="$1" run_dir k
    for run_dir in "$XCBUILD_RUNS_DIR"/*(N/On); do
        [[ -f "$run_dir/meta.json" ]] || continue
        k=$(_xcbuild_config_key "$run_dir/meta.json")
        [[ "$k" == "$detail_key" ]] || continue
        _xcbuild_emit_run_line "$run_dir" 1
    done
}

_xcbuild_config_key() {
    # Stable identifier for a build config. Two runs are "the same build" if
    # their repo, project, scheme, and destination all match.
    jq -r '"\(.repo)|\(.project)|\(.scheme)|\(.destination_id)"' "$1" 2>/dev/null
}

_xcbuild_emit_run_line() {
    local run_dir="$1" run_count="${2:-1}"
    local id="${run_dir:t}"
    local meta run_status icon scheme project project_disp \
          dest_label started age repo_full repo_short wid

    [[ -r "$run_dir/meta.json" ]] || return 1
    meta=$(<"$run_dir/meta.json")

    run_status=$(jq -r '.status // "unknown"' <<<"$meta")
    if [[ "$run_status" == "running" ]]; then
        wid=$(jq -r '.tmux_window_id // ""' <<<"$meta")
        # If the window died without finalizing (e.g., session killed), treat
        # the run as failed so it doesn't masquerade as still active.
        if [[ -n "$wid" ]] && ! _xcbuild_window_alive "$wid"; then
            _xcbuild_finalize "$id" 1 >/dev/null 2>&1
            meta=$(<"$run_dir/meta.json")
            run_status=$(jq -r '.status' <<<"$meta")
        fi
    fi

    case "$run_status" in
        success) icon=$'\e[32m✓\e[0m' ;;
        failed)  icon=$'\e[31m✗\e[0m' ;;
        running) icon=$'\e[33m●\e[0m' ;;
        *)       icon=$'\e[90m?\e[0m' ;;
    esac
    scheme=$(jq -r '.scheme' <<<"$meta")
    project=$(jq -r '.project' <<<"$meta")
    repo_full=$(jq -r '.repo' <<<"$meta")
    # Show the project relative to its repo so monorepo projects in nested
    # directories are distinguishable; falls back to basename if the project
    # path doesn't sit under the recorded repo.
    project_disp="${project#${repo_full}/}"
    [[ "$project_disp" == "$project" ]] && project_disp="${project:t}"
    dest_label=$(jq -r '.destination_label' <<<"$meta")
    started=$(jq -r '.started_at' <<<"$meta")
    age=$(_xcbuild_age "$started")
    repo_short="${repo_full:t}"

    local more_hint=""
    if (( run_count > 1 )); then
        more_hint=$(printf '  \e[90m(+%d more — ctrl-h)\e[0m' $((run_count - 1)))
    fi

    printf 'run\t%s\t  %b  %-9s  %s  \e[90m·\e[0m  %s  \e[90m·\e[0m  %s  \e[90m·  %s\e[0m%s\n' \
        "$id" "$icon" "$age" "$scheme" "$project_disp" "$dest_label" "$repo_short" "$more_hint"
}

# ── Wizard ──────────────────────────────────────────────────────────────────

_xcbuild_wizard() {
    local repo="$1"

    # Step 1: project / workspace.
    local -a project_files
    while IFS= read -r -d $'\0' f; do
        [[ "$f" == *".xcodeproj/"* ]] && continue
        project_files+=("$f")
    done < <(find "$repo" -path "$repo/.git" -prune -o \
        \( -name '*.xcodeproj' -o -name '*.xcworkspace' \) -print0)

    (( ${#project_files[@]} == 0 )) && {
        print -u2 "xcbuild: no Xcode projects found under $repo"
        return 1
    }

    local project
    if (( ${#project_files[@]} == 1 )); then
        project="${project_files[1]}"
    else
        project=$(printf '%s\n' "${project_files[@]}" \
            | sed "s|^${repo}/||" \
            | fzf --prompt='project ▸ ' --header="$repo" \
                --layout=reverse --no-multi --no-info) || return 1
        project="$repo/$project"
    fi

    local project_flag
    case "$project" in
        *.xcworkspace) project_flag='-workspace' ;;
        *.xcodeproj)   project_flag='-project'   ;;
        *) print -u2 "xcbuild: unknown project type: $project"; return 1 ;;
    esac

    # Step 2: scheme.
    local list_json
    list_json=$(xcodebuild -list -json "$project_flag" "$project" 2>/dev/null) || {
        print -u2 "xcbuild: xcodebuild -list failed for $project"
        return 1
    }
    local -a schemes
    schemes=( ${(f)"$(jq -r '(.workspace // .project).schemes[]?' <<<"$list_json")"} )
    (( ${#schemes[@]} == 0 )) && {
        print -u2 "xcbuild: no schemes in $project"
        return 1
    }

    local scheme
    if (( ${#schemes[@]} == 1 )); then
        scheme="${schemes[1]}"
    else
        scheme=$(printf '%s\n' "${schemes[@]}" \
            | fzf --prompt='scheme ▸ ' --header="${project:t}" \
                --layout=reverse --no-multi --no-info) || return 1
    fi

    # Step 3: destination.
    local dest_raw dest_rc
    dest_raw=$(xcodebuild -showdestinations \
        "$project_flag" "$project" -scheme "$scheme" 2>&1)
    dest_rc=$?

    # Take every `{ platform:... }` line that isn't tagged with an `error:`
    # (which marks ineligible entries). This works regardless of whether
    # xcodebuild emits the "Available destinations" / "Ineligible" headers.
    local -a dest_lines
    local line
    while IFS= read -r line; do
        [[ "$line" == *'{ platform:'* ]] || continue
        [[ "$line" == *' error:'* ]]    && continue
        dest_lines+=("$line")
    done <<<"$dest_raw"

    (( ${#dest_lines[@]} == 0 )) && {
        print -u2 "xcbuild: no destinations for scheme $scheme"
        print -u2 "xcbuild: -showdestinations exited with $dest_rc; output was:"
        print -u2 "----"
        print -u2 -- "$dest_raw"
        print -u2 "----"
        return 1
    }

    # Pack each destination as id|platform|name|os for the picker + lookup.
    # Generic `Any <Platform> Device` entries stay in the list — picking one
    # builds for that platform without deploying (good for compile checks
    # against iOS/visionOS/etc. without a paired device).
    local -a fmt
    local plat name os id
    for line in "${dest_lines[@]}"; do
        plat=$(_xcbuild_dest_field "$line" platform)
        name=$(_xcbuild_dest_field "$line" name)
        os=$(_xcbuild_dest_field "$line" OS)
        id=$(_xcbuild_dest_field "$line" id)
        [[ -z "$id" ]] && continue
        fmt+=( "${id}|${plat}|${name}|${os}" )
    done

    (( ${#fmt[@]} == 0 )) && {
        print -u2 "xcbuild: no concrete destinations available."
        return 1
    }

    # Picker: hidden id column up front, display columns after the tab.
    # Destinations whose name begins with "Any " are marked [build only].
    local choice
    choice=$(printf '%s\n' "${fmt[@]}" \
        | awk -F'|' '{
            tag = ($3 ~ /^Any /) ? "  [build only]" : ""
            printf "%s\t%-32s  %-22s  %-6s%s\n", $1, $3, $2, $4, tag
          }' \
        | fzf --delimiter=$'\t' --with-nth='2..' \
            --prompt='destination ▸ ' --header="$scheme" \
            --layout=reverse --no-multi --no-info) || return 1

    local dest_id="${choice%%$'\t'*}"
    local dest_label dest_plat dest_name build_only=false
    dest_name=$(printf '%s\n' "${fmt[@]}" \
        | awk -F'|' -v id="$dest_id" '$1==id { print $3; exit }')
    dest_plat=$(printf '%s\n' "${fmt[@]}" \
        | awk -F'|' -v id="$dest_id" '$1==id { print $2; exit }')
    dest_label=$(printf '%s\n' "${fmt[@]}" \
        | awk -F'|' -v id="$dest_id" '$1==id {
            if ($4 != "") printf "%s (%s, %s)", $3, $2, $4
            else          printf "%s (%s)",     $3, $2
            exit
          }')
    # "Any <Platform> Device" entries are compile-only. The id xcodebuild
    # advertises for these is sometimes a literal placeholder (e.g.
    # `dvtdevice-DVTiOSDevicePlaceholder-xros:placeholder`) that xcodebuild
    # then refuses as a `-destination 'id=...'` value. Rewrite to the
    # canonical generic spec, which always works.
    if [[ "$dest_name" == "Any "* ]]; then
        build_only=true
        dest_id="generic/platform=${dest_plat}"
    fi

    jq -nc \
        --arg project "$project" \
        --arg project_flag "$project_flag" \
        --arg scheme "$scheme" \
        --arg dest_id "$dest_id" \
        --arg dest_plat "$dest_plat" \
        --arg dest_label "$dest_label" \
        --argjson build_only "$build_only" \
        '{project:$project, project_flag:$project_flag, scheme:$scheme,
          destination_id:$dest_id, destination_platform:$dest_plat,
          destination_label:$dest_label, build_only:$build_only}'
}

_xcbuild_dest_field() {
    # Extract a key:value from `{ platform:iOS, id:UUID, OS:17.4, name:My iPhone }`.
    local line="$1" key="$2"
    print -r -- "$line" \
        | sed -nE "s/.*[{,][[:space:]]*${key}:[[:space:]]*([^,}]*)[,}].*/\1/p" \
        | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

# ── Launch & runner ─────────────────────────────────────────────────────────

_xcbuild_launch() {
    local repo="$1" cfg="$2"

    local id="$(date +%s)-$$"
    local run_dir="$XCBUILD_RUNS_DIR/$id"
    mkdir -p "$run_dir"
    : > "$run_dir/log"

    local started
    started=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local scheme dest_label
    scheme=$(jq -r '.scheme' <<<"$cfg")
    dest_label=$(jq -r '.destination_label' <<<"$cfg")
    # Compact destination label for the tmux window title — strip the
    # trailing " (platform, OS)" parenthetical. The `\(` escape is required
    # because `(` starts a group in zsh glob patterns.
    local dest_short="${dest_label%% \(*}"
    local wbase="${scheme} @ ${dest_short}"
    local wname="● ${wbase}"

    local cmd
    cmd="zsh -c 'source ${(q)XCBUILD_LIB} && _xcbuild_runner ${(q)run_dir}'"

    # Write meta.json BEFORE launching the tmux window — the runner reads it
    # as its first act, so it has to exist. Window id gets patched in below.
    print -r -- "$cfg" | jq \
        --arg id "$id" \
        --arg repo "$repo" \
        --arg sess "$XCBUILD_TMUX_SESSION" \
        --arg wbase "$wbase" \
        --arg started "$started" \
        '. + {id:$id, repo:$repo, tmux_session:$sess, tmux_window_id:"",
              tmux_window_basename:$wbase, started_at:$started, ended_at:null,
              exit_code:null, status:"running"}' > "$run_dir/meta.json"

    _xcbuild_recent_update "$repo" "$cfg"

    local wid
    if tmux has-session -t "$XCBUILD_TMUX_SESSION" 2>/dev/null; then
        wid=$(tmux new-window -t "${XCBUILD_TMUX_SESSION}:" -d \
            -n "$wname" -P -F '#{window_id}' "$cmd")
    else
        wid=$(tmux new-session -d -s "$XCBUILD_TMUX_SESSION" \
            -n "$wname" -P -F '#{window_id}' "$cmd")
    fi
    # Keep windows around after their command exits so the user can attach
    # later and see the build output from inside tmux.
    tmux set-window-option -t "$wid" remain-on-exit on 2>/dev/null

    # Patch the window id into meta.json now that we have it.
    if [[ -n "$wid" ]]; then
        local tmp
        tmp=$(mktemp)
        jq --arg wid "$wid" '.tmux_window_id=$wid' "$run_dir/meta.json" > "$tmp" \
            && mv "$tmp" "$run_dir/meta.json"
    fi

    _xcbuild_view "$id"
}

_xcbuild_runner() {
    emulate -L zsh
    setopt LOCAL_OPTIONS PIPE_FAIL

    local run_dir="$1"
    local meta=$(<"$run_dir/meta.json")
    local log="$run_dir/log"
    local ec_file="$run_dir/exit_code"

    local project project_flag scheme dest_id build_only
    project=$(jq -r '.project'              <<<"$meta")
    project_flag=$(jq -r '.project_flag'    <<<"$meta")
    scheme=$(jq -r '.scheme'                <<<"$meta")
    dest_id=$(jq -r '.destination_id'       <<<"$meta")
    build_only=$(jq -r '.build_only // false' <<<"$meta")

    # Build the `-destination` argument. For concrete devices/simulators the
    # id is a UUID and we prefix `id=`; for build-only runs the wizard has
    # already rewritten it to `generic/platform=<Platform>`, which is passed
    # through verbatim.
    local -a dest_args build_args
    if [[ -n "$dest_id" ]]; then
        case "$dest_id" in
            generic/*|platform=*) dest_args=( -destination "$dest_id" ) ;;
            *)                    dest_args=( -destination "id=$dest_id" ) ;;
        esac
    fi
    if [[ "$build_only" == "true" ]]; then
        build_args=(
            CODE_SIGNING_ALLOWED=NO
            CODE_SIGNING_REQUIRED=NO
            CODE_SIGN_IDENTITY=
        )
    fi

    # Build phase: banners + xcodebuild. Raw output lands in the log via tee;
    # the window TTY gets a beautified copy through _xcbuild_pretty. Using an
    # explicit pipeline (instead of `exec > >(...)`) ensures the log is fully
    # flushed by the time we grep it for errors below.
    {
        print -- "──── BUILD ────"
        print -- "Project:     $project"
        print -- "Scheme:      $scheme"
        print -- "Destination: $(jq -r '.destination_label' <<<"$meta")"
        [[ "$build_only" == "true" ]] && \
            print -- "(build only — code signing disabled, deploy skipped)"
        print -- ""

        xcodebuild "$project_flag" "$project" \
            -scheme "$scheme" \
            "${dest_args[@]}" \
            -configuration Debug \
            "${build_args[@]}" \
            build
    } 2>&1 | tee -a "$log" | _xcbuild_pretty
    local bec=${pipestatus[1]}
    local dec=0

    if (( bec == 0 )) && [[ "$build_only" != "true" ]]; then
        {
            print -- ""
            print -- "──── DEPLOY ────"
            _xcbuild_deploy "$run_dir"
        } 2>&1 | tee -a "$log" | _xcbuild_pretty
        dec=${pipestatus[1]}
    fi

    # Errors summary: extract diagnostics from the log so the user doesn't
    # have to scroll through thousands of build lines to find them.
    local errors error_count
    errors=$(_xcbuild_extract_errors "$log")
    error_count=$(_xcbuild_count_errors "$log")

    {
        if [[ -n "$errors" ]]; then
            print -- ""
            print -- "──── ERRORS (${error_count}) ────"
            print -r -- "$errors"
        fi
        print -- ""

        local ec
        if (( bec != 0 )); then
            if (( error_count > 0 )); then
                print -- "──── BUILD FAILED (exit $bec, ${error_count} errors) ────"
            else
                print -- "──── BUILD FAILED (exit $bec) ────"
            fi
            ec=$bec
        elif (( dec != 0 )); then
            print -- "──── DEPLOY FAILED (exit $dec) ────"
            ec=$dec
        else
            print -- "──── SUCCESS ────"
            ec=0
        fi
        print -- "$ec" > "$ec_file"
    } | tee -a "$log" | _xcbuild_pretty

    _xcbuild_finalize "${run_dir:t}" "$(<"$ec_file" 2>/dev/null)"
}

_xcbuild_pretty() {
    # `--preserve-unbeautified` keeps our own banner lines (`── BUILD ────`,
    # `── ERRORS ────`, etc.) visible — without it, xcbeautify drops anything
    # that isn't a recognized xcodebuild pattern. `--disable-logging`
    # suppresses xcbeautify's own startup version table.
    if command -v xcbeautify >/dev/null 2>&1; then
        xcbeautify --preserve-unbeautified --disable-logging
    else
        cat
    fi
}

_xcbuild_extract_errors() {
    # Match clang/swiftc/ld/xcodebuild error lines and include 2 lines of
    # source context (the code line and the `^` pointer that follow clang
    # diagnostics). `awk '!seen[$0]++'` dedupes identical error lines that
    # Xcode sometimes emits multiple times.
    grep -E -A 2 \
        -e '^error:' \
        -e '^ld: error' \
        -e '^clang: error' \
        -e '[[:space:]:]error:' \
        "$1" 2>/dev/null \
        | awk '!seen[$0]++'
}

_xcbuild_count_errors() {
    # Count deduped error lines so the summary header and the listed entries
    # agree. Errors are the grep-matching lines inside _xcbuild_extract_errors
    # output (which also includes context lines and `--` separators).
    _xcbuild_extract_errors "$1" \
        | grep -cE \
            -e '^error:' \
            -e '^ld: error' \
            -e '^clang: error' \
            -e '[[:space:]:]error:'
    return 0
}

_xcbuild_deploy() {
    local run_dir="$1"
    local meta=$(<"$run_dir/meta.json")
    local project project_flag scheme dest_id dest_plat
    project=$(jq -r '.project'              <<<"$meta")
    project_flag=$(jq -r '.project_flag'    <<<"$meta")
    scheme=$(jq -r '.scheme'                <<<"$meta")
    dest_id=$(jq -r '.destination_id'       <<<"$meta")
    dest_plat=$(jq -r '.destination_platform'<<<"$meta")

    print -- "Resolving build settings…"
    local settings
    settings=$(xcodebuild -showBuildSettings \
        "$project_flag" "$project" \
        -scheme "$scheme" \
        -destination "id=$dest_id" \
        -configuration Debug 2>/dev/null) || {
        print -u2 "Failed to read build settings."
        return 1
    }

    local built_dir product bundle_id app_path
    built_dir=$(awk -F' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR = / {print $2; exit}' <<<"$settings")
    product=$(awk -F' = ' '/^[[:space:]]*FULL_PRODUCT_NAME = / {print $2; exit}' <<<"$settings")
    bundle_id=$(awk -F' = ' '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = / {print $2; exit}' <<<"$settings")
    app_path="$built_dir/$product"

    print -- "App:         $app_path"
    print -- "Bundle ID:   $bundle_id"

    if [[ ! -d "$app_path" ]]; then
        print -u2 "App not found at $app_path"
        return 1
    fi

    case "$dest_plat" in
        *Simulator*)
            print -- "Booting simulator (no-op if already booted)…"
            xcrun simctl boot "$dest_id" 2>/dev/null
            print -- "Installing on simulator…"
            xcrun simctl install "$dest_id" "$app_path" || return 1
            if [[ -n "$bundle_id" ]]; then
                print -- "Launching ${bundle_id}…"
                xcrun simctl launch "$dest_id" "$bundle_id" || return 1
            fi
            ;;
        *)
            print -- "Installing on device…"
            xcrun devicectl device install app --device "$dest_id" "$app_path" || return 1
            if [[ -n "$bundle_id" ]]; then
                print -- "Launching ${bundle_id}…"
                xcrun devicectl device process launch --device "$dest_id" "$bundle_id" || return 1
            fi
            ;;
    esac
}

_xcbuild_finalize() {
    local id="$1" ec="${2:-1}"
    local meta_file="$XCBUILD_RUNS_DIR/$id/meta.json"
    [[ -f "$meta_file" ]] || return 0

    local ended run_status icon wid wbase
    ended=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [[ "$ec" == "0" ]]; then
        run_status="success"; icon="✓"
    else
        run_status="failed";  icon="✗"
    fi
    wid=$(jq -r '.tmux_window_id // ""' "$meta_file")
    wbase=$(jq -r '.tmux_window_basename // ""' "$meta_file")

    local tmp
    tmp=$(mktemp)
    jq --arg ended "$ended" --argjson ec "${ec:-1}" --arg s "$run_status" \
       '.ended_at=$ended | .exit_code=$ec | .status=$s' \
       "$meta_file" > "$tmp" && mv "$tmp" "$meta_file"

    if [[ -n "$wid" && -n "$wbase" ]] && _xcbuild_window_alive "$wid"; then
        tmux rename-window -t "$wid" "$icon $wbase" 2>/dev/null
    fi
}

_xcbuild_window_alive() {
    local wid="$1"
    [[ -z "$wid" ]] && return 1
    tmux list-windows -a -F '#{window_id}' 2>/dev/null | grep -qx "$wid"
}

# ── Viewer ──────────────────────────────────────────────────────────────────

_xcbuild_view() {
    local id="$1"
    local run_dir="$XCBUILD_RUNS_DIR/$id"
    [[ -d "$run_dir" ]] || { print -u2 "xcbuild: no run $id"; return 1; }
    local log="$run_dir/log"

    # Wait briefly for the runner to create the log file.
    local i
    for i in {1..20}; do
        [[ -s "$log" ]] && break
        sleep 0.05
    done
    [[ -f "$log" ]] || : > "$log"

    local run_status
    run_status=$(jq -r '.status' <"$run_dir/meta.json" 2>/dev/null)

    if [[ "$run_status" == "running" ]]; then
        # Live tail. tail -F exits on Ctrl-C with a single keystroke (unlike
        # `less +F`, which needs Ctrl-C + q). The build keeps running in its
        # tmux window regardless. Return 2 so the caller can close the popup
        # instead of bouncing back into the picker. Pipe through xcbeautify so
        # the live output is colorized just like the post-build viewer.
        {
            print -- $'\e[90m── live output · Ctrl-C to close (build keeps running) ──\e[0m'
            print -- ""
            tail -n +1 -F "$log"
        } | _xcbuild_pretty
        return 2
    elif command -v xcbeautify >/dev/null 2>&1; then
        xcbeautify --preserve-unbeautified --disable-logging < "$log" 2>/dev/null \
            | less -R +G
    else
        less -R +G "$log"
    fi
}

# ── Recent (quick-build history) ────────────────────────────────────────────

_xcbuild_recent_for_repo() {
    local repo="$1"
    jq -c --arg repo "$repo" '[.[] | select(.repo == $repo)]' "$XCBUILD_RECENT" 2>/dev/null \
        || print -- '[]'
}

_xcbuild_recent_update() {
    local repo="$1" cfg="$2"
    local now tmp
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    tmp=$(mktemp)

    # Drop any existing entry matching repo+project+scheme+destination, then
    # prepend a fresh entry with bumped use_count. Cap each repo at 10.
    jq -n --slurpfile cur "$XCBUILD_RECENT" \
          --argjson new "$cfg" \
          --arg repo "$repo" \
          --arg now "$now" '
        ($cur[0]) as $arr
        | ($arr | map(select(
            .repo == $repo
            and .project == $new.project
            and .scheme == $new.scheme
            and .destination_id == $new.destination_id
          ))[0] // {use_count: 0}) as $prev
        | ($arr | map(select(
            .repo != $repo
            or .project != $new.project
            or .scheme != $new.scheme
            or .destination_id != $new.destination_id
          ))) as $rest
        | ($new + {repo: $repo, last_used: $now,
                   use_count: ($prev.use_count + 1)}) as $entry
        | [$entry] + $rest
        | group_by(.repo)
        | map(sort_by(.last_used) | reverse | .[0:10])
        | flatten
        | sort_by(.last_used) | reverse
    ' > "$tmp" && mv "$tmp" "$XCBUILD_RECENT"
}

# ── Pruning ─────────────────────────────────────────────────────────────────

_xcbuild_delete_run() {
    # Explicit deletion (Ctrl-X in the picker). Kills the tmux window if it's
    # still alive — for active builds this aborts the running xcodebuild.
    local id="$1"
    local run_dir="$XCBUILD_RUNS_DIR/$id"
    [[ -d "$run_dir" ]] || return 0
    local wid
    wid=$(jq -r '.tmux_window_id // ""' <"$run_dir/meta.json" 2>/dev/null)
    [[ -n "$wid" ]] && tmux kill-window -t "$wid" 2>/dev/null
    rm -rf "$run_dir"
}

_xcbuild_prune() {
    setopt LOCAL_OPTIONS NULL_GLOB
    local -a dirs
    dirs=( "$XCBUILD_RUNS_DIR"/*(N/On) )
    (( ${#dirs[@]} <= XCBUILD_MAX_RUNS )) && return

    local d run_status wid
    for d in "${dirs[@]:$XCBUILD_MAX_RUNS}"; do
        if [[ -f "$d/meta.json" ]]; then
            run_status=$(jq -r '.status' <"$d/meta.json" 2>/dev/null)
            # Don't delete a still-running run.
            [[ "$run_status" == "running" ]] && continue
            wid=$(jq -r '.tmux_window_id // ""' <"$d/meta.json" 2>/dev/null)
            [[ -n "$wid" ]] && tmux kill-window -t "$wid" 2>/dev/null
        fi
        rm -rf "$d"
    done
}

# ── Pretty time ─────────────────────────────────────────────────────────────

_xcbuild_age() {
    local ts="$1"
    [[ -z "$ts" || "$ts" == "null" ]] && { print -- "?"; return; }
    local epoch
    epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" "+%s" 2>/dev/null) || {
        print -- "?"
        return
    }
    local now delta
    now=$(date -u +%s)
    delta=$(( now - epoch ))
    if   (( delta < 60 ));    then print -- "${delta}s ago"
    elif (( delta < 3600 ));  then print -- "$(( delta / 60 ))m ago"
    elif (( delta < 86400 )); then print -- "$(( delta / 3600 ))h ago"
    else                           print -- "$(( delta / 86400 ))d ago"
    fi
}
