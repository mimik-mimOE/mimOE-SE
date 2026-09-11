#!/bin/bash

#######################################################################
# mimOE AI Foundation Installer
#
# Acquires the four release packages, lays them out as a bundle, and
# hands the bundle to `mimoe-setup install --source` — which owns the
# on-disk layout, the atomic swap, PATH, addon .ini generation and
# daemon control. This script only *acquires* and then provisions the
# default model (model pull is not in mimoe-setup yet).
#
# The four packages (see SETUP.md for the naming convention):
#   1. runtime     mimOE-SE-developer-<platform>-<arch>-v<rel>.zip
#   2. addons      mimOE-addons-v<rel>.zip                (cross-platform)
#   3. extensions  mimoe-<backend>-<platform>-<arch>-v<ver>.zip  (one per backend)
#   4. setup       mimoe-setup-<platform>-<arch>-v<ver>.zip
#
# Usage:
#   curl -L https://... | bash                    # Production install
#   LOCAL_TEST=1 ./install-mimOE-ai.sh            # From a laid-out local bundle
#   LOCAL_HTTP=1 ./install-mimOE-ai.sh            # From localhost:8000
#######################################################################

# CHANNEL_BASE variable is an important url base address for packages, it can  
# be both remote and local url. Use local http address to do local http install. 

# `set -e`, deliberately WITHOUT `set -o pipefail`.
#
# The readiness polls below are `curl ... | grep -q`, and grep -q exits the
# moment it matches. If the response is larger than the pipe buffer, curl then
# takes a SIGPIPE and reports 141, which pipefail would surface as a failed
# pipeline even though grep succeeded — and the poll would stop breaking out of
# its loop. Today those responses are small enough that it does not trigger,
# which is exactly what makes it a bad trade: it would pass every test and then
# fail once a model list outgrows the buffer.
#
# The one pipeline whose left-hand status genuinely matters — the model
# download — captures curl's exit code explicitly instead. Turning pipefail on
# would mean converting every poll away from `| grep -q` first.
set -e

#######################################################################
# RELEASE MANIFEST
#
# Everything you edit for a new release OR a change to the package name
# format lives between here and the END marker. No code below this block
# constructs a package name — it only calls the pkg_* functions here.
#######################################################################

# --- versions --------------------------------------------------------

# The release id (BOM). The runtime and the addon set are published under it.
RELEASE="v3.30.26"

# mimoe-setup has its own cadence (separate repo, separate version).
SETUP_VERSION="v0.7.0"

# Per-backend versions: each backend's own manifest.json version, NOT the
# release id, so an unchanged backend keeps its number across a runtime bump.
# mcp_shell ships no manifest.json but is not versionless — mimoe-setup
# discovers its version by running `mcp_shell --version`.
# In a channel install these come from index.json; here they are the
# bootstrap default.
EXT_LLAMACPP_VERSION="v1.18.0"
EXT_ONNX_VERSION="v1.2.1"
EXT_MCP_SHELL_VERSION="v0.1.1"

# --- package name grammar --------------------------------------------
#
#   <component>[-<flavor>]-<platform>-<arch>[-<gpu>]-v<version>.zip
#
# Only the llamacpp backend carries a <gpu>, and it carries it inside its own
# name (mimoe-llamacpp-metal). Nothing else does: the runtime, the addon set,
# onnx, mcp_shell and setup are all GPU-agnostic. $GPU below exists solely to
# pick which llamacpp package to fetch.
#
# One line per package kind. To change the format, change it HERE and
# nowhere else. Keep in sync with install-mimOE-ai.bat and
# assemble-packages.sh; SETUP.md section 2 is the spec, and
# ./verify-naming.sh proves the three agree.
#
# These are functions rather than strings on purpose: $PLATFORM and $GPU are
# not known until detect_platform() runs, and a function body expands its
# variables at call time.

