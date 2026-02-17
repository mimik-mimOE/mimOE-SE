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
# Initialize INSTALL_DIR at the very top
INSTALL_DIR=$(pwd)
CREATED_DIR=""
INSTALLED=false
MIMOE_LOG="./.edge/logs/mimoe.log"
INVALID_FOLDER=false

prepare_install_dir() {
    # Check if current directory is empty (ignoring . and ..)
    # ls -A lists all files; if the output is empty, the directory is empty.
    if [ -n "$(ls -A)" ]; then
        # Current directory is NOT empty
        if [ ! -d "mimOE" ]; then
            # No mimOE folder. Create it.
            NEW_DIR="mimOE"
            mkdir -p "$NEW_DIR"
            cd "$NEW_DIR"
            CREATED_DIR=$(pwd)
        elif [ -z "$(ls -A mimOE 2>/dev/null)" ]; then
            # mimOE exists and is empty. Use it.
            NEW_DIR="mimOE"
            cd "$NEW_DIR"
        else
            # mimOE is occupied. Create a new one with timestamp.
            NEW_DIR="mimOE_$(date +%H%M%S)"
            mkdir -p "$NEW_DIR"
            cd "$NEW_DIR"
            CREATED_DIR=$(pwd)
        fi
    fi
    # Important update INSTALL_DIR with the current directory again
    INSTALL_DIR=$(pwd)
    # echo "[+] Installing mimoe in directory: $INSTALL_DIR"
}

cleanup_new_dir() {
    if [ -n "$CREATED_DIR" ]; then
        # Get absolute path of current location
        local current_dir=$(pwd)

        # Only proceed if we are actually inside the directory we created
        if [ "$current_dir" = "$CREATED_DIR" ]; then
            # Check if it's empty
            if [ -z "$(ls -A "$CREATED_DIR" 2>/dev/null)" ]; then
                cd ..
                rmdir "$CREATED_DIR"
            fi
        fi
    fi
}

create_mimoe_stop_script_file() {
    cat << 'EOF' > stop.sh
#!/bin/bash
# Check if mimoe is running
if pgrep -f mimoe > /dev/null; then
    echo
    echo "Stopping mimoe..."
    echo
    pkill -f mimoe

    # Verification loop: 5 attempts with 1s sleep
    STOPPED=false
    for i in {1..5}; do
        if ! pgrep -f mimoe > /dev/null; then
            STOPPED=true
            break
        fi
        echo "Waiting for mimoe to exit... ($i/5)"
        sleep 1
    done

    if [ "$STOPPED" = true ]; then
        echo
        echo "mimoe stopped successfully."
        echo
    else
        echo
        echo "mimoe is still running after 5 seconds."
        echo
    fi
else
    echo
    echo "mimoe is not running"
    echo
fi
EOF
    chmod +x stop.sh
}

