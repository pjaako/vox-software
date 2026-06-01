#!/bin/bash

# --- UI Helpers ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

function info() { echo -e "${BLUE}info:${NC} $1"; }
function success() { echo -e "${GREEN}✓${NC} $1"; }
function warn() {
    if [ "$1" = "-n" ]; then
        shift
        echo -en "${YELLOW}$*${NC}"
    else
        echo -e "${YELLOW}$*${NC}"
    fi
}
function error() { echo -e "${RED}error:${NC} $1"; }
function task() { echo -ne "  ${BLUE}..${NC} $1... "; }
function step() { echo -e "\n${BOLD}${BLUE}==>${NC} ${BOLD}$1${NC}"; }
function print_OK() { echo -e "${GREEN}OK${NC}"; }
function print_failed() { echo -e "${RED}FAILED${NC}"; }

run_cmd() {
    if "$@"; then
        print_OK
    else
        print_failed
        exit 1
    fi
}

run_optional() {
    if "$@"; then
        print_OK
    else
        warn "SKIPPED"
        warn "Non-fatal command failed: $*"
    fi
}

run_block() {
    if bash -e -o pipefail -c "$1"; then
        print_OK
    else
        print_failed
        exit 1
    fi
}