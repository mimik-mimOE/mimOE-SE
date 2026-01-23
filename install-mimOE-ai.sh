#!/bin/bash

#######################################################################
# mimOE AI Foundation Installer
#
# This script installs mimOE runtime + AI Foundation addon and provisions
# a default model for immediate inference.
#
# Usage:
#   curl -L https://... | bash          # Production install
#   LOCAL_TEST=1 ./install-mimOE-ai.sh  # Local testing
#######################################################################

set -e

# Configuration
VERSION="3.20.0-preview"
API_KEY="1234"
DEFAULT_MODEL_ID="smollm2-360m"
DEFAULT_MODEL_URL="https://huggingface.co/lmstudio-community/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q8_0.gguf?download=true"

# Local HTTP server for testing (run: python3 -m http.server 8000)
# Set LOCAL_HTTP=1 to use these URLs instead of GitHub
LOCAL_HTTP_BASE="http://localhost:8000"
LOCAL_MACOS_ARM64_URL="${LOCAL_HTTP_BASE}/mimOE-SE/mimOE-ai-SE-macOS-developer-ARM64-v3.18.0-39-g474c155e.tar"
LOCAL_ADDON_URL="${LOCAL_HTTP_BASE}/mimOE-addon-ai-foundation/ai-foundation-1.6.1.addon"

# Remote URLs (production)
PROD_MACOS_ARM64_URL="https://github.com/mimik-mimOE/mimOE-SE/releases/download/v${VERSION}/mimOE-ai-SE-macOS-developer-ARM64-v${VERSION}.zip"
PROD_LINUX_AMD64_URL="https://github.com/mimik-mimOE/mimOE-SE/releases/download/v${VERSION}/mimOE-ai-SE-linux-developer-X86_64-v${VERSION}.tar"
PROD_LINUX_ARM64_URL="https://github.com/mimik-mimOE/mimOE-SE/releases/download/v${VERSION}/mimOE-ai-SE-linux-developer-ARM64-v${VERSION}.tar"
PROD_ADDON_URL="https://github.com/mimik-mimOE/mimOE-addon-ai-foundation-/releases/download/v1.6.1/ai-foundation-1.6.1.addon"

# Select URLs based on mode
if [ "$LOCAL_HTTP" == "1" ]; then
    MACOS_ARM64_URL="$LOCAL_MACOS_ARM64_URL"
    ADDON_URL="$LOCAL_ADDON_URL"
else
    MACOS_ARM64_URL="$PROD_MACOS_ARM64_URL"
    LINUX_AMD64_URL="$PROD_LINUX_AMD64_URL"
    LINUX_ARM64_URL="$PROD_LINUX_ARM64_URL"
    ADDON_URL="$PROD_ADDON_URL"
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

