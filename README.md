# CrossCraft

Cria e roda um servidor de **Minecraft Java + Bedrock** (Paper + Geyser + Floodgate) com poucos comandos. Jogadores do Java e do Bedrock entram no mesmo mundo, e o acesso pela internet é feito com **playit.gg**, sem abrir porta no roteador.

Funciona em **Termux (Android)** e em **Linux Debian/Ubuntu** (PC, VPS, Raspberry Pi 64 bits, sandbox como o Daytona etc.). Tudo é controlado por um único comando: `./mc`.

## O que vem no projeto

| Arquivo | Para que serve |
|---|---|
| `install.sh` | Instala as dependências e chama o setup e o start |
| `mc` | Script principal: inicia, para, faz backup, mostra logs etc. |
| `config.env` | Todas as configurações do servidor |

## O que é instalado

- **Java 25**: no Termux vem do `pkg` (openjdk-25); no Linux é baixado automaticamente (Temurin) para `runtime/java`
- **Paper**: o servidor em si
- **Geyser**: deixa jogadores Bedrock entrarem no servidor Java
- **Floodgate**: jogadores Bedrock entram só com conta Xbox, sem precisar de conta Java
- **playit**: túnel que dá um endereço público pro servidor (TCP e UDP)
- **ViaVersion** (opcional): deixa jogadores Java de versões diferentes entrarem

## Requisitos

| | Termux (Android) | Linux |
|---|---|---|
| CPU | arm64 (aarch64) | x86_64 ou aarch64/arm64 |
| RAM | ~2 GB livres ou mais | ~2 GB livres ou mais |
| Sistema | Termux da F-Droid ou do GitHub (não o da Play Store) | Debian/Ubuntu (usa `apt-get`) |
| Dependências | instaladas pelo `install.sh` | `curl`, `tar`, `tmux`, `jq` (o `install.sh` instala se faltar) |
| Permissão | nenhuma especial | root ou `sudo`, só se faltar alguma dependência |
| Internet | na primeira execução | na primeira execução |

O `./mc doctor` avisa se a memória estiver abaixo de ~2 GB, porque o Paper 26.x com Geyser precisa disso.

## Instalação

### 1. Pegue os arquivos

**Termux:**

```bash
pkg install -y git
git clone https://github.com/SEU-USUARIO/crosscraft.git
cd crosscraft
```

**Linux:**

```bash
git clone https://github.com/SEU-USUARIO/crosscraft.git
cd crosscraft
```

(Se o `git` não estiver instalado: `sudo apt-get install -y git`.)

### 2. Aceite o EULA do Minecraft

Leia o EULA em <https://aka.ms/MinecraftEULA>. Se concordar, abra o `config.env` (por exemplo `nano config.env`) e troque:

```bash
EULA="false"
```

por:

```bash
EULA="true"
```

> O script **não aceita o EULA por você**. Sem isso o setup não continua.

### 3. Rode o instalador

```bash
bash install.sh
```

Ele instala as dependências, baixa tudo e já inicia o servidor. Para instalar sem iniciar:

```bash
bash install.sh --no-start
```

**Termux:** antes de tudo, o instalador faz um upgrade completo dos pacotes. Isso evita bibliotecas quebradas, mas demora um pouco.

**Linux:** se faltar alguma dependência e você não for root nem tiver `sudo`, ele para e avisa quais instalar manualmente. Se o GitHub do Temurin estiver bloqueado, defina `JAVA_URL` no `config.env` com o link de um `.tar.gz` do Java 25.

### 4. Vincule o playit (acesso pela internet)

```bash
./mc playit-setup
```

Ele mostra um **link de aprovação** (no Termux também tenta abrir no navegador). Abra, entre na conta do playit.gg e aprove o agente. Depois:

1. **Confirme o e-mail da conta do playit.** Enquanto não confirmar, o agente registra `account_status="email_not_verified"` e o túnel não funciona (o `./mc doctor` avisa).
2. No painel do playit.gg, crie **dois túneis**. Isso é manual, o script não faz:
   - **Minecraft Java**, origem `127.0.0.1`, porta `25565`
   - **Minecraft Bedrock**, origem `127.0.0.1`, porta `19132`
3. Rode `./mc restart`.
4. Os **endereços públicos ficam na aba Overview de cada túnel, no site**. Eles não aparecem no terminal.

Deixe `BEDROCK_TRANSPORT="raknet"` no `config.env`: é o único modo que o túnel do playit aceita.

### 5. Acompanhe a subida

