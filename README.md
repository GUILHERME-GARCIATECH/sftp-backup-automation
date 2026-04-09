# 📦 SFTP Backup Pipeline (PowerShell)

![PowerShell](https://img.shields.io/badge/PowerShell-5.1-blue)
![Windows](https://img.shields.io/badge/Windows-Supported-blue)
![Status](https://img.shields.io/badge/status-active-success)
![Security](https://img.shields.io/badge/security-antivirus-critical)

> 🚀 Automação em **PowerShell** para envio de backups compactados via **SFTP**, com triagem antivírus, quarentena e promoção segura para destino final.  
> 🔐 Provisionamento automatizado de usuários via **OpenSSH**.

---

## 📑 Índice

- [🧭 Visão geral](#-visão-geral)
- [🔄 Fluxo do pipeline](#-fluxo-do-pipeline)
- [📂 Estrutura dos scripts](#-estrutura-dos-scripts)
- [🔐 Modelo de acesso](#-modelo-de-acesso)
- [🗂️ Estrutura de diretórios](#️-estrutura-de-diretórios)
- [⚙️ Requisitos](#️-requisitos)
- [🔑 OpenSSH e chaves](#-openssh-e-chaves)
- [🚀 Como usar](#-como-usar)
- [🌟 Destaques](#-destaques)
- [✅ Boas práticas](#-boas-práticas)
- [🔮 Sugestões de evolução](#-sugestões-de-evolução)
- [📁 Estrutura do repositório](#-estrutura-do-repositório)
- [🤝 Contribuição](#-contribuição)
- [📄 Licença](#-licença)
- [👨‍💻 Autor](#-autor)

---

## 🧭 Visão geral

O projeto foi dividido em três partes:

- **`backup_sftp.ps1`** → coleta, compacta e envia backups
- **`scan+promote.ps1`** → escaneia, valida e promove arquivos
- **`gen-users.ps1`** → provisiona usuários e estrutura SFTP

---

## 🔄 Fluxo do pipeline

Separação clara:

- 📤 envio  
- 📥 recebimento  
- 🔍 verificação  
- 🚀 promoção  
- 🛑 isolamento  

### 🏗️ Arquitetura

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

📤 Responsável pelo envio

- valida chave SSH e `sftp.exe`
- identifica alterações
- backup full + incremental
- staging + compactação `.zip`
- envio para `_incoming`
- envio de logs

---

### 🔹 `scan+promote.ps1`

🔍 Responsável pela triagem

- monitora `_incoming`
- move para `_processing`
- executa scan antivírus
- promove ou envia para quarentena

---

### 🔹 `gen-users.ps1`

🔐 Provisionamento

- cria usuário Windows
- configura OpenSSH
- cria diretórios
- aplica ACLs
- configura chroot

---

## 🔐 Modelo de acesso

- 🔒 chroot por cliente  
- 📥 `_incoming` acessível  
- 🚫 FINAL restrito  
- 🔑 autenticação por chave  
- ❌ senha desabilitada  

---

## 🗂️ Estrutura de diretórios

```text
Cliente:
C:\TI\backup-sftp

Servidor:
C:\SRV-BACKUP\<Cliente>
E:\SFTP-IN\Clientes\<Cliente>
```

---

## ⚙️ Requisitos

### Cliente

- PowerShell 5.1  
- OpenSSH Client  
- chave SSH  

### Servidor

- PowerShell 5.1  
- OpenSSH Server  
- Microsoft Defender  

---

## 🔑 OpenSSH e chaves

```powershell
%USERPROFILE%\.ssh\id_ed25519
C:\ProgramData\ssh\keys\<usuario>_authorized_keys
```

---

## 🚀 Como usar

### 1️⃣ Criar usuário

```powershell
.\gen-users.ps1
```

### 2️⃣ Rodar backup

```powershell
.\backup_sftp.ps1
```

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
- ⏰ agendar execução  

---

## 🔮 Sugestões de evolução

- inspeção interna do ZIP  
- notificações  
- dashboard  
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

Desenvolvido por **Guilherme Garcia**

- 🔗 LinkedIn: https://www.linkedin.com/in/guilherme-garcia-pinto-bb63613b7
- 💻 GitHub: https://github.com/GUILHERME-GARCIATECH
