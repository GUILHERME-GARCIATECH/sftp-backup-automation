#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

<#
SCAN + PROMOTE (Servidor)
- Lê ZIPs em E:\SFTP-IN\Clientes\<Cliente>\_incoming
- Faz lock movendo para _processing
- Escaneia com Windows Defender (MpCmdRun)
- Se limpo: move para C:\SRV-BACKUP\<Cliente>\FINAL e copia para SharePoint sync \<Cliente>\FINAL
- Se suspeito/infectado: move para E:\SFTP-IN\Clientes\<Cliente>\_quarantine
#>

# =========================
# CONFIGURAÇÕES
# =========================
$IncomingRoot      = "E:\SFTP-IN\Clientes"
$LocalFinalRoot    = "C:\SRV-BACKUP"  # cada cliente: C:\SRV-BACKUP\<Cliente>\FINAL
$SharePointRoot    = "C:\pasta\na\nuvem" # sync (limpo)

$ScanMinAgeMinutes = 3      # não pega arquivo com menos de X minutos
$OnlyExtensions    = @(".zip")

$ServerLogRoot     = "E:\SFTP-IN\_server-logs"
$RunId             = ([guid]::NewGuid()).ToString().Substring(0,8)
$LogFile           = Join-Path $ServerLogRoot ("scan_promote_{0}_{1}.log" -f (Get-Date -Format "yyyy-MM-dd_HH-mm-ss"), $RunId)

# Defender
$MpCmdRun = Join-Path $env:ProgramFiles "Windows Defender\MpCmdRun.exe"
if (!(Test-Path -LiteralPath $MpCmdRun)) {
  $MpCmdRun = Join-Path $env:ProgramFiles "Microsoft Defender\MpCmdRun.exe"
}

