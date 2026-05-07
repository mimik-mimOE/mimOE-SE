#!/bin/bash

#######################################################################
# mimOE AI Foundation Installer
#
# Installs mimOE runtime + AI Foundation addon to ~/.mimoe/ and
# provisions a default model for immediate inference.
#
# Usage:
#   curl -L https://... | bash          # Production install
#   LOCAL_TEST=1 ./install-mimOE-ai.sh  # Local testing
#######################################################################

set -e

# Installation target
MIMOE_HOME="$HOME/.mimoe"
MIMOE_BIN="$MIMOE_HOME/bin"
MIMOE_ADDON="$MIMOE_HOME/addon"
MIMOE_LOG="$MIMOE_HOME/.edge/logs/mimoe.log"

# Configuration
VERSION="3.24.4"
API_KEY="1234"
DEFAULT_MODEL_ID="smollm2-360m"
DEFAULT_MODEL_URL="https://huggingface.co/lmstudio-community/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q8_0.gguf?download=true"

# Local HTTP server for testing (run: python3 -m http.server 8000)
LOCAL_HTTP_BASE="http://localhost:8000"
ADDON_AI_VERSION=1.15.0
ADDON_MESH_VERSION=1.0.1
ADDON_AI_FILENAME=ai-foundation-$ADDON_AI_VERSION.addon

LOCAL_MACOS_ARM64_URL="${LOCAL_HTTP_BASE}/mimOE-SE/mimOE-ai-SE-macOS-developer-ARM64-v3.18.0-39-g474c155e.tar"
LOCAL_ADDON_URL="${LOCAL_HTTP_BASE}/mimOE-addon-ai-foundation/$ADDON_AI_FILENAME"

# Remote URLs (production)
PROD_MACOS_ARM64_URL="https://github.com/mimik-mimOE/mimOE-SE/releases/download/v${VERSION}/mimOE-ai-SE-macOS-developer-ARM64-v${VERSION}.zip"
PROD_LINUX_AMD64_URL="https://github.com/mimik-mimOE/mimOE-SE/releases/download/v${VERSION}/mimOE-ai-SE-linux-developer-X86_64-VULKAN-v${VERSION}.tar"
PROD_LINUX_ARM64_URL="https://github.com/mimik-mimOE/mimOE-SE/releases/download/v${VERSION}/mimOE-ai-SE-linux-developer-ARM64-v${VERSION}.tar"
PROD_LINUX_ARM64_CUDA_URL="https://github.com/mimik-mimOE/mimOE-SE/releases/download/v${VERSION}/mimOE-ai-SE-linux-developer-ARM64-CUDA-v${VERSION}.tar"
PROD_ADDON_URL="https://github.com/mimik-mimOE/mimOE-addon-ai-foundation/releases/download/v$ADDON_AI_VERSION/$ADDON_AI_FILENAME"
PROD_MESH_ADDON_URL="https://github.com/mimik-mimOE/mimOE-addon-mesh-foundation/releases/download/v$ADDON_MESH_VERSION/mesh-foundation-$ADDON_MESH_VERSION.addon"
#PROD_MESH_ADDON_URL="https://github.com/mimik-mimOE/mimOE-addon-mesh-foundation/releases/download/v1.0.1/mesh-foundation-1.0.1.addon"

# Select URLs based on mode
if [ "$LOCAL_HTTP" == "1" ]; then
    MACOS_ARM64_URL="$LOCAL_MACOS_ARM64_URL"
    ADDON_URL="$LOCAL_ADDON_URL"
    MESH_ADDON_URL="$PROD_MESH_ADDON_URL"
else
    MACOS_ARM64_URL="$PROD_MACOS_ARM64_URL"
    LINUX_AMD64_URL="$PROD_LINUX_AMD64_URL"
    LINUX_ARM64_URL="$PROD_LINUX_ARM64_URL"
    LINUX_ARM64_CUDA_URL="$PROD_LINUX_ARM64_CUDA_URL"
    ADDON_URL="$PROD_ADDON_URL"
    MESH_ADDON_URL="$PROD_MESH_ADDON_URL"
fi

# Local test paths (relative to script directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_RUNTIME_DIR="${SCRIPT_DIR}/mimOE-SE"
LOCAL_ADDON_DIR="${SCRIPT_DIR}/mimOE-addon-ai-foundation"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "\n${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Progress bar
progress_bar() {
    local current=$1
    local total=$2
    local width=40
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "\r  ["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%% (%d/%d MB)" "$percent" "$((current / 1048576))" "$((total / 1048576))"
}

