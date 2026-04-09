📦 SFTP Backup Automation (PowerShell)

Sistema de automação de backups utilizando SFTP com scripts em PowerShell, focado em segurança, confiabilidade e redução de intervenção manual.

🚀 Sobre o projeto

Este projeto foi desenvolvido para automatizar o processo de backup de arquivos e diretórios, garantindo:

  Transferência segura via SFTP
  Execução automatizada de rotinas de backup
  Redução de falhas humanas
  Padronização do processo

⚙️ Funcionalidades
  📁 Backup automatizado de arquivos e diretórios
  🔐 Transferência segura via SFTP
  👤 Criação e gerenciamento de usuários (script auxiliar)
  🔍 Validação e promoção de arquivos (scan + promote)
  🛠 Scripts modulares para diferentes etapas do processo

📂 Estrutura do projeto
.
├── backup_sftp.ps1       # Script principal de backup via SFTP
├── gen-users.ps1         # Script para criação de usuários
├── scan+promote.ps1      # Script para validação e promoção de arquivos
└── README.md

🧩 Requisitos
  Windows com PowerShell
  Acesso a servidor SFTP
  Credenciais válidas de autenticação
  Permissões de leitura/escrita nos diretórios envolvidos
  
▶️ Como usar
  1. Clone o repositório
  git clone https://github.com/seu-usuario/sftp-backup-automation.git
  cd sftp-backup-automation
  2. Configure os parâmetros
    Edite o script principal (backup_sftp.ps1) e ajuste:
      Host do servidor SFTP
      Usuário e senha ou chave SSH
      Diretórios de origem e destino
  3. Execute o script
     .\backup_sftp.ps1
     
🔐 Segurança
  Utilize variáveis seguras para armazenar credenciais
  Evite hardcode de senhas no código
  Prefira autenticação via chave SSH sempre que possível

📌 Possíveis melhorias futuras
  Logs estruturados
  Notificações (e-mail / webhook)
  Integração com agendadores (Task Scheduler)
  Versionamento de backups
  Monitoramento de falhas

🤝 Contribuição

  Sinta-se à vontade para abrir issues ou enviar pull requests com melhorias.

📄 Licença
  Este projeto está sob a licença MIT.

👨‍💻 Autor
 Desenvolvido por GUILHERME GARCIA PINTO
   🔗 LinkedIn: www.linkedin.com/in/guilherme-garcia-pinto-bb63613b7
   💻 GitHub: https://github.com/GUILHERME-GARCIATECH
