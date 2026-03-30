@echo off
setlocal enabledelayedexpansion

REM #######################################################################
REM mimOE AI Foundation Installer for Windows
REM
REM Installs mimOE runtime + AI Foundation addon to %USERPROFILE%\.mimoe\
REM and provisions a default model for immediate inference.
REM
REM Usage:
REM   install-mimOE-ai.bat                          - Production install
REM   set LOCAL_HTTP=1 && install-mimOE-ai.bat      - Local testing
REM
REM Requirements: Windows 10 1803+ (has curl.exe and tar.exe built-in)
REM #######################################################################

REM Installation target
set "MIMOE_HOME=%USERPROFILE%\.mimoe"
set "MIMOE_BIN=%MIMOE_HOME%\bin"
set "MIMOE_ADDON=%MIMOE_HOME%\addon"
set "MIMOE_LOG=%MIMOE_HOME%\.edge\logs\mimoe.log"

REM Configuration
set VERSION=3.22.6
set API_KEY=1234
set DEFAULT_MODEL_ID=smollm2-360m
set DEFAULT_MODEL_URL=https://huggingface.co/lmstudio-community/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q8_0.gguf?download=true

REM Local HTTP server for testing (run: python -m http.server 8000)
set LOCAL_HTTP_BASE=http://localhost:8000
set LOCAL_WINDOWS_URL=%LOCAL_HTTP_BASE%/mimOE-SE/mimOE-ai-SE-windows-developer-x64-v3.18.0.zip
set ADDON_AI_VERSION=1.8.5
set ADDON_MESH_VERSION=1.0.1
set ADDON_AI_FILENAME=ai-foundation-%ADDON_AI_VERSION%.addon
set LOCAL_ADDON_URL=%LOCAL_HTTP_BASE%/mimOE-addon-ai-foundation/%ADDON_AI_FILENAME%

REM Remote URLs (production)
set PROD_WINDOWS_URL=https://github.com/mimik-mimOE/mimOE-SE/releases/download/v%VERSION%/mimOE-ai-SE-windows-developer-AMD64-VULKAN-v%VERSION%.zip
set PROD_ADDON_URL=https://github.com/mimik-mimOE/mimOE-addon-ai-foundation/releases/download/v%ADDON_AI_VERSION%/%ADDON_AI_FILENAME%
set PROD_MESH_ADDON_URL=https://github.com/mimik-mimOE/mimOE-addon-mesh-foundation/releases/download/v%ADDON_MESH_VERSION%/mesh-foundation-%ADDON_MESH_VERSION%.addon
REM set PROD_MESH_ADDON_URL=https://github.com/mimik-mimOE/mimOE-addon-mesh-foundation/releases/download/v1.0.1/mesh-foundation-1.0.1.addon

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
    echo [x] Running in LOCAL HTTP mode ^(%LOCAL_HTTP_BASE%^)
    echo.
)

REM Check if mimOE is already running
curl -s "http://localhost:8083/jsonrpc/v1" -X POST -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"method\":\"getMe\",\"id\":1}" >nul 2>&1
if %ERRORLEVEL%==0 (
    call :print_mimoe_status
    echo.
    echo [x] mimOE is already running. To re-install, stop it first using: taskkill /f /im mimoe.exe /T
    exit /b 0
)

REM Check for existing installation
call :check_existing_install
if %ERRORLEVEL% neq 0 exit /b 1

echo [+] Installing mimOE to %MIMOE_HOME%

call :install_runtime
if %ERRORLEVEL% neq 0 exit /b 1

call :setup_path
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


:check_existing_install
if not exist "%MIMOE_HOME%" exit /b 0

REM Check if directory has any contents
set "HAS_FILES=false"
for /f "delims=" %%A in ('dir /b /a "%MIMOE_HOME%" 2^>nul') do (set "HAS_FILES=true")

if "%HAS_FILES%"=="true" (
    echo [x] mimOE is already installed at %MIMOE_HOME%
    echo [x] To reinstall, first remove the existing installation:
    echo [x]   cmd /c rmdir /s /q "%MIMOE_HOME%"
    exit /b 1
)
exit /b 0


:install_runtime
echo.
echo ==^> Installing mimOE runtime...

REM Create directory structure
if not exist "%MIMOE_BIN%" mkdir "%MIMOE_BIN%"
if not exist "%MIMOE_ADDON%" mkdir "%MIMOE_ADDON%"

REM Download to a temp directory
set "TMPDIR=%TEMP%\mimoe-install-%RANDOM%"
mkdir "%TMPDIR%"

set FILENAME=mimoe-runtime.zip
echo     Downloading runtime...
curl -L --progress-bar -o "%TMPDIR%\%FILENAME%" "%RUNTIME_URL%"
if %ERRORLEVEL% neq 0 (
    echo [x] Failed to download runtime
    rmdir /s /q "%TMPDIR%"
    exit /b 1
)

