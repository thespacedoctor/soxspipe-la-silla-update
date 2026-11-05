#!/usr/bin/env bash
#
# Replace the soxspipe install on the La Silla pipeline workstation with a fresh one.
# README.md explains when to run this script and what it does.
set -euo pipefail

SCRIPT_NAME="update-pipeline.sh"
PIPELINE_USER="pipeline"
RAW_DIR="/data/raw"
REDUCED_DIR="/data/reduced"
MINIFORGE_DIR="$HOME/miniforge3"
WORKSPACE_DIR="$HOME/soxspipe_reductions"
MINIFORGE_URL="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
PYTHON_VERSION="3.12"
MONIT_STOP_SECONDS="${MONIT_STOP_SECONDS:-30}"

DRY_RUN=false
DRY_RUN_PROBLEMS=0
MONIT_STOPPED=false
CURRENT_STEP="Starting up"
INSTALLER_DIR=""
SOXSPIPE_VERSION=""

usage() {
    cat <<USAGE
Usage: bash $SCRIPT_NAME [--dry-run | --help]

Stop monit, delete the old pipeline install, install the latest soxspipe,
prepare the workspace, and start monit. The script does not touch $REDUCED_DIR.

  --dry-run   Print every step and change nothing.
  --help      Print this message.
USAGE
}

step() {
    CURRENT_STEP="$1"
    echo "==> $1"
}

run() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "would run: $*"
        return 0
    fi
    echo "+ $*"
    "$@"
}

stop() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "would stop here: $*"
        DRY_RUN_PROBLEMS=$((DRY_RUN_PROBLEMS + 1))
        return 0
    fi
    echo "ERROR: $*" >&2
    exit 1
}

on_exit() {
    local exitCode=$?
    if [[ -n "$INSTALLER_DIR" ]]; then
        rm -rf "$INSTALLER_DIR"
    fi
    if [[ "$exitCode" -eq 0 || "$DRY_RUN" == true ]]; then
        return
    fi
    echo "FAILED during this step: $CURRENT_STEP." >&2
    if [[ "$MONIT_STOPPED" == true ]]; then
        echo "monit is stopped and this script did not restart it." >&2
    else
        echo "monit was not stopped and nothing was deleted." >&2
    fi
    echo "Fix the problem, then run this script again." >&2
}

has_fits_file() {
    # THE SAME FILE NAMES THAT `soxspipe prep` COUNTS AS RAW FRAMES
    [[ -n "$(find "$RAW_DIR/" \( -iname '*.fits' -o -name '*.[fF][iI][tT][sS].Z' \) -print -quit 2>/dev/null)" ]]
}

check_machine() {
    step "Checking the machine"
    [[ "$(id -un)" == "$PIPELINE_USER" ]] || stop "Run this script as the $PIPELINE_USER user."
    command -v monit >/dev/null || stop "The monit command is not available."
    command -v wget >/dev/null || stop "The wget command is not available."
    [[ -d "$REDUCED_DIR" ]] || stop "The folder $REDUCED_DIR does not exist."
    has_fits_file || stop "There are no FITS files in $RAW_DIR, so soxspipe prep cannot run."
}

# THE DOWNLOAD COMES BEFORE THE DELETE, SO A NETWORK FAILURE LEAVES THE OLD INSTALL WORKING
download_installer() {
    step "Downloading miniforge"
    if [[ "$DRY_RUN" == false ]]; then
        INSTALLER_DIR="$(mktemp -d)"
    fi
    run wget -nv -O "$INSTALLER_DIR/miniforge.sh" "$MINIFORGE_URL"
}

stop_monit() {
    step "Stopping monit"
    # `monit quit` FAILS WHEN MONIT IS ALREADY STOPPED, WHICH IS FINE
    run monit quit || true
    [[ "$DRY_RUN" == false ]] || return 0
    local waited=0
    while pgrep -u "$PIPELINE_USER" -x monit >/dev/null; do
        ((waited < MONIT_STOP_SECONDS)) || stop "monit did not stop after $MONIT_STOP_SECONDS seconds."
        sleep 1
        waited=$((waited + 1))
    done
    MONIT_STOPPED=true
}

