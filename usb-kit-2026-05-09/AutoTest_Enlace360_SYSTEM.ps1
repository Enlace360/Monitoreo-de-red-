param(
    [string]$InstallDir = "C:\ProgramData\Enlace360\Agent",
    [string]$ClientName = "Cenco Malls",
    [string]$Location = "Costanera",
    [string]$KioskName = $env:COMPUTERNAME,
    [int]$ObserveSeconds = 180,
    [switch]$SkipInstall,
    [switch]$PostReboot,
    [switch]$AutoReboot
)

$ErrorActionPreference = "Stop"
$AutoTestVersion = "SYSTEM-2026-06-04.1"
$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile = "C:\Enlace360_SYSTEM_autotest.log"
$ServiceName = "Enlace360Agent"
$TaskAgent = "Enlace360_Agent"
$TaskHealthCheck = "Enlace360_HealthCheck"
$PostRebootTaskName = "Enlace360_SYSTEM_AutoTest_PostReboot"
$InstallerScript = Join-Path $SourceDir "Instalar_Enlace360_SYSTEM.ps1"
$VerifierScript = Join-Path $SourceDir "Verificar_Enlace360_SYSTEM.ps1"
$DiagnosticScript = Join-Path $SourceDir "Diagnosticar_Enlace360_SYSTEM.ps1"
$ReadmePath = Join-Path $SourceDir "README_SYSTEM_FINAL.txt"
$RequiredScripts = @(
    "Agente_Enlace360_Service.ps1",
    "Instalar_Enlace360_SYSTEM.ps1",
    "Verificar_Enlace360_SYSTEM.ps1",
    "Diagnosticar_Enlace360_SYSTEM.ps1",
    "AutoTest_Enlace360_SYSTEM.ps1"
)

function Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    $line | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Ejecuta AutoTest_Enlace360_SYSTEM.bat como Administrador."
    }
}

function Assert-FileExists {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Falta $Label`: $Path"
    }
    Log ("OK archivo {0}: {1}" -f $Label, $Path)
}

function Assert-PowerShellSyntax {
    param([string]$Path)
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        foreach ($parseError in $errors) {
            Log ("[PARSER] {0}:{1}:{2} {3}" -f $Path, $parseError.Extent.StartLineNumber, $parseError.Extent.StartColumnNumber, $parseError.Message)
        }
        throw "ParserError en $Path"
    }
    Log ("OK sintaxis PowerShell: {0}" -f $Path)
}

function Invoke-LoggedStep {
    param([string]$Name, [scriptblock]$Action)
    Log ("===== INICIO {0} =====" -f $Name)
    try {
        & $Action
        Log ("===== PASS {0} =====" -f $Name)
    } catch {
        Log ("===== FAIL {0}: {1} =====" -f $Name, $_.Exception.Message)
        throw
    }
}

function Test-KitVersion {
    Assert-FileExists -Path $ReadmePath -Label "README"
    $readme = Get-Content -LiteralPath $ReadmePath -Raw -ErrorAction Stop
    if ($readme -notmatch [regex]::Escape($AutoTestVersion)) {
        throw "README no declara version $AutoTestVersion"
    }
    Log ("OK version kit {0}" -f $AutoTestVersion)
}

function Test-KitFiles {
    foreach ($fileName in $RequiredScripts) {
        $path = Join-Path $SourceDir $fileName
        Assert-FileExists -Path $path -Label $fileName
        Assert-PowerShellSyntax -Path $path
    }
}

function Invoke-Installer {
    Assert-FileExists -Path $InstallerScript -Label "instalador"
    Log "Ejecutando instalador directo sin prompts BAT"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallerScript -InstallDir $InstallDir -ClientName $ClientName -Location $Location -KioskName $KioskName
    $exit = $LASTEXITCODE
    if ($exit -ne 0) {
        throw "Instalador fallo con exit=$exit. Revisa C:\Enlace360_SYSTEM_installer.log"
    }
}

function Invoke-Verifier {
    Assert-FileExists -Path $VerifierScript -Label "verificador"
    Log "Ejecutando verificador con TestHealthCheck"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $VerifierScript -InstallDir $InstallDir -ObserveSeconds $ObserveSeconds -TestHealthCheck
    $exit = $LASTEXITCODE
    if ($exit -ne 0) {
        throw "Verificador fallo con exit=$exit. Revisa C:\Enlace360_SYSTEM_verifier.log"
    }
}

function Test-ServiceAndTasks {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) { throw "No existe servicio $ServiceName" }
    Log ("Servicio {0}: Status={1}; StartType={2}" -f $ServiceName, $svc.Status, $svc.StartType)
    if ($svc.Status -ne "Running") { throw "Servicio $ServiceName no esta Running" }

    foreach ($taskName in @($TaskAgent, $TaskHealthCheck)) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if (-not $task) { throw "No existe tarea $taskName" }
        $info = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
        Log ("Tarea {0}: State={1}; Last={2}" -f $taskName, $task.State, $info.LastTaskResult)
    }
}

function Get-RelatedProcesses {
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        ($_.Name -eq "powershell.exe" -or $_.Name -eq "pwsh.exe") -and
        $_.CommandLine -like "*Agente_Enlace360_Service.ps1*"
    })
}

function Test-AgentProcess {
    $procs = Get-RelatedProcesses
    if ($procs.Count -lt 1) {
        throw "No se detecta proceso Agente_Enlace360_Service.ps1"
    }
    foreach ($proc in $procs) {
        Log ("Proceso agente pid={0} cmd={1}" -f $proc.ProcessId, $proc.CommandLine)
    }
}

function Register-PostRebootTask {
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -InstallDir `"$InstallDir`" -ClientName `"$ClientName`" -Location `"$Location`" -KioskName `"$KioskName`" -ObserveSeconds $ObserveSeconds -SkipInstall -PostReboot"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $args -WorkingDirectory $SourceDir
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)
    Register-ScheduledTask -TaskName $PostRebootTaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Continuacion post-reinicio AutoTest Enlace360 SYSTEM" -Force | Out-Null
    Log ("OK post-reinicio registrado: {0}" -f $PostRebootTaskName)
}

