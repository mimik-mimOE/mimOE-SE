@echo off
setlocal enabledelayedexpansion

REM #######################################################################
REM mimOE AI Foundation Installer for Windows
REM
REM Acquires the four release packages, lays them out as a bundle, and hands
REM the bundle to `mimoe-setup.exe install --source` - which owns the on-disk
REM layout, the atomic swap, the user PATH, addon .ini generation and daemon
REM control. This script only *acquires* and then provisions the default
REM model (model pull is not in mimoe-setup yet).
REM
REM The four packages (see SETUP.md for the naming convention):
REM   1. runtime     mimOE-SE-developer-windows-x64-v<rel>.zip
REM   2. addons      mimOE-addons-v<rel>.zip                (cross-platform)
REM   3. extensions  mimoe-<backend>-windows-x64-v<ver>.zip (one per backend)
REM   4. setup       mimoe-setup-windows-x64-v<ver>.zip
REM
REM Usage:
REM   install-mimOE-ai.bat                                - Production install
REM   cmd /C "set LOCAL_HTTP=1 && install-mimOE-ai.bat"   - From localhost:8000
REM   cmd /C "set LOCAL_TEST=1 && install-mimOE-ai.bat"   - From a local bundle dir
REM
REM Requirements: Windows 10 1803+ (curl.exe and tar.exe built in)
REM #######################################################################

REM #######################################################################
REM RELEASE MANIFEST
REM
REM Everything you edit for a new release OR a change to the package name
REM format lives between here and the END marker. No code below this block
REM constructs a package name.
REM #######################################################################

REM --- versions --------------------------------------------------------

REM CHANNEL_BASE variable is very import url base address for packages, it can
REM be both remote and local url. Use local http address to do local http install.

REM The release id (BOM). The runtime and the addon set are published under it.
set "RELEASE=v3.30.42"

REM mimoe-setup has its own cadence (separate repo, separate version).
set "SETUP_VERSION=v0.7.0"

REM Per-backend versions: each backend's own manifest.json version, NOT the
REM release id, so an unchanged backend keeps its number across a runtime bump.
REM mcp_shell ships no manifest.json but is not versionless - mimoe-setup
REM discovers its version by running `mcp_shell --version`.
set "EXT_LLAMACPP_VERSION=v1.36.0"
set "EXT_ONNX_VERSION=v1.3.1"
set "EXT_MCP_SHELL_VERSION=v0.1.2"

REM --- platform row ----------------------------------------------------

REM This script is the windows-x64 row. GPU only selects which llamacpp
REM package to fetch - the runtime itself is GPU-agnostic.
REM
REM v3.30.26 publishes only mimoe-llamacpp-vulkan for windows-x64, so vulkan
REM is the only value that resolves to a real package; GPU=cuda would 404.
REM verify-naming.sh exercises the default row only, so it will not catch a
REM bad override for you.
set "PLATFORM=windows-x64"
if "%GPU%"=="" set "GPU=vulkan"

REM --- package name grammar --------------------------------------------
REM
REM   <component>[-<flavor>]-<platform>-<arch>[-<gpu>]-v<version>.zip
REM
REM One line per package. To change the format, change it HERE and in the
REM matching block of install-mimOE-ai.sh / assemble-packages.sh. SETUP.md
REM section 2 is the spec, and verify-naming.sh proves all three agree.
REM
REM EXT_n / EXT_n_DEST are the extension set for this row. `backends` vs `mcp`
REM differ because a backend is versioned and normalized from its own
REM manifest.json, while an MCP server ships no descriptor and its folder name
REM is literally what the gateway spawns.

REM The runtime carries NO gpu segment: mimoe.exe links no GPU library - the
REM GPU belongs entirely to the ML plugin, which is a separate package.
set "RUNTIME_PKG=mimOE-SE-developer-%PLATFORM%-%RELEASE%.zip"
set "ADDONS_PKG=mimOE-addons-%RELEASE%.zip"
set "SETUP_PKG=mimoe-setup-%PLATFORM%-%SETUP_VERSION%.zip"

