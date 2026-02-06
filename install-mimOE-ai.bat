@echo off
setlocal enabledelayedexpansion

REM #######################################################################
REM mimOE AI Foundation Installer for Windows
REM
REM This script installs mimOE runtime + AI Foundation addon and provisions
REM a default model for immediate inference.
REM
REM Usage:
REM   install-mimOE-ai.bat              - Production install
REM   set LOCAL_HTTP=1 && install-mimOE-ai.bat   - Local testing
REM
REM Requirements: Windows 10 1803+ (has curl.exe and tar.exe built-in)
REM #######################################################################

REM Configuration
set VERSION=3.20.0
set API_KEY=1234
set DEFAULT_MODEL_ID=smollm2-360m
set DEFAULT_MODEL_URL=https://huggingface.co/lmstudio-community/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q8_0.gguf?download=true

REM Local HTTP server for testing (run: python -m http.server 8000)
set LOCAL_HTTP_BASE=http://localhost:8000
set LOCAL_WINDOWS_URL=%LOCAL_HTTP_BASE%/mimOE-SE/mimOE-ai-SE-windows-developer-x64-v3.18.0.zip
set ADDON_AI_FILENAME=ai-foundation-1.8.1.addon
set LOCAL_ADDON_URL=%LOCAL_HTTP_BASE%/mimOE-addon-ai-foundation/%ADDON_AI_FILENAME%
REM set LOCAL_ADDON_URL=%LOCAL_HTTP_BASE%/mimOE-addon-ai-foundation/ai-foundation-1.8.1.addon

REM Remote URLs (production)
set PROD_WINDOWS_URL=https://github.com/mimik-mimOE/mimOE-SE/releases/download/v%VERSION%/mimOE-ai-SE-windows-developer-AMD64-VULKAN-v%VERSION%.zip
set PROD_ADDON_URL=https://github.com/mimik-mimOE/mimOE-addon-ai-foundation/releases/download/v1.6.1/%ADDON_AI_FILENAME%
REM set PROD_ADDON_URL=https://github.com/mimik-mimOE/mimOE-addon-ai-foundation/releases/download/v1.6.1/ai-foundation-1.8.1.addon
set PROD_MESH_ADDON_URL=https://github.com/mimik-mimOE/mimOE-addon-mesh-foundation/releases/download/v1.0.0/mesh-foundation-1.0.0.addon

REM Select URLs based on mode
if "%LOCAL_HTTP%"=="1" (
    set RUNTIME_URL=%LOCAL_WINDOWS_URL%
    set ADDON_URL=%LOCAL_ADDON_URL%
    set MESH_ADDON_URL=%PROD_MESH_ADDON_URL%
) else (
    set RUNTIME_URL=%PROD_WINDOWS_URL%
    set ADDON_URL=%PROD_ADDON_URL%
    set MESH_ADDON_URL=%PROD_MESH_ADDON_URL%
)

REM Main entry point
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

if "%LOCAL_HTTP%"=="1" (
    echo [!] Running in LOCAL HTTP mode ^(%LOCAL_HTTP_BASE%^)
    echo.
)

REM Check if mimOE is already running
curl -s "http://localhost:8083/jsonrpc/v1" -X POST -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"method\":\"getMe\",\"id\":1}" >nul 2>&1
if %ERRORLEVEL%==0 (
    echo [+] mimOE is already running
    echo [!] Skipping model provisioning ^(mimOE already running from another location^)
    echo [!] To provision a model, stop the running instance first: taskkill /f /im mimoe.exe
    call :print_ready_message
    exit /b 0
)

