#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =========================
# CONFIGURAÇÕES
# =========================
$ScriptVersion = "1.9.1"

$BackupHost = "192.168.10.161"
$BackupUser = "Guilherme.ASS"          # usuário SFTP
$Client     = "Guilherme.ASS"          # deve ser IGUAL ao usuário (pasta no servidor)
$Key        = "$env:USERPROFILE\.ssh\id_ed25519"

# Use caminho absoluto do OpenSSH pra não depender do PATH (ISE/Task Scheduler)
$SftpExe    = Join-Path $env:WINDIR "System32\OpenSSH\sftp.exe"

if ($Client -ne $BackupUser) {
  throw "Config inválida: Client ('$Client') diferente de BackupUser ('$BackupUser'). Ajuste para serem iguais."
}

# =========================
# REMOTE DIRS (SFTP)
# =========================
$RemoteIncomingDir     = "/C:/SRV-BACKUP/$Client/_incoming"
$RemoteIncomingLogsDir = "$RemoteIncomingDir/logs"

# =========================
# ORIGENS
# =========================
$Pastas = @(
  "C:\Users\Guilherme.Garcia\Downloads"
)

# =========================
# PADRÃO LOCAL
# =========================
$RootLocal = "C:\TI\backup-sftp"

if (!(Test-Path -LiteralPath $RootLocal)) {
  throw "Pasta base não encontrada: $RootLocal. Crie manualmente e rode de novo."
}

$StageDir    = Join-Path $RootLocal ("Stage\{0}" -f $Client)
$StateDir    = Join-Path $RootLocal "State"
$TempDir     = Join-Path $RootLocal "Temp"
$LogDir      = Join-Path $RootLocal "Logs"

$LastRunFile = Join-Path $StateDir ("{0}_last_success.txt" -f $Client.ToLower())
$LogFile     = Join-Path $LogDir ("{0}_{1}.log" -f $Client.ToLower(), (Get-Date -Format "yyyy-MM-dd_HH-mm-ss"))

$LogRetentionDays = 30
$Data    = Get-Date -Format "yyyy-MM-dd_HH-mm"
$Arquivo = ("{0}_delta_{1}.zip" -f $Client.ToLower(), $Data)
$ZipPath = Join-Path $TempDir $Arquivo

# =========================
# VARIÁVEIS DE EXECUÇÃO / LOG
# =========================
$RunId = ([guid]::NewGuid()).ToString().Substring(0,8)
$StartTime = Get-Date
$Global:BackupStatus = "RUNNING"
$Global:FailReason   = ""

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

function Fail([string]$Msg, [int]$Code = 1) {
  $Global:BackupStatus = "FAILED"
  $Global:FailReason = $Msg
  Write-Log "ERRO CRÍTICO: $Msg"
  throw $Msg
}

function Send-FileToServer {
  param(
    [Parameter(Mandatory=$true)][string]$LocalPath,
    [Parameter(Mandatory=$true)][string]$KeyPath,
    [Parameter(Mandatory=$true)][string]$User,
    [Parameter(Mandatory=$true)][string]$SftpHost,
    [Parameter(Mandatory=$true)][string]$TempFolder,
    [Parameter(Mandatory=$true)][string]$RemoteTargetDir,
    [Parameter(Mandatory=$true)][string]$Tag
  )

  try {
    if (!(Test-Path -LiteralPath $LocalPath)) {
      Write-Log "SFTP($Tag).....: Arquivo não existe localmente: $LocalPath"
      return $false
    }
    if (!(Test-Path -LiteralPath $SftpExe)) {
      Write-Log "SFTP($Tag).....: sftp.exe não encontrado em: $SftpExe"
      return $false
    }
    if (!(Test-Path -LiteralPath $KeyPath)) {
      Write-Log "SFTP($Tag).....: Chave não encontrada: $KeyPath"
      return $false
    }

    Ensure-Dir $TempFolder
    $batch = Join-Path $TempFolder ("sftp_{0}_{1}_{2}.txt" -f $Tag.ToLower(), $Client.ToLower(), (Get-Date -Format "yyyyMMdd_HHmmss"))

@"
cd $RemoteTargetDir
put "$LocalPath"
bye
"@ | Set-Content -LiteralPath $batch -Encoding ASCII

    Write-Log "SFTP($Tag).....: Iniciando envio"
    Write-Log "SFTP($Tag) Host: $User@$SftpHost"
    Write-Log "SFTP($Tag) Dest: $RemoteTargetDir"
    Write-Log "SFTP($Tag) File: $LocalPath"
    Write-Log "SFTP($Tag) Exe.: $SftpExe"

    $out = & $SftpExe -b $batch -i $KeyPath "$User@$SftpHost" 2>&1
    $code = $LASTEXITCODE

    $out | ForEach-Object { Write-Log "SFTP($Tag)> $_" }

    Remove-Item -LiteralPath $batch -Force -ErrorAction SilentlyContinue

    if ($code -ne 0) {
      Write-Log "SFTP($Tag).....: FALHOU (ExitCode=$code)"
      return $false
    }

    Write-Log "SFTP($Tag).....: OK"
    return $true
  } catch {
    Write-Log "SFTP($Tag).....: EXCEÇÃO ao enviar: $($_.Exception.Message)"
    return $false
  }
}