set "EXT_1=mimoe-llamacpp-%GPU%-%PLATFORM%-%EXT_LLAMACPP_VERSION%.zip"
set "EXT_1_DEST=backends"
set "EXT_2=mimoe-onnx-cpu-%PLATFORM%-%EXT_ONNX_VERSION%.zip"
set "EXT_2_DEST=backends"
set "EXT_3=mimoe-mcp-shell-%PLATFORM%-%EXT_MCP_SHELL_VERSION%.zip"
set "EXT_3_DEST=mcp"

REM --- endpoints and install target ------------------------------------

if "%CHANNEL_BASE%"=="" set "CHANNEL_BASE=https://github.com/mimik-mimOE/mimOE-SE/releases/download/%RELEASE%"
REM if "%CHANNEL_BASE%"=="" set "CHANNEL_HANNEL_BASEBASE=https://dl.mimik.com/mimoe/stable/%RELEASE%"

if "%MIMOE_HOME%"=="" set "MIMOE_HOME=%USERPROFILE%\.mimoe"
set "MIMOE_LOG=%MIMOE_HOME%\.edge\logs\mimoe.log"

set "API_KEY=1234"
set "DEFAULT_MODEL_ID=smollm2-360m"
set "DEFAULT_MODEL_URL=https://huggingface.co/lmstudio-community/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q8_0.gguf?download=true"

REM LOCAL_TEST=1 - install straight from an already laid-out bundle dir
REM (bin\ addon\ extensions\ mimoe.lic), skipping acquisition entirely.
if "%LOCAL_BUNDLE_DIR%"=="" set "LOCAL_BUNDLE_DIR=%CD%\runtime-bundle-signed"
if "%LOCAL_SETUP_BIN%"=="" set "LOCAL_SETUP_BIN=%CD%\mimoe-setup.exe"

if "%LOCAL_HTTP_BASE%"=="" set "LOCAL_HTTP_BASE=http://localhost:8000"

REM #######################################################################
REM END RELEASE MANIFEST - nothing below builds a package name
REM #######################################################################

call :main
exit /b %ERRORLEVEL%

REM #######################################################################
REM Functions
REM #######################################################################

:main
echo.
echo ======================================================
echo        mimOE AI Foundation Installer for Windows
echo ======================================================
echo.
echo [+] Platform: %PLATFORM%-%GPU%
echo [+] Release:  %RELEASE%
echo.

REM Staging lives under TEMP; the bundle is assembled into the shape
REM `mimoe-setup --source` expects.
set "WORK=%TEMP%\mimoe-install-%RANDOM%"
set "STAGE=%WORK%\download"
set "BUNDLE=%WORK%\bundle"
mkdir "%WORK%" 2>nul
set "MAIN_RC=0"

if "%LOCAL_TEST%"=="1" (
    echo [x] LOCAL TEST mode - installing from a local bundle dir
    call :use_local_bundle
    if !ERRORLEVEL! neq 0 ( set "MAIN_RC=1" & goto :fail )
) else (
    if "%LOCAL_HTTP%"=="1" (
	        echo [x] LOCAL HTTP mode ^(%LOCAL_HTTP_BASE%^)
        set "PACKAGE_BASE=%LOCAL_HTTP_BASE%"
    ) else (
        set "PACKAGE_BASE=%CHANNEL_BASE%"
    )
    call :build_bundle
    if !ERRORLEVEL! neq 0 ( set "MAIN_RC=1" & goto :fail )
)

REM An already-running daemon is fine: mimoe-setup stops it for the swap and
REM `install` is the same code path as `upgrade`.
curl -s "http://localhost:8083/jsonrpc/v1" -X POST -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"method\":\"getMe\",\"id\":1}" >nul 2>&1
if !ERRORLEVEL!==0 (
    call :print_mimoe_status
    echo [x] mimoe-setup will stop it to activate the new release
)