REM Check if already installed in current folder
REM if exist "start.bat" (
if exist "mimoe.exe" (
    echo [!] mimOE appears to be already installed
    echo Ensuring addons are installed...
    call :install_addon
    if %ERRORLEVEL% neq 0 exit /b 1
    call :install_mesh_addon
    if %ERRORLEVEL% neq 0 exit /b 1
    echo Starting runtime and provisioning model...
    call :start_runtime
    call :provision_model
    call :print_ready_message
    exit /b 0
)

call :install_runtime
if %ERRORLEVEL% neq 0 exit /b 1

call :install_addon
if %ERRORLEVEL% neq 0 exit /b 1

call :install_mesh_addon
if %ERRORLEVEL% neq 0 exit /b 1

call :start_runtime
if %ERRORLEVEL% neq 0 exit /b 1

call :provision_model
if %ERRORLEVEL% neq 0 exit /b 1

call :print_ready_message
exit /b 0


:install_runtime
echo.
echo ==^> Installing mimOE runtime...

set FILENAME=mimoe-runtime.zip
echo     Downloading runtime...
curl -L --progress-bar -o %FILENAME% "%RUNTIME_URL%"
if %ERRORLEVEL% neq 0 (
    echo [x] Failed to download runtime
    exit /b 1
)

REM Check if download failed (small file = error page)
for %%A in (%FILENAME%) do set FILESIZE=%%~zA
if %FILESIZE% LSS 10000 (
    echo [x] Download failed - file too small, likely error page
    echo     URL: %RUNTIME_URL%
    del %FILENAME%
    exit /b 1
)

echo     Extracting...
tar -xf %FILENAME%
if %ERRORLEVEL% neq 0 (
    echo [x] Failed to extract runtime
    exit /b 1
)
del %FILENAME%

if exist "start.bat" (
    echo [+] Runtime installed
) else (
    echo [x] Runtime installation failed - start.bat not found
    exit /b 1
)
exit /b 0


:install_addon
echo.
echo ==^> Installing AI Foundation addon...

if not exist "addon" mkdir addon

REM Hardcode addon filename (URL parsing unreliable in batch)
set ADDON_FILENAME=%ADDON_AI_FILENAME%
REM set ADDON_FILENAME=ai-foundation-1.8.1.addon

echo     Downloading addon...
curl -L --progress-bar -o "addon\%ADDON_FILENAME%" "%ADDON_URL%"
if %ERRORLEVEL% neq 0 (
    echo [x] Failed to download addon
    exit /b 1
)

REM Check if download failed (small file = error page)
for %%A in ("addon\%ADDON_FILENAME%") do set ADDONSIZE=%%~zA
if %ADDONSIZE% LSS 10000 (
    echo [x] Download failed - file too small, likely error page
    echo     URL: %ADDON_URL%
    del "addon\%ADDON_FILENAME%"
    exit /b 1
)

REM Get basename without .addon extension for .ini file
set ADDON_BASENAME=%ADDON_FILENAME:.addon=%

REM Create .ini file for custom configuration
call :create_addon_ini

echo [+] AI Foundation addon installed
exit /b 0


:create_addon_ini
echo.
echo ==^> Creating addon configuration ^(%ADDON_BASENAME%.ini^)...

(
echo # AI Foundation addon configuration
echo # This file customizes environment variables for the addon mims.
echo # See: https://developer.mimik.com/docs/api/mcm#environment-variables
echo.
echo [milm-v1]
echo # API key for local development ^(any value works for local usage^)
echo API_KEY=1234
echo.
echo # Extend execution timeout to 3 minutes for AI inference operations
echo # Default is 30 seconds, which may not be enough for larger models
echo MCM.MAX_EXECUTION_TIME_SEC=180
echo.
echo # Model Registry API key ^(milm uses this to communicate with mmodelstore^)
echo # If you change MMODELSTORE_API_KEY below, update this value to match
echo # MMODELSTORE_API_KEY=1234
echo.
echo # [mmodelstore-v1]
echo # Model Registry API key
echo # IMPORTANT: If you change this, you must also set MMODELSTORE_API_KEY
echo # in the [milm-v1] section above to the same value
echo # API_KEY=1234
) > addon\%ADDON_BASENAME%.ini

echo [+] Configuration file created
exit /b 0


:install_mesh_addon
echo.
echo ==^> Installing Mesh Foundation addon...

if not exist "addon" mkdir addon

REM Hardcode mesh addon filename
set MESH_ADDON_FILENAME=mesh-foundation-1.0.0.addon

echo     Downloading mesh addon...
curl -L --progress-bar -o "addon\%MESH_ADDON_FILENAME%" "%MESH_ADDON_URL%"
if %ERRORLEVEL% neq 0 (
    echo [x] Failed to download mesh addon
    exit /b 1
)

REM Check if download failed (small file = error page)
for %%A in ("addon\%MESH_ADDON_FILENAME%") do set MESHADDONSIZE=%%~zA
if %MESHADDONSIZE% LSS 10000 (
    echo [x] Download failed - file too small, likely error page
    echo     URL: %MESH_ADDON_URL%
    del "addon\%MESH_ADDON_FILENAME%"
    exit /b 1
)

REM Get basename without .tar extension for .ini file
set MESH_ADDON_BASENAME=%MESH_ADDON_FILENAME:.addon=%

REM Create .ini file for custom configuration
call :create_mesh_addon_ini

echo [+] Mesh Foundation addon installed
exit /b 0


:create_mesh_addon_ini
echo.
echo ==^> Creating mesh addon configuration ^(%MESH_ADDON_BASENAME%.ini^)...

(
echo # Mesh Foundation addon configuration
echo # This file customizes environment variables for the addon mims.
echo # See: https://developer.mimik.com/docs/api/mcm#environment-variables
echo.
echo [minsight-v1]
echo # API key for local development ^(any value works for local usage^)
echo API_KEY=1234
) > addon\%MESH_ADDON_BASENAME%.ini

echo [+] Mesh configuration file created
exit /b 0


:start_runtime
echo.
echo ==^> Starting mimOE runtime...

REM Create log directory
if not exist "logs" mkdir logs

REM Start in background
start /b cmd /c "start.bat > logs\mimoe.log 2>&1"

REM Wait for runtime to be ready
set MAX_ATTEMPTS=30
set ATTEMPT=0

:wait_loop
if %ATTEMPT% geq %MAX_ATTEMPTS% goto wait_timeout

set /a ATTEMPT+=1
echo     Waiting for runtime to start... ^(%ATTEMPT%/%MAX_ATTEMPTS%s^)

curl -s "http://localhost:8083/jsonrpc/v1" -X POST -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"method\":\"getMe\",\"id\":1}" >nul 2>&1
if %ERRORLEVEL%==0 (
    echo [+] mimOE runtime is ready ^(logs: logs\mimoe.log^)
    exit /b 0
)

timeout /t 1 /nobreak >nul
goto wait_loop

:wait_timeout
echo [x] Timeout waiting for runtime to start. Check logs\mimoe.log
exit /b 1


:provision_model
echo.
echo ==^> Provisioning default model ^(%DEFAULT_MODEL_ID%^)...

set BASE_URL=http://localhost:8083/mimik-ai/store/v1

REM Wait for AI Foundation addon to be ready
set MAX_ADDON_WAIT=30
set ADDON_WAIT=0

:addon_wait_loop
if %ADDON_WAIT% geq %MAX_ADDON_WAIT% goto addon_wait_timeout

curl -s "%BASE_URL%/models" -H "Authorization: Bearer %API_KEY%" 2>nul | findstr /C:"[" >nul
if %ERRORLEVEL%==0 goto addon_ready

set /a ADDON_WAIT+=1
echo     Waiting for AI Foundation addon to initialize... ^(%ADDON_WAIT%/%MAX_ADDON_WAIT%s^)
timeout /t 1 /nobreak >nul
goto addon_wait_loop

:addon_wait_timeout
echo [x] Timeout waiting for AI Foundation addon. Check logs\mimoe.log
exit /b 1

:addon_ready

REM Check if model already exists and is ready
curl -s "%BASE_URL%/models/%DEFAULT_MODEL_ID%" -H "Authorization: Bearer %API_KEY%" 2>nul | findstr /C:"\"readyToUse\":true" >nul
if %ERRORLEVEL%==0 (
    echo [+] Model already installed and ready
    exit /b 0
)

REM Create model metadata
echo     Creating model metadata...
curl -s -X POST "%BASE_URL%/models" -H "Content-Type: application/json" -H "Authorization: Bearer %API_KEY%" -d "{\"id\":\"%DEFAULT_MODEL_ID%\",\"version\":\"1.0.0\",\"kind\":\"llm\"}" > metadata_response.tmp 2>&1

REM Check if response contains error (but "already exists" is OK)
findstr /C:"error" metadata_response.tmp >nul 2>&1
if %ERRORLEVEL%==0 (
    findstr /C:"already exists" metadata_response.tmp >nul 2>&1
    if %ERRORLEVEL% neq 0 (
        echo [x] Failed to create model metadata:
        type metadata_response.tmp
        del metadata_response.tmp
        exit /b 1
    )
)
del metadata_response.tmp 2>nul

REM Check if model is already ready
curl -s "%BASE_URL%/models/%DEFAULT_MODEL_ID%" -H "Authorization: Bearer %API_KEY%" 2>nul | findstr /C:"\"readyToUse\":true" >nul
if %ERRORLEVEL%==0 (
    echo [+] Model already provisioned and ready
    exit /b 0
)

REM Download model from Hugging Face
echo     Downloading model ^(~386MB^)...
echo     This may take several minutes...

REM Use PowerShell for streaming download with progress
powershell -NoProfile -Command ^
    "$ProgressPreference = 'Continue'; " ^
    "$uri = '%BASE_URL%/models/%DEFAULT_MODEL_ID%/download'; " ^
    "$body = '{\"url\":\"%DEFAULT_MODEL_URL%\"}'; " ^
    "$headers = @{Authorization='Bearer %API_KEY%'}; " ^
    "try { " ^
    "  $reader = [System.Net.WebRequest]::Create($uri); " ^
    "  $reader.Method = 'POST'; " ^
    "  $reader.ContentType = 'application/json'; " ^
    "  $reader.Headers.Add('Authorization', 'Bearer %API_KEY%'); " ^
    "  $reader.Timeout = 600000; " ^
    "  $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body); " ^
    "  $reader.ContentLength = $bodyBytes.Length; " ^
    "  $reqStream = $reader.GetRequestStream(); " ^
    "  $reqStream.Write($bodyBytes, 0, $bodyBytes.Length); " ^
    "  $reqStream.Close(); " ^
    "  $response = $reader.GetResponse(); " ^
    "  $stream = $response.GetResponseStream(); " ^
    "  $sr = New-Object System.IO.StreamReader($stream); " ^
    "  while (-not $sr.EndOfStream) { " ^
    "    $line = $sr.ReadLine(); " ^
    "    if ($line -match 'data: (.+)') { " ^
    "      try { " ^
    "        $json = $Matches[1] | ConvertFrom-Json; " ^
    "        if ($json.totalSize -gt 0) { " ^
    "          $pct = [math]::Round(($json.size / $json.totalSize) * 100); " ^
    "          $mb = [math]::Round($json.size / 1MB, 1); " ^
    "          $totalMb = [math]::Round($json.totalSize / 1MB, 1); " ^
    "          Write-Host \"`r    Progress: $pct%% ($mb / $totalMb MB)   \" -NoNewline; " ^
    "        } " ^
    "      } catch {} " ^
    "    } " ^
    "  } " ^
    "  $sr.Close(); " ^
    "  Write-Host ''; " ^
    "} catch { Write-Host $_.Exception.Message }"

echo [+] Model download complete

REM Wait for model to be ready
set MAX_ATTEMPTS=120
set ATTEMPT=0

:model_wait_loop
if %ATTEMPT% geq %MAX_ATTEMPTS% goto model_wait_timeout

set /a ATTEMPT+=1
set /a SECONDS=%ATTEMPT%*2

REM Show progress every 10 seconds
set /a MOD=%ATTEMPT% %% 5
if %MOD%==0 (
    echo     Waiting for model to be ready... ^(%SECONDS%s^)
)

curl -s "%BASE_URL%/models/%DEFAULT_MODEL_ID%" -H "Authorization: Bearer %API_KEY%" 2>nul | findstr /C:"\"readyToUse\":true" >nul
if %ERRORLEVEL%==0 (
    echo [+] Model is ready for inference
    exit /b 0
)

timeout /t 2 /nobreak >nul
goto model_wait_loop

:model_wait_timeout
echo [x] Timeout waiting for model to be ready
exit /b 1


:print_ready_message
echo.
echo ============================================
echo   mimOE AI Foundation is ready!
echo ============================================
echo.
echo Test your setup:
echo.
echo   Command Prompt:
echo   curl -X POST "http://localhost:8083/mimik-ai/openai/v1/chat/completions" -H "Content-Type: application/json" -H "Authorization: Bearer %API_KEY%" -d "{\"model\":\"%DEFAULT_MODEL_ID%\",\"messages\":[{\"role\":\"user\",\"content\":\"Write a haiku about AI\"}]}"
echo.
echo   PowerShell:
echo   Invoke-RestMethod -Uri "http://localhost:8083/mimik-ai/openai/v1/chat/completions" -Method Post -ContentType "application/json" -Headers @{Authorization="Bearer %API_KEY%"} -Body '{"model":"%DEFAULT_MODEL_ID%","messages":[{"role":"user","content":"Write a haiku about AI"}]}' ^| ConvertTo-Json -Depth 5
echo.
echo To stop mimOE:   taskkill /f /im mimoe.exe
echo To restart:      start.bat
echo View logs:       type logs\mimoe.log
echo.
echo Documentation: https://developer.mimik.com/docs/ai-foundation
echo.
exit /b 0
