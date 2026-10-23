param([string]$GodotPath="",[string]$OutputDirectory="",[string]$Seed="Asabiya",[switch]$SkipWorld)
# Kept as the client entry point; no test or world-generation process is run.
& (Join-Path $PSScriptRoot "../../tools/package-windows.ps1") -GodotPath $GodotPath -OutputDirectory $OutputDirectory -Seed $Seed