call :run_setup
set "MAIN_RC=!ERRORLEVEL!"
if !MAIN_RC! neq 0 goto :fail

call :wait_for_runtime
set "MAIN_RC=!ERRORLEVEL!"
if !MAIN_RC! neq 0 goto :fail

call :provision_model
set "MAIN_RC=!ERRORLEVEL!"
if !MAIN_RC! neq 0 goto :fail

call :print_ready_message
call :cleanup
exit /b 0

REM Every failure path funnels through here so staging is always removed.
REM Previously :cleanup ran only after a successful install, so a failed run
REM left %TEMP%\mimoe-install-<rand>\ holding the downloaded zips plus the
REM extracted bundle - over 600 MB on windows-x64, and %RANDOM% means each
REM retry starts a fresh pile. The shell installer gets this free from
REM `trap ... EXIT`; batch has no equivalent, so it is done by hand.
:fail
call :cleanup
exit /b !MAIN_RC!

REM ---------------------------------------------------------------------
REM Acquisition
REM ---------------------------------------------------------------------

REM :fetch_package <name.zip>
REM
REM There is deliberately no checksum sidecar: a package must stay copyable and
REM renameable by hand without anything else needing to be regenerated to match.
REM Integrity is covered anyway - curl -f fails on an HTTP error or a short
REM transfer, and because every package is a .zip, the tar -xf that follows
REM fails loudly on a truncated or corrupt one.
:fetch_package
set "PKG=%~1"
echo     %PKG%
curl -fL --progress-bar -o "%STAGE%\%PKG%" "%PACKAGE_BASE%/%PKG%"
if %ERRORLEVEL% neq 0 (
    echo [!] Download failed: %PACKAGE_BASE%/%PKG%
    exit /b 1
)

REM A proxy can serve a 404 page as a 200 with HTML in it. Check the first
REM line only, for the zip magic: `findstr` over the whole file scanned all
REM 163 MB of the windows mcp_shell package, and it silently skips lines
REM longer than its internal limit - which is what binary data is made of, so
REM the guard was weakest on the largest package. `set /p` reads one line and
REM stops. Compare a substring rather than echoing the content, so bytes from
REM an HTML page can never be parsed as redirection.
set "MAGIC="
set /p MAGIC=<"%STAGE%\%PKG%"
if defined MAGIC if /i "!MAGIC:~0,2!" neq "PK" (
    echo [!] Not a zip archive ^(HTML error page or corrupt download^): %PACKAGE_BASE%/%PKG%
    exit /b 1
)

exit /b 0

REM Lay the four packages out as the bundle dir mimoe-setup --source expects:
REM   bin\  addon\  extensions\  mimoe.lic  mimoe-config.env
:build_bundle
echo [+] Acquiring release %RELEASE% for %PLATFORM%-%GPU%...
mkdir "%STAGE%" 2>nul
mkdir "%BUNDLE%\addon" 2>nul
mkdir "%BUNDLE%\extensions\backends" 2>nul
mkdir "%BUNDLE%\extensions\mcp" 2>nul

REM 1. runtime - carries bin\mimoe.exe, mimoe.lic and mimoe-config.env
call :fetch_package "%RUNTIME_PKG%"
if %ERRORLEVEL% neq 0 exit /b 1
tar -xf "%STAGE%\%RUNTIME_PKG%" -C "%BUNDLE%"
if %ERRORLEVEL% neq 0 ( echo [!] Failed to extract %RUNTIME_PKG% & exit /b 1 )
call :prune_macmeta "%BUNDLE%"

REM 2. addons - cross-platform, the whole tested-together set. Flat .addon
REM    files; tolerate a zip that wraps them in addon\.
call :fetch_package "%ADDONS_PKG%"
if %ERRORLEVEL% neq 0 exit /b 1
mkdir "%STAGE%\addons-x" 2>nul
tar -xf "%STAGE%\%ADDONS_PKG%" -C "%STAGE%\addons-x"
if %ERRORLEVEL% neq 0 ( echo [!] Failed to extract %ADDONS_PKG% & exit /b 1 )
call :prune_macmeta "%STAGE%\addons-x"
for /r "%STAGE%\addons-x" %%f in (*.addon) do copy /y "%%f" "%BUNDLE%\addon\" >nul

