# Hot Wheels: Stunt Track Driver no Android

`build_apk.sh` gera um APK arm64 que abre o jogo direto, sem passar pela interface do Winlator.
O APK não contém nenhum arquivo do jogo: no primeiro uso ele pede a sua ISO.

## Abordagem

Fork mínimo do [Winlator](https://github.com/brunodev85/winlator-app) (Wine + Box64 + servidor X próprio, LGPL-2.1).
O script baixa o código do Winlator num commit fixo, aplica `winlator.patch`, copia `overlay/` por cima e compila.

Alternativas descartadas:

- **App próprio com Box64 + Wine + Termux-X11**: seria preciso recompilar glibc, Wine e Box64 para Android e escrever o app. Dá meses de trabalho para chegar ao que o Winlator já entrega.
- **Forks maiores (Winlator Ludashi/cmod, GameNative)**: APKs de 550 a 700 MB contra cerca de 160 MB do upstream, e nada que este jogo precise (ele usa DirectDraw por software, sem 3D acelerado).

O que muda em relação ao Winlator (cerca de 25 linhas de patch e três arquivos novos):

| Arquivo | O quê |
|---|---|
| `overlay/.../StuntLauncher.java` | Ao abrir o app: cria o container "Stunt Track Driver" uma vez, pede a ISO, copia `SETUP/HOT98` para `C:\hot98` e lança `stunt.exe`. Também tem o diálogo Game Settings |
| `overlay/.../IsoExtractor.java` | Leitor ISO 9660 mínimo, sem dependências |
| `overlay/.../controls-5.icp` | Perfil de controles: botões na tela e mapeamento de qualquer gamepad |
| `winlator.patch` | Chama o StuntLauncher depois da instalação do sistema; fecha o app quando o jogo fecha; item Game Settings no menu do jogo; aceita o id de controle `*` (qualquer gamepad); faz o analógico chegar ao perfil antes do bridge XInput; controles escondidos deixam de capturar toques; o X server recusa grab de ponteiro em janela desabilitada (ver abaixo); renomeia o app |

O `applicationId` continua `com.winlator`, porque o rootfs pré-compilado do Winlator tem `/data/data/com.winlator` embutido.
Por isso o APK **substitui um Winlator já instalado** (e falha ao instalar por cima de um Winlator assinado com outra chave: desinstale antes).

## Gerar o APK

Requisitos: git, JDK 17 a 21 e o Android SDK com `sdkmanager`.
O script instala sozinho o NDK 24, o CMake 3.22.1 e a plataforma 35.
No macOS, `brew install openjdk@21 android-commandlinetools` resolve.

```bash
android/build_apk.sh
```

A saída fica em `android/out/StuntTrackDriver-winlator-<commit>.apk`, com cerca de 160 MB.
O primeiro build baixa cerca de 330 MB de código e assets do Winlator para `android/.cache/`.
Os assets incluem o rootfs com Wine 10.10 e Box64 0.4.4 já compilados pelo autor do Winlator: o script não os recompila.

## Usar

1. Instale o APK (`adb install -r android/out/*.apk`) e abra **Stunt Track Driver**.
2. Aceite a permissão de armazenamento e espere a instalação dos arquivos de sistema (só na primeira vez).
3. Escolha a ISO do jogo no seletor de arquivos. A pasta `SETUP/HOT98` (cerca de 470 MB) é copiada para dentro do app, então a ISO pode ser apagada depois.
4. O jogo abre. Ao sair do jogo o app fecha; abrir de novo vai direto para o jogo.

Se você cancelar o seletor, a interface normal do Winlator aparece; feche e abra o app para tentar de novo.

## Controles

**Touch**: o centro da tela funciona como touchpad (arrastar move o mouse, tocar clica) para os menus.
Botões ◀ ▶ ficam embaixo à esquerda; acelerar (▲) e frear (▼) ficam à direita; ESC e ENTER ficam no topo.

**Gamepad estilo Xbox** (qualquer controle que o Android reconheça; o perfil usa o id `*`):

| Controle | Tecla ou mouse |
|---|---|
| Analógico esquerdo, D-pad | Setas |
| RT / LT | ↑ acelerar / ↓ frear |
| Analógico direito | Move o mouse |
| A | Clique esquerdo |
| B, Back | ESC |
| X, Start | ENTER |
| Y | Espaço |

Para mudar os botões: menu lateral do jogo (botão voltar) → Input Controls → perfil "Stunt Track Driver".

## Game Settings

No jogo, o botão voltar do Android abre o menu lateral; o primeiro item é **Game Settings**.
As opções valem na hora e ficam salvas para as próximas aberturas:

| Opção | Padrão | Efeito |
|---|---|---|
| Show touch controls | ligado | Desligado: some o overlay e os botões invisíveis não capturam toques (a tela inteira vira touchpad). O gamepad continua funcionando |
| Stretch to fill screen | desligado | Ligado: estica 640x480 para a tela toda. Desligado: mantém 4:3 com barras laterais |
| Gamepad support | ligado | Desligado: o gamepad deixa de ser mapeado para teclado e mouse |

## Mouse nos menus: bug do Winlator corrigido

O jogo lê o mouse via DirectInput exclusivo com `SetEventNotification`: só consulta o mouse quando o DirectInput sinaliza um evento.
No Winlator sem correção, o mouse não respondia nos menus.
A causa: o Wine faz `XGrabPointer` na "clip window" dele, que pertence ao `explorer.exe`. O workaround de desktop do Winlator desabilita essa janela, e um grab numa janela desabilitada engole todos os eventos de ponteiro.
O patch faz o X server recusar grab em janela desabilitada (`GrabRequests.java`). O Wine segue sem grab e os eventos chegam.

## Configuração do Wine aplicada

O StuntLauncher aplica a mesma configuração validada no Linux (Box64 + Wine 11):

| Configuração | Como |
|---|---|
| ddraw builtin com renderer GDI, sem GPU | Container com DX wrapper `wined3d` e config `renderer=gdi`. O Winlator vira isso em `WINE_D3D_CONFIG`, que tem precedência sobre `HKCU\Software\Wine\Direct3D\renderer`; por isso o valor não vai no registro |
| Chave `HKLM\Software\Mattel\Stunt Track Driver\1.0` | Escrita vazia no `system.reg`, também em `Wow6432Node` (visão de 32 bits) |
| DLLs nativas do Winlator (wincomponents) | Todas desligadas: só builtins do Wine |
| Resolução | Tela X de 640x480 (o jogo usa 640x480; F1 alterna para 320x240) |
| Áudio | ALSA do Winlator, saída para o Android. Sem áudio o jogo para em "Sound card not found" |

O prompt do Wine Mono não apareceu nos testes: o prefixo do Winlator já vem pronto.

## Validação

Feita em 2026-10-17 num emulador Android 14 arm64 (AVD Pixel 7, Mac M1), com APK gerado do zero pelo script:

| Item | Resultado |
|---|---|
| Build do APK do zero (`build_apk.sh`) | OK, cerca de 2,5 min com cache do Gradle, 151 MB |
| Primeira abertura: instala o sistema, cria o container, abre o seletor | OK |
| Cópia da ISO e lançamento direto do `stunt.exe` | OK (o extrator também foi conferido no Mac: 246 arquivos, md5 igual ao da ISO) |
| Menus por touch (touchpad) | OK depois da correção do grab, nos 4 inícios testados (2 deles com instalação limpa) |
| Corrida 3D, acelerar pelo botão na tela | OK |
| Game Settings: esconder overlay, esticar tela, persistência | OK |
| Gamepad | **Não validado**: o emulador não tem gamepad virtual. O mapeamento segue o formato de perfil do Winlator, mas falta testar num aparelho com controle |
| Som | Não verificado (emulador sem saída de áudio audível); o jogo não travou em "Sound card not found" |
| Aparelho físico e desempenho | Não testado |

## Licença

O patch e o overlay são derivados do Winlator e seguem a LGPL-2.1.
O APK gerado redistribui Winlator, Wine, Box64 e Mesa sob as licenças deles. Não publique APKs com arquivos do jogo.
