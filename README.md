# Dead Space 2 AI Remaster

Pipeline automatizado para remasterizar as texturas do Dead Space 2 com modelos de IA open source.

Ele trabalha junto com o [DS2TexInject](https://github.com/sidnei-almeida/dead-space-2-texmod-linux): o plugin salva as texturas originais do jogo, esta ferramenta refaz cada uma com IA e gera um pacote que o plugin carrega de volta. Nenhum arquivo do jogo é modificado.

```
jogo (DumpTextures=1) → texmod/_dump/0xHASH.dds
        ↓ scan       classifica: diffuse, normal map, máscara, pequena
        ↓ upscale    IA (spandrel + PyTorch) ou Lanczos
        ↓ encode     volta para DXT1/DXT5/RGBA
        ↓ pack       texmod/zz_ai_remaster.zip
        ↓ preview    página HTML com original e IA lado a lado
ds2tex.py → texmod/_cache → jogo
```

## Uso rápido

Tudo passa pelo `remaster.sh`:

```bash
./remaster.sh setup      # uma vez: instala PyTorch e spandrel e baixa o modelo
./remaster.sh dump-on    # liga a coleta; depois jogue normalmente
./remaster.sh dump-off   # desliga a coleta quando terminar de jogar
./remaster.sh            # processa só as texturas novas e instala no jogo
./remaster.sh status     # progresso de uma rodada em andamento (em outro terminal)
./remaster.sh off        # volta para só os seus .tpf
./remaster.sh on         # reativa o remaster
```

O `./remaster.sh` pode ficar rodando sozinho:

- Confere se o jogo está fechado. Se você abrir o jogo no meio, ele para, para não disputar a GPU.
- Pula tudo o que já foi feito. Dá para interromper (Ctrl+C) e rodar de novo depois.
- Se a GPU travar, percebe pela falta de progresso, reinicia e continua de onde parou.
- Avisa com uma notificação na área de trabalho quando termina.
- Grava tudo em `work/pbrify4x/remaster.log`.

As configurações (modelo, escala, tamanho máximo) ficam no topo do `remaster.sh`. O padrão é o
[4x-PBRify_UpscalerV4](https://openmodeldb.info/models/4x-PBRify-UpscalerV4) (licença CC0) em 4x
para texturas de cor e normal maps, 2x para máscaras e mapas de luz, e no máximo 2048px.

Cada DDS já sai com a cadeia completa de mipmaps. Assim o jogo não precisa gerar nada ao entrar
numa área nova, o que causava engasgos.

## Instalação manual

O `./remaster.sh setup` faz isto:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pip install torch torchvision --index-url https://download.pytorch.org/whl/xpu   # Intel Arc
# NVIDIA: pip install torch torchvision
```

Na Intel Arc, o PyTorch também precisa do driver de computação (o de Vulkan não basta):

```bash
sudo pacman -S intel-compute-runtime level-zero-loader   # Arch
```

Instale o `torchvision` junto com o `torch` e do mesmo índice. A versão do PyPI não é compatível e dá o erro `operator torchvision::nms does not exist`.

## Uso avançado (ds2remaster.py)

O `remaster.sh` chama o `ds2remaster.py`, que também pode ser usado direto, etapa por etapa:

```bash
.venv/bin/python ds2remaster.py all --model models/4x-PBRify_UpscalerV4.pth --limit 20
```

Abra `work/preview.html` para comparar. No jogo, **F10** liga e desliga as texturas novas.

### Acompanhar o progresso

Cada linha do log mostra a porcentagem, o tempo decorrido e quanto falta:

```
  [ 751/3458  21.7%] 0x36853E83 mask       256x256  ->  512x512    0.3s | decorrido 5m12s | faltam ~18m40s
```

Para acompanhar em outro terminal:

```bash
python3 ds2remaster.py all --model models/4x-PBRify_UpscalerV4.pth > work/run.log 2>&1 &
tail -f work/run.log              # linha a linha
python3 ds2remaster.py status     # resumo: barra, tempo restante, erros, contagem por classe
```

### Opções principais

| Opção | Padrão | O que faz |
|---|---|---|
| `--model` | nenhum | Modelo de upscale. Sem ele, usa Lanczos (só para testar). |
| `--cleanup` | nenhum | Modelo 1x aplicado antes, para limpar artefatos de compressão. |
| `--scale` | 2 | Fator final de aumento. |
| `--max-size` | 2048 | Lado máximo de qualquer textura. |
| `--tile` | 544 | Tamanho do bloco enviado à GPU. Uma textura de 1024px vira 4 blocos. Na Intel Arc, blocos de 1088 causaram erros de memória na GPU e travaram o processo. |
| `--only` | todas | Só algumas classes: `diffuse`, `normal`, `normal_ag`, `mask`. |
| `--limit` | todas | Processa no máximo N texturas. |
| `--ai-alpha` | não | Passa o canal alpha pelo modelo também. |
| `--ai-masks` | não | Passa máscaras e specular pelo modelo também. |
| `--no-color-lock` | não | Deixa a IA alterar as cores. Por padrão, as cores e a iluminação geral são as do original e a IA só acrescenta detalhe fino. |
| `--force` | não | Refaz o que já existe. |

### Rejeitar resultados ruins

No `work/preview.html`, marque as texturas ruins e cole a lista gerada em `work/rejected.txt`. Depois rode `pack` de novo.

## Como cada tipo é tratado

| Classe | Tratamento |
|---|---|
| diffuse | Modelo de IA (com padding circular para não criar costura em texturas que se repetem). |
| normal | Lanczos e renormalização. Modelos de foto estragam normal maps. |
| normal_ag | Igual ao anterior, no formato DXT5nm (X no alpha, Y no verde). |
| mask | Lanczos, ou IA com `--ai-masks`. |
| alpha | Upscale separado. Em DXT1, volta a ser alpha de 1 bit. |

Texturas já cobertas pelos seus pacotes `.tpf` são puladas. O pacote da IA se chama `zz_...` para ficar por último na ordem: os pacotes feitos à mão sempre têm prioridade.

## Memória

O Dead Space 2 é um programa de 32 bits. Se todas as texturas forem para 4K, ele fica sem memória e trava. Por isso o padrão é 2x com limite de 2048px. Se travar, experimente `Pool=default` no `DS2TexInject.ini` ou diminua `--max-size`.

## Licença

MIT