REM 3. extensions - one zip per backend, each its own signed artifact
for %%i in (1 2 3) do (
    call :fetch_extension %%i
    if !ERRORLEVEL! neq 0 exit /b 1
)

REM 4. mimoe-setup - the installer itself
call :fetch_package "%SETUP_PKG%"
if %ERRORLEVEL% neq 0 exit /b 1
mkdir "%STAGE%\setup-x" 2>nul
tar -xf "%STAGE%\%SETUP_PKG%" -C "%STAGE%\setup-x"
if %ERRORLEVEL% neq 0 ( echo [!] Failed to extract %SETUP_PKG% & exit /b 1 )
call :prune_macmeta "%STAGE%\setup-x"
set "SETUP_BIN="
for /r "%STAGE%\setup-x" %%f in (mimoe-setup.exe) do (
    if not defined SETUP_BIN set "SETUP_BIN=%%f"
)
if not defined SETUP_BIN (
    echo [!] mimoe-setup.exe not found in %SETUP_PKG%
    exit /b 1
)

echo [+] All four packages acquired
exit /b 0

REM :prune_macmeta <dir> - drop macOS archiver metadata after extraction.
REM A __MACOSX\ dir landing in extensions\backends\ reads as a package and
REM mimoe-setup rejects the whole bundle.
:prune_macmeta
if exist "%~1\__MACOSX" rd /s /q "%~1\__MACOSX" 2>nul
for /r "%~1" %%f in (._*) do del /f /q "%%f" 2>nul
exit /b 0

REM :fetch_extension <index> - indirection so the loop can read EXT_<i>
:fetch_extension
call set "PKG=%%EXT_%~1%%"
call set "DEST=%%EXT_%~1_DEST%%"
if not defined PKG exit /b 0
call :fetch_package "%PKG%"
if %ERRORLEVEL% neq 0 exit /b 1
tar -xf "%STAGE%\%PKG%" -C "%BUNDLE%\extensions\%DEST%"
if %ERRORLEVEL% neq 0 ( echo [!] Failed to extract %PKG% & exit /b 1 )
call :prune_macmeta "%BUNDLE%\extensions\%DEST%"
exit /b 0

REM LOCAL_TEST - the local bundle is already in --source shape, so there is
REM nothing to acquire or stage.
:use_local_bundle
if not exist "%LOCAL_BUNDLE_DIR%\bin" (
    echo [!] Not a laid-out bundle ^(no bin\^): %LOCAL_BUNDLE_DIR%
    echo [!] Set LOCAL_BUNDLE_DIR to a dir with bin\ addon\ extensions\
    exit /b 1
)
set "BUNDLE=%LOCAL_BUNDLE_DIR%"
echo [+] Bundle: %BUNDLE%

if not exist "%LOCAL_SETUP_BIN%" (
    echo [!] No mimoe-setup.exe at %LOCAL_SETUP_BIN%
    echo [!] Build it: powershell -File build-windows.ps1
    exit /b 1
)
set "SETUP_BIN=%LOCAL_SETUP_BIN%"
echo [+] Installer: %SETUP_BIN%
exit /b 0

REM ---------------------------------------------------------------------
REM Install - mimoe-setup owns everything from here to a running daemon
REM ---------------------------------------------------------------------

:run_setup
echo.
echo [+] Installing to %MIMOE_HOME%...

REM --source: a laid-out bundle, no manifest needed.
REM --start:  mimoe-setup launches the daemon after activation.
REM The user PATH, addon .ini generation, the atomic rename-swap and dist\
REM backups are all its job, not this script's.
"%SETUP_BIN%" install --source "%BUNDLE%" --mimoe-dir "%MIMOE_HOME%" --start
set "RC=%ERRORLEVEL%"