function Clear-PostRebootTask {
    Stop-ScheduledTask -TaskName $PostRebootTaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $PostRebootTaskName -Confirm:$false -ErrorAction SilentlyContinue
}

function Export-AutoTestEvidence {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $evidenceDir = Join-Path $env:TEMP ("Enlace360_SYSTEM_AutoTest_{0}" -f $stamp)
    New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null

    $knownLogs = @(
        "C:\Enlace360_SYSTEM_autotest.log",
        "C:\Enlace360_SYSTEM_installer.log",
        "C:\Enlace360_SYSTEM_verifier.log",
        (Join-Path $InstallDir "agente.log"),
        (Join-Path $InstallDir "healthcheck.log"),
        (Join-Path $InstallDir "c2.log"),
        (Join-Path $InstallDir "install_manifest.json"),
        (Join-Path $InstallDir "integrity_state.json")
    )
    foreach ($logPath in $knownLogs) {
        if (Test-Path -LiteralPath $logPath -PathType Leaf) {
            Copy-Item -LiteralPath $logPath -Destination (Join-Path $evidenceDir (Split-Path $logPath -Leaf)) -Force -ErrorAction SilentlyContinue
        }
    }

    Get-Service -Name $ServiceName -ErrorAction SilentlyContinue | Format-List * | Out-File -FilePath (Join-Path $evidenceDir "service_Enlace360Agent.txt") -Encoding UTF8
    Get-ScheduledTask -TaskName $TaskAgent, $TaskHealthCheck, $PostRebootTaskName -ErrorAction SilentlyContinue | Format-List * | Out-File -FilePath (Join-Path $evidenceDir "scheduled_tasks.txt") -Encoding UTF8
    Get-RelatedProcesses | Format-List * | Out-File -FilePath (Join-Path $evidenceDir "agent_processes.txt") -Encoding UTF8
    "remote_commands verification is executed by Verificar_Enlace360_SYSTEM.ps1 and logged in C:\Enlace360_SYSTEM_verifier.log." | Out-File -FilePath (Join-Path $evidenceDir "remote_commands_context.txt") -Encoding UTF8

    $zipPath = "C:\Enlace360_SYSTEM_AutoTest_$stamp.zip"
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -Path (Join-Path $evidenceDir "*") -DestinationPath $zipPath -Force
    Log ("Evidencia AutoTest: {0}" -f $zipPath)
}

try {
    "" | Out-File -FilePath $LogFile -Force -Encoding UTF8
    Log ("===== AUTOTEST SYSTEM ENLACE360 {0} =====" -f $AutoTestVersion)
    Log ("Equipo={0}; Usuario={1}; SourceDir={2}; InstallDir={3}" -f $env:COMPUTERNAME, [Security.Principal.WindowsIdentity]::GetCurrent().Name, $SourceDir, $InstallDir)
    Log ("Cliente={0}; Ubicacion={1}; Kiosco={2}; SkipInstall={3}; PostReboot={4}; AutoReboot={5}" -f $ClientName, $Location, $KioskName, $SkipInstall.IsPresent, $PostReboot.IsPresent, $AutoReboot.IsPresent)

    Invoke-LoggedStep -Name "Admin" -Action { Assert-Admin }
    Invoke-LoggedStep -Name "Preflight kit" -Action {
        Test-KitVersion
        Test-KitFiles
    }

    if ($PostReboot) {
        Invoke-LoggedStep -Name "Limpiar tarea post-reinicio" -Action { Clear-PostRebootTask }
    }

    if (-not $SkipInstall) {
        Invoke-LoggedStep -Name "Instalar" -Action { Invoke-Installer }
    } else {
        Log "SkipInstall activo: no se ejecuta instalador."
    }

    Invoke-LoggedStep -Name "Servicio y tareas" -Action { Test-ServiceAndTasks }
    Invoke-LoggedStep -Name "Proceso agente" -Action { Test-AgentProcess }
    Invoke-LoggedStep -Name "Verificador completo" -Action { Invoke-Verifier }
    Invoke-LoggedStep -Name "Evidencia" -Action { Export-AutoTestEvidence }

    if (-not $PostReboot) {
        Invoke-LoggedStep -Name "Preparar post-reinicio" -Action { Register-PostRebootTask }
        if ($AutoReboot) {
            Log "AutoReboot activo: reiniciando Windows en 15 segundos."
            shutdown.exe /r /t 15 /c "Enlace360 AutoTest SYSTEM post-reinicio" | Out-Null
        } else {
            Log "Post-reinicio listo. Reinicia Windows manualmente y el AutoTest continuara como SYSTEM al arrancar."
        }
    }

    Log "[PASS] AUTOTEST SYSTEM ENLACE360 completado."
    exit 0
} catch {
    Log ("[FAIL] AUTOTEST SYSTEM ENLACE360: {0}" -f $_.Exception.Message)
    try { Export-AutoTestEvidence } catch { Log ("[WARN] No se pudo exportar evidencia: {0}" -f $_.Exception.Message) }
    exit 1
}
