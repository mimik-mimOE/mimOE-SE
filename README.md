# mimOE-SE v3.22.6

mimOE (mimik Operating Environment) Standard Edition - A lightweight runtime for running AI Agents and microservices directly on-device.

## What is mimOE?

mimOE is an operating environment that runs **mims** (micro intelligence modules)—lightweight, serverless compute units that execute on-device without container overhead. It enables developers to build distributed, AI-powered applications with processing that starts on-device.

**Key Features:**
- On-device AI inference with OpenAI-compatible API
- Support for GGUF (generative) and ONNX (predictive) models
- Cross-platform: macOS, Linux, Windows
- Node-to-node discovery and communication
- Lightweight (~50MB runtime)

## Platform Support

| Platform | Architecture | Notes |
|----------|--------------|-------|
| macOS | Apple Silicon (ARM64) | Metal acceleration |
| Linux | x86_64, ARM64 | CUDA/ROCm/Vulkan acceleration |
| Windows | x64 | Vulkan acceleration |

## Quick Install

The quickest way to get started is with the AI Foundation Package, which includes the runtime, AI addon, and a pre-configured model.

### macOS / Linux

```bash
curl -L https://raw.githubusercontent.com/mimik-mimOE/mimOE-SE/main/install-mimOE-ai.sh | bash
```

### Windows (Command Prompt)

```cmd
curl -L https://raw.githubusercontent.com/mimik-mimOE/mimOE-SE/main/install-mimOE-ai.bat -o install.bat && install.bat
```

### Windows (PowerShell)

```powershell
curl.exe -L https://raw.githubusercontent.com/mimik-mimOE/mimOE-SE/main/install-mimOE-ai.bat -o install.bat; .\install.bat
```

This installs:
- mimOE runtime
- AI Foundation addon (Model Registry + Inference APIs)
- SmolLM2-360M model (~386MB)
- Custom configuration with 3-minute inference timeout

Once complete, the API is available at `http://localhost:8083`.

## Manual Install

Download the appropriate release for your platform from [GitHub Releases](https://github.com/mimik-mimOE/mimOE-SE/releases/tag/v3.22.6):

| Platform | File |
|----------|------|
| macOS (Apple Silicon) | `mimOE-SE-macOS-ARM64-v3.22.6.zip` |
| Linux (x64) | `mimOE-SE-linux-x86_64-v3.22.6.tar` |
| Linux (ARM64) | `mimOE-SE-linux-ARM64-v3.22.6.tar` |
| Windows (x64) | `mimOE-SE-windows-x64-v3.22.6.zip` |

### Extract and Start

**macOS / Linux:**
```bash
# Extract
tar -xf mimOE-SE-*.tar  # or unzip for .zip

# Start
./start.sh
```

**Windows:**
```cmd
REM Extract the zip file, then:
start.bat
```

## Quick Start

Once mimOE is running, test the API:

### Check Status

```bash
curl http://localhost:8083/jsonrpc/v1 \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"getMe","id":1}'
```

### Run Inference (with AI Foundation)

```bash
curl -X POST "http://localhost:8083/mimik-ai/openai/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer 1234" \
  -d '{
    "model": "smollm2-360m",
    "messages": [{"role": "user", "content": "Write a haiku about AI"}]
  }'
```

## Stop mimOE

**macOS / Linux:**
```bash
pkill -f mimoe
```

**Windows:**
```cmd
taskkill /f /im mimoe.exe
```

## API Endpoints

| Service | Base URL | Description |
|---------|----------|-------------|
| Model Registry | `/mimik-ai/store/v1` | Upload, download, manage AI models |
| Inference | `/mimik-ai/openai/v1` | OpenAI-compatible chat/completions |
| MCM | `/mcm/v1` | Deploy and manage mims |

## Documentation

Full documentation is available at the **mimOE Developer Portal**:

- **[Getting Started](https://developer.mimik.com/docs/ai-foundation)** - AI Foundation overview
- **[Installation Guide](https://developer.mimik.com/docs/ai-foundation/install)** - Detailed setup instructions
- **[Quick Start](https://developer.mimik.com/docs/ai-foundation/quick-start)** - First inference in minutes
- **[Model Registry API](https://developer.mimik.com/docs/api/model-registry)** - Model management reference
- **[Inference API](https://developer.mimik.com/docs/api/inference)** - OpenAI-compatible API reference
- **[MCM API](https://developer.mimik.com/docs/api/mcm)** - mim deployment and management

## Release Notes

### v3.20.0

- AI Foundation addon support
- Improved model registry with SSE download progress
- Extended execution timeout configuration (`MCM.MAX_EXECUTION_TIME_SEC`)
- Windows install script support
- Performance improvements for on-device inference

## Directory Structure

### Quick Install (using install script)

The install script sets up everything you need for AI inference:

```
mimOE-SE/
├── start.sh / start.bat    # Startup script
├── mimoe                   # Runtime binary
├── addon/                  # Addon packages
│   ├── ai-foundation.addon # AI Foundation addon (Model Registry + Inference APIs)
│   └── ai-foundation.ini   # Custom configuration (API key, timeout)
├── logs/                   # Runtime logs
│   └── mimoe.log
└── .edge/                  # Runtime data
    └── ...                 # Downloaded models stored here
```

**Includes:** mimOE runtime + AI Foundation addon + SmolLM2-360M model + configuration

### Manual Install (downloading release artifact)

Extracting the release tar/zip gives you the bare runtime only:

```
mimOE-SE/
├── start.sh / start.bat    # Startup script
├── mimoe                   # Runtime binary
└── .edge/                  # Runtime data (created on first run)
```

**Includes:** mimOE runtime only

To add AI capabilities after manual install, you need to:
1. Download and place the AI Foundation addon in `addon/` folder
2. Create `addon/ai-foundation.ini` for configuration
3. Provision a model via the Model Registry API

See [Installation Guide](https://developer.mimik.com/docs/ai-foundation/install) for detailed instructions.

## Configuration

The AI Foundation addon is configured via `addon/ai-foundation.ini`:

```ini
[milm-v1]
# API key for Inference API
API_KEY=1234

# Execution timeout (default: 30s, recommended: 180s for AI)
MCM.MAX_EXECUTION_TIME_SEC=180
```

See [MCM Environment Variables](https://developer.mimik.com/docs/api/mcm#environment-variables) for all options.

## License

mimOE Standard Edition is free for development and evaluation. See [LICENSE](LICENSE) for details.

For enterprise features including iOS, Android, and QNX support, visit [mimik.com](https://mimik.com).

## Support

- **Documentation**: https://developer.mimik.com
- **Developer Console**: https://console.mimik.com
- **Issues**: https://github.com/mimik-mimOE/mimOE-SE/issues
