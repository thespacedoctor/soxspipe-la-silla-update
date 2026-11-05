#!/usr/bin/env bash
#
# BEHAVIOUR TESTS FOR update-pipeline.sh. RUN THESE WITH run-tests.sh, NEVER DIRECTLY.
set -uo pipefail

if [[ ! -f /.dockerenv ]]; then
    echo "These tests delete files in the home folder. Use tests/run-tests.sh." >&2
    exit 2
fi

SCRIPT="/repo/update-pipeline.sh"
SCRIPT_UNDER_TEST="$SCRIPT"
export STUBS_DIR="/repo/tests/stubs"
export CALLS="/tmp/calls.log"
export FAKE_DAEMON="/tmp/fake-daemon/monit"
OUTPUT="/tmp/output.log"
BIN_DIR="/tmp/fake-bin"
PASSED=0
FAILED=0

# REBUILD THE FAKE WORKSTATION: AN OLD INSTALL, RAW DATA, AND A RUNNING MONIT
reset_machine() {
    stop_fake_monit
    rm -rf "${HOME:?}"/miniforge3 "$HOME/.conda" "$HOME/.condarc" "$HOME/soxspipe_reductions" /data/raw/* /data/reduced/* "$BIN_DIR"
    : >"$CALLS"
    unset STUB_FAIL
    mkdir -p "$HOME/miniforge3/old" "$HOME/.conda" "$HOME/soxspipe_reductions" "$BIN_DIR"
    mkdir -p /data/raw/2026-01-19
    touch "$HOME/.condarc" "$HOME/.monitrc" /data/raw/2026-01-19/frame.fits /data/reduced/product.fits
    ln -s /data/raw "$HOME/soxspipe_reductions/raw"
    ln -sf "$STUBS_DIR/monit" "$STUBS_DIR/wget" "$BIN_DIR/"
    mkdir -p "$(dirname "$FAKE_DAEMON")"
    cp /bin/sleep "$FAKE_DAEMON"
    "$FAKE_DAEMON" 600 &
}

stop_fake_monit() {
    pkill -f "^$FAKE_DAEMON" || true
    while pgrep -x monit >/dev/null; do
        sleep 0.1
    done
}

rmdir_reduced() { rm -rf /data/reduced; }
restore_reduced() { mkdir -p /data/reduced; }

run_script() {
    PATH="$BIN_DIR:$PATH" bash "$SCRIPT_UNDER_TEST" "$@" >"$OUTPUT" 2>&1
    EXIT_CODE=$?
}

fail() {
    echo "    FAILED: $1"
    CURRENT_FAILED=1
}

assert_exit_zero() { [[ "$EXIT_CODE" -eq 0 ]] || fail "exit code was $EXIT_CODE: $(tail -3 "$OUTPUT")"; }
assert_exit_nonzero() { [[ "$EXIT_CODE" -ne 0 ]] || fail "exit code was 0"; }
assert_exists() { [[ -e "$1" ]] || fail "$1 is missing"; }
assert_missing() { [[ ! -e "$1" ]] || fail "$1 still exists"; }
assert_output() { grep -qF -- "$1" "$OUTPUT" || fail "output lacks '$1': $(tail -3 "$OUTPUT")"; }
assert_called() { grep -qF -- "$1" "$CALLS" || fail "'$1' was not called"; }
assert_not_called() { if grep -qF -- "$1" "$CALLS"; then fail "'$1' was called"; fi; }
assert_order() {
    local first second
    first="$(grep -nF -- "$1" "$CALLS" | head -1 | cut -d: -f1)"
    second="$(grep -nF -- "$2" "$CALLS" | head -1 | cut -d: -f1)"
    [[ -n "$first" && -n "$second" && "$first" -lt "$second" ]] || fail "'$1' did not come before '$2'"
}
assert_last_call() { [[ "$(tail -1 "$CALLS")" == "$1" ]] || fail "last call was '$(tail -1 "$CALLS")', not '$1'"; }
assert_monit_running() { pgrep -x monit >/dev/null || fail "monit is not running"; }
assert_monit_stopped() { if pgrep -x monit >/dev/null; then fail "monit is running"; fi; }
assert_old_install_kept() { assert_exists "$HOME/miniforge3/old"; assert_exists "$HOME/.condarc"; }

scenario() {
    CURRENT_FAILED=0
    reset_machine
    "$1"
    if [[ "$CURRENT_FAILED" -eq 0 ]]; then
        echo "ok      $1"
        PASSED=$((PASSED + 1))
    else
        echo "FAILED  $1"
        FAILED=$((FAILED + 1))
    fi
}

test_full_update_replaces_install_and_starts_monit() {
    run_script
    assert_exit_zero
    assert_missing "$HOME/miniforge3/old"
    assert_missing "$HOME/.conda"
    assert_missing "$HOME/.condarc"
    assert_exists "$HOME/soxspipe_reductions/soxspipe.yaml"
    assert_exists "$HOME/.monitrc"
    assert_exists /data/raw/2026-01-19/frame.fits
    assert_exists /data/reduced/product.fits
    assert_order "monit quit" "installer -b -p $HOME/miniforge3"
    assert_called "conda init bash"
    assert_called "conda create --yes --name soxspipe python=3.12 soxspipe"
    assert_called "soxspipe prep . --vlt cwd=$HOME/soxspipe_reductions"
    assert_last_call "monit "
    assert_monit_running
    assert_output "soxspipe 9.9.9"
}

test_stops_before_deleting_when_soxspipe_is_running() {
    cp /bin/sleep /tmp/soxspipe-reduction
    /tmp/soxspipe-reduction 600 &
    local reduction=$!
    run_script
    kill "$reduction"
    wait "$reduction" 2>/dev/null
    assert_exit_nonzero
    assert_old_install_kept
    assert_output "soxspipe-reduction"
    assert_not_called "installer"
    assert_last_call "monit quit"
}

test_does_not_mistake_itself_for_a_running_soxspipe() {
    mkdir -p "$HOME/soxspipe-la-silla-update"
    cp "$SCRIPT" "$HOME/soxspipe-la-silla-update/update-pipeline.sh"
    SCRIPT_UNDER_TEST="$HOME/soxspipe-la-silla-update/update-pipeline.sh"
    run_script
    SCRIPT_UNDER_TEST="$SCRIPT"
    rm -rf "$HOME/soxspipe-la-silla-update"
    assert_exit_zero
}

test_stops_before_touching_anything_when_raw_folder_has_no_fits() {
    rm /data/raw/2026-01-19/frame.fits
    touch /data/raw/notes.txt
    run_script
    assert_exit_nonzero
    assert_old_install_kept
    assert_monit_running
    assert_not_called "monit quit"
    assert_output "/data/raw"
}

test_accepts_compressed_fits_in_a_subfolder_of_raw() {
    rm /data/raw/2026-01-19/frame.fits
    mkdir -p /data/raw/2026-11-05
    touch /data/raw/2026-11-05/frame.fits.Z
    run_script
    assert_exit_zero
}

test_stops_when_reduced_folder_is_missing() {
    rmdir_reduced
    run_script
    restore_reduced
    assert_exit_nonzero
    assert_old_install_kept
    assert_output "/data/reduced"
}

test_refuses_to_run_as_another_user() {
    printf '#!/usr/bin/env bash\necho someone-else\n' >"$BIN_DIR/id"
    chmod +x "$BIN_DIR/id"
    run_script
    assert_exit_nonzero
    assert_old_install_kept
    assert_monit_running
    assert_output "Run this script as the pipeline user"
}

test_refuses_to_run_with_a_wrong_home_folder() {
    mkdir -p /tmp/other-home/miniforge3
    HOME=/tmp/other-home run_script
    assert_exit_nonzero
    assert_exists /tmp/other-home/miniforge3
    assert_old_install_kept
    assert_output "HOME is not the home folder of the pipeline user"
    rm -rf /tmp/other-home
}

test_stops_before_touching_anything_when_a_frame_is_directly_in_raw() {
    touch /data/raw/loose.fits
    run_script
    assert_exit_nonzero
    assert_old_install_kept
    assert_monit_running
    assert_not_called "monit quit"
    assert_output "dated folder"
}

test_failed_download_leaves_old_install_and_monit_running() {
    export STUB_FAIL="wget"
    run_script
    assert_exit_nonzero
    assert_old_install_kept
    assert_monit_running
    assert_not_called "monit quit"
}

test_stops_when_monit_does_not_stop() {
    export STUB_FAIL="monit-quit"
    MONIT_STOP_SECONDS=1 run_script
    assert_exit_nonzero
    assert_old_install_kept
    assert_output "monit did not stop"
}

test_runs_when_monit_is_already_stopped() {
    stop_fake_monit
    run_script
    assert_exit_zero
    assert_monit_running
}

assert_stopped_with_monit_down() {
    assert_exit_nonzero
    assert_monit_stopped
    if grep -qx "monit " "$CALLS"; then fail "monit was started"; fi
    assert_output "$1"
    assert_output "monit is stopped"
    if grep -q "^Finished" "$OUTPUT"; then fail "script reported success"; fi
}

test_failed_miniforge_install_stops_and_leaves_monit_stopped() {
    export STUB_FAIL="installer"
    run_script
    assert_stopped_with_monit_down "Installing miniforge"
    assert_not_called "conda create"
}

test_failed_environment_create_stops_and_leaves_monit_stopped() {
    export STUB_FAIL="conda-create"
    run_script
    assert_stopped_with_monit_down "Installing soxspipe"
    assert_not_called "soxspipe prep"
}

test_failed_prep_stops_and_leaves_monit_stopped() {
    export STUB_FAIL="prep"
    run_script
    assert_stopped_with_monit_down "Preparing the workspace"
}

test_prep_that_exits_zero_without_finishing_counts_as_a_failure() {
    export STUB_FAIL="prep-silent"
    run_script
    assert_stopped_with_monit_down "soxspipe.yaml"
}

test_failed_monit_start_is_reported() {
    export STUB_FAIL="monit-start"
    run_script
    assert_exit_nonzero
    assert_output "FAILED during this step: Starting monit"
}

test_monit_that_exits_zero_but_is_not_running_is_a_failure() {
    export STUB_FAIL="monit-start-silent"
    run_script
    assert_exit_nonzero
    assert_output "FAILED during this step: Starting monit"
}

test_missing_version_counts_as_a_failure() {
    export STUB_FAIL="no-version"
    run_script
    assert_stopped_with_monit_down "version"
}

test_removes_installer_after_success_and_failure() {
    run_script
    assert_exit_zero
    [[ -z "$(find /tmp -maxdepth 2 -name 'miniforge.sh')" ]] || fail "installer left after success"
    reset_machine
    export STUB_FAIL="installer"
    run_script
    [[ -z "$(find /tmp -maxdepth 2 -name 'miniforge.sh')" ]] || fail "installer left after failure"
}

test_runs_from_inside_the_workspace_it_deletes() {
    cd "$HOME/soxspipe_reductions" || return
    run_script
    cd "$HOME" || return
    assert_exit_zero
    assert_called "cwd=$HOME"
}

test_ignores_an_activated_conda_environment() {
    CONDA_PREFIX="$HOME/miniforge3/envs/soxspipe" CONDA_DEFAULT_ENV="soxspipe" CONDA_SHLVL=2 run_script
    assert_exit_zero
    assert_called "CONDA_PREFIX= "
}

test_dry_run_prints_every_step_and_changes_nothing() {
    local before
    before="$(find "$HOME" /data /tmp -not -path /tmp/output.log | sort)"
    run_script --dry-run
    assert_exit_zero
    [[ "$before" == "$(find "$HOME" /data /tmp -not -path /tmp/output.log | sort)" ]] || fail "files changed"
    [[ ! -s "$CALLS" ]] || fail "dry run called: $(cat "$CALLS")"
    assert_monit_running
    assert_output "<temporary folder>/miniforge.sh https://github.com"
    assert_output "bash <temporary folder>/miniforge.sh"
    assert_output "monit quit"
    assert_output "rm -rf $HOME/miniforge3 $HOME/.conda $HOME/.condarc $HOME/soxspipe_reductions"
    assert_output "-b -p $HOME/miniforge3"
    assert_output "conda init bash"
    assert_output "conda create --yes --name soxspipe python=3.12 soxspipe"
    assert_output "conda activate soxspipe"
    assert_output "soxspipe prep . --vlt"
    assert_output "Starting monit"
}

test_dry_run_reports_a_problem_and_still_prints_every_step() {
    rm /data/raw/2026-01-19/frame.fits
    run_script --dry-run
    assert_exit_nonzero
    assert_output "/data/raw"
    assert_output "soxspipe prep . --vlt"
    [[ ! -s "$CALLS" ]] || fail "dry run called: $(cat "$CALLS")"
}

test_rejects_an_unknown_option_without_changing_anything() {
    run_script --force
    assert_exit_nonzero
    assert_old_install_kept
    assert_output "Usage"
    [[ ! -s "$CALLS" ]] || fail "called: $(cat "$CALLS")"
}

test_help_prints_usage_without_changing_anything() {
    run_script --help
    assert_exit_zero
    assert_output "--dry-run"
    assert_old_install_kept
}

for name in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do
    scenario "$name"
done
echo "$PASSED passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
