$ErrorActionPreference = 'Continue'
$env:Path = "C:\Users\y-morita\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin;$env:Path"
$logPath = "C:\Users\y-morita\Documents\Pinlogy\tool\supabase_login.log"
Start-Transcript -Path $logPath -Force
& "C:\Users\y-morita\.cache\codex-runtimes\codex-primary-runtime\dependencies\bin\fallback\pnpm.cmd" dlx supabase@latest login --name Pinlogy-Codex --agent no
$exitCode = $LASTEXITCODE
Stop-Transcript
Write-Host ""
if ($exitCode -eq 0) {
  Write-Host "SUCCESS: Supabase login completed."
} else {
  Write-Host "FAILED: Supabase login was not completed. Codex can now inspect the saved error log."
}
Read-Host "Press Enter to close"