create_mimoe_status_script_file() {
  # Use 'EOF' in quotes to prevent the current shell from expanding variables
  cat << 'EOF' > status.sh
#!/bin/bash
# Get the PID 
PID=$(pgrep -f mimoe | head -n 1)

# Get the API status 
GET_ME=$(curl -s "http://localhost:8083/jsonrpc/v1" -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"getMe","id":1}' 2>/dev/null)

if [ -n "$PID" ]; then
    if [[ "$GET_ME" == *"version"* ]]; then
        # Extract version without a JSON parser 
        VERSION=$(echo "$GET_ME" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
        echo
        echo "mimoe [pid = $PID, version = $VERSION] is running"
        echo
    else
        # Found PID but API failed 
        echo
        echo "mimoe [pid = $PID] is running"
        echo
    fi
elif [[ "$GET_ME" == *"version"* ]]; then
    # Found API but PID hidden 
    VERSION=$(echo "$GET_ME" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
    echo
    echo "mimoe [version = $VERSION] is running"
    echo
else
    echo
    echo "mimoe is not running"
    echo
fi
EOF
  chmod +x status.sh
}

start_bg() {
    # Define the command with full redirection
    # This ensures nohup returns back to the script immediately
    if command -v nohup >/dev/null 2>&1; then
        nohup ./start.sh < /dev/null > /dev/null 2>&1 &
        #echo "[+] Started with nohup (Detached)"
        echo -e "${GREEN}✓${NC} Started mimoe with nohup (Detached)."
    else
        # Fallback for systems without nohup
        ./start.sh > /dev/null 2>&1 &
        MIMOE_PID=$!
        
        if help disown >/dev/null 2>&1 || builtin type disown >/dev/null 2>&1; then
            disown $MIMOE_PID
            #echo "[+] Started and disowned (PID: $MIMOE_PID)"
            echo -e "${GREEN}✓${NC} Started mimoe and disowned (PID: $MIMOE_PID)."
        else
            shopt -u huponexit 2>/dev/null || true
            #echo "[+] Started with IO redirection"
            echo -e "${GREEN}✓${NC} Started mimoe in background with IO redirection."
        fi
    fi
}

enforce_empty_install_dir_ori() {
    local installer_part="install-mimOE-ai"
    local total_files=$(ls -A | wc -l)
    INVALID_FOLDER=false

    # Condition 1: If there are 2 or more files, it's definitely not empty.
    if [ "$total_files" -gt 1 ]; then
        INVALID_FOLDER=true
    
    # Condition 2: If there is exactly 1 file, it must be the installer.
    # If it's NOT the installer, then the folder is "not empty" of junk.
    elif [ "$total_files" -eq 1 ] && ! ls -A | grep -q "$installer_part"; then
        INVALID_FOLDER=true
    fi

    # If either check failed, print the message and exit
    #if [ "$INVALID_FOLDER" = true ]; then
    #   print_error "Error: Installation Directory is not empty."
    #   print_error "Our installer requires an empty directory. Run this from an empty folder."
        # exit 1
    #fi

}

enforce_empty_install_filecount_dir() {
    local invoked_name=$(basename "$0")
    local file_count=0
    INVALID_FOLDER=false

    # ls -A lists everything (files and folders)
    for item in $(ls -A 2>/dev/null); do
        ((file_count++))
        
        is_installer=false
        case "$item" in
            "install.sh"|"install-mimOE-ai.sh"|"$invoked_name"|"bash"|"sh"|"stdin")
                is_installer=true
                ;;
        esac

        # If it's not one of our installers OR count > 2, fail
        if [ "$is_installer" = false ] || [ "$file_count" -gt 2 ]; then
            INVALID_FOLDER=true
            #echo [x] Found unexpected item: $item
            print_error "Found unexpected item: $item"
            break
        fi
    done
}

enforce_empty_install_dir() {
    local invoked_name=$(basename "$0")
    INVALID_FOLDER=false

    for item in $(ls -A 2>/dev/null); do
        is_installer=false
        
        case "$item" in
            "install.sh" | "install-mimOE-ai.sh" | "$invoked_name" | "bash" | "sh" | "stdin")
                is_installer=true
                ;;
        esac

        if [ "$is_installer" = false ]; then
            INVALID_FOLDER=true
            #echo "[x] Found unexpected item: $item"
            print_error "Found unexpected item: $item"
            break
        fi
    done
}


# prepare_install_dir checks if current directory is empty else create a new
# empty folder mimOE or mimOE_datetime and cd to it.
#prepare_install_dir


# Configuration
VERSION="3.20.2"
API_KEY="1234"
DEFAULT_MODEL_ID="smollm2-360m"
DEFAULT_MODEL_URL="https://huggingface.co/lmstudio-community/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q8_0.gguf?download=true"

# Local HTTP server for testing (run: python3 -m http.server 8000)
# Set LOCAL_HTTP=1 to use these URLs instead of GitHub
LOCAL_HTTP_BASE="http://localhost:8000"
ADDON_AI_VERSION=v1.8.3
ADDON_AI_FILENAME=ai-foundation-$ADDON_AI_VERSION.addon
#ADDON_AI_FILENAME=ai-foundation-1.8.3.addon
LOCAL_MACOS_ARM64_URL="${LOCAL_HTTP_BASE}/mimOE-SE/mimOE-ai-SE-macOS-developer-ARM64-v3.18.0-39-g474c155e.tar"
LOCAL_ADDON_URL="${LOCAL_HTTP_BASE}/mimOE-addon-ai-foundation/$ADDON_AI_FILENAME"
#LOCAL_ADDON_URL="${LOCAL_HTTP_BASE}/mimOE-addon-ai-foundation/ai-foundation-1.7.0.addon"