if "%RC%"=="0" ( echo [+] mimOE installed & exit /b 0 )
if "%RC%"=="2" ( echo [+] Already up to date & exit /b 0 )
if "%RC%"=="3" ( echo [!] mimoe-setup verify failure & exit /b 3 )
if "%RC%"=="4" ( echo [!] Another installer holds the lock & exit /b 4 )
if "%RC%"=="5" ( echo [!] Health check failed - rolled back & exit /b 5 )
echo [!] mimoe-setup install failed ^(exit %RC%^)
exit /b %RC%

:wait_for_runtime
echo.
echo [+] Waiting for mimOE runtime...
set /a ATTEMPT=0
:wait_loop
if %ATTEMPT% geq 30 (
    echo [!] Timeout waiting for runtime. Check %MIMOE_LOG%
    exit /b 1
)
curl -s "http://localhost:8083/jsonrpc/v1" -X POST -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"method\":\"getMe\",\"id\":1}" >nul 2>&1
if %ERRORLEVEL%==0 (
    echo [+] mimOE runtime is ready
    exit /b 0
)
timeout /t 1 /nobreak >nul 2>&1
set /a ATTEMPT+=1

if %ATTEMPT% == 5 (
    mimoe start
)
goto :wait_loop

REM ---------------------------------------------------------------------
REM Default model - still here because mimoe-setup parses default_models
REM but does not pull them yet (deferred to a later phase).
REM ---------------------------------------------------------------------

:provision_model
echo.
echo [+] Provisioning default model ^(%DEFAULT_MODEL_ID%^)...
set "BASE_URL=http://localhost:8083/mimik-ai/store/v1"

set /a WAITC=0
:addon_wait_loop
if %WAITC% geq 30 (
    echo [!] Timeout waiting for AI Foundation addon. Check %MIMOE_LOG%
    exit /b 1
)
curl -s "%BASE_URL%/models" -H "Authorization: Bearer %API_KEY%" 2>nul | findstr /c:"[" >nul 2>&1
if %ERRORLEVEL%==0 goto :addon_ready
timeout /t 1 /nobreak >nul 2>&1
set /a WAITC+=1
goto :addon_wait_loop

:addon_ready
curl -s "%BASE_URL%/models/%DEFAULT_MODEL_ID%" -H "Authorization: Bearer %API_KEY%" 2>nul | findstr /c:"\"readyToUse\":true" >nul 2>&1
if %ERRORLEVEL%==0 (
    echo [+] Model already installed and ready
    exit /b 0
)

echo     Creating model metadata...
curl -s -X POST "%BASE_URL%/models" -H "Content-Type: application/json" -H "Authorization: Bearer %API_KEY%" -d "{\"id\": \"%DEFAULT_MODEL_ID%\", \"version\": \"1.0.0\", \"kind\": \"llm\"}" -o "%WORK%\model-create.json" 2>nul
if %ERRORLEVEL% neq 0 (
    echo [!] Failed to create model metadata ^(curl exit %ERRORLEVEL%^)
    exit /b 1
)
REM "already exists" is the re-run case and is not fatal; any other error is.
findstr /c:"error" "%WORK%\model-create.json" >nul 2>&1
if %ERRORLEVEL%==0 (
    findstr /c:"already exists" "%WORK%\model-create.json" >nul 2>&1
    if !ERRORLEVEL! neq 0 (
        echo [!] Failed to create model metadata:
        type "%WORK%\model-create.json"
        exit /b 1
    )
)

echo     Downloading model ^(~386MB^) - this can take several minutes...
REM Capture the progress stream and check curl's own exit code. Discarding it
REM to nul meant a failed download was reported 120 seconds later as "Timeout
REM waiting for model to be ready" rather than the actual error - the same bug
REM the shell installer fixed by stashing curl's exit code out of the pipeline.
curl -s -N -X POST "%BASE_URL%/models/%DEFAULT_MODEL_ID%/download" -H "Content-Type: application/json" -H "Authorization: Bearer %API_KEY%" -d "{\"url\": \"%DEFAULT_MODEL_URL%\"}" -o "%WORK%\model-download.log" 2>nul
if %ERRORLEVEL% neq 0 (
    echo [!] Model download request failed ^(curl exit %ERRORLEVEL%^)
    echo [!] Check %MIMOE_LOG%
    exit /b 1
)