# Check if ~/.mimoe already exists and is non-empty
check_existing_install() {
    if [ -d "$MIMOE_HOME" ]; then
        # Check if directory has any contents (ignoring . and ..)
        if [ -n "$(ls -A "$MIMOE_HOME" 2>/dev/null)" ]; then
            print_error "mimOE is already installed at $MIMOE_HOME"
            print_error "To reinstall, first remove the existing installation:"
            print_error "  rm -rf $MIMOE_HOME"
            exit 1
        fi
    fi
}

# Detect OS and architecture
check_ubuntu_compatibility() {
    if [ -f /etc/os-release ]; then
        if grep -qi "ubuntu" /etc/os-release; then
            DISTRO_VER=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
            MAJOR_VER=$(echo "$DISTRO_VER" | cut -d. -f1)
            if [ "$MAJOR_VER" -lt 22 ]; then
                print_error "Unsupported Ubuntu ($DISTRO_VER) OS Version. Ubuntu 22.04+ required for GLIBC 2.34 compatibility."
                exit 1
            fi
        fi
    fi
}

detect_platform() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    if [ "$OS" = "darwin" ]; then
        if [ "$ARCH" = "arm64" ]; then
            PLATFORM="macos-arm64"
            RUNTIME_URL="$MACOS_ARM64_URL"
        else
            print_error "macOS Intel (x86_64) is not supported. Apple Silicon (ARM64) required."
            exit 1
        fi
    elif [ "$OS" = "linux" ]; then
        if [ "$ARCH" = "x86_64" ]; then
            PLATFORM="linux-x64"
            RUNTIME_URL="$LINUX_AMD64_URL"
            check_ubuntu_compatibility
        elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
            TEGRA=$(uname -r | grep -i tegra || true)

            # Check device-tree model if TEGRA is empty from uname -r
            # This is essential because many Jetson environments use standard kernels
            PLATFORM="linux-arm64"
            if [ -z "$TEGRA" ]; then
                RUNTIME_URL="$LINUX_ARM64_URL"
            else
                RUNTIME_URL="$LINUX_ARM64_CUDA_URL"
            fi
        else
            print_error "Unsupported architecture for Linux: $ARCH"
            exit 1
        fi
    else
        print_error "Unsupported operating system: $OS"
        exit 1
    fi

    print_success "Detected platform: $PLATFORM"
}

# Download and extract runtime binary to ~/.mimoe/bin/
install_runtime() {
    print_step "Installing mimOE runtime..."

    # Create directory structure
    mkdir "$MIMOE_HOME"
 #   mkdir -p "$MIMOE_BIN"
 #   mkdir -p "$MIMOE_ADDON"

    # Extract to a temp directory, then copy the binary
    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" EXIT

    if [ "$LOCAL_TEST" == "1" ]; then
        RUNTIME_FILE=$(find "$LOCAL_RUNTIME_DIR" -name "*.tar" -o -name "*.zip" 2>/dev/null | head -1)
        if [ -z "$RUNTIME_FILE" ]; then
            print_error "No runtime archive found in $LOCAL_RUNTIME_DIR"
            exit 1
        fi
        print_success "Using local runtime: $(basename "$RUNTIME_FILE")"

        if [[ "$RUNTIME_FILE" == *.zip ]]; then
            unzip -o "$RUNTIME_FILE" -d "$tmpdir"
        else
            tar -xf "$RUNTIME_FILE" -C "$tmpdir"
        fi
    else
        local filename
        filename=$(basename "$RUNTIME_URL")
        echo "  Downloading runtime..."
        curl -L --progress-bar -o "$tmpdir/$filename" "$RUNTIME_URL"

        if grep -q "Not Found\|<!DOCTYPE\|<html" "$tmpdir/$filename" 2>/dev/null; then
            print_error "Download failed - file not found at URL: $RUNTIME_URL"
            exit 1
        fi

        echo "  Extracting..."
        if [[ "$filename" == *.zip ]]; then
            unzip -q -o "$tmpdir/$filename" -d "$tmpdir"
        else
            tar -xf "$tmpdir/$filename" -C "$tmpdir"
        fi
        rm "$tmpdir/$filename"
    fi

    #Copy content to ~/.mimoe/
    cp -a "$tmpdir/bin" "$MIMOE_HOME/"
    cp -a "$tmpdir/addon" "$MIMOE_HOME/"
    cp -a "$tmpdir/extensions" "$MIMOE_HOME/"
    cp  "$tmpdir/start.sh" "$MIMOE_HOME/"

    # Copy binary to ~/.mimoe/bin/
#    if [ -f "$tmpdir/bin/mimoe" ]; then
#        cp "$tmpdir/bin/mimoe" "$MIMOE_BIN/mimoe"
#    else
#        print_error "Runtime binary not found in archive (expected bin/mimoe)"
#        exit 1
#    fi

    # Copy license file if present
    local lic_file
    lic_file=$(find "$tmpdir" -maxdepth 1 -name "*.lic" 2>/dev/null | head -1)
    if [ -n "$lic_file" ]; then
        cp "$lic_file" "$MIMOE_HOME/"
    fi

    # Set permissions
    chmod 755 "$MIMOE_BIN/mimoe"

    # macOS: strip quarantine attributes
    if [ "$OS" = "darwin" ]; then
        xattr -cr "$MIMOE_HOME" 2>/dev/null || true
    fi

    print_success "Runtime installed to $MIMOE_HOME"
}