# =========================
# FUNÇÕES
# =========================
function Ensure-Dir([string]$Path) {
  if (!(Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Write-Log([string]$Msg) {
  $line = "{0}  [{1}]  {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $RunId, $Msg
  Write-Host $line
  Add-Content -LiteralPath $LogFile -Value $line
}

function Get-ClientNameFromPath([string]$Path) {
  # Esperado: E:\SFTP-IN\Clientes\<Cliente>\_incoming\arquivo.zip
  $p1 = Split-Path -Parent $Path       # ...\_incoming
  $p2 = Split-Path -Parent $p1         # ...\<Cliente>
  return (Split-Path -Leaf $p2)
}

function Invoke-DefenderScanFile([string]$FilePath) {
  if (!(Test-Path -LiteralPath $FilePath)) { throw "Arquivo não encontrado para scan: $FilePath" }
  if (!(Test-Path -LiteralPath $MpCmdRun))  { throw "MpCmdRun.exe não encontrado (Defender)." }

  $start = Get-Date

  $out = & $MpCmdRun -Scan -ScanType 3 -File "$FilePath" 2>&1
  $code = $LASTEXITCODE

  Write-Log "Defender Scan..: ExitCode=$code File=$FilePath"
  $out | ForEach-Object { Write-Log "Defender> $_" }

  # Confirmação adicional: tenta consultar detecções recentes ligadas ao arquivo
  $detected = $false
  try {
    $recent = @(Get-MpThreatDetection -ErrorAction SilentlyContinue |
      Where-Object {
        ($_.InitialDetectionTime -ge $start.AddMinutes(-2)) -or
        ($_.LastThreatStatusChangeTime -ge $start.AddMinutes(-2))
      })

    foreach ($d in $recent) {
      $res = $d.Resources -join " | "
      if ($res -and ($res -like "*$FilePath*")) {
        $detected = $true
        Write-Log "Defender Detect.: ThreatName=$($d.ThreatName) Severity=$($d.SeverityID) Resources=$res"
        break
      }
    }
  } catch {
    Write-Log "Aviso.........: Não consegui consultar Get-MpThreatDetection: $($_.Exception.Message)"
  }

  # Fail-safe:
  if ($detected) { return @{ Status="INFECTED"; ExitCode=$code } }
  if ($code -ne 0) { return @{ Status="SUSPECT"; ExitCode=$code } }
  return @{ Status="CLEAN"; ExitCode=$code }
}

function Safe-Move([string]$From, [string]$To) {
  Ensure-Dir (Split-Path -Parent $To)
  if (Test-Path -LiteralPath $To) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $To = "{0}.{1}.dup" -f $To, $stamp
  }
  Move-Item -LiteralPath $From -Destination $To -Force
  return $To
}

function Safe-Copy([string]$From, [string]$To) {
  Ensure-Dir (Split-Path -Parent $To)
  Copy-Item -LiteralPath $From -Destination $To -Force
}

# =========================
# EXECUÇÃO
# =========================
Ensure-Dir $ServerLogRoot

Write-Log "===== SCAN+PROMOTE START ====="
Write-Log "IncomingRoot...: $IncomingRoot"
Write-Log "LocalFinalRoot.: $LocalFinalRoot"
Write-Log "SharePointRoot.: $SharePointRoot"
Write-Log "MinAge(min)....: $ScanMinAgeMinutes"
Write-Log "MpCmdRun.......: $MpCmdRun"
Write-Log "=============================="

if (!(Test-Path -LiteralPath $IncomingRoot)) {
  Write-Log "Nada a fazer...: IncomingRoot não existe."
  Write-Log "===== END ====="
  exit 0
}

$now = Get-Date
$cutoff = $now.AddMinutes(-$ScanMinAgeMinutes)

# FORÇA ARRAY com @(...)
$zips = @(
  Get-ChildItem -LiteralPath $IncomingRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
      $_.DirectoryName -like "*\_incoming" -and
      $OnlyExtensions -contains $_.Extension.ToLower() -and
      $_.LastWriteTime -le $cutoff
    } |
    Sort-Object LastWriteTime
)

Write-Log "Encontrados.....: $($zips.Count) arquivo(s) elegível(is) para processar."

foreach ($f in $zips) {
  try {
    $client = Get-ClientNameFromPath $f.FullName

    $incomingDir    = Join-Path (Join-Path $IncomingRoot $client) "_incoming"
    $processingDir  = Join-Path $incomingDir "_processing"
    $quarantineDir  = Join-Path (Join-Path $IncomingRoot $client) "_quarantine"

    $localFinalDir  = Join-Path (Join-Path $LocalFinalRoot $client) "FINAL"
    $spFinalDir     = Join-Path (Join-Path $SharePointRoot $client) "FINAL"

    Ensure-Dir $processingDir
    Ensure-Dir $quarantineDir
    Ensure-Dir $localFinalDir
    Ensure-Dir $spFinalDir

    Write-Log "----------------------------------------"
    Write-Log "Arquivo........: $($f.FullName)"
    Write-Log "Cliente........: $client"

    # 1) LOCK: move para _processing
    $lockedPath = Join-Path $processingDir $f.Name
    $lockedPath = Safe-Move -From $f.FullName -To $lockedPath
    Write-Log "Lock..........: OK -> $lockedPath"

    # 2) SCAN
    $scan = Invoke-DefenderScanFile -FilePath $lockedPath
    Write-Log "Scan Status...: $($scan.Status) (ExitCode=$($scan.ExitCode))"

    if ($scan.Status -eq "CLEAN") {
      # 3) PROMOTE
      $destLocal = Join-Path $localFinalDir $f.Name
      $destLocal = Safe-Move -From $lockedPath -To $destLocal
      Write-Log "Promote Local.: OK -> $destLocal"

      $destSp = Join-Path $spFinalDir $f.Name
      Safe-Copy -From $destLocal -To $destSp
      Write-Log "Promote SP....: OK -> $destSp"
    } else {
      # 4) QUARANTINE
      $destQ = Join-Path $quarantineDir $f.Name
      $destQ = Safe-Move -From $lockedPath -To $destQ
      Write-Log "Quarantine....: OK -> $destQ"
    }

  } catch {
    Write-Log "ERRO..........: $($_.Exception.Message)"
  }
}

Write-Log "===== SCAN+PROMOTE END ====="