# Spinner animation
spinner() {
    local pid=$1
    local message=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % ${#spin} ))
        printf "\r${BLUE}${spin:$i:1}${NC} %s" "$message"
        sleep 0.1
    done
    printf "\r"
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

# Detect OS and architecture
detect_platform() {
    OS=$(uname -s)
    ARCH=$(uname -m)

    if [ "$OS" == "Darwin" ]; then
        if [ "$ARCH" == "arm64" ]; then
            PLATFORM="macos-arm64"
            RUNTIME_URL="$MACOS_ARM64_URL"
        else
            print_error "macOS Intel (x86_64) is not supported. Apple Silicon (ARM64) required."
            exit 1
        fi
    elif [ "$OS" == "Linux" ]; then
        if [ "$ARCH" == "x86_64" ]; then
            PLATFORM="linux-x64"
            RUNTIME_URL="$LINUX_AMD64_URL"
        elif [ "$ARCH" == "aarch64" ]; then
            PLATFORM="linux-arm64"
            RUNTIME_URL="$LINUX_ARM64_URL"
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

# Download and extract runtime
install_runtime() {
    print_step "Installing mimOE runtime..."

    if [ "$LOCAL_TEST" == "1" ]; then
        # Local test mode - use local files
        RUNTIME_FILE=$(find "$LOCAL_RUNTIME_DIR" -name "*.tar" -o -name "*.zip" 2>/dev/null | head -1)
        if [ -z "$RUNTIME_FILE" ]; then
            print_error "No runtime archive found in $LOCAL_RUNTIME_DIR"
            exit 1
        fi
        print_success "Using local runtime: $(basename "$RUNTIME_FILE")"

        if [[ "$RUNTIME_FILE" == *.zip ]]; then
            unzip -o "$RUNTIME_FILE"
        else
            tar -xf "$RUNTIME_FILE"
        fi
    else
        # Production mode - download from GitHub
        local filename=$(basename "$RUNTIME_URL")
        echo "  Downloading runtime..."
        curl -L --progress-bar -o "$filename" "$RUNTIME_URL"

        # Check if download failed (file contains "Not Found" or is HTML)
        if grep -q "Not Found\|<!DOCTYPE\|<html" "$filename" 2>/dev/null; then
            print_error "Download failed - file not found at URL: $RUNTIME_URL"
            rm -f "$filename"
            exit 1
        fi

        echo "  Extracting..."
        if [[ "$filename" == *.zip ]]; then
            unzip -q -o "$filename"
            rm "$filename"
        else
            tar -xf "$filename"
            rm "$filename"
        fi
    fi

    if [ -f "start.sh" ]; then
        print_success "Runtime installed"
    else
        print_error "Runtime installation failed - start.sh not found"
        exit 1
    fi
}

# Install AI Foundation addon
install_addon() {
    print_step "Installing AI Foundation addon..."

    # Create addon directory if needed
    mkdir -p addon

    if [ "$LOCAL_TEST" == "1" ]; then
        # Local test mode - copy local addon file
        ADDON_FILE=$(find "$LOCAL_ADDON_DIR" -name "*.addon" 2>/dev/null | head -1)
        if [ -z "$ADDON_FILE" ]; then
            print_error "No addon file found in $LOCAL_ADDON_DIR"
            exit 1
        fi
        print_success "Using local addon: $(basename "$ADDON_FILE")"
        cp "$ADDON_FILE" addon/
        ADDON_BASENAME=$(basename "$ADDON_FILE" .addon)
    else
        # Production mode - download from GitHub
        local addon_filename=$(basename "$ADDON_URL")
        echo "  Downloading addon..."
        curl -L --progress-bar -o "addon/$addon_filename" "$ADDON_URL"

        # Check if download failed (file contains "Not Found" or is HTML)
        if grep -q "Not Found\|<!DOCTYPE\|<html" "addon/$addon_filename" 2>/dev/null; then
            print_error "Download failed - file not found at URL: $ADDON_URL"
            rm -f "addon/$addon_filename"
            exit 1
        fi

        ADDON_BASENAME="${addon_filename%.addon}"
    fi

    # Create .ini file for custom configuration
    create_addon_ini "$ADDON_BASENAME"

    print_success "AI Foundation addon installed"
}

# Create custom .ini configuration for the addon
create_addon_ini() {
    local addon_name=$1
    local ini_file="addon/${addon_name}.ini"

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

# Start mimOE runtime
start_runtime() {
    print_step "Starting mimOE runtime..."

    # Create log directory
    mkdir -p logs

    # Start in background, redirect output to log file
    ./start.sh > logs/mimoe.log 2>&1 &
    MIMOE_PID=$!

    # Wait for runtime to be ready with spinner
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        printf "\r${BLUE}⠋${NC} Starting mimOE runtime... (%d/%ds)" "$attempt" "$max_attempts"
        if curl -s "http://localhost:8083/jsonrpc/v1" -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"getMe","id":1}' > /dev/null 2>&1; then
            printf "\r%-60s\r" " "
            print_success "mimOE runtime is ready (logs: logs/mimoe.log)"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done

    printf "\r%-60s\r" " "
    print_error "Timeout waiting for runtime to start. Check logs/mimoe.log"
    exit 1
}

# Provision default model
provision_model() {
    print_step "Provisioning default model (${DEFAULT_MODEL_ID})..."

    local base_url="http://localhost:8083/mimik-ai/store/v1"

    # Step 0: Check if model already exists and is ready
    local existing=$(curl -s "${base_url}/models/${DEFAULT_MODEL_ID}" \
        -H "Authorization: Bearer ${API_KEY}" 2>/dev/null)

    if echo "$existing" | grep -q '"readyToUse":true'; then
        print_success "Model already installed and ready"
        return 0
    fi

    # Step 1: Create model metadata
    printf "  Creating model metadata..."
    local create_response=$(curl -s -X POST "${base_url}/models" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d "{
            \"id\": \"${DEFAULT_MODEL_ID}\",
            \"version\": \"1.0.0\",
            \"kind\": \"llm\"
        }")

    # Check if response is empty (API not responding)
    if [ -z "$create_response" ]; then
        printf " failed\n"
        print_error "Failed to create model metadata: No response from API"
        exit 1
    fi

    # Check if model already exists (that's OK) or other error
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

    # Step 2: Check if model is already ready
    local status_response=$(curl -s "${base_url}/models/${DEFAULT_MODEL_ID}" \
        -H "Authorization: Bearer ${API_KEY}")

    if echo "$status_response" | grep -q '"readyToUse":true'; then
        print_success "Model already provisioned and ready"
        return 0
    fi

    # Step 3: Download model from Hugging Face
    echo "  Downloading model (~386MB)..."

    # Start download and parse SSE progress
    # SSE format: data: {"size": 100000000, "totalSize": 386000000}
    curl -s -N -X POST "${base_url}/models/${DEFAULT_MODEL_ID}/download" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d "{\"url\": \"${DEFAULT_MODEL_URL}\"}" 2>/dev/null | while IFS= read -r line; do
            # Parse SSE data lines (format: "data: {json}")
            if [[ "$line" == data:* ]]; then
                json="${line#data: }"
                # Extract size and totalSize
                current_size=$(echo "$json" | grep -o '"size":[0-9]*' | head -1 | cut -d: -f2)
                total_size=$(echo "$json" | grep -o '"totalSize":[0-9]*' | head -1 | cut -d: -f2)

                if [ -n "$current_size" ] && [ -n "$total_size" ] && [ "$total_size" -gt 0 ]; then
                    progress_bar "$current_size" "$total_size"
                fi
            fi
        done

    # Clear progress line and show success
    printf "\r%-60s\r" " "
    print_success "Model download complete"

    # Step 4: Wait for model to be ready
    local max_attempts=60
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        printf "\r  Verifying model is ready... (%d/%ds)" "$attempt" "$((max_attempts * 2))"
        local status=$(curl -s "${base_url}/models/${DEFAULT_MODEL_ID}" \
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

# Print success message with test command
print_ready_message() {
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  mimOE AI Foundation is ready!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo "Test your setup with this command:"
    echo ""
    echo -e "${YELLOW}curl -X POST \"http://localhost:8083/mimik-ai/openai/v1/chat/completions\" \\
  -H \"Content-Type: application/json\" \\
  -H \"Authorization: Bearer ${API_KEY}\" \\
  -d '{
    \"model\": \"${DEFAULT_MODEL_ID}\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Write a haiku about AI\"}]
  }'${NC}"
    echo ""
    echo -e "${BLUE}To stop mimOE:${NC}  pkill -f mimoe"
    echo -e "${BLUE}To restart:${NC}    ./start.sh > logs/mimoe.log 2>&1 &"
    echo -e "${BLUE}View logs:${NC}     tail -f logs/mimoe.log"
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

    # Check if mimOE is already running (even from another folder)
    if curl -s "http://localhost:8083/jsonrpc/v1" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"getMe","id":1}' > /dev/null 2>&1; then
        print_success "mimOE is already running"
        provision_model
        print_ready_message
        exit 0
    fi

    # Check if already installed in current folder
    if [ -f "start.sh" ]; then
        print_warning "mimOE appears to be already installed"
        echo "Starting runtime and provisioning model..."
        start_runtime
        provision_model
        print_ready_message
        exit 0
    fi

    detect_platform
    install_runtime
    install_addon
    start_runtime
    provision_model
    print_ready_message
}

main "$@"