# The runtime carries NO gpu segment: bin/mimoe links no GPU library on any
# platform (no Metal, no Vulkan, no CUDA) — the GPU belongs entirely to the ML
# plugin, which is a separate package. The GPU tag on the old monolithic
# archives described the plugin bundled inside them, not the runtime.
pkg_runtime()   { echo "mimOE-SE-developer-${PLATFORM}-${RELEASE}.zip"; }
pkg_addons()    { echo "mimOE-addons-${RELEASE}.zip"; }
pkg_setup()     { echo "mimoe-setup-${PLATFORM}-${SETUP_VERSION}.zip"; }
pkg_extension() { echo "mimoe-$1-${PLATFORM}-$2.zip"; }   # $1 backend, $2 version

# --- which extensions each platform row ships ------------------------
#
# One "<backend>|<version>|<dest under extensions/>" line per package.
#
# The llamacpp backend name embeds the GPU, so it is per-row. onnx now does
# too on linux-arm64 (cuda vs cpu); mcp_shell stays arch-scoped.
# `backends` vs `mcp` differ because a backend is versioned and normalized
# from its own manifest.json, while an MCP server ships no descriptor and its
# folder name is literally what the gateway spawns.
#
# The rows do NOT all ship the same set, so each one states its own —
# collapsing them into a shared arm plus `if` tests is what produced a
# `[ a != x || a != y ]`, which is not valid `test` syntax at all: the shell
# splits it into two commands, the first missing its `]`, and the branch then
# never fires. Keep the sets declarative. Drop a line to stop shipping that
# package for a row; add one to start.
#
# Where the rows currently differ:
#   - linux-arm64-cuda takes onnx-cuda; every other row takes onnx-cpu.
#   - mcp_shell is published for macos-arm64 and windows-x64 only, so the two
#     linux rows omit it. (windows-x64 is install-mimOE-ai.bat's row, not one
#     of these.) Add the line back here when the linux packages ship.

extension_set() {
    case "${PLATFORM}-${GPU}" in
        macos-arm64-metal)
            echo "llamacpp-metal|${EXT_LLAMACPP_VERSION}|backends"
            echo "onnx-cpu|${EXT_ONNX_VERSION}|backends"
            echo "mcp-shell|${EXT_MCP_SHELL_VERSION}|mcp"
            ;;
        linux-x64-vulkan)
            echo "llamacpp-vulkan|${EXT_LLAMACPP_VERSION}|backends"
            echo "onnx-cpu|${EXT_ONNX_VERSION}|backends"
            ;;
        linux-arm64-cuda)
            echo "llamacpp-cuda|${EXT_LLAMACPP_VERSION}|backends"
            echo "onnx-cuda|${EXT_ONNX_VERSION}|backends"
            ;;
        linux-arm64-cpu)
            echo "llamacpp-cpu|${EXT_LLAMACPP_VERSION}|backends"
            echo "onnx-cpu|${EXT_ONNX_VERSION}|backends"
            ;;
        *) return 1 ;;
    esac
}

# --- endpoints and install target ------------------------------------

# Where published packages live. One base for all four.
CHANNEL_BASE="${CHANNEL_BASE:-https://github.com/mimik-mimOE/mimOE-SE/releases/download/${RELEASE}}"
#CHANNEL_BASE="${CHANNEL_BASE:-https://dl.mimik.com/mimoe/stable/${RELEASE}}"

# Install target. mimoe-setup defaults to this too; passed explicitly so the
# script and the binary can never disagree about where things went.
MIMOE_HOME="${MIMOE_HOME:-$HOME/.mimoe}"
MIMOE_LOG="$MIMOE_HOME/.edge/logs/mimoe.log"

API_KEY="1234"
DEFAULT_MODEL_ID="smollm2-360m"
DEFAULT_MODEL_URL="https://huggingface.co/lmstudio-community/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q8_0.gguf?download=true"

