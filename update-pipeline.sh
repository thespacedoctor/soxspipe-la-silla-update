#!/usr/bin/env bash
#
# REPLACE THE SOXSPIPE INSTALL ON THE LA SILLA PIPELINE WORKSTATION WITH A FRESH ONE.
# README.md EXPLAINS WHEN TO RUN THIS SCRIPT AND WHAT IT DOES.
set -euo pipefail

SCRIPT_NAME="update-pipeline.sh"
PIPELINE_USER="pipeline"
RAW_DIR="/data/raw"
REDUCED_DIR="/data/reduced"
# THE MONIT FILES HARDCODE THIS PATH
EXPECTED_HOME="/diska/home/pipeline"
MINIFORGE_DIR="$HOME/miniforge3"
WORKSPACE_DIR="$HOME/soxspipe_reductions"
MINIFORGE_URL="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
MONIT_FILES_URL="https://raw.githubusercontent.com/thespacedoctor/soxspipe-la-silla-update/main/monit"
MONIT_DIR="$HOME/monit"
MONIT_HTTPD_FILE="$MONIT_DIR/monit-httpd.conf"
SLACK_WEBHOOK_FILE="$MONIT_DIR/slack-webhook-url"
ENVIRONMENT_DIR="$MINIFORGE_DIR/envs/soxspipe"
PYTHON_VERSION="3.12"
MONIT_STOP_SECONDS="${MONIT_STOP_SECONDS:-30}"

DRY_RUN=false
DRY_RUN_PROBLEMS=0
MONIT_STOPPED=false
CURRENT_STEP="Starting up"
TEMPORARY_DIR=""
DOWNLOAD_DIR="<temporary folder>"
SOXSPIPE_VERSION=""