function Update-LastSuccess {
  $nowIso = (Get-Date).ToString("o")
  Ensure-Dir $StateDir
  Set-Content -LiteralPath $LastRunFile -Value $nowIso -Force
  Write-Log "State..........: Last success atualizado em $LastRunFile => $nowIso"
}

# =========================
# INÍCIO
# =========================
try {
  Ensure-Dir $TempDir
  Ensure-Dir $LogDir
  Ensure-Dir $StageDir
  Ensure-Dir $StateDir

  Write-Log "===== BACKUP START ====="
  Write-Log "Run ID........: $RunId"
  Write-Log "Client........: $Client"
  Write-Log "Host..........: $env:COMPUTERNAME"
  Write-Log "User..........: $env:USERNAME"
  Write-Log "Script........: $PSCommandPath"
  Write-Log "Version.......: $ScriptVersion"
  Write-Log "RootLocal.....: $RootLocal"
  Write-Log "Start Time....: $StartTime"
  Write-Log "Remote In.....: $RemoteIncomingDir"
  Write-Log "Remote InLogs.: $RemoteIncomingLogsDir"
  Write-Log "========================"

  # Limpeza de logs antigos
  Write-Log "Limpando logs antigos (Retenção: $LogRetentionDays dias)..."
  Get-ChildItem -Path $LogDir -Filter "*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$LogRetentionDays) } |
    ForEach-Object {
      try {
        Remove-Item $_.FullName -Force
        Write-Log "Log removido: $($_.Name)"
      } catch {
        Write-Log "Aviso: Não foi possível remover o log $($_.Name)"
      }
    }

  # Validações
  if (!(Test-Path -LiteralPath $Key))    { Fail "Chave SSH não encontrada: $Key" 10 }
  if (!(Test-Path -LiteralPath $SftpExe)){ Fail "sftp.exe não encontrado em: $SftpExe" 11 }

  # Determina baseline
  $Since = $null
  if (Test-Path -LiteralPath $LastRunFile) {
    $raw = (Get-Content -LiteralPath $LastRunFile | Select-Object -First 1).Trim()
    if ($raw) { $Since = [DateTime]::Parse($raw) }
  }

  if (-not $Since) {
    $Since = (Get-Date).AddYears(-50)
    Write-Log "Backup Type...: FULL (primeira execução)"
    Write-Log "Baseline From.: (n/a)"
  } else {
    Write-Log "Backup Type...: INCREMENTAL"
    Write-Log "Baseline From.: $Since"
  }

  # Limpa staging
  Write-Log "Limpando Stage: $StageDir"
  if (Test-Path -LiteralPath $StageDir) {
    Get-ChildItem -LiteralPath $StageDir -Force -Recurse -ErrorAction SilentlyContinue |
      Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
  }
  Ensure-Dir $StageDir

  $totalCopied = 0
  $dateStr = $Since.ToString("yyyyMMdd")   # Robocopy trabalha por data (dia)

  $roboHadError = $false

  foreach ($src in $Pastas) {
    if (!(Test-Path -LiteralPath $src)) { Write-Log "Aviso: Origem não encontrada: $src"; continue }

    $srcName = Split-Path $src -Leaf
    $dest = Join-Path $StageDir $srcName
    Ensure-Dir $dest

    Write-Log "Robocopy Source.: $src"
    Write-Log "Robocopy Dest...: $dest"

    # IMPORTANTE:
    # /MAXAGE:yyyyMMdd => exclui arquivos mais antigos que a baseline => mantém apenas os mais novos/iguais
    $roboArgs = @($src, $dest, "/S", "/XO", "/FFT", "/R:1", "/W:2", "/XJD", "/NP", "/NFL", "/NDL", "/MAXAGE:$dateStr")

    $null = & robocopy @roboArgs
    $rc = $LASTEXITCODE

    if ($rc -ge 8) {
      $roboHadError = $true
      Write-Log "Aviso: Robocopy retornou erro (ExitCode: $rc) para: $src"
    } else {
      Write-Log "Robocopy OK (ExitCode: $rc) para: $src"
    }

    $count = (Get-ChildItem -LiteralPath $dest -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
    $totalCopied += $count
    Write-Log "Arquivos no Stage para '$srcName': $count"
  }

  # Se não tem nada novo
  if ($totalCopied -le 0) {
    $Global:BackupStatus = "SUCCESS"

    $end = Get-Date
    $duration = $end - $StartTime
    Write-Log "Nenhuma alteração detectada. Nada a compactar/enviar."
    Write-Log "Files Copied..: 0"
    Write-Log "Data Size.....: 0.00 GB"
    Write-Log "Duration......: $($duration.ToString())"

    # ATUALIZA estado mesmo sem mudanças (baseline anda)
    Update-LastSuccess

    Write-Log "Upload ZIP....: SKIPPED (sem mudanças)"
    Write-Log "Upload LOG....: ATTEMPT (para _incoming/logs)"

    $okLog = Send-FileToServer -LocalPath $LogFile -KeyPath $Key -User $BackupUser -SftpHost $BackupHost `
      -TempFolder $TempDir -RemoteTargetDir $RemoteIncomingLogsDir -Tag "LOG"

    Write-Log ("Upload LOG....: {0}" -f ($(if($okLog){"OK"}else{"FAILED"})))

    Write-Log "STATUS........: $Global:BackupStatus"
    Write-Log "END TIME......: $end"
    Write-Log "===== BACKUP END ====="
    exit 0
  }

  # ZIP
  Write-Log "Criando ZIP....: $ZipPath"
  Compress-Archive -Path "$StageDir\*" -DestinationPath $ZipPath -Force

  # Métricas
  $files = @(Get-ChildItem -LiteralPath $StageDir -Recurse -File -ErrorAction SilentlyContinue)
  $fileCount = $files.Count
  $sizeBytes = ($files | Measure-Object Length -Sum).Sum
  if (-not $sizeBytes) { $sizeBytes = 0 }
  $sizeGB = [Math]::Round($sizeBytes / 1GB, 2)

  Write-Log "Files Copied..: $fileCount"
  Write-Log "Data Size.....: $sizeGB GB"

  # SFTP ZIP -> _incoming
  Write-Log "Upload ZIP....: ATTEMPT (para _incoming)"
  $okZip = Send-FileToServer -LocalPath $ZipPath -KeyPath $Key -User $BackupUser -SftpHost $BackupHost `
    -TempFolder $TempDir -RemoteTargetDir $RemoteIncomingDir -Tag "ZIP"

  if (-not $okZip) {
    Fail "Falha no envio SFTP do ZIP para _incoming." 40
  }

  Write-Log "Upload ZIP....: OK (enviado para _incoming; aguardando scan/promote no servidor)"

  # Atualiza estado e limpa ZIP local
  Update-LastSuccess
  Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue

  # Status final
  if ($roboHadError) {
    $Global:BackupStatus = "SUCCESS_WITH_WARNINGS"
    $Global:FailReason = "Robocopy teve erro em uma ou mais origens (ver ExitCode no log)."
  } else {
    $Global:BackupStatus = "SUCCESS"
    $Global:FailReason = ""
  }

  $end = Get-Date
  $duration = $end - $StartTime

  Write-Log "Duration......: $($duration.ToString())"
  if ($Global:FailReason) { Write-Log "Notes.........: $Global:FailReason" }

  # LOG -> _incoming/logs (best-effort)
  Write-Log "Upload LOG....: ATTEMPT (para _incoming/logs)"
  $okLog2 = Send-FileToServer -LocalPath $LogFile -KeyPath $Key -User $BackupUser -SftpHost $BackupHost `
    -TempFolder $TempDir -RemoteTargetDir $RemoteIncomingLogsDir -Tag "LOG"

  Write-Log ("Upload LOG....: {0}" -f ($(if($okLog2){"OK"}else{"FAILED"})))

  Write-Log "STATUS........: $Global:BackupStatus"
  Write-Log "END TIME......: $end"
  Write-Log "===== BACKUP END ====="

} catch {
  if ($Global:BackupStatus -ne "FAILED") { $Global:BackupStatus = "FAILED" }
  if (-not $Global:FailReason) { $Global:FailReason = $_.Exception.Message }

  try {
    Write-Log "EXCEÇÃO......: $($_.Exception.Message)"
    Write-Log "STATUS........: $Global:BackupStatus"
    Write-Log "Reason........: $Global:FailReason"
    Write-Log "END TIME......: $(Get-Date)"
    Write-Log "===== BACKUP END ====="
  } catch {}

  # tenta enviar o log mesmo em falha (best-effort)
  try {
    $null = Send-FileToServer -LocalPath $LogFile -KeyPath $Key -User $BackupUser -SftpHost $BackupHost `
      -TempFolder $TempDir -RemoteTargetDir $RemoteIncomingLogsDir -Tag "LOG"
  } catch {}

  if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue }
  exit 99
}