REM Check if download failed (small file = error page)
for %%A in ("%TMPDIR%\%FILENAME%") do set FILESIZE=%%~zA
if %FILESIZE% LSS 10000 (
    echo [x] Download failed - file too small, likely error page
    echo     URL: %RUNTIME_URL%
    rmdir /s /q "%TMPDIR%"
    exit /b 1
)

echo     Extracting...
tar -xf "%TMPDIR%\%FILENAME%" -C "%TMPDIR%"
if %ERRORLEVEL% neq 0 (
    echo [x] Failed to extract runtime
    rmdir /s /q "%TMPDIR%"
    exit /b 1
)
del "%TMPDIR%\%FILENAME%"

REM Copy binary to ~/.mimoe/bin/
if exist "%TMPDIR%\bin\mimoe.exe" (
    copy /y "%TMPDIR%\bin\mimoe.exe" "%MIMOE_BIN%\mimoe.exe" >nul
    REM ADDED: Copy all DLLs found in the zip's bin folder
    if exist "%TMPDIR%\bin\*.dll" (
        copy /y "%TMPDIR%\bin\*.dll" "%MIMOE_BIN%\" >nul
    )
) else (
    echo [x] Runtime binary not found in archive ^(expected bin\mimoe.exe^)
    rmdir /s /q "%TMPDIR%"
    exit /b 1
)

REM Copy license file if present
for %%F in ("%TMPDIR%\*.lic") do (
    copy /y "%%F" "%MIMOE_HOME%\" >nul
)

REM Cleanup temp
rmdir /s /q "%TMPDIR%"

echo [+] Runtime installed to %MIMOE_HOME%
exit /b 0


:setup_path
echo.
echo ==^> Setting up PATH...

REM Read current user PATH from registry
set "CURRENT_PATH="
for /f "tokens=2,*" %%a in ('reg query "HKCU\Environment" /v Path 2^>nul ^| findstr /i "Path"') do (
    set "CURRENT_PATH=%%b"
)

REM Check if already in PATH (case-insensitive)
echo !CURRENT_PATH! | findstr /i ".mimoe\bin" >nul 2>&1
if %ERRORLEVEL%==0 (
    echo [+] Already in PATH
    exit /b 0
)

REM Append to user PATH
if defined CURRENT_PATH (
    set "NEW_PATH=!CURRENT_PATH!;%MIMOE_BIN%"
) else (
    set "NEW_PATH=%MIMOE_BIN%"
)

reg add "HKCU\Environment" /v Path /t REG_EXPAND_SZ /d "!NEW_PATH!" /f >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [x] Could not update PATH in registry. You may need to add %MIMOE_BIN% to PATH manually.
    exit /b 0
)

REM Broadcast WM_SETTINGCHANGE so Explorer picks up the change
powershell -NoProfile -Command "[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path', 'User'), 'User')" >nul 2>&1

REM Make mimoe available in this session
set "PATH=%MIMOE_BIN%;%PATH%"

echo [+] Added %MIMOE_BIN% to user PATH
echo [+] Open a new terminal for PATH changes to take effect
exit /b 0


:install_addon
echo.
echo ==^> Installing AI Foundation addon...

set ADDON_FILENAME=%ADDON_AI_FILENAME%

TIMEOUT /T 1 /NOBREAK > NUL

echo     Downloading addon...
curl -L --progress-bar -o "%MIMOE_ADDON%\%ADDON_FILENAME%" "%ADDON_URL%"
if %ERRORLEVEL% neq 0 (
    echo [x] Failed to download addon
    exit /b 1
)

REM Check if download failed (small file = error page)
for %%A in ("%MIMOE_ADDON%\%ADDON_FILENAME%") do set ADDONSIZE=%%~zA
if %ADDONSIZE% LSS 10000 (
    echo [x] Download failed - file too small, likely error page
    echo     URL: %ADDON_URL%
    del "%MIMOE_ADDON%\%ADDON_FILENAME%"
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
) > "%MIMOE_ADDON%\%ADDON_BASENAME%.ini"

echo [+] Configuration file created
exit /b 0


:install_mesh_addon
echo.
echo ==^> Installing Mesh Foundation addon...

set MESH_ADDON_FILENAME=mesh-foundation-%ADDON_MESH_VERSION%.addon
REM set MESH_ADDON_FILENAME=mesh-foundation-1.0.1.addon

echo     Downloading mesh addon...
curl -L --progress-bar -o "%MIMOE_ADDON%\%MESH_ADDON_FILENAME%" "%MESH_ADDON_URL%"
if %ERRORLEVEL% neq 0 (
    echo [x] Failed to download mesh addon
    exit /b 1
)

