# 📦 SFTP Backup Pipeline (PowerShell)

> 🚀 Automação em **PowerShell** para envio de backups compactados via **SFTP**, com triagem antivírus, quarentena e promoção segura para destino final.  
> 🔐 Provisionamento automatizado de usuários via **OpenSSH**.

---

## 🧭 Visão geral

O projeto foi dividido em três partes:

- **`backup_sftp.ps1`** → roda no cliente, coleta os arquivos alterados, compacta em `.zip` e envia via SFTP para `_incoming`
- **`scan+promote.ps1`** → roda no servidor, escaneia os arquivos e decide destino
- **`gen-users.ps1`** → provisiona usuários, estrutura pastas, ACLs e OpenSSH

---

## 🔄 Fluxo do pipeline

Separação clara:

- 📤 envio  
- 📥 recebimento  
- 🔍 verificação  
- 🚀 promoção  
- 🛑 isolamento  

### 🏗️ Arquitetura do fluxo

```text
Cliente
  ↓
backup_sftp.ps1
  ↓
compacta arquivos em .zip
  ↓
envia via SFTP → _incoming
  ↓
Servidor
  ↓
scan+promote.ps1
  ↓
move para _processing
  ↓
scan com Microsoft Defender
    ├─ ✅ limpo → FINAL + SharePoint
    └─ 🚨 infectado → _quarantine
```

---

## 📂 Estrutura dos scripts

### 🔹 `backup_sftp.ps1`

📤 Script cliente responsável pelo envio

#### ⚙️ O que faz

- valida chave SSH e `sftp.exe`
- usa `C:\TI\backup-sftp`
- identifica alterações pela última execução
- backup full inicial
- backup incremental nas próximas execuções
- staging de arquivos
- compactação `.zip`
- envio para `_incoming`
- envio de logs

#### ⚠️ Importante

- ❌ não envia arquivos soltos  
- 📦 sempre compacta  
- 🧠 mantém estado incremental  

---

### 🔹 `scan+promote.ps1`

🔍 Script servidor de triagem

#### ⚙️ O que faz

- monitora `E:\SFTP-IN\Clientes`
- busca `.zip` em `_incoming`
- ignora arquivos recentes
- move para `_processing`
- scan com `MpCmdRun.exe`
- valida com `Get-MpThreatDetection`

#### 🔀 Decisão

**Se limpo:**

- move para `FINAL`
- copia para SharePoint

**Se infectado:**

- move para `_quarantine`

---

### 🛑 Modelo de quarentena

- `_incoming` → entrada  
- `_processing` → análise  
- `_quarantine` → isolamento  
- `FINAL` → aprovado  

✔ Segurança garantida  
✔ Nada vai direto pra produção  

---

### 🔹 `gen-users.ps1`

🔐 Provisionamento de usuários

#### ⚙️ O que faz

- cria usuário Windows  
- adiciona ao OpenSSH Users  
- cria diretórios  
- configura chroot  
- cria junction  
- grava chave pública  
- aplica ACLs  
- atualiza `sshd_config`  
- cria `Match User`  
- reinicia serviço  

---

## 🔐 Modelo de acesso

- 🔒 chroot por cliente  
- 📥 `_incoming` acessível  
- 🚫 FINAL e quarentena restritos  
- 🔑 autenticação por chave  
- ❌ senha desabilitada  

---

## 🗂️ Estrutura de diretórios

### 🖥️ Cliente

```text
C:\TI\backup-sftp
├── Logs
├── Stage\<Cliente>
├── State
└── Temp
```

### 🗄️ Servidor

```text
C:\SRV-BACKUP\<Cliente>
├── _incoming → junction
└── FINAL
```

### 📥 Entrada física

```text
E:\SFTP-IN\Clientes\<Cliente>
├── _incoming
│   ├── logs
│   └── _processing
└── _quarantine
```

---

## ⚙️ Requisitos

### 🖥️ Cliente

- PowerShell 5.1  
- OpenSSH Client  
- chave SSH  
- acesso SFTP  
- permissões de leitura  

### 🗄️ Servidor

- PowerShell 5.1  
- OpenSSH Server  
- Microsoft Defender  
- permissões administrativas  

---

## 🔑 OpenSSH e chaves

### Cliente

```powershell
%USERPROFILE%\.ssh\id_ed25519
```

### Servidor

```powershell
C:\ProgramData\ssh\keys\<usuario>_authorized_keys
```

### Configuração

- `AuthorizedKeysFile`
- `ChrootDirectory`
- `ForceCommand internal-sftp -d /_incoming`
- `PasswordAuthentication no`

---

## 🚀 Como usar

### 1️⃣ Criar usuário

Editar no `gen-users.ps1`:

- `$ClientUser`
- `$ClientFullName`
- `$BackupHost`
- `$ClientPublicKey`

```powershell
.\gen-users.ps1
```

---

### 2️⃣ Configurar cliente

Editar no `backup_sftp.ps1`:

- `$BackupHost`
- `$BackupUser`
- `$Client`
- `$Key`
- `$Pastas`

```powershell
.\backup_sftp.ps1
```

---

### 3️⃣ Processar arquivos

```powershell
.\scan+promote.ps1
```

---

## 🌟 Destaques

- 📈 Backup incremental  
- 📦 Compactação antes do envio  
- 🛡️ Pipeline com antivírus  
- 🚨 Quarentena automática  
- ⚙️ Escalável  

---

## ✅ Boas práticas

- ❌ não versionar chave privada  
- 🔒 mascarar dados sensíveis  
- 🧹 revisar hardcoded  
- ⚙️ usar config externa  
- ⏰ agendar tarefas  

---

## 🔮 Melhorias futuras

- inspeção interna do ZIP  
- notificações  
- checksum  
- dashboard  
- multi-origem  
- centralização de logs  

---

## 📁 Estrutura do repositório

```text
.
├── backup_sftp.ps1
├── gen-users.ps1
├── scan+promote.ps1
└── README.md
```
---

## 🤝 Contribuição

Sinta-se à vontade para abrir **issues** ou enviar **pull requests** com melhorias.

---

## 📄 Licença

Este projeto está sob a licença **MIT**.

---

## 👨‍💻 Autor

Desenvolvido por **Seu Nome**

- 🔗 LinkedIn: [seu-linkedin](https://www.linkedin.com/in/seu-linkedin)
- 💻 GitHub: [seu-github](https://github.com/seu-github)