# LOCAL_TEST=1 — install straight from an already laid-out bundle dir
# (bin/ addon/ extensions/ mimoe.lic), skipping acquisition entirely.
LOCAL_BUNDLE_DIR="${LOCAL_BUNDLE_DIR:-$HOME/Workspace/mimoe-workspace/agent-harness-mim/ui/src-tauri/runtime-bundle-signed}"
# The locally built mimoe-setup. Host platform only — there is no
# cross-compiled binary sitting on a dev laptop.
LOCAL_SETUP_BIN="${LOCAL_SETUP_BIN:-$HOME/Workspace/mimoe-workspace/mimoe-setup/target/release/mimoe-setup}"

# LOCAL_HTTP=1 — same package names, served from a local http.server.
LOCAL_HTTP_BASE="${LOCAL_HTTP_BASE:-http://localhost:8000}"

#######################################################################
# END RELEASE MANIFEST — nothing below builds a package name
#######################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step()    { echo -e "\n${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1"; }

progress_bar() {
    local current=$1 total=$2 width=40
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    printf "\r  ["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%% (%d/%d MB)" "$percent" "$((current / 1048576))" "$((total / 1048576))"
}

# ---------------------------------------------------------------------
# Platform detection
#
# Emits the same tokens index.json keys on — macos-arm64 / linux-x64 /
# linux-arm64 / windows-x64 plus metal|vulkan|cuda|cpu — so every package
# name below is derivable from one release id and one index row.
# ---------------------------------------------------------------------

# Cold-start machines are the target, so the tools cannot be assumed present.
# unzip especially: it is absent from many minimal images, and without this
# check its absence surfaces from unzip_clean as "Corrupt or truncated
# package" — a confidently wrong diagnosis of a missing-dependency problem.
check_prerequisites() {
    local missing=""
    command -v curl >/dev/null 2>&1 || missing="curl"
    # LOCAL_TEST installs from a laid-out dir, so nothing is ever unzipped.
    if [ "$LOCAL_TEST" != "1" ] && ! command -v unzip >/dev/null 2>&1; then
        missing="${missing:+$missing }unzip"
    fi
    if [ -n "$missing" ]; then
        print_error "Missing required tool(s): $missing"
        print_error "Install and re-run, e.g.  sudo apt-get install -y $missing"
        exit 1
    fi
}

check_ubuntu_compatibility() {
    if [ -f /etc/os-release ] && grep -qi "ubuntu" /etc/os-release; then
        local distro_ver major_ver
        distro_ver=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
        major_ver=$(echo "$distro_ver" | cut -d. -f1)
        if [ "$major_ver" -lt 22 ]; then
            print_error "Unsupported Ubuntu ($distro_ver). 22.04+ required for GLIBC 2.34."
            exit 1
        fi
    fi
}

detect_platform() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    if [ "$OS" = "darwin" ]; then
        if [ "$ARCH" != "arm64" ]; then
            print_error "macOS Intel (x86_64) is not supported. Apple Silicon required."
            exit 1
        fi
        PLATFORM="macos-arm64"
        GPU="metal"
    elif [ "$OS" = "linux" ]; then
        if [ "$ARCH" = "x86_64" ]; then
            PLATFORM="linux-x64"
            GPU="vulkan"
            check_ubuntu_compatibility
        elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
            PLATFORM="linux-arm64"
            # Jetson/Tegra gets the CUDA build; every other arm64 box is CPU-only.
            if uname -r | grep -qi tegra; then
                GPU="cuda"
            else
                GPU="cpu"
            fi
        else
            print_error "Unsupported architecture for Linux: $ARCH"
            exit 1
        fi
    else
        print_error "Unsupported operating system: $OS"
        exit 1
    fi

    print_success "Detected platform: ${PLATFORM}-${GPU}"
}

# Fill in the package names for the detected platform, using only the
# pkg_* grammar and extension_set() from the RELEASE MANIFEST block above.
#
# EXTENSIONS ends up as "<package-name>|<dest-subdir-under-extensions>".
resolve_packages() {
    RUNTIME_PKG="$(pkg_runtime)"
    ADDONS_PKG="$(pkg_addons)"
    SETUP_PKG="$(pkg_setup)"

    local rows backend ver dest
    if ! rows="$(extension_set)"; then
        print_error "No extension set defined for ${PLATFORM}-${GPU}"
        exit 1
    fi

    EXTENSIONS=()
    while IFS='|' read -r backend ver dest; do
        [ -n "$backend" ] || continue
        EXTENSIONS+=("$(pkg_extension "$backend" "$ver")|$dest")
    done <<< "$rows"
}