# Add ~/.mimoe/bin to PATH in shell profiles
setup_path() {
    print_step "Setting up PATH..."

    local path_line='export PATH="$PATH:$HOME/.mimoe/bin"'
    local path_comment='# mimOE runtime'

  if [ "$OS" = "darwin" ]; then
    # Always update ~/.zshrc (macOS default shell)
    local zshrc="$HOME/.zshrc"
    if [ ! -f "$zshrc" ] || ! grep -q '.mimoe/bin' "$zshrc" 2>/dev/null; then
        echo "" >> "$zshrc"
        echo "$path_comment" >> "$zshrc"
        echo "$path_line" >> "$zshrc"
        print_success "Added mimoe path to $zshrc"
    else
        print_success "Already mimoe path is in $zshrc"
    fi

    # Update ~/.bash_profile if it exists
    local bash_profile="$HOME/.bash_profile"
    if [ -f "$bash_profile" ]; then
        if ! grep -q '.mimoe/bin' "$bash_profile" 2>/dev/null; then
            echo "" >> "$bash_profile"
            echo "$path_comment" >> "$bash_profile"
            echo "$path_line" >> "$bash_profile"
            print_success "Added mimoe path to $bash_profile"
        else
            print_success "Already mimoe path is in $bash_profile"
        fi
    fi
  elif [ "$OS" = "linux" ]; then
    local bashrc="$HOME/.bashrc"
    if [ ! -f "$bashrc" ] || ! grep -q '.mimoe/bin' "$bashrc" 2>/dev/null; then
        echo "" >> "$bashrc"
        echo "$path_comment" >> "$bashrc"
        echo "$path_line" >> "$bashrc"
        print_success "Added mimoe path to $bashrc"
    else
        print_success "Already mimoe path is in $bashrc"
    fi

    local profile="$HOME/.profile"
    if [ ! -f "$profile" ] || ! grep -q '.mimoe/bin' "$profile" 2>/dev/null; then
        echo "" >> "$profile"
        echo "$path_comment" >> "$profile"
        echo "$path_line" >> "$profile"
        print_success "Added mimoe path to $profile"
    else
        print_success "Already mimoe path is in $profile"
    fi

  fi

    # Make mimoe available in this session
    export PATH="$PATH:$HOME/.mimoe/bin"
}

# Install AI Foundation addon
install_addon() {
    print_step "Installing AI Foundation addon..."

    if [ "$LOCAL_TEST" == "1" ]; then
        ADDON_FILE=$(find "$LOCAL_ADDON_DIR" -name "*.addon" 2>/dev/null | head -1)
        if [ -z "$ADDON_FILE" ]; then
            print_error "No addon file found in $LOCAL_ADDON_DIR"
            exit 1
        fi
        print_success "Using local addon: $(basename "$ADDON_FILE")"
        cp "$ADDON_FILE" "$MIMOE_ADDON/"
        ADDON_BASENAME=$(basename "$ADDON_FILE" .addon)
    else
        local addon_filename
        addon_filename=$(basename "$ADDON_URL")
        echo "  Downloading addon..."
        curl -L --progress-bar -o "$MIMOE_ADDON/$addon_filename" "$ADDON_URL"

        if grep -q "Not Found\|<!DOCTYPE\|<html" "$MIMOE_ADDON/$addon_filename" 2>/dev/null; then
            print_error "Download failed - file not found at URL: $ADDON_URL"
            rm -f "$MIMOE_ADDON/$addon_filename"
            exit 1
        fi

        ADDON_BASENAME="${addon_filename%.addon}"
    fi

    create_addon_ini "$ADDON_BASENAME"
    print_success "AI Foundation addon installed"
}

