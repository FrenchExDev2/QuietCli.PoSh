# 1. Dossiers à exclure (adaptez le chemin de vos projets si besoin)
$PathsToExclude = @(
    "c:\code",                                              # Vos dépôts Git
    "$env:USERPROFILE\source\repos",                         # Dépôts par défaut sur C:
    "$env:USERPROFILE\.nuget\packages",                      # Cache NuGet local
    "$env:LOCALAPPDATA\npm-cache",                           # Cache npm par défaut
    "$env:LOCALAPPDATA\Programs\Microsoft VS Code Insiders", # Binaires VS Code Insiders
    "$env:APPDATA\Code - Insiders",                          # Config/Cache VS Code Insiders
    "$env:USERPROFILE\.vscode-insiders",                     # Extensions VS Code Insiders
    "C:\Program Files\dotnet"                                # SDK & Runtime .NET
)

foreach ($path in $PathsToExclude) {
    if (Test-Path $path) {
        Add-MpPreference -ExclusionPath $path
        Write-Host "Chemin exclu : $path" -ForegroundColor Green
    }
}

# 2. Processus de build et d'IDE à exclure
$ProcessesToExclude = @(
    "dotnet.exe",
    "MSBuild.exe",
    "VBCSCompiler.exe",   # Compilateur Roslyn C#
    "node.exe",           # TypeScript / npm / serveurs LSP
    "code.exe",
    "Code - Insiders.exe",
    "git.exe",
    "codex.exe",
    "claude.exe"
)

foreach ($proc in $ProcessesToExclude) {
    Add-MpPreference -ExclusionProcess $proc
    Write-Host "Processus exclu : $proc" -ForegroundColor Cyan
}

Add-MpPreference -ExclusionExtension "vhdx"

# 3. Vérifier les exclusions actives
Get-MpPreference | Select-Object ExclusionPath, ExclusionProcess
