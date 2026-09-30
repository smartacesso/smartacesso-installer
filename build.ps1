#Requires -Version 5.1
<#
.SYNOPSIS
  Empacota nucleo (Java 21 64-bit), TopData (Java 21 32-bit Liberica) e Desktop (Electron).

.EXAMPLE
  .\build.ps1
  .\build.ps1 -SkipJava -SkipElectron   # so recompila o Inno a partir do staging ja existente
  .\build.ps1 -Version 1.1.0
#>
[CmdletBinding()]
param(
    [string]$Version = "1.0.0",
    [switch]$SkipJava,
    [switch]$SkipElectron,
    [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"

$InstallerRoot = $PSScriptRoot
$WorkspacesRoot = Split-Path $InstallerRoot -Parent
$RepoCore = Join-Path $WorkspacesRoot "smartAcesso"
$RepoTopData = Join-Path $WorkspacesRoot "smartAcesso-topData"
$RepoElectron = Join-Path $WorkspacesRoot "smartacesso-desktop-electron"

$Staging = Join-Path $InstallerRoot "staging"
$Dist = Join-Path $InstallerRoot "dist"
$Tools = Join-Path $InstallerRoot "tools"

function Get-JavaVersionInfo([string]$JavaExe) {
    # java -version writes to stderr; cmd merges streams so PowerShell Stop does not abort.
    return (cmd.exe /c "`"$JavaExe`" -version 2>&1") | Out-String
}

function Test-Java32Bit([string]$JavaHome) {
    $java = Join-Path $JavaHome "bin\java.exe"
    if (-not (Test-Path $java)) { return $false }
    return (Get-JavaVersionInfo $java) -match "32-Bit"
}

function Test-Jdk21([string]$JavaHome) {
    $java = Join-Path $JavaHome "bin\java.exe"
    $jlink = Join-Path $JavaHome "bin\jlink.exe"
    if (-not ((Test-Path $java) -and (Test-Path $jlink))) { return $false }
    return (Get-JavaVersionInfo $java) -match 'version "21'
}

function Find-Jdk([string]$EnvName, [string[]]$SearchRoots, [bool]$Want32Bit) {
    $fromEnv = [Environment]::GetEnvironmentVariable($EnvName)
    if ($fromEnv -and (Test-Jdk21 $fromEnv) -and ((Test-Java32Bit $fromEnv) -eq $Want32Bit)) {
        return $fromEnv
    }

    $dirs = foreach ($root in $SearchRoots) {
        if (Test-Path $root) {
            Get-ChildItem $root -Directory -ErrorAction SilentlyContinue
        }
    }
    foreach ($dir in $dirs) {
        $jdkDir = $dir.FullName
        if (-not (Test-Jdk21 $jdkDir)) { continue }
        if ((Test-Java32Bit $jdkDir) -ne $Want32Bit) { continue }
        return $jdkDir
    }
    return $null
}

$Jdk21 = Find-Jdk -EnvName "SMARTACESSO_JDK21" -Want32Bit $false -SearchRoots @(
    "C:\Program Files\Java",
    "C:\Program Files\Eclipse Adoptium",
    "C:\Program Files\BellSoft",
    "C:\Program Files\Microsoft"
)
$Jdk21x86 = Find-Jdk -EnvName "SMARTACESSO_JDK21_X86" -Want32Bit $true -SearchRoots @(
    "C:\Program Files (x86)\BellSoft",
    "C:\Program Files (x86)\Java",
    "C:\Program Files (x86)\Eclipse Adoptium",
    "C:\Program Files (x86)\Microsoft"
)

if (-not $Jdk21) {
    throw "JDK 21 64-bit nao encontrado. Instale um JDK 21 x64 ou defina SMARTACESSO_JDK21."
}
if (-not $Jdk21x86) {
    throw "JDK 21 32-bit nao encontrado. Instale Liberica JDK 21 x86 (https://bell-sw.com/pages/downloads/) ou defina SMARTACESSO_JDK21_X86."
}

$WinSwUrl = "https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe"
$WinSwExe = Join-Path $Tools "WinSW-x64.exe"

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Assert-Path([string]$Path, [string]$What) {
    if (-not (Test-Path $Path)) {
        throw "$What nao encontrado: $Path"
    }
}

function Invoke-MvnPackage([string]$Repo, [string]$JavaHome) {
    Assert-Path $Repo "Repositorio"
    $mvnw = Join-Path $Repo "mvnw.cmd"
    Assert-Path $mvnw "Maven wrapper"
    Assert-Path $JavaHome "JAVA_HOME"

    $previousJavaHome = ${env:JAVA_HOME}
    $previousPath = $env:Path
    try {
        ${env:JAVA_HOME} = $JavaHome
        $env:Path = "$(Join-Path $JavaHome 'bin');$previousPath"
        Push-Location $Repo
        & $mvnw package '-DskipTests' '-Dmaven.test.skip=true'
        if ($LASTEXITCODE -ne 0) {
            throw "Maven package falhou em $Repo (exit $LASTEXITCODE)"
        }
    }
    finally {
        ${env:JAVA_HOME} = $previousJavaHome
        $env:Path = $previousPath
        Pop-Location
    }
}

function New-Jre21([string]$JdkHome, [string]$Destination) {
    $jlink = Join-Path $JdkHome "bin\jlink.exe"
    Assert-Path $jlink "jlink ($JdkHome)"
    if (Test-Path $Destination) {
        Remove-Item $Destination -Recurse -Force
    }
    $modules = @(
        "java.base", "java.compiler", "java.datatransfer", "java.desktop",
        "java.instrument", "java.logging", "java.management", "java.management.rmi",
        "java.naming", "java.net.http", "java.prefs", "java.rmi", "java.scripting",
        "java.security.jgss", "java.security.sasl", "java.sql", "java.sql.rowset",
        "java.transaction.xa", "java.xml", "java.xml.crypto",
        "jdk.crypto.cryptoki", "jdk.crypto.ec", "jdk.httpserver", "jdk.jfr",
        "jdk.localedata", "jdk.management", "jdk.management.agent",
        "jdk.naming.dns", "jdk.unsupported", "jdk.xml.dom", "jdk.zipfs"
    ) -join ","

    & $jlink `
        --output $Destination `
        --compress=zip-6 `
        --no-header-files `
        --no-man-pages `
        --strip-debug `
        --add-modules $modules
    if ($LASTEXITCODE -ne 0) {
        throw "jlink falhou (exit $LASTEXITCODE)"
    }
}

function Get-WinSw {
    if (Test-Path $WinSwExe) {
        return
    }
    New-Item -ItemType Directory -Force -Path $Tools | Out-Null
    Write-Host "Baixando WinSW..."
    Invoke-WebRequest -Uri $WinSwUrl -OutFile $WinSwExe -UseBasicParsing
}

function Find-Iscc {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

function Install-InnoSetupIfMissing {
    $iscc = Find-Iscc
    if ($iscc) { return $iscc }

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        return $null
    }

    Write-Step "Inno Setup nao encontrado. Tentando instalar via winget..."
    & winget install --id JRSoftware.InnoSetup -e --accept-source-agreements --accept-package-agreements | Out-Host
    return [string](Find-Iscc)
}

Write-Step "SmartAcesso installer $Version"
Write-Host "  JDK 21 x64 : $Jdk21"
Write-Host "  JDK 21 x86 : $Jdk21x86"
Assert-Path $RepoCore "smartAcesso"
Assert-Path $RepoTopData "smartAcesso-topData"
Assert-Path $RepoElectron "smartacesso-desktop-electron"

New-Item -ItemType Directory -Force -Path $Staging, $Dist, $Tools | Out-Null

if (-not $SkipJava) {
    Get-WinSw

    Write-Step "Build nucleo SmartAcesso (JDK 21)"
    Invoke-MvnPackage -Repo $RepoCore -JavaHome $Jdk21
    $coreJar = Join-Path $RepoCore "target\smartacesso.jar"
    Assert-Path $coreJar "JAR do nucleo"

    $coreOut = Join-Path $Staging "core"
    if (Test-Path $coreOut) { Remove-Item $coreOut -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $coreOut | Out-Null
    Copy-Item $coreJar (Join-Path $coreOut "smartacesso.jar")
    Copy-Item (Join-Path $InstallerRoot "resources\winsw\SmartAcessoCore.xml.tpl") $coreOut
    Copy-Item $WinSwExe (Join-Path $coreOut "SmartAcessoCore.exe")

    Write-Step "Gerando JRE 21 64-bit do nucleo (jlink)"
    New-Jre21 -JdkHome $Jdk21 -Destination (Join-Path $coreOut "jre")

    Write-Step "Build TopData (Liberica JDK 21 32-bit)"
    Invoke-MvnPackage -Repo $RepoTopData -JavaHome $Jdk21x86
    $topJar = Join-Path $RepoTopData "target\topdata.jar"
    Assert-Path $topJar "JAR do TopData"

    $topOut = Join-Path $Staging "topdata"
    if (Test-Path $topOut) { Remove-Item $topOut -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $topOut | Out-Null
    Copy-Item $topJar (Join-Path $topOut "topdata.jar")
    Copy-Item (Join-Path $InstallerRoot "resources\winsw\SmartAcessoTopData.xml.tpl") $topOut
    Copy-Item $WinSwExe (Join-Path $topOut "SmartAcessoTopData.exe")

    Write-Step "Gerando JRE 21 32-bit do TopData (jlink Liberica)"
    New-Jre21 -JdkHome $Jdk21x86 -Destination (Join-Path $topOut "jre")

    $nativeSrc = Join-Path $RepoTopData "lib"
    Assert-Path $nativeSrc "pasta lib do TopData (JARs + DLLs nativas)"
    $easyInnerDll = Join-Path $nativeSrc "EasyInner.dll"
    Assert-Path $easyInnerDll "EasyInner.dll (obrigatoria em smartAcesso-topData\lib para o servico TopData)"
    Copy-Item $nativeSrc (Join-Path $topOut "native") -Recurse -Force

    $configOut = Join-Path $Staging "config"
    if (Test-Path $configOut) { Remove-Item $configOut -Recurse -Force }
    Copy-Item (Join-Path $InstallerRoot "resources\config") $configOut -Recurse -Force
}

if (-not $SkipElectron) {
    Write-Step "Empacotando Desktop (electron-builder --dir)"
    Push-Location $RepoElectron
    try {
        if (-not (Test-Path (Join-Path $RepoElectron "node_modules\electron-builder"))) {
            npm install
            if ($LASTEXITCODE -ne 0) { throw "npm install falhou no Electron" }
        }
        npm run pack:win
        if ($LASTEXITCODE -ne 0) { throw "electron-builder falhou" }
    }
    finally {
        Pop-Location
    }

    $unpacked = Join-Path $RepoElectron "dist\win-unpacked"
    Assert-Path $unpacked "electron-builder win-unpacked"
    $desktopOut = Join-Path $Staging "desktop"
    if (Test-Path $desktopOut) { Remove-Item $desktopOut -Recurse -Force }
    Copy-Item $unpacked $desktopOut -Recurse -Force
}

if (-not $SkipInstaller) {
    Write-Step "Compilando Inno Setup"
    $iscc = Install-InnoSetupIfMissing
    if (-not $iscc) {
        Write-Host ""
        Write-Host "Inno Setup 6 nao encontrado. Staging pronto em:" -ForegroundColor Yellow
        Write-Host "  $Staging"
        Write-Host "Instale https://jrsoftware.org/isinfo.php e rode de novo com:"
        Write-Host "  .\build.ps1 -SkipJava -SkipElectron"
        exit 0
    }

    $iss = Join-Path $InstallerRoot "inno\SmartAcesso.iss"
    & $iscc "/DMyAppVersion=$Version" $iss
    if ($LASTEXITCODE -ne 0) {
        throw "ISCC falhou (exit $LASTEXITCODE)"
    }

    Write-Step "Pronto"
    Get-ChildItem $Dist -Filter "SmartAcesso-Setup-*.exe" | ForEach-Object {
        Write-Host ("  {0} ({1:N1} MB)" -f $_.FullName, ($_.Length / 1MB))
    }
}
