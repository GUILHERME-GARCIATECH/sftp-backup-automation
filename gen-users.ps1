#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =========================
# VARIÁVEIS FÁCEIS (EDITE AQUI)
# =========================
$ClientUser       = "Client_Name"
$ClientFullName   = "Client_Name_completo"
$CreateLocalUser  = $true

$BackupHost       = "SEU_IP_OU_DNS_DO_SERVIDOR"

# Cole aqui a CHAVE PÚBLICA (uma linha):
$ClientPublicKey  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqq2543e5453gfdgfdgfdgFDGDFGfdgFDGfdgfdseuemail@exemplo.com"

# =========================
# ESTRUTURA - ARQUITETURA SEGURA (CHROOT + INCOMING EM E:)
# =========================
$BackupRoot   = "C:\SRV-BACKUP"
$ClientRoot   = Join-Path $BackupRoot $ClientUser

# Dentro do chroot (o que o cliente “vê”):
$IncomingDir  = Join-Path $ClientRoot "_incoming"

# Físico (onde os arquivos caem de verdade):
$IncomingPhysicalRoot      = "E:\SFTP-IN\Clientes"
$ClientPhysicalRoot        = Join-Path $IncomingPhysicalRoot $ClientUser
$IncomingRealDir           = Join-Path $ClientPhysicalRoot "_incoming"
$IncomingLogsRealDir       = Join-Path $IncomingRealDir "logs"

# Quarentena física (admin-only)
$QuarantineRealDir         = Join-Path $ClientPhysicalRoot "_quarantine"

# Pasta final local (admin-only)
$FinalLocalDir             = Join-Path $ClientRoot "FINAL"

# =========================
# OpenSSH
# =========================
$SshProgramData         = "C:\ProgramData\ssh"
$SshdConfigPath         = Join-Path $SshProgramData "sshd_config"
$KeysDir                = Join-Path $SshProgramData "keys"
$AuthorizedKeysPath     = Join-Path $KeysDir ("{0}_authorized_keys" -f $ClientUser)

# Segurança / comportamento
$DisablePasswordAuthGlobal = $true
$AddToOpenSshUsersGroup     = $true

# Conta(s) admin sempre permitidas no ssh
$AlwaysAllowedUsers = @("Administrador")

# SIDs (independente de idioma)
$AdminsSid = "*S-1-5-32-544" # Administrators
$SystemSid = "*S-1-5-18"     # LOCAL SYSTEM

# =========================
# FUNÇÕES
# =========================
function Ensure-Dir([string]$Path) {
  if (!(Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Execute este script em um PowerShell **Executar como Administrador**."
  }
}

function New-RandomPassword {
  $chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%*_-+='
  -join (1..24 | ForEach-Object { $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)] })
}

