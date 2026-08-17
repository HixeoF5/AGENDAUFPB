Markdown

<div align="center">

# 🪐 Agenda Acadêmica — Second Brain
### Engenharia da Computação · UFPB

Uma aplicação desktop nativa desenvolvida em **Flutter & Dart** projetada para auxiliar discentes no planejamento curricular, acompanhamento de notas, controle de faltas e visualização tridimensional da grade acadêmica.

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![SQLite](https://img.shields.io/badge/SQLite-07405E?style=for-the-badge&logo=sqlite&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![Windows](https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white)

</div>

---

## ⚡ Principais Funcionalidades

- 🌌 **Grafo Orbital 3D Interativo:** Visualização em tempo real das disciplinas divididas em anéis orbitais por período letivo, com status de *Aprovado*, *Cursando*, *Disponível* e *Bloqueado* de acordo com a malha de pré-requisitos.
- 🗓️ **Cronograma Semanal com Detecção de Choques:** Grade horária inteligente que impede marcação de aulas conflitantes no mesmo horário.
- 📊 **Dashboard de Desempenho:** Cálculo dinâmico de pontuação acumulada por unidade, metas de aprovação direta, projeção automática da nota necessária para a **Prova Final** e acompanhamento do limite de faltas.
- 📌 **Mural de Avisos & Radar Acadêmico:** Painel dedicado para contagem regressiva de prazos, provas, entregas de trabalhos e recessos.
- 🔒 **Privacidade Total & Offline First:** Armazenamento local SQLite (`sqflite_common_ffi`). Nenhum dado pessoal, nota ou matrícula sai da máquina do usuário.

---

## 📥 Downloads (Binários Prontos)

Baixe a versão compilada diretamente na seção de [**Releases**](https://github.com/HixeoF5/AGENDAUFPB/releases):

| Sistema Operacional | Formato | Como Executar |
| :--- | :--- | :--- |
| **🐧 Linux** | `.tar.gz` | Extraia a pasta e execute `./bundle/agenda_academica` |
| **🪟 Windows** | `.zip` | Extraia o arquivo e execute `agenda_academica.exe` |

---

## 🛠️ Instalação para Desenvolvedores

Se desejar executar ou modificar o código-fonte localmente:

### Pré-requisitos
- [Flutter SDK](https://docs.flutter.dev/get-started/install) instalado (canal `stable`).
- Dependências de compilação desktop Linux:
  ```bash
  sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev

Passo a Passo

01. Clone o repositório:
git clone [https://github.com/HixeoF5/AGENDAUFPB.git](https://github.com/HixeoF5/AGENDAUFPB.git)
cd AGENDAUFPB

02. Instale os pacotes e dependências:
flutter pub get

03. Execute a aplicação:

No Linux:
Bash

flutter run -d linux

No Windows:
PowerShell

flutter run -d windows

🏗️ Estrutura de Arquitetura
Plaintext

AGENDAUFPB/
├── lib/
│   └── main.dart            # Interface, State Management, CustomPainter 3D e Banco Local
├── assets/
│   └── brasao_ufpb.png      # Identidade visual institucional
├── .github/workflows/
│   └── build_windows.yml    # CI/CD automatizado via GitHub Actions
└── pubspec.yaml             # Configurações de pacotes e assets

