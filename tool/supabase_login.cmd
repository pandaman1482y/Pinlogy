@echo off
set "PATH=C:\Users\y-morita\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin;%PATH%"
call "C:\Users\y-morita\.cache\codex-runtimes\codex-primary-runtime\dependencies\bin\fallback\pnpm.cmd" dlx supabase@latest login --name Pinlogy-Codex
if errorlevel 1 goto failed
echo.
echo SUCCESS: Supabase login completed. You can return to Codex.
pause
exit /b 0

:failed
echo.
echo FAILED: Supabase login was not completed.
echo Please keep this window open and send Codex a screenshot of the error.
pause