# Remote URLs (production)
PROD_MACOS_ARM64_URL="https://github.com/mimik-mimOE/mimOE-SE/releases/download/v${VERSION}/mimOE-ai-SE-macOS-developer-ARM64-v${VERSION}.zip"
PROD_LINUX_AMD64_URL="https://github.com/mimik-mimOE/mimOE-SE/releases/download/v${VERSION}/mimOE-ai-SE-linux-developer-X86_64-VULKAN-v${VERSION}.tar"
PROD_LINUX_ARM64_URL="https://github.com/mimik-mimOE/mimOE-SE/releases/download/v${VERSION}/mimOE-ai-SE-linux-developer-ARM64-v${VERSION}.tar"
PROD_LINUX_ARM64_CUDA_URL="https://github.com/mimik-mimOE/mimOE-SE/releases/download/v${VERSION}/mimOE-ai-SE-linux-developer-ARM64-CUDA-v${VERSION}.tar"
PROD_ADDON_URL="https://github.com/mimik-mimOE/mimOE-addon-ai-foundation/releases/download/$ADDON_AI_VERSION/$ADDON_AI_FILENAME"
#PROD_ADDON_URL="https://github.com/mimik-mimOE/mimOE-addon-ai-foundation/releases/download/v1.6.1/ai-foundation-1.8.1.addon"
PROD_MESH_ADDON_URL="https://github.com/mimik-mimOE/mimOE-addon-mesh-foundation/releases/download/v1.0.0/mesh-foundation-1.0.0.addon"

# Select URLs based on mode
if [ "$LOCAL_HTTP" == "1" ]; then
    MACOS_ARM64_URL="$LOCAL_MACOS_ARM64_URL"
    ADDON_URL="$LOCAL_ADDON_URL"
    MESH_ADDON_URL="$PROD_MESH_ADDON_URL"  # No local override for mesh addon
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
check_ubuntu_compatibility() {

    # Check for Ubuntu or Ubuntu-based derivatives safely
    if [ -f /etc/os-release ]; then
        # Search the whole file for "ubuntu" to catch ID, ID_LIKE, or NAME
        if grep -qi "ubuntu" /etc/os-release; then
            
            # Extract only the VERSION_ID (e.g., "20.04" or "22.04.1")
            DISTRO_VER=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
            
            # Extract the Major version integer (e.g., "20")
            MAJOR_VER=$(echo "$DISTRO_VER" | cut -d. -f1)

            # If it's anything less than 22 (21, 20, 18...), it lacks GLIBC 2.34
            if [ "$MAJOR_VER" -lt 22 ]; then
                print_error "Unsupported Ubuntu ($DISTRO_VER) OS Version. Ubuntu 22.04+ required for GLIBC 2.34 compatibility."
                exit 1
            fi
        fi
    fi
}