# ---------------------------------------------------------------------
# Acquisition
# ---------------------------------------------------------------------

# Extract a zip, then prune macOS archiver metadata.
#
# A __MACOSX/ dir landing in extensions/backends/ reads as a package and
# mimoe-setup rejects the whole bundle ("backend package __MACOSX is not
# installable"). Pruning after the fact beats `unzip -x`, which prints a
# "caution: excluded filename not matched" line for every clean archive.
unzip_clean() {
    local archive="$1" dest="$2"
    # This is also the integrity check: with no checksum sidecar, a truncated or
    # corrupt download shows up here and must not be allowed to pass.
    if ! unzip -q -o "$archive" -d "$dest"; then
        print_error "Corrupt or truncated package: $(basename "$archive")"
        exit 1
    fi
    rm -rf "$dest/__MACOSX"
    find "$dest" -name "._*" -delete 2>/dev/null || true
}

# Download one package.
#
# There is deliberately no checksum sidecar: a package must stay copyable and
# renameable by hand without anything else needing to be regenerated to match.
# Integrity is covered anyway — `curl -f` fails on an HTTP error or a short
# transfer, and because every package is a .zip, unzip_clean fails loudly on a
# truncated or corrupt one.
fetch_package() {
    local name="$1" dest_dir="$2"
    local url="${PACKAGE_BASE}/${name}"
    local out="${dest_dir}/${name}"

    echo "  ${name}"
    curl -fL --progress-bar -o "$out" "$url" || {
        print_error "Download failed: $url"
        exit 1
    }

    # A GitHub/S3 404 page is a 200 with HTML in some proxy setups.
    if head -c 512 "$out" | grep -q "<!DOCTYPE\|<html"; then
        print_error "Download returned HTML, not an archive: $url"
        exit 1
    fi
}

# Lay the four packages out as the bundle dir mimoe-setup --source expects:
#   bin/  addon/  extensions/  mimoe.lic  mimoe-config.env
build_bundle() {
    print_step "Acquiring release ${RELEASE} for ${PLATFORM}-${GPU}..."

    STAGE="$TMPDIR_INSTALL/download"
    BUNDLE="$TMPDIR_INSTALL/bundle"
    mkdir -p "$STAGE" "$BUNDLE/addon" "$BUNDLE/extensions/backends" "$BUNDLE/extensions/mcp"

    # 1. runtime — carries bin/mimoe, mimoe.lic and mimoe-config.env
    fetch_package "$RUNTIME_PKG" "$STAGE"
    unzip_clean "$STAGE/$RUNTIME_PKG" "$BUNDLE"

    # 2. addons — cross-platform, the whole tested-together set. Flat .addon
    #    files; tolerate a zip that wraps them in addon/.
    fetch_package "$ADDONS_PKG" "$STAGE"
    unzip_clean "$STAGE/$ADDONS_PKG" "$STAGE/addons-x"
    find "$STAGE/addons-x" -name "*.addon" -exec cp {} "$BUNDLE/addon/" \;

    # 3. extensions — one zip per backend, each its own notarized artifact
    local entry pkg dest
    for entry in "${EXTENSIONS[@]}"; do
        pkg="${entry%%|*}"
        dest="${entry##*|}"
        fetch_package "$pkg" "$STAGE"
        unzip_clean "$STAGE/$pkg" "$BUNDLE/extensions/$dest"
    done

    # 4. mimoe-setup — the installer itself
    fetch_package "$SETUP_PKG" "$STAGE"
    unzip_clean "$STAGE/$SETUP_PKG" "$STAGE/setup-x"
    SETUP_BIN="$STAGE/setup-x/mimoe-setup"
    if [ ! -f "$SETUP_BIN" ]; then
        SETUP_BIN=$(find "$STAGE/setup-x" -name "mimoe-setup" -type f | head -1)
    fi
    if [ -z "$SETUP_BIN" ] || [ ! -f "$SETUP_BIN" ]; then
        print_error "mimoe-setup binary not found in $SETUP_PKG"
        exit 1
    fi
    chmod 755 "$SETUP_BIN"

    print_success "All four packages acquired"
}