REM Check if download failed (small file = error page)
for %%A in ("%MIMOE_ADDON%\%MESH_ADDON_FILENAME%") do set MESHADDONSIZE=%%~zA
if %MESHADDONSIZE% LSS 10000 (
    echo [x] Download failed - file too small, likely error page
    echo     URL: %MESH_ADDON_URL%
    del "%MIMOE_ADDON%\%MESH_ADDON_FILENAME%"
    exit /b 1
)

set MESH_ADDON_BASENAME=%MESH_ADDON_FILENAME:.addon=%

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
) > "%MIMOE_ADDON%\%MESH_ADDON_BASENAME%.ini"

echo [+] Mesh configuration file created
exit /b 0


:start_runtime
echo.
echo ==^> Starting mimOE runtime...

REM Start mimoe daemon from ~/.mimoe/
pushd "%MIMOE_HOME%"
powershell -Command "Start-Process '%MIMOE_BIN%\mimoe.exe' -ArgumentList 'start' -WorkingDirectory '%MIMOE_HOME%' -WindowStyle Hidden" 2>NUL || start "" /b "%MIMOE_BIN%\mimoe.exe" start
popd

REM Wait for runtime to be ready
set MAX_ATTEMPTS=30
set ATTEMPT=0

:wait_loop
if %ATTEMPT% geq %MAX_ATTEMPTS% goto wait_timeout

set /a ATTEMPT+=1
echo     Waiting for runtime to start... ^(%ATTEMPT%/%MAX_ATTEMPTS%s^)

curl -s "http://localhost:8083/jsonrpc/v1" -X POST -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"method\":\"getMe\",\"id\":1}" >nul 2>&1
if %ERRORLEVEL%==0 (
    echo [+] mimOE runtime is ready
    exit /b 0
)

timeout /t 1 /nobreak >nul
goto wait_loop

:wait_timeout
echo [x] Timeout waiting for runtime to start. Check %MIMOE_LOG%
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
echo [x] Timeout waiting for AI Foundation addon. Check %MIMOE_LOG%
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


:print_mimoe_status
set "T_GET_ME="
for /f "delims=" %%i in ('curl -s "http://localhost:8083/jsonrpc/v1" -X POST -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"method\":\"getMe\",\"id\":1}" 2^>nul') do set "T_GET_ME=%%i"
set "T_PID="
for /f "tokens=2" %%i in ('tasklist /fi "imagename eq mimoe.exe" /nh 2^>nul ^| findstr /i "mimoe.exe"') do set "T_PID=%%i"
set "T_VER="
if defined T_GET_ME (
    for %%a in (!T_GET_ME!) do (
        set "item=%%a"
        set "item=!item:{=!"
        set "item=!item:}=!"
        for /f "tokens=1,2 delims=:" %%g in ("!item!") do (
            set "key=%%g"
            set "key=!key:"=!"
            if /i "!key!"=="version" (
                set "T_VER=%%h"
                set "T_VER=!T_VER:"=!"
                set "T_VER=!T_VER:,=!"
            )
        )
    )
    if defined T_PID ( echo [+] mimoe [pid = !T_PID!, version = !T_VER!] is already running ) else ( echo [+] mimoe [version = !T_VER!] is already running )
) else if defined T_PID ( echo [+] mimoe [pid = !T_PID!] is already running )
exit /b 0


:print_ready_message
echo.
echo ============================================
echo   mimOE AI Foundation is ready!
echo ============================================
echo.
echo   Installed to: %MIMOE_HOME%
echo.
echo Test your setup:
echo.
echo   Command Prompt:
echo   curl -X POST "http://localhost:8083/mimik-ai/openai/v1/chat/completions" -H "Content-Type: application/json" -H "Authorization: Bearer %API_KEY%" -d "{\"model\":\"%DEFAULT_MODEL_ID%\",\"messages\":[{\"role\":\"user\",\"content\":\"Complete this sentence: AI is like a\"}]}"
echo.
echo   PowerShell:
echo   Invoke-RestMethod -Uri "http://localhost:8083/mimik-ai/openai/v1/chat/completions" -Method Post -ContentType "application/json" -Headers @{Authorization="Bearer %API_KEY%"} -Body '{"model":"%DEFAULT_MODEL_ID%","messages":[{"role":"user","content":"Complete this sentence: AI is like a"}]}' ^| ConvertTo-Json -Depth 5
echo.
echo To stop mimOE:        taskkill /f /im mimoe.exe /T
echo To start mimOE:       mimoe start
echo To check status:      mimoe status
echo To view logs:         type "%MIMOE_LOG%"
echo.
echo NOTE: Open a new terminal for 'mimoe' to be in your PATH.
echo.
echo Documentation: https://developer.mimik.com/docs/ai-foundation
echo.
exit /b 0
