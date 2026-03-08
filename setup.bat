@echo off
setlocal
title Voice Command Setup
cd /d "%~dp0"

echo ==================================================
echo   Voice Command -- Setup
echo ==================================================
echo.

rem -- Check Python is installed --
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python was not found.
    echo.
    echo Please download and install Python 3.8 or higher from:
    echo   https://www.python.org/downloads/
    echo.
    echo IMPORTANT: During installation, tick "Add Python to PATH"
    echo.
    pause
    exit /b 1
)

rem -- Check Python version >= 3.8 --
for /f "tokens=2" %%v in ('python --version 2^>^&1') do set PYVER=%%v
for /f "tokens=1,2 delims=." %%a in ("%PYVER%") do (
    set PYMAJ=%%a
    set PYMIN=%%b
)
if %PYMAJ% LSS 3 goto version_error
if %PYMAJ% EQU 3 if %PYMIN% LSS 8 goto version_error
goto version_ok

:version_error
echo ERROR: Python %PYVER% is installed, but 3.8 or higher is required.
echo Please upgrade from: https://www.python.org/downloads/
echo.
pause
exit /b 1

:version_ok
echo Python %PYVER% found.
echo.

rem -- Check setup_helper.py exists --
if not exist "python\setup_helper.py" (
    echo ERROR: python\setup_helper.py not found.
    echo Please reinstall Voice Command from the original package.
    echo.
    pause
    exit /b 1
)

rem -- Run setup helper --
python python\setup_helper.py
if errorlevel 1 (
    echo.
    echo Setup did not complete successfully. See messages above.
    echo.
    pause
    exit /b 1
)

echo.
pause
exit /b 0