# LOCAL_TEST — the local bundle is already in --source shape, so there is
# nothing to acquire or stage. Same install code path, no LOCAL_* branch
# inside mimoe-setup.
use_local_bundle() {
    print_step "Using local bundle..."

    if [ ! -d "$LOCAL_BUNDLE_DIR/bin" ]; then
        print_error "Not a laid-out bundle (no bin/): $LOCAL_BUNDLE_DIR"
        print_error "Set LOCAL_BUNDLE_DIR to a dir with bin/ addon/ extensions/"
        exit 1
    fi
    BUNDLE="$LOCAL_BUNDLE_DIR"
    print_success "Bundle: $BUNDLE"

    if [ ! -x "$LOCAL_SETUP_BIN" ]; then
        print_error "No mimoe-setup binary at $LOCAL_SETUP_BIN"
        print_error "Build it: (cd mimoe-setup && cargo build --release)"
        exit 1
    fi
    SETUP_BIN="$LOCAL_SETUP_BIN"
    print_success "Installer: $($SETUP_BIN --version)"
}

# ---------------------------------------------------------------------
# Install — mimoe-setup owns everything from here to a running daemon
# ---------------------------------------------------------------------

run_setup() {
    print_step "Installing to $MIMOE_HOME..."

    # --source: a laid-out bundle, no manifest needed.
    # --start:  mimoe-setup launches the daemon after activation.
    # PATH wiring, addon .ini generation, the atomic rename-swap and
    # dist/ backups are all its job, not this script's.
    # `set -e` must not swallow the exit code — mimoe-setup's codes are the
    # stable contract (2 = already up to date is a success for us).
    local rc=0
    "$SETUP_BIN" install \
        --source "$BUNDLE" \
        --mimoe-dir "$MIMOE_HOME" \
        --start || rc=$?

    case $rc in
        0) print_success "mimOE installed" ;;
        2) print_success "Already up to date" ;;
        3) print_error "mimoe-setup verify failure"; exit 3 ;;
        4) print_error "Another installer holds the lock"; exit 4 ;;
        5) print_error "Health check failed — rolled back"; exit 5 ;;
        *) print_error "mimoe-setup install failed (exit $rc)"; exit $rc ;;
    esac
}

wait_for_runtime() {
    print_step "Waiting for mimOE runtime..."
    local max_attempts=30 attempt=0
    while [ $attempt -lt $max_attempts ]; do
        printf "\r${BLUE}⠋${NC} Waiting for mimOE runtime... (%d/%ds)" "$attempt" "$max_attempts"
        if curl -s "http://localhost:8083/jsonrpc/v1" -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"getMe","id":1}' > /dev/null 2>&1; then
            printf "\r%-60s\r" " "
            print_success "mimOE runtime is ready"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
        
        if [ $attempt == 5 ]; then
            mimoe start
        fi
        
    done
    printf "\r%-60s\r" " "
    print_error "Timeout waiting for runtime. Check $MIMOE_LOG"
    exit 1
}

# ---------------------------------------------------------------------
# Default model — still here because `mimoe-setup` parses default_models
# but does not pull them yet (deferred to a later phase).
# ---------------------------------------------------------------------