function Ensure-LocalUser([string]$UserName, [string]$FullName) {
  $existing = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
  if ($existing) {
    Write-Host "[OK] Usuário já existe: $UserName"
    return
  }

  $pwdPlain = New-RandomPassword
  $pwd = ConvertTo-SecureString -String $pwdPlain -AsPlainText -Force

  New-LocalUser -Name $UserName -FullName $FullName -Password $pwd `
    -PasswordNeverExpires -UserMayNotChangePassword | Out-Null

  Write-Host "[OK] Usuário criado: $UserName"
  Write-Host "     (Senha gerada automaticamente — guarde se precisar): $pwdPlain"
}

function Try-AddToOpenSshUsersGroup([string]$UserName) {
  if (-not $AddToOpenSshUsersGroup) { return }

  $candidateNames = @("OpenSSH Users","Usuários do OpenSSH","Usuarios do OpenSSH")
  $group = $null
  foreach ($g in $candidateNames) {
    $group = Get-LocalGroup -Name $g -ErrorAction SilentlyContinue
    if ($group) { break }
  }

  if (-not $group) {
    Write-Host "[WARN] Grupo 'OpenSSH Users/Usuários do OpenSSH' não encontrado. Pulando."
    return
  }

  try {
    Add-LocalGroupMember -Group $group.Name -Member $UserName -ErrorAction Stop
    Write-Host "[OK] Usuário '$UserName' adicionado ao grupo '$($group.Name)'."
  } catch {
    if ($_.Exception.Message -match "already a member") {
      Write-Host "[OK] Usuário '$UserName' já está no grupo '$($group.Name)'."
    } else {
      Write-Host "[WARN] Não foi possível adicionar ao grupo '$($group.Name)': $($_.Exception.Message)"
    }
  }
}

function Ensure-Junction([string]$LinkPath, [string]$TargetPath) {
  if (Test-Path -LiteralPath $LinkPath) {
    Write-Host "[OK] Link/pasta já existe: $LinkPath"
    return
  }

  Ensure-Dir $TargetPath
  Ensure-Dir (Split-Path -Parent $LinkPath)

  New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath | Out-Null
  Write-Host "[OK] Junction criado: $LinkPath -> $TargetPath"
}

function Ensure-KeysDirAcl([string]$DirPath) {
  Ensure-Dir $DirPath
  & icacls $DirPath /inheritance:e | Out-Null
  & icacls $DirPath /grant "${SystemSid}:(OI)(CI)F" "${AdminsSid}:(OI)(CI)F" | Out-Null
}

function Force-UnlockFileForAdmin([string]$FilePath) {
  if (-not (Test-Path -LiteralPath $FilePath)) { return }

  try { attrib -R $FilePath 2>$null | Out-Null } catch {}

  & takeown.exe /F "$FilePath" /A | Out-Null
  & icacls "$FilePath" /grant "${AdminsSid}:(F)" "${SystemSid}:(F)" | Out-Null
}

function Set-AclAuthorizedKeysFile([string]$FilePath, [string]$UserName) {
  & icacls $FilePath /inheritance:r | Out-Null
  & icacls $FilePath /grant:r "${SystemSid}:(F)" "${AdminsSid}:(F)" "${UserName}:(R)" | Out-Null
  & icacls $FilePath /remove "Everyone" "Users" "Authenticated Users" 2>$null | Out-Null
  Write-Host "[OK] ACL aplicada em: $FilePath"
}

function Write-AuthorizedKeys([string]$FilePath, [string]$UserName, [string]$PublicKeyLine) {
  $dir = Split-Path -Parent $FilePath
  Ensure-KeysDirAcl $dir

  if (Test-Path -LiteralPath $FilePath) {
    Force-UnlockFileForAdmin $FilePath
    Remove-Item -LiteralPath $FilePath -Force
  }

  Set-Content -LiteralPath $FilePath -Value ($PublicKeyLine.Trim() + "`r`n") -Encoding ASCII -Force
  Set-AclAuthorizedKeysFile -FilePath $FilePath -UserName $UserName
  Write-Host "[OK] Arquivo de chave criado/atualizado: $FilePath"
}

function Set-AclChroot([string]$ClientRootPath, [string]$UserName) {
  # Root do chroot deve ser "seguro": Admin/SYSTEM full.
  # O usuário NÃO pode escrever aqui, mas PRECISA conseguir "atravessar" (RX) para chegar no _incoming.
  & icacls $ClientRootPath /inheritance:r | Out-Null
  & icacls $ClientRootPath /grant:r "${SystemSid}:(OI)(CI)F" "${AdminsSid}:(OI)(CI)F" "${UserName}:(RX)" | Out-Null
  Write-Host "[OK] ACL aplicada no Chroot (Admins/SYSTEM F, User RX): $ClientRootPath"
}

function Set-AclIncomingPhysical([string]$IncomingRealPath, [string]$IncomingLogsRealPath, [string]$QuarantineRealPath, [string]$UserName) {
  Ensure-Dir $IncomingRealPath
  Ensure-Dir $IncomingLogsRealPath
  Ensure-Dir $QuarantineRealPath

  # Incoming real (E:): usuário pode escrever (M). Admins/SYSTEM Full.
  & icacls $IncomingRealPath /inheritance:r | Out-Null
  & icacls $IncomingRealPath /grant:r "${SystemSid}:(OI)(CI)F" "${AdminsSid}:(OI)(CI)F" "${UserName}:(OI)(CI)M" | Out-Null

  & icacls $IncomingLogsRealPath /inheritance:r | Out-Null
  & icacls $IncomingLogsRealPath /grant:r "${SystemSid}:(OI)(CI)F" "${AdminsSid}:(OI)(CI)F" "${UserName}:(OI)(CI)M" | Out-Null

  # Quarentena: admin-only
  & icacls $QuarantineRealPath /inheritance:r | Out-Null
  & icacls $QuarantineRealPath /grant:r "${SystemSid}:(OI)(CI)F" "${AdminsSid}:(OI)(CI)F" | Out-Null
  & icacls $QuarantineRealPath /remove "$UserName" 2>$null | Out-Null

  Write-Host "[OK] ACL aplicada em pastas físicas (E:):"
  Write-Host "     Incoming REAL: $IncomingRealPath"
  Write-Host "     Logs REAL....: $IncomingLogsRealPath"
  Write-Host "     Quarantine...: $QuarantineRealPath"
}

function Set-AclIncomingLink([string]$IncomingLinkPath, [string]$UserName) {
  # Garante que o item dentro do chroot (_incoming) seja atravessável pelo user.
  # (O controle de escrita real fica no alvo E:)
  if (Test-Path -LiteralPath $IncomingLinkPath) {
    & icacls $IncomingLinkPath /inheritance:e | Out-Null
    & icacls $IncomingLinkPath /grant "${UserName}:(RX)" | Out-Null
    Write-Host "[OK] ACL aplicada no link do chroot (_incoming) para permitir acesso: $IncomingLinkPath"
  }
}

function Set-AclFinalLocal([string]$FinalLocalPath, [string]$UserName) {
  Ensure-Dir $FinalLocalPath
  & icacls $FinalLocalPath /inheritance:r | Out-Null
  & icacls $FinalLocalPath /grant:r "${SystemSid}:(OI)(CI)F" "${AdminsSid}:(OI)(CI)F" | Out-Null
  & icacls $FinalLocalPath /remove "$UserName" 2>$null | Out-Null
  Write-Host "[OK] ACL aplicada em FINAL (admin-only): $FinalLocalPath"
}

function Backup-File([string]$Path) {
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $bak = "$Path.bak_$stamp"
  Copy-Item -LiteralPath $Path -Destination $bak -Force
  Write-Host "[OK] Backup do sshd_config: $bak"
}

function Ensure-GlobalSshdOptions([string]$ConfigText) {
  $t = $ConfigText

  if ($t -match '(?m)^\s*#?\s*PubkeyAuthentication\s+') {
    $t = [regex]::Replace($t, '(?m)^\s*#?\s*PubkeyAuthentication\s+.*$', 'PubkeyAuthentication yes')
  } else { $t += "`r`nPubkeyAuthentication yes`r`n" }

  if ($DisablePasswordAuthGlobal) {
    if ($t -match '(?m)^\s*#?\s*PasswordAuthentication\s+') {
      $t = [regex]::Replace($t, '(?m)^\s*#?\s*PasswordAuthentication\s+.*$', 'PasswordAuthentication no')
    } else { $t += "`r`nPasswordAuthentication no`r`n" }
  }

  if ($t -match '(?m)^\s*Subsystem\s+sftp\s+') {
    $t = [regex]::Replace($t, '(?m)^\s*Subsystem\s+sftp\s+.*$', 'Subsystem sftp sftp-server.exe')
  } else { $t += "`r`nSubsystem sftp sftp-server.exe`r`n" }

  return $t
}

function Ensure-AllowUsers([string]$ConfigText, [string[]]$AllowedUsers) {
  $t = $ConfigText

  $allowedSet = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
  foreach ($u in $AllowedUsers) { [void]$allowedSet.Add($u) }
  [void]$allowedSet.Add($ClientUser)

  $newAllow = "AllowUsers " + (($allowedSet | Sort-Object) -join " ")

  if ($t -match '(?m)^\s*AllowUsers\s+.*$') {
    $t = [regex]::Replace($t, '(?m)^\s*AllowUsers\s+.*$', $newAllow)
  } else {
    $t += "`r`n# Controle de quem pode logar`r`n$newAllow`r`n"
  }

  return $t
}

function Remove-ExistingMatchBlock([string]$ConfigText, [string]$UserName) {
  $pattern = "(?ms)^\s*Match\s+User\s+$([regex]::Escape($UserName))\s*\r?\n.*?(?=^\s*Match\s+|\z)"
  return [regex]::Replace($ConfigText, $pattern, "")
}

function Append-MatchUserBlock([string]$ConfigText, [string]$UserName, [string]$AuthKeysPath, [string]$ChrootDirWinPath) {
  $auth  = $AuthKeysPath -replace '\\','/'
  $chroot = $ChrootDirWinPath -replace '\\','/'

  $block = @"
# =========================
# CLIENTE SFTP: $UserName
# =========================
Match User $UserName
    AuthorizedKeysFile $auth
    PubkeyAuthentication yes
    PasswordAuthentication no
    ChrootDirectory $chroot
    ForceCommand internal-sftp -d /_incoming
    AllowTcpForwarding no
    X11Forwarding no
    PermitTunnel no
    PermitTTY no

"@

  return ($ConfigText.TrimEnd() + "`r`n`r`n" + $block)
}

function Restart-Sshd {
  $svc = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
  if (-not $svc) { throw "Serviço 'sshd' não encontrado. OpenSSH Server está instalado?" }
  Restart-Service sshd -Force
  Write-Host "[OK] Serviço sshd reiniciado."
}

# =========================
# EXECUÇÃO
# =========================
Assert-Admin
Write-Host "==== Provisionando cliente SFTP: $ClientUser ===="

# 1) Usuário local
if ($CreateLocalUser) { Ensure-LocalUser -UserName $ClientUser -FullName $ClientFullName }

# 2) Grupo OpenSSH Users (best-effort)
Try-AddToOpenSshUsersGroup -UserName $ClientUser

# 3) Diretórios
Ensure-Dir $BackupRoot
Ensure-Dir $ClientRoot
Ensure-Dir $FinalLocalDir

Ensure-Dir $IncomingPhysicalRoot
Ensure-Dir $ClientPhysicalRoot
Ensure-Dir $IncomingRealDir
Ensure-Dir $IncomingLogsRealDir
Ensure-Dir $QuarantineRealDir

# 4) Junction (incoming do chroot -> incoming físico no E:)
Ensure-Junction -LinkPath $IncomingDir -TargetPath $IncomingRealDir

Write-Host "[OK] Pastas criadas/validadas:"
Write-Host "     Chroot..........: $ClientRoot"
Write-Host "     Incoming (link).: $IncomingDir"
Write-Host "     Incoming REAL...: $IncomingRealDir"
Write-Host "     Logs REAL.......: $IncomingLogsRealDir"
Write-Host "     Quarantine REAL.: $QuarantineRealDir"
Write-Host "     Final (local)...: $FinalLocalDir"

# 5) Authorized keys + ACL
$parts = $ClientPublicKey.Trim() -split '\s+'
if ($parts.Count -lt 2) { throw "ClientPublicKey inválida. Cole a linha completa: 'ssh-ed25519 AAAA... [comentário]'" }

Write-AuthorizedKeys -FilePath $AuthorizedKeysPath -UserName $ClientUser -PublicKeyLine $ClientPublicKey

# 6) ACLs
Set-AclChroot -ClientRootPath $ClientRoot -UserName $ClientUser
Set-AclIncomingPhysical -IncomingRealPath $IncomingRealDir -IncomingLogsRealPath $IncomingLogsRealDir -QuarantineRealPath $QuarantineRealDir -UserName $ClientUser
Set-AclIncomingLink -IncomingLinkPath $IncomingDir -UserName $ClientUser
Set-AclFinalLocal -FinalLocalPath $FinalLocalDir -UserName $ClientUser

# 7) sshd_config
if (!(Test-Path -LiteralPath $SshdConfigPath)) {
  throw "sshd_config não encontrado em: $SshdConfigPath"
}

Backup-File $SshdConfigPath
$config = Get-Content -LiteralPath $SshdConfigPath -Raw

$config = Ensure-GlobalSshdOptions $config
$config = Ensure-AllowUsers -ConfigText $config -AllowedUsers $AlwaysAllowedUsers
$config = Remove-ExistingMatchBlock -ConfigText $config -UserName $ClientUser

# ChrootDirectory precisa ser caminho Windows ABSOLUTO
$config = Append-MatchUserBlock -ConfigText $config -UserName $ClientUser -AuthKeysPath $AuthorizedKeysPath -ChrootDirWinPath $ClientRoot

Set-Content -LiteralPath $SshdConfigPath -Value $config -Encoding ASCII -Force
Write-Host "[OK] sshd_config atualizado: $SshdConfigPath"

# 8) Reinicia sshd
Restart-Sshd

Write-Host ""
Write-Host "==== FINALIZADO ===="
Write-Host "Cliente:   $ClientUser"
Write-Host "Chave:     $AuthorizedKeysPath"
Write-Host "Chroot:    $ClientRoot"
Write-Host "Incoming:  $IncomingDir  (JUNCTION -> $IncomingRealDir)"
Write-Host "Logs REAL: $IncomingLogsRealDir"
Write-Host "Quar.:     $QuarantineRealDir"
Write-Host "Final:     $FinalLocalDir"
Write-Host ""
Write-Host "Teste do lado do cliente:"
Write-Host "  sftp -i `"<CAMINHO_DA_CHAVE_PRIVADA>`" $ClientUser@$BackupHost"