# Create custom .ini configuration for the AI addon
create_addon_ini() {
    local addon_name=$1
    local ini_file="$MIMOE_ADDON/${addon_name}.ini"

    print_step "Creating addon configuration (${addon_name}.ini)..."

    cat > "$ini_file" << 'EOF'
# AI Foundation addon configuration
# This file customizes environment variables for the addon mims.
# See: https://developer.mimik.com/docs/api/mcm#environment-variables

[milm-v1]
# API key for local development (any value works for local usage)
API_KEY=1234

# Extend execution timeout to 3 minutes for AI inference operations
# Default is 30 seconds, which may not be enough for larger models
MCM.MAX_EXECUTION_TIME_SEC=180

# Model Registry API key (milm uses this to communicate with mmodelstore)
# If you change MMODELSTORE_API_KEY below, update this value to match
# MMODELSTORE_API_KEY=1234

# [mmodelstore-v1]
# Model Registry API key
# IMPORTANT: If you change this, you must also set MMODELSTORE_API_KEY
# in the [milm-v1] section above to the same value
# API_KEY=1234
EOF

    print_success "Configuration file created"
}

# Install Mesh Foundation addon
install_mesh_addon() {
    print_step "Installing Mesh Foundation addon..."

    if [ "$LOCAL_TEST" == "1" ]; then
        LOCAL_MESH_ADDON_DIR="${SCRIPT_DIR}/mimOE-addon-mesh-foundation"
        MESH_ADDON_FILE=$(find "$LOCAL_MESH_ADDON_DIR" -name "*.addon" 2>/dev/null | head -1)
        if [ -z "$MESH_ADDON_FILE" ]; then
            print_error "No mesh addon file found in $LOCAL_MESH_ADDON_DIR"
            exit 1
        fi
        print_success "Using local mesh addon: $(basename "$MESH_ADDON_FILE")"
        cp "$MESH_ADDON_FILE" "$MIMOE_ADDON/"
        MESH_ADDON_BASENAME=$(basename "$MESH_ADDON_FILE" .addon)
    else
        local mesh_addon_filename
        mesh_addon_filename=$(basename "$MESH_ADDON_URL")
        echo "  Downloading mesh addon..."
        curl -L --progress-bar -o "$MIMOE_ADDON/$mesh_addon_filename" "$MESH_ADDON_URL"

        if grep -q "Not Found\|<!DOCTYPE\|<html" "$MIMOE_ADDON/$mesh_addon_filename" 2>/dev/null; then
            print_error "Download failed - file not found at URL: $MESH_ADDON_URL"
            rm -f "$MIMOE_ADDON/$mesh_addon_filename"
            exit 1
        fi

        MESH_ADDON_BASENAME="${mesh_addon_filename%.addon}"
    fi

    create_mesh_addon_ini "$MESH_ADDON_BASENAME"
    print_success "Mesh Foundation addon installed"
}

# Create custom .ini configuration for the mesh addon
create_mesh_addon_ini() {
    local addon_name=$1
    local ini_file="$MIMOE_ADDON/${addon_name}.ini"

    print_step "Creating mesh addon configuration (${addon_name}.ini)..."

    cat > "$ini_file" << 'EOF'
# Mesh Foundation addon configuration
# This file customizes environment variables for the addon mims.
# See: https://developer.mimik.com/docs/api/mcm#environment-variables

[minsight-v1]
# API key for local development (any value works for local usage)
API_KEY=1234
EOF

    print_success "Mesh configuration file created"
}

# Start mimOE runtime
start_runtime() {
    print_step "Starting mimOE runtime..."

    # Start mimoe daemon from ~/.mimoe/
    cd "$MIMOE_HOME"
    "$MIMOE_BIN/mimoe" start < /dev/null > /dev/null 2>&1 &
    print_success "Started mimoe daemon"

    # Wait for runtime to be ready
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        printf "\r${BLUE}⠋${NC} Starting mimOE runtime... (%d/%ds)" "$attempt" "$max_attempts"
        if curl -s "http://localhost:8083/jsonrpc/v1" -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"getMe","id":1}' > /dev/null 2>&1; then
            printf "\r%-60s\r" " "
            print_success "mimOE runtime is ready"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done

    printf "\r%-60s\r" " "
    print_error "Timeout waiting for runtime to start. Check $MIMOE_LOG"
    exit 1
}

