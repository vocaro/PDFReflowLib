# Sourced by scripts/check-all.sh, and by tools/test_check_all_runs.py to test it: the bookkeeping
# of the gate runs' results directories, `pdfreflow-checks.*` in the scratch directory. Written for
# macOS's /bin/bash 3.2. macOS has no flock(1) to hold a lock for a run's lifetime, so a run is
# identified instead by a record in its directory.
#
# A run's directory holds an `owner` file: the PID of the check-all.sh process and that process's
# start time as ps reports it. A run is live while a process with that PID exists and started at
# that time; a PID the system has since given to another process does not match, so a recycled
# PID never keeps a finished run's directory.

# PID: prints the process's start time, in one form whatever the caller's time zone and locale;
# nothing, and a nonzero status, when there is no such process.
process_start_time() {
    local started
    started="$(LC_ALL=C TZ=UTC ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ')" || return 1
    started="${started# }"
    started="${started% }"
    [[ -n $started ]] || return 1
    printf '%s\n' "$started"
}

# DIRECTORY PID: records PID's process as the run that owns DIRECTORY.
record_run() {
    local started
    if ! started="$(process_start_time "$2")"; then
        echo "Cannot read the start time of process $2 to record it in $1." >&2
        return 1
    fi
    printf '%s %s\n' "$2" "$started" > "$1/owner"
}

# DIRECTORY: succeeds while the run recorded in DIRECTORY is still in progress. A directory with
# no record (an earlier version of the script wrote none) or whose process is gone is finished.
run_is_live() {
    local pid started current
    { read -r pid started < "$1/owner"; } 2>/dev/null || return 1
    [[ $pid =~ ^[0-9]+$ ]] || return 1
    current="$(process_start_time "$pid")" || return 1
    [[ $current == "$started" ]]
}

# SCRATCH: creates this run's results directory, owned by this shell's process ($$), and prints
# its path. It is made under a name the prune does not match, recorded, and only then renamed to
# its final `pdfreflow-checks.` name, so no prune ever sees it without its record. A name already
# taken by a kept run is never reused.
new_run_directory() {
    local staging final
    while :; do
        staging="$(mktemp -d "$1/.pdfreflow-checks.XXXXXX")" || return 1
        record_run "$staging" "$$" || { rm -rf "$staging"; return 1; }
        final="$1/pdfreflow-checks.${staging##*.}"
        if [[ ! -e $final ]]; then
            mv "$staging" "$final" || { rm -rf "$staging"; return 1; }
            printf '%s\n' "$final"
            return 0
        fi
        rm -rf "$staging"
    done
}

# SCRATCH KEPT_RUNS: removes all but the KEPT_RUNS most recent finished runs' directories, naming
# each one it removes. A run still in progress is left alone and not counted, so KEPT_RUNS
# finished runs are kept however many others are running. A staging directory whose run died
# before naming it is removed; one still being created is not.
prune_old_runs() {
    local kept=0 directory
    # Newest first, by modification time, so the ones kept are the ones just run.
    while IFS= read -r directory; do
        [[ -d $directory ]] || continue
        if run_is_live "$directory"; then
            echo "Leaving a run still in progress: $directory"
            continue
        fi
        kept=$((kept + 1))
        if [[ $kept -gt $2 ]]; then
            echo "Removing an earlier run's results: $directory"
            rm -rf "$directory"
        fi
    done < <(ls -dt "$1"/pdfreflow-checks.* 2>/dev/null)
    for directory in "$1"/.pdfreflow-checks.*; do
        if [[ -f $directory/owner ]] && ! run_is_live "$directory"; then rm -rf "$directory"; fi
    done
}
