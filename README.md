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

## Instalação

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# PyTorch para a sua GPU (escolha um):
pip install torch torchvision --index-url https://download.pytorch.org/whl/xpu   # Intel Arc
pip install torch                                                     # NVIDIA
pip install torch --index-url https://download.pytorch.org/whl/rocm6.4 # AMD
```

Na Intel Arc, o PyTorch também precisa do driver de computação (o de Vulkan não basta):

```bash
sudo pacman -S intel-compute-runtime level-zero-loader   # Arch
```

Instale o `torchvision` junto com o `torch` e do mesmo índice. A versão do PyPI não é compatível e dá o erro `operator torchvision::nms does not exist`.

Depois baixe um modelo para a pasta `models/` (veja [models/README.md](models/README.md)).

## Uso

**1. Coletar as texturas.** No `DS2TexInject.ini`, na pasta do jogo:

```ini
DumpTextures=1
```

Jogue normalmente. Cada textura que aparecer na tela é salva em `texmod/_dump/`. Quanto mais do jogo você percorrer, mais texturas entram. Depois volte para `DumpTextures=0`.

**2. Testar com poucas texturas:**

```bash
python3 ds2remaster.py all --model models/4x-UltraSharp.pth --limit 20
python3 "<pasta do jogo>/DS2TexInject/ds2tex.py"
```

Abra `work/preview.html` para comparar. No jogo, **F10** liga e desliga as texturas novas.

**3. Rodar tudo.** Tire o `--limit`. O que já foi feito é pulado, então dá para parar e continuar depois.

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