running_soxspipe_processes() {
    # THE [s] STOPS AWK MATCHING ITSELF; THIS SCRIPT MAY SIT IN A FOLDER NAMED AFTER SOXSPIPE
    ps -eo pid=,args= | awk -v self="$SCRIPT_NAME" '/[s]oxspipe/ && index($0, self) == 0'
}

check_no_soxspipe_running() {
    step "Checking that soxspipe is not running"
    local processes
    processes="$(running_soxspipe_processes)"
    [[ -z "$processes" ]] || stop "soxspipe is still running. Wait for it to finish.
$processes"
}

remove_old_install() {
    step "Deleting the old install"
    run rm -rf "$MINIFORGE_DIR" "$HOME/.conda" "$HOME/.condarc" "$WORKSPACE_DIR"
}

# THESE TWO CHANGES REPLACE THE LOGOUT AND LOGIN STEPS OF THE OLD MANUAL PROCEDURE
leave_old_conda_environment() {
    unset "${!CONDA_@}" _CE_M _CE_CONDA
    PATH="$(tr ':' '\n' <<<"$PATH" | grep -vF "$MINIFORGE_DIR/" | paste -sd: -)"
}

install_miniforge() {
    step "Installing miniforge"
    leave_old_conda_environment
    run bash "$INSTALLER_DIR/miniforge.sh" -b -p "$MINIFORGE_DIR"
    run "$MINIFORGE_DIR/bin/conda" init bash
}

install_soxspipe() {
    step "Installing soxspipe"
    if [[ "$DRY_RUN" == true ]]; then
        echo "would run: conda create --yes --name soxspipe python=$PYTHON_VERSION soxspipe"
        echo "would run: conda activate soxspipe"
        return 0
    fi
    # CONDA'S SHELL FUNCTIONS READ UNSET VARIABLES, SO THIS STAYS OFF FROM HERE ON
    set +u
    # shellcheck source=/dev/null
    source "$MINIFORGE_DIR/etc/profile.d/conda.sh"
    run conda create --yes --name soxspipe "python=$PYTHON_VERSION" soxspipe
    run conda activate soxspipe
    SOXSPIPE_VERSION="$(conda list --name soxspipe --full-name soxspipe | awk '$1 == "soxspipe" {print $2}')"
}

prepare_workspace() {
    step "Preparing the workspace"
    run mkdir -p "$WORKSPACE_DIR"
    [[ "$DRY_RUN" == true ]] || cd "$WORKSPACE_DIR"
    run soxspipe prep . --vlt
    # `soxspipe prep` CAN EXIT WITH STATUS 0 AND LEAVE A PARTIAL WORKSPACE WITH A DATABASE BUT NO SESSION
    [[ "$DRY_RUN" == true || -f soxspipe.yaml ]] || stop "soxspipe prep did not finish: there is no soxspipe.yaml in $WORKSPACE_DIR."
}

start_monit() {
    step "Starting monit"
    run monit
}

report_result() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "Dry run finished with $DRY_RUN_PROBLEMS problem(s). Nothing changed."
        [[ "$DRY_RUN_PROBLEMS" -eq 0 ]]
        return
    fi
    echo "Finished: soxspipe $SOXSPIPE_VERSION is installed and monit is running."
}

main() {
    case "${1:-}" in
        "") ;;
        --dry-run) DRY_RUN=true ;;
        --help | -h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
    trap on_exit EXIT
    # THE WORKSPACE IS DELETED BELOW, AND THE USER MAY HAVE STARTED THE SCRIPT INSIDE IT
    cd "$HOME"

    check_machine
    download_installer
    stop_monit
    check_no_soxspipe_running
    remove_old_install
    install_miniforge
    install_soxspipe
    prepare_workspace
    start_monit
    report_result
}

main "$@"