```bash
./mc logs
```

## Como jogar

| Edição | Rede local | Pela internet |
|---|---|---|
| Java | `IP-do-servidor:25565` (TCP) | endereço do túnel Java no playit |
| Bedrock | `IP-do-servidor:19132` (UDP) | endereço do túnel Bedrock no playit |

- Jogadores **Bedrock** entram só com conta Xbox (Floodgate ativo por padrão).
- Jogadores **Java** precisam estar na **mesma versão do jogo** que o Paper (o `./mc status` mostra qual é), a menos que você ligue o ViaVersion (`VIAVERSION="1"`).
- Sem playit (`USE_PLAYIT="0"`), no Linux você precisa liberar as portas **25565/TCP** e **19132/UDP** no firewall e no roteador/provedor.

## Comandos

| Comando | O que faz |
|---|---|
| `./mc setup` | instala Java, Paper, Geyser, Floodgate e playit (exige `EULA="true"`) |
| `./mc start` / `stop` / `restart` / `status` | controla o servidor (roda dentro do tmux; no Termux ativa o wake-lock sozinho) |
| `./mc console` | abre o console (sair sem parar o servidor: `Ctrl+B`, depois `D`) |
| `./mc logs` | mostra as últimas 200 linhas do console (não fica acompanhando) |
| `./mc cmd <comando>` | manda um comando pro servidor. Ex.: `./mc cmd op Steve`, `./mc cmd geyser version` |
| `./mc run` | roda em primeiro plano, sem tmux. Use pra ver erros de inicialização |
| `./mc backup` | compacta mundos e configs em `backups/` (mantém os últimos `BACKUP_KEEP`, padrão 3) |
| `./mc update` | atualiza Paper, Geyser e Floodgate, com backup antes |
| `./mc doctor` | diagnóstico: dependências, memória, rede, Geyser, Floodgate e conta do playit |
| `./mc preflight` | só a checagem de rede |
| `./mc playit-setup` | vincula o playit à sua conta |
| `./mc playit-start` / `playit-stop` / `playit-status` / `playit-logs` | controla o túnel |

Se os arquivos perderem a permissão de execução ao serem copiados, `bash mc ...` funciona igual, ou rode `chmod +x mc install.sh`.

## Configuração (`config.env`)

Edite o arquivo e rode `./mc restart` para aplicar.

### Java e Bedrock

| Variável | Padrão | Descrição |
|---|---|---|
| `EULA` | `false` | Precisa ser `true` para o servidor funcionar |
| `PAPER_VERSION` | `26.3` | Versão do Paper. Precisa ser uma versão que o Geyser suporte. `latest` pega a mais nova |
| `PAPER_ALLOW_UNSTABLE` | `0` | `1` aceita build não estável se a versão não tiver build estável |
| `JAVA_PORT` | `25565` | Porta TCP dos jogadores Java |
| `BEDROCK_PORT` | `19132` | Porta UDP dos jogadores Bedrock |
| `BEDROCK_TRANSPORT` | `raknet` | `raknet` é o único modo que o túnel do playit aceita. O Geyser marca o RakNet como removido no Minecraft Bedrock 26.60. `both` aceita RakNet e NetherNet, mas o NetherNet precisa de outra porta UDP e de signaling |
| `USE_FLOODGATE` | `1` | `1` deixa Bedrock entrar sem conta Java |
| `VIAVERSION` | `0` | `1` instala o ViaVersion |

### Recursos

| Variável | Padrão | Descrição |
|---|---|---|
| `MEMORY` | `auto` | `auto` usa cerca de 60% da RAM (entre 768M e 4G). Ou fixe, ex.: `2G`. Não fixe abaixo de 2G |
| `JAVA_FLAGS` | `-XX:+UseG1GC` | Flags extras do Java |
| `JAVA_URL` | (vazio) | Só Linux: link de um `.tar.gz` do Java 25, útil se o GitHub do Temurin estiver bloqueado |

### Servidor

Valores iniciais do `server.properties`:

| Variável | Padrão | Descrição |
|---|---|---|
| `SERVER_NAME` | `Crossplay Server` | Nome do servidor |
| `MAX_PLAYERS` | `10` | Máximo de jogadores |
| `VIEW_DISTANCE` | `8` | Distância de visão. No celular ou sandbox pequeno, mantenha entre 6 e 8 |
| `SIMULATION_DISTANCE` | `6` | Distância de simulação |
| `GAMEMODE` | `survival` | Modo de jogo |
| `DIFFICULTY` | `normal` | Dificuldade |
| `ONLINE_MODE` | `true` | `false` deixa Java sem conta oficial entrar, mas é inseguro na internet |