# Provision default model
provision_model() {
    print_step "Provisioning default model (${DEFAULT_MODEL_ID})..."

    local base_url="http://localhost:8083/mimik-ai/store/v1"

    # Wait for AI Foundation addon to be ready
    local max_wait=30
    local wait_count=0
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

    # Check if model already exists and is ready
    local existing
    existing=$(curl -s "${base_url}/models/${DEFAULT_MODEL_ID}" \
        -H "Authorization: Bearer ${API_KEY}" 2>/dev/null)

    if echo "$existing" | grep -q '"readyToUse":true'; then
        print_success "Model already installed and ready"
        return 0
    fi

    # Create model metadata
    printf "  Creating model metadata..."
    local create_response
    create_response=$(curl -s -X POST "${base_url}/models" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d "{
            \"id\": \"${DEFAULT_MODEL_ID}\",
            \"version\": \"1.0.0\",
            \"kind\": \"llm\"
        }")

    if [ -z "$create_response" ]; then
        printf " failed\n"
        print_error "Failed to create model metadata: No response from API"
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

    # Check if model is already ready
    local status_response
    status_response=$(curl -s "${base_url}/models/${DEFAULT_MODEL_ID}" \
        -H "Authorization: Bearer ${API_KEY}")

    if echo "$status_response" | grep -q '"readyToUse":true'; then
        print_success "Model already provisioned and ready"
        return 0
    fi

    # Download model from Hugging Face
    echo "  Downloading model (~386MB)..."

    curl -s -N -X POST "${base_url}/models/${DEFAULT_MODEL_ID}/download" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d "{\"url\": \"${DEFAULT_MODEL_URL}\"}" 2>/dev/null | while IFS= read -r line; do
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
    print_success "Model download complete"

    # Wait for model to be ready
    local max_attempts=60
    local attempt=0

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

print_mimoe_status() {
    local get_me_info
    get_me_info=$(curl -s "http://localhost:8083/jsonrpc/v1" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"getMe","id":1}' 2>/dev/null)

    local pid version
    pid=$(pgrep -f mimoe | head -n 1)

    if [[ "$get_me_info" == *"version"* ]]; then
        version=$(echo "$get_me_info" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$pid" ]; then
            print_success "mimOE [pid = $pid, version = $version] is already running"
        else
            print_success "mimOE [version = $version] is already running"
        fi
    elif [ -n "$pid" ]; then
        print_success "mimOE [pid = $pid] is already running"
    fi
}

# Print success message
print_ready_message() {
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  mimOE AI Foundation is ready!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "  Installed to: ${BLUE}$MIMOE_HOME${NC}"
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
    echo -e "${BLUE}To stop mimOE:${NC}        pkill -f mimoe"
    echo -e "${BLUE}To start mimOE:${NC}       mimoe start"
    echo -e "${BLUE}To check status:${NC}      mimoe status"
    echo -e "${BLUE}To view logs:${NC}         tail -f $MIMOE_LOG"
    echo ""
    echo -e "${YELLOW}NOTE: To use 'mimoe' in this terminal, run:${NC}"
    echo "  export PATH=\"\$PATH:\$HOME/.mimoe/bin\""
    echo ""
    echo -e "${YELLOW}Otherwise, open a new terminal to use the mimoe PATH set in your profile.${NC}"
    echo ""
    echo "Documentation: https://developer.mimik.com/docs/ai-foundation"
    echo ""
}

# Main installation flow
main() {
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║     mimOE AI Foundation Installer            ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""

    if [ "$LOCAL_TEST" == "1" ]; then
        print_warning "Running in LOCAL TEST mode (file copy)"
    fi

    if [ "$LOCAL_HTTP" == "1" ]; then
        print_warning "Running in LOCAL HTTP mode (${LOCAL_HTTP_BASE})"
    fi

    # Check if mimOE is already running
    if curl -s "http://localhost:8083/jsonrpc/v1" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"getMe","id":1}' > /dev/null 2>&1; then
        print_mimoe_status
        print_warning "mimOE is already running. To re-install, stop it first using: pkill -f mimoe"
        exit 0
    fi

    # Check for existing installation
    check_existing_install

    detect_platform
    install_runtime
    setup_path
    install_addon
    install_mesh_addon
    start_runtime
    provision_model
    print_ready_message
}

main "$@"