usage() {
    cat <<USAGE
Usage: bash $SCRIPT_NAME [--dry-run | --help]

Stop monit, delete the old pipeline install, install the latest soxspipe,
prepare the workspace, install the monit files, and start monit. The script does not touch $REDUCED_DIR.

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
    if [[ -n "$TEMPORARY_DIR" ]]; then
        rm -rf "$TEMPORARY_DIR"
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

first_fits_file() {
    # THE SAME FILE NAMES THAT `soxspipe prep` COUNTS AS RAW FRAMES
    find "$RAW_DIR/" "$@" ! -type d \( -iname '*.fits' -o -name '*.[fF][iI][tT][sS].Z' \) -print -quit 2>/dev/null
}

check_machine() {
    step "Checking the machine"
    [[ "$(id -un)" == "$PIPELINE_USER" ]] || stop "Run this script as the $PIPELINE_USER user."
    # THE DELETE STEP WORKS FROM $HOME, SO IT MUST BE THE REAL HOME FOLDER OF THE ACCOUNT
    [[ "$HOME" == "$(getent passwd "$PIPELINE_USER" | cut -d: -f6)" ]] || stop "HOME is not the home folder of the $PIPELINE_USER user."
    [[ "$HOME" -ef "$EXPECTED_HOME" ]] || stop "The monit files need the home folder $EXPECTED_HOME, but HOME is $HOME."
    [[ -f "$MONIT_HTTPD_FILE" ]] || stop "The private file $MONIT_HTTPD_FILE is missing. The README tells you how to make it."
    [[ -f "$SLACK_WEBHOOK_FILE" ]] || echo "WARNING: $SLACK_WEBHOOK_FILE is missing, so monit will not send Slack alerts."
    command -v monit >/dev/null || stop "The monit command is not available."
    command -v wget >/dev/null || stop "The wget command is not available."
    [[ -d "$REDUCED_DIR" ]] || stop "The folder $REDUCED_DIR does not exist."
    [[ -n "$(first_fits_file)" ]] || stop "There are no FITS files in $RAW_DIR, so soxspipe prep cannot run."
    # `soxspipe prep --vlt` CANNOT FINISH WITH A FRAME OUTSIDE A DATED FOLDER, AND THE OLD INSTALL WOULD ALREADY BE GONE
    [[ -z "$(first_fits_file -maxdepth 1)" ]] || stop "FITS frames sit directly in $RAW_DIR. Move each one into its dated folder, such as $RAW_DIR/2026-01-19/."
}

# THE DOWNLOAD COMES BEFORE THE DELETE, SO A NETWORK FAILURE LEAVES THE OLD INSTALL WORKING
download_installer() {
    step "Downloading miniforge"
    if [[ "$DRY_RUN" == false ]]; then
        TEMPORARY_DIR="$(mktemp -d)"
        DOWNLOAD_DIR="$TEMPORARY_DIR"
    fi
    # WSXPL DOES NOT TRUST THE CERTIFICATE ISSUER THAT GITHUB DOWNLOADS USE
    run wget -nv --no-check-certificate -O "$DOWNLOAD_DIR/miniforge.sh" "$MINIFORGE_URL"
}

download_monit_files() {
    step "Downloading the monit files"
    local name
    for name in monitrc monit2slack.rb soxspipe-cycle.sh; do
        run wget -nv --no-check-certificate -O "$DOWNLOAD_DIR/$name" "$MONIT_FILES_URL/$name"
    done
}

# THIS COMES BEFORE THE DELETE, SO BAD SETTINGS LEAVE THE OLD INSTALL AND MONIT RUNNING.
# `monit -t` NEEDS THE PROGRAMS THAT THE SETTINGS NAME, SO THE TWO SCRIPTS GO IN FIRST.
install_monit_scripts() {
    step "Installing the monit scripts"
    run install -m 700 "$DOWNLOAD_DIR/monit2slack.rb" "$DOWNLOAD_DIR/soxspipe-cycle.sh" "$MONIT_DIR/"
    run chmod 600 "$MONIT_HTTPD_FILE"
    if [[ -f "$SLACK_WEBHOOK_FILE" ]]; then
        run chmod 600 "$SLACK_WEBHOOK_FILE"
    fi
    run chmod 700 "$DOWNLOAD_DIR/monitrc"
    run monit -t -c "$DOWNLOAD_DIR/monitrc"
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
    run bash "$DOWNLOAD_DIR/miniforge.sh" -b -p "$MINIFORGE_DIR"
    run "$MINIFORGE_DIR/bin/conda" init bash
}

install_soxspipe() {
    step "Installing soxspipe"
    # CONDA'S SHELL FUNCTIONS READ UNSET VARIABLES
    set +u
    if [[ "$DRY_RUN" == false ]]; then
        # shellcheck source=/dev/null
        source "$MINIFORGE_DIR/etc/profile.d/conda.sh"
    fi
    run conda create --yes --name soxspipe "python=$PYTHON_VERSION" soxspipe ruby
    run conda activate soxspipe
    if [[ "$DRY_RUN" == false ]]; then
        # monit2slack.rb NEEDS BOTH OF THESE. A MISSING RUBY IS WHAT STOPPED SLACK ALERTS BEFORE
        [[ -x "$ENVIRONMENT_DIR/bin/ruby" ]] || stop "There is no ruby in the soxspipe environment."
        [[ -f "$ENVIRONMENT_DIR/ssl/cert.pem" ]] || stop "There is no ssl/cert.pem in the soxspipe environment."
        SOXSPIPE_VERSION="$(conda list --name soxspipe --full-name soxspipe | awk '$1 == "soxspipe" {print $2}')"
        [[ -n "$SOXSPIPE_VERSION" ]] || stop "conda does not list a soxspipe version."
    fi
    set -u
}

prepare_workspace() {
    step "Preparing the workspace"
    run mkdir -p "$WORKSPACE_DIR"
    [[ "$DRY_RUN" == true ]] || cd "$WORKSPACE_DIR"
    run soxspipe prep . --vlt
    # `soxspipe prep` CAN EXIT WITH STATUS 0 AND LEAVE A PARTIAL WORKSPACE WITH A DATABASE BUT NO SESSION
    [[ "$DRY_RUN" == true || -f soxspipe.yaml ]] || stop "soxspipe prep did not finish: there is no soxspipe.yaml in $WORKSPACE_DIR."
}

install_monit_settings() {
    step "Installing the monit settings"
    # ONLY THE FIRST BACKUP HOLDS THE ORIGINAL SETTINGS, SO A RERUN KEEPS IT
    if [[ -f "$HOME/.monitrc" && ! -e "$HOME/.monitrc.bak" ]]; then
        run install -m 600 "$HOME/.monitrc" "$HOME/.monitrc.bak"
    fi
    run install -m 700 "$DOWNLOAD_DIR/monitrc" "$HOME/.monitrc"
}

start_monit() {
    step "Starting monit"
    run monit
    [[ "$DRY_RUN" == true ]] || pgrep -u "$PIPELINE_USER" -x monit >/dev/null || stop "monit is not running after the start command."
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
    download_monit_files
    install_monit_scripts
    stop_monit
    check_no_soxspipe_running
    remove_old_install
    install_miniforge
    install_soxspipe
    prepare_workspace
    install_monit_settings
    start_monit
    report_result
}

main "$@"