> Esses valores **só são aplicados na criação** do `server.properties`. Depois disso, edite `server/server.properties` direto, ou apague `server/.configured` para o script aplicar de novo.

### Execução e playit

| Variável | Padrão | Descrição |
|---|---|---|
| `AUTO_RESTART` | `1` | Reinicia se o servidor cair (para depois de 3 quedas em menos de 30s) |
| `BACKUP_KEEP` | `3` | Quantos backups manter |
| `USE_PLAYIT` | `1` | Usa o túnel do playit |
| `PLAYIT_VERSION` | `v1.0.10` | Versão do playit. `latest` arrisca mudança na linha de comando |

## Android: o que costuma derrubar o servidor

Só vale para o **Termux**.

- **Phantom process killer (Android 12+):** o sistema mata processos em segundo plano do Termux (aparece como `Killed` / sinal 9). Desative uma vez via ADB:
  `adb shell "/system/bin/device_config set_sync_disabled_for_tests persistent; /system/bin/device_config put activity_manager max_phantom_processes 2147483647"`
  (Android 14+: rode também `adb shell settings put global settings_enable_monitor_phantom_procs false`)
- Desative a otimização de bateria do Termux.
- `VIEW_DISTANCE` alto com muitos jogadores esgota a RAM e a CPU do celular. Comece com 6 e poucos jogadores.

## Jogadores não conseguem entrar

Teste nesta ordem. Cada passo elimina uma possibilidade.

1. `./mc status`: servidor e playit estão rodando? Anote a **versão do Paper** que ele mostra.
2. `./mc doctor`: confere se Geyser e Floodgate carregaram, se a memória é suficiente e se a conta do playit está ok.
3. Entre por **outro aparelho na mesma rede**, com o IP local e a porta certa. No Wi-Fi, "isolamento de clientes" e redes de visitantes bloqueiam isso.
4. Enquanto tenta, rode `./mc logs`. Se aparecer uma linha de login ou de versão incompatível, o pacote chegou (problema de versão). Se não aparecer nada, ele nem chegou ao servidor (problema de rede, IP ou firewall).
5. Só depois que o teste local funcionar, teste o endereço do playit. Confira `./mc playit-logs` e o tráfego do túnel no site.
6. Pra checar o Geyser: `./mc cmd geyser version`.

Se os jogadores Bedrock estiverem numa versão do jogo que o Geyser não aceita, eles não entram. Rode `./mc update` e confira a versão do Geyser.

## Solução de problemas

**O upgrade do Termux falhou**
Rode `termux-change-repo`, escolha outro mirror e tente de novo.

**`curl` quebrado no Termux**
Rode `apt update && apt full-upgrade -y` e depois `bash install.sh`.

**Falha ao instalar o openjdk-25 no Termux**
Rode `apt update && apt full-upgrade -y` e tente de novo.

**Faltam dependências e o script não instala (Linux)**
Você não é root e não tem `sudo`, ou a distro não tem `apt-get`. Instale `curl`, `tar`, `tmux` e `jq` manualmente e rode o instalador de novo.

**Não consigo baixar o Java (Linux)**
Se o GitHub do Temurin estiver bloqueado, defina `JAVA_URL` no `config.env`.

**O servidor não sobe e não aparece erro**
Rode `./mc run`. Ele executa em primeiro plano e mostra o erro na tela.

**Não consigo baixar nada**
Rode `./mc preflight` para checar a rede. Ele mostra quais endereços estão bloqueados.

**Mudei o `config.env` e nada mudou**
Rode `./mc restart`. Se a mudança era de nome, jogadores, distância etc., lembre que esses valores só valem na criação do `server.properties`.

## Estrutura de pastas

```
.
├── install.sh
├── mc
├── config.env
├── server/      # servidor, mundos e plugins
├── playit/      # agente do playit (inclui o secret)
├── runtime/     # Java baixado (só no Linux; no Termux o Java vem do pkg)
└── backups/     # backups gerados por ./mc backup
```

## Segurança

`playit/secret` é a chave da sua conta de túnel. Se for colocar o projeto no Git, crie um `.gitignore` com:

```
server/
playit/
backups/
runtime/
```

Não compartilhe esse arquivo nem o link de aprovação do `playit-setup`. E não deixe `ONLINE_MODE="false"` com o servidor aberto na internet.