provision_model() {
    print_step "Provisioning default model (${DEFAULT_MODEL_ID})..."

    local base_url="http://localhost:8083/mimik-ai/store/v1"

    local max_wait=30 wait_count=0
    while [ $wait_count -lt $max_wait ]; do
        if curl -s "${base_url}/models" -H "Authorization: Bearer ${API_KEY}" 2>/dev/null | grep -q "\["; then
            break
        fi
        printf "\r  Waiting for AI Foundation addon to initialize... (%d/%ds)" "$wait_count" "$max_wait"
        sleep 1
        wait_count=$((wait_count + 1))
    done
    printf "\r%-60s\r" " "

    if [ $wait_count -ge $max_wait ]; then
        print_error "Timeout waiting for AI Foundation addon. Check $MIMOE_LOG"
        exit 1
    fi

    local existing
    existing=$(curl -s "${base_url}/models/${DEFAULT_MODEL_ID}" \
        -H "Authorization: Bearer ${API_KEY}" 2>/dev/null)
    if echo "$existing" | grep -q '"readyToUse":true'; then
        print_success "Model already installed and ready"
        return 0
    fi

    printf "  Creating model metadata..."
    local create_response
    create_response=$(curl -s -X POST "${base_url}/models" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d "{\"id\": \"${DEFAULT_MODEL_ID}\", \"version\": \"1.0.0\", \"kind\": \"llm\"}")

    if [ -z "$create_response" ]; then
        printf " failed\n"
        print_error "Failed to create model metadata: no response from API"
        exit 1
    fi
    if echo "$create_response" | grep -q "error"; then
        if echo "$create_response" | grep -q "already exists"; then
            printf " exists\n"
        else
            printf " failed\n"
            print_error "Failed to create model metadata: $create_response"
            exit 1
        fi
    else
        printf " done\n"
    fi

    echo "  Downloading model (~386MB)..."

    # The status of a pipeline is its RIGHTMOST command, so a curl failure here
    # would otherwise be masked by the while loop exiting 0 — and the script
    # would report a successful download that never happened. Stash curl's own
    # exit code and check it.
    local rc_file="$TMPDIR_INSTALL/model-download.rc"
    local body_file="$TMPDIR_INSTALL/model-download.out"
    {
        curl -s -N -X POST "${base_url}/models/${DEFAULT_MODEL_ID}/download" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${API_KEY}" \
            -d "{\"url\": \"${DEFAULT_MODEL_URL}\"}" 2>/dev/null
        echo $? > "$rc_file"
    } | tee "$body_file" | while IFS= read -r line; do
            if [[ "$line" == data:* ]]; then
                json="${line#data: }"
                current_size=$(echo "$json" | grep -o '"size":[0-9]*' | head -1 | cut -d: -f2)
                total_size=$(echo "$json" | grep -o '"totalSize":[0-9]*' | head -1 | cut -d: -f2)
                if [ -n "$current_size" ] && [ -n "$total_size" ] && [ "$total_size" -gt 0 ]; then
                    progress_bar "$current_size" "$total_size"
                fi
            fi
        done
    printf "\r%-76s\r" " "

    local dl_rc
    dl_rc=$(cat "$rc_file" 2>/dev/null || echo 1)
    if [ "$dl_rc" != "0" ]; then
        print_error "Model download request failed (curl exit $dl_rc)"
        print_error "Check $MIMOE_LOG"
        exit 1
    fi

    # curl's exit code only reports whether the LOCAL api answered, and
    # wait_for_runtime has already proved that it does — so it is 0 for every
    # realistic failure (bad model url, HuggingFace unreachable, no disk).
    # The store reports a failed fetch in the response BODY instead:
    #     {"error":{"code":500,"message":"Connection failed"}}
    # Checking the body is what actually separates a completed download from a
    # failed one. Without it this prints success and the real symptom surfaces
    # 120s later as "Timeout waiting for model to be ready", which sends you
    # looking at the runtime instead of at the url that would not fetch.
    if grep -q '"error"[[:space:]]*:' "$body_file"; then
        local msg
        msg=$(tr -d '\n' < "$body_file" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)
        print_error "Model download failed: ${msg:-$(tail -c 200 "$body_file")}"
        print_error "Check $MIMOE_LOG"
        exit 1
    fi
    print_success "Model download request completed"

    local max_attempts=60 attempt=0
    while [ $attempt -lt $max_attempts ]; do
        printf "\r  Verifying model is ready... (%d/%ds)" "$attempt" "$((max_attempts * 2))"
        local status
        status=$(curl -s "${base_url}/models/${DEFAULT_MODEL_ID}" \
            -H "Authorization: Bearer ${API_KEY}")
        if echo "$status" | grep -q '"readyToUse":true'; then
            printf "\r%-60s\r" " "
            print_success "Model is ready for inference"
            return 0
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    printf "\r%-60s\r" " "
    print_error "Timeout waiting for model to be ready"
    exit 1
}

# ---------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------

print_mimoe_status() {
    local get_me_info pid version
    get_me_info=$(curl -s "http://localhost:8083/jsonrpc/v1" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"getMe","id":1}' 2>/dev/null)
    # -x matches the process NAME exactly. `pgrep -f mimoe` matches any
    # command line containing "mimoe" — including this script's own, and
    # every mimoe-llamacpp-*-worker — so it reported arbitrary pids.
    pid=$(pgrep -x mimoe | head -n 1)

    if [[ "$get_me_info" == *"version"* ]]; then
        version=$(echo "$get_me_info" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$pid" ]; then
            print_success "mimOE [pid = $pid, version = $version] is running"
        else
            print_success "mimOE [version = $version] is running"
        fi
    elif [ -n "$pid" ]; then
        print_success "mimOE [pid = $pid] is running"
    fi
}

print_ready_message() {
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  mimOE AI Foundation is ready!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "  Installed to: ${BLUE}$MIMOE_HOME${NC}"
    echo -e "  Release:      ${BLUE}${RELEASE} (${PLATFORM}-${GPU})${NC}"
    echo ""
    echo "Test your setup with this command:"
    echo ""
    echo -e "${YELLOW}curl -X POST \"http://localhost:8083/mimik-ai/openai/v1/chat/completions\" \\
  -H \"Content-Type: application/json\" \\
  -H \"Authorization: Bearer ${API_KEY}\" \\
  -d '{
    \"model\": \"${DEFAULT_MODEL_ID}\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Complete this sentence: AI is like a\"}]
  }'${NC}"
    echo ""
    echo -e "${BLUE}To stop mimOE:${NC}        mimoe stop"
    echo -e "${BLUE}To start mimOE:${NC}       mimoe start"
    echo -e "${BLUE}To check status:${NC}      mimoe status"
    echo -e "${BLUE}To view logs:${NC}         tail -f $MIMOE_LOG"
    echo ""
    echo -e "${YELLOW}NOTE: To use 'mimoe' in this terminal, run:${NC}"
    echo "  export PATH=\"\$PATH:$MIMOE_HOME/bin\""
    echo ""
    echo "Documentation: https://developer.mimik.com/docs/ai-foundation"
    echo ""
}

# ---------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------

main() {
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║     mimOE AI Foundation Installer            ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""

    check_prerequisites
    detect_platform
    resolve_packages

    TMPDIR_INSTALL=$(mktemp -d)
    trap 'rm -rf "$TMPDIR_INSTALL"' EXIT

    if [ "$LOCAL_TEST" == "1" ]; then
        print_warning "LOCAL TEST mode — installing from a local bundle dir"
        use_local_bundle
    else
        if [ "$LOCAL_HTTP" == "1" ]; then
            print_warning "LOCAL HTTP mode (${LOCAL_HTTP_BASE})"
            PACKAGE_BASE="$LOCAL_HTTP_BASE"
        else
            PACKAGE_BASE="$CHANNEL_BASE"
        fi
        build_bundle
    fi

    # An already-running daemon is fine: mimoe-setup stops it for the swap
    # and `install` is the same code path as `upgrade`.
    if curl -s "http://localhost:8083/jsonrpc/v1" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"getMe","id":1}' > /dev/null 2>&1; then
        print_mimoe_status
        print_warning "mimoe-setup will stop it to activate the new release"
    fi

    run_setup
    wait_for_runtime
    provision_model
    print_ready_message
}

main "$@"