detect_platform() {
    # Normalize OS to lowercase for safe comparison
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
            # 1. Primary Tegra check: Kernel string
            TEGRA=$(uname -r | grep -i tegra)

            # 2. Check device-tree model (more robust)
            if [ -z "$TEGRA" ] && [ -f /proc/device-tree/model ]; then
                TEGRA=$(grep -i "tegra" /proc/device-tree/model 2>/dev/null)
            fi

            PLATFORM="linux-arm64"
            if [ -z "$TEGRA" ]; then
               # Standard ARM64 Linux
               RUNTIME_URL="$LINUX_ARM64_URL"
            else
               # NVIDIA Tegra/Jetson specific build
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

        # create stop.sh script
        #echo "pkill -f mimoe" > stop.sh && chmod +x stop.sh
        create_mimoe_stop_script_file

        # create status.sh script
        create_mimoe_status_script_file
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

# Install Mesh Foundation addon
install_mesh_addon() {
    print_step "Installing Mesh Foundation addon..."

    # Create addon directory if needed
    mkdir -p addon

    if [ "$LOCAL_TEST" == "1" ]; then
        # Local test mode - copy local addon file
        LOCAL_MESH_ADDON_DIR="${SCRIPT_DIR}/mimOE-addon-mesh-foundation"
        MESH_ADDON_FILE=$(find "$LOCAL_MESH_ADDON_DIR" -name "*.addon" 2>/dev/null | head -1)
        if [ -z "$MESH_ADDON_FILE" ]; then
            print_error "No mesh addon file found in $LOCAL_MESH_ADDON_DIR"
            exit 1
        fi
        print_success "Using local mesh addon: $(basename "$MESH_ADDON_FILE")"
        cp "$MESH_ADDON_FILE" addon/
        MESH_ADDON_BASENAME=$(basename "$MESH_ADDON_FILE" .addon)
    else
        # Production mode - download from GitHub
        local mesh_addon_filename=$(basename "$MESH_ADDON_URL")
        echo "  Downloading mesh addon..."
        curl -L --progress-bar -o "addon/$mesh_addon_filename" "$MESH_ADDON_URL"

        # Check if download failed (file contains "Not Found" or is HTML)
        if grep -q "Not Found\|<!DOCTYPE\|<html" "addon/$mesh_addon_filename" 2>/dev/null; then
            print_error "Download failed - file not found at URL: $MESH_ADDON_URL"
            rm -f "addon/$mesh_addon_filename"
            exit 1
        fi

        MESH_ADDON_BASENAME="${mesh_addon_filename%.addon}"
    fi

    # Create .ini file for custom configuration
    create_mesh_addon_ini "$MESH_ADDON_BASENAME"

    print_success "Mesh Foundation addon installed"
}

# Create custom .ini configuration for the mesh addon
create_mesh_addon_ini() {
    local addon_name=$1
    local ini_file="addon/${addon_name}.ini"

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

    # Start in background.
    #./start.sh > /dev/null 2>&1 &
    start_bg

    # Wait for runtime to be ready with spinner
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        printf "\r${BLUE}⠋${NC} Starting mimOE runtime... (%d/%ds)" "$attempt" "$max_attempts"
        if curl -s "http://localhost:8083/jsonrpc/v1" -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"getMe","id":1}' > /dev/null 2>&1; then
            printf "\r%-60s\r" " "
            print_success "mimOE runtime is ready (logs: $MIMOE_LOG)"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done

    printf "\r%-60s\r" " "
    print_error "Timeout waiting for runtime to start. Check ./.edge/logs/mimikEdge.log"
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
    printf "\r%-76s\r" " "
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
    \"messages\": [{\"role\": \"user\", \"content\": \"Complete this sentence: AI is like a\"}]
  }'${NC}"
    echo ""
    echo -e "${BLUE}To stop mimOE (universal):${NC}    pkill -f mimoe"
    echo ""
    if [ "$INSTALLED" = true ]; then
	echo -e "${BLUE} cd to the mimOE installed directory ${NC}"
	echo -e "  cd $INSTALL_DIR"
	echo ""
	echo -e "${BLUE}To stop mimOE (local):${NC}        ./stop.sh"
	#echo -e "${BLUE}To restart (background):${NC}      ./stop.sh > /dev/null; ./start.sh > /dev/null 2>&1 &"
        echo -e "${BLUE}To restart (background):${NC}      ./stop.sh >/dev/null; ./start.sh >/dev/null 2>&1 & sleep 2; ./status.sh"
        echo -e "${BLUE}To restart (interactive):${NC}      ./stop.sh ; ./start.sh"
	echo -e "${BLUE}To get mimoe status:${NC}          ./status.sh"
	echo -e "${BLUE}To view logs (follow):${NC}        tail -f $MIMOE_LOG"
	echo ""
    fi
    echo "Documentation: https://developer.mimik.com/docs/ai-foundation"
    echo ""
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

# Main installation flow
main() {
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║     mimOE AI Foundation Installer            ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""

    enforce_empty_install_dir
    if [ "$INVALID_FOLDER" = true ]; then
       print_error "Error: Installation directory/folder is not empty. It has files other than this installer."
       print_error "Our installer requires an empty directory - not even hidden files. Run this from an empty folder."
       echo
       exit 0
    fi

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
        #print_success "mimOE is already running"
        print_mimoe_status

        print_warning "Skipping model provisioning (mimOE already running from another location)"
        print_warning "To provision a model, stop the running instance first: pkill -f mimoe"
        print_ready_message
        cleanup_new_dir
        exit 0
    fi

    detect_platform

    print_success "Installing mimoe in directory: $INSTALL_DIR"
    # set installation logic
    INSTALLED=true

    install_runtime
    install_addon
    install_mesh_addon
    start_runtime
    provision_model
    print_ready_message
}

main "$@"