REM curl's exit code only reports whether the LOCAL api answered, and
REM wait_for_runtime has already proved that it does - so it is 0 for every
REM realistic failure (bad model url, HuggingFace unreachable, no disk). The
REM store reports a failed fetch in the response BODY instead:
REM     {"error":{"code":500,"message":"Connection failed"}}
REM Checking the body is what actually separates a completed download from a
REM failed one. Without it this prints success and the real symptom surfaces
REM 120s later as "Timeout waiting for model to be ready".
findstr /c:"\"error\"" "%WORK%\model-download.log" >nul 2>&1
if %ERRORLEVEL%==0 (
    echo [!] Model download failed:
    type "%WORK%\model-download.log"
    echo.
    echo [!] Check %MIMOE_LOG%
    exit /b 1
)
echo [+] Model download request completed

set /a ATTEMPT=0
:model_wait_loop
if %ATTEMPT% geq 60 (
    echo [!] Timeout waiting for model to be ready
    exit /b 1
)
curl -s "%BASE_URL%/models/%DEFAULT_MODEL_ID%" -H "Authorization: Bearer %API_KEY%" 2>nul | findstr /c:"\"readyToUse\":true" >nul 2>&1
if %ERRORLEVEL%==0 (
    echo [+] Model is ready for inference
    exit /b 0
)
timeout /t 2 /nobreak >nul 2>&1
set /a ATTEMPT+=1
goto :model_wait_loop

REM ---------------------------------------------------------------------
REM Reporting
REM ---------------------------------------------------------------------

:print_mimoe_status
REM GET_ME used to be captured and then discarded. Batch has no reliable way
REM to pull the version out of a JSON line, so this reports what it can
REM actually determine rather than parsing; the shell installer prints pid and
REM version because it has grep.
set "GET_ME="
for /f "tokens=*" %%v in ('curl -s "http://localhost:8083/jsonrpc/v1" -X POST -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"method\":\"getMe\",\"id\":1}" 2^>nul') do set "GET_ME=%%v"
if defined GET_ME (
    echo [+] mimOE is running ^(responded to getMe on :8083^)
) else (
    echo [+] mimOE is running
)
exit /b 0

:cleanup
REM WORK always lives under %TEMP% and is never the caller's bundle dir - in
REM LOCAL_TEST mode BUNDLE points outside it - so this is safe in every mode,
REM and it must run in every mode, because staging is where the ~400 MB of
REM extracted portable git ends up.
if not defined WORK exit /b 0
if exist "%WORK%" rd /s /q "%WORK%" 2>nul
exit /b 0

:print_ready_message
echo.
echo ============================================
echo   mimOE AI Foundation is ready!
echo ============================================
echo.
echo   Installed to: %MIMOE_HOME%
echo   Release:      %RELEASE% ^(%PLATFORM%-%GPU%^)
echo.
echo Test your setup with this command:
echo.
echo curl -X POST "http://localhost:8083/mimik-ai/openai/v1/chat/completions" -H "Content-Type: application/json" -H "Authorization: Bearer %API_KEY%" -d "{\"model\": \"%DEFAULT_MODEL_ID%\", \"messages\": [{\"role\": \"user\", \"content\": \"Complete this sentence: AI is like a\"}]}"
echo.
echo To stop mimOE:        mimoe stop
echo To start mimOE:       mimoe start
echo To check status:      mimoe status
echo To view logs:         type "%MIMOE_LOG%"
echo.
echo NOTE: open a new terminal to pick up the mimoe PATH entry.
echo.
echo Documentation: https://developer.mimik.com/docs/ai-foundation
echo.
exit /b 0
