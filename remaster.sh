#!/bin/bash
# remaster.sh - tudo do remaster do Dead Space 2 em um comando.
#
#   ./remaster.sh            abre o menu (num terminal). Sem terminal, faz o mesmo que "run"
#   ./remaster.sh run        processa as texturas novas do dump e instala no jogo (pode deixar rodando)
#   ./remaster.sh status     mostra o progresso de uma rodada em andamento
#   ./remaster.sh preview    gera uma pagina com original x IA lado a lado (para rejeitar texturas ruins)
#   ./remaster.sh dump-on    liga a coleta de texturas (jogue normalmente depois)
#   ./remaster.sh dump-off   desliga a coleta
#   ./remaster.sh on         ativa o pacote da IA no jogo
#   ./remaster.sh off        desativa o pacote da IA (fica so com os seus .tpf)
#   ./remaster.sh setup      instala o ambiente Python (PyTorch, spandrel) e baixa o modelo
#   ./remaster.sh --help     explica tudo isso com mais detalhes
#
# As configuracoes ficam logo abaixo. Para mudar, edite este arquivo.

# Pasta do jogo: descoberta sozinha na primeira vez (Steam, Heroic, Lutris, Bottles, prefixos do Wine
# ou qualquer pasta do disco) e lembrada em .game-path. Para trocar: ./remaster.sh game [pasta]
GAME="${GAME:-}"
# Modelo principal: PBRify_UpscalerV4 (DAT2, feito para texturas de jogos antigos: tira a compressao
# DXT e recupera detalhe de verdade). Mais pesado que um ESRGAN, mas vale cada minuto.
MODEL="${MODEL:-models/4x-PBRify_UpscalerV4.pth}"
MODEL_URL="https://github.com/Kim2091/Kim2091-Models/releases/download/4x-PBRify_UpscalerV4/4x-PBRify_UpscalerV4.pth"
# Luzes, brilhos, fachos e fumaca (classe "glow"): o PBRify endurece as bordas e enche de chuvisco, entao
# essas vao para o UltraSharp, que respeita o degrade. O mesmo modelo entra quando a checagem anti-invencao
# pega o PBRify criando textura onde nao havia (medida "invencao" acima de 1.15). GLOW_MODEL= desliga os dois.
GLOW_MODEL="${GLOW_MODEL-models/4x-UltraSharp.pth}"
ULTRASHARP_URL="https://huggingface.co/Kim2091/UltraSharp/resolve/main/4x-UltraSharp.pth"
# Degrades puros (facho da lanterna, brilhos lisos) nao passam por IA nenhuma: so Lanczos.
# Opcional: um segundo modelo mais conservador para texturas de pouco detalhe, ex.:
#   SOFT_MODEL=models/4x-UltraSharp.pth ./remaster.sh run
SOFT_MODEL="${SOFT_MODEL:-}"
SOFT_MODEL_URL="$ULTRASHARP_URL"
SCALE="${SCALE:-2}"            # texturas de cor e normal maps
MASK_SCALE="${MASK_SCALE:-2}"  # mascaras, specular e mapas de luz (ganham pouco e ocupam muita memoria)
MAX_SIZE="${MAX_SIZE:-2048}"   # lado maximo de qualquer textura
WORK="${WORK:-work/pbrify${SCALE}x}"
# Rodada experimental em 4x (o 2x fica guardado em work/pbrify2x; o pacote no jogo e substituido):
#   SCALE=4 MAX_SIZE=4096 ./remaster.sh run
# Para voltar ao 2x depois: ./remaster.sh run (reaproveita o que ja foi feito, so refaz DDS e pacote)
PACK="zz_ai_remaster.zip"
STALL_SECONDS=300  # sem progresso por esse tempo = GPU travada: reinicia e continua de onde parou
MAX_RESTARTS=5
LIMIT="${LIMIT:-}"  # so para testes: processa no maximo N texturas

set -u -o pipefail
SELF=$(readlink -f "$0")
cd "$(dirname "$SELF")" || exit 1
PY=.venv/bin/python
GAME_FILE=.game-path

say_early() { echo "$*" >&2; }

# lista as pastas com o deadspace2.exe, uma por linha, as que ja tem o DS2TexInject primeiro.
# Com --deep, varre tambem o disco inteiro (home, /mnt, /media, /run/media, /opt).
find_game_dirs() {
    python3 - "$@" <<'FINDPY'
import glob, json, os, sqlite3, sys
H = os.path.expanduser('~')
deep = '--deep' in sys.argv
EXE = 'deadspace2.exe'
found, seen = [], set()

def add(d):
    if not d or not os.path.isdir(d):
        return
    try:
        exe = next((f for f in os.listdir(d) if f.lower() == EXE), None)
    except OSError:
        return
    if not exe:
        return
    st = os.stat(d)
    if (st.st_dev, st.st_ino) in seen:  # a mesma pasta montada em dois lugares
        return
    seen.add((st.st_dev, st.st_ino))
    found.append(os.path.realpath(d))

def walk(root, depth):
    root = os.path.expanduser(root)
    if not os.path.isdir(root):
        return
    base = root.rstrip('/').count('/')
    skip = {'proc', 'sys', 'dev', '.cache', 'node_modules', '.git', 'Trash', 'shadercache', 'compatdata'}
    for d, dirs, files in os.walk(root, onerror=lambda e: None):
        if any(f.lower() == EXE for f in files):
            add(d)
        if d.count('/') - base >= depth:
            dirs[:] = []
        else:
            dirs[:] = [x for x in dirs if x not in skip and not os.path.islink(os.path.join(d, x))]

def load(p):
    try:
        return json.load(open(p))
    except Exception:
        return None

# Steam: todas as bibliotecas (nativo, flatpak, snap)
steams = ['~/.local/share/Steam', '~/.steam/steam', '~/.steam/root',
          '~/.var/app/com.valvesoftware.Steam/.local/share/Steam', '~/snap/steam/common/.local/share/Steam']
libs = set()
for s in steams:
    s = os.path.expanduser(s)
    libs.add(s)
    vdf = os.path.join(s, 'steamapps', 'libraryfolders.vdf')
    if os.path.exists(vdf):
        for line in open(vdf, errors='ignore'):
            if '"path"' in line:
                libs.add(line.split('"')[3].replace('\\\\', '/'))
for lib in libs:
    acf = os.path.join(lib, 'steamapps', 'appmanifest_47780.acf')
    if os.path.exists(acf):
        for line in open(acf, errors='ignore'):
            if '"installdir"' in line:
                add(os.path.join(lib, 'steamapps', 'common', line.split('"')[3]))
    add(os.path.join(lib, 'steamapps', 'common', 'Dead Space 2'))

# Heroic (GOG, Epic, Amazon e jogos adicionados a mao), nativo e flatpak
for h in ['~/.config/heroic', '~/.var/app/com.heroicgameslauncher.hgl/config/heroic']:
    h = os.path.expanduser(h)
    gog = load(os.path.join(h, 'gog_store', 'installed.json')) or {}
    for g in gog.get('installed', []):
        add(g.get('install_path'))
    leg = load(os.path.join(h, 'legendaryConfig', 'legendary', 'installed.json')) or {}
    for g in leg.values() if isinstance(leg, dict) else []:
        add(g.get('install_path'))
    side = load(os.path.join(h, 'sideload_apps', 'library.json')) or {}
    for g in side.get('games', []):
        exe = (g.get('install') or {}).get('executable')
        if exe:
            add(os.path.dirname(exe))
            walk(os.path.dirname(exe), 2)

# Lutris
for db in ['~/.local/share/lutris/pga.db', '~/.var/app/net.lutris.Lutris/data/lutris/pga.db']:
    db = os.path.expanduser(db)
    if os.path.exists(db):
        try:
            for (d,) in sqlite3.connect(f'file:{db}?mode=ro', uri=True).execute('select directory from games'):
                if d:
                    add(d)
                    walk(d, 6)
        except Exception:
            pass

# prefixos do Wine, Bottles, EA app e pastas comuns de jogos
for root in ['~/Games', '~/games', '~/.wine/drive_c', '~/.local/share/bottles/bottles',
             '~/.var/app/com.usebottles.bottles/data/bottles/bottles', '~/GOG Games', '~/.local/share/lutris']:
    walk(root, 6)

if deep or not found:
    for root in [H, '/mnt', '/media', '/run/media', '/opt', '/games']:
        walk(root, 8)

found.sort(key=lambda d: not os.path.exists(os.path.join(d, 'DS2TexInject.ini')))
print('\n'.join(found))
FINDPY
}

is_game_dir() { [ -n "$1" ] && [ -d "$1" ] && ls "$1" 2>/dev/null | grep -qix 'deadspace2.exe'; }

# escolhe uma pasta entre varias (ou pede o caminho, se nao achou nenhuma) e grava em .game-path
pick_game_dir() {
    local list=("$@") choice
    if [ ${#list[@]} -eq 1 ]; then choice=${list[0]}
    elif [ ${#list[@]} -gt 1 ]; then
        if [ -t 0 ] && command -v gum >/dev/null; then
            choice=$(gum choose --header "  Achei o Dead Space 2 em mais de um lugar. Qual voce joga?" "${list[@]}") || return 1
        elif [ -t 0 ]; then
            say_early "Achei o Dead Space 2 em mais de um lugar. Qual voce joga?"
            PS3="Escolha um numero: "; select choice in "${list[@]}"; do [ -n "$choice" ] && break; done
        else choice=${list[0]}; fi
    else
        [ -t 0 ] || return 1
        say_early "Nao achei o Dead Space 2 sozinho. Cole o caminho da pasta do jogo (a que tem o deadspace2.exe):"
        if command -v gum >/dev/null; then choice=$(gum input --placeholder "/caminho/para/Dead Space 2" --width 80) || return 1
        else read -r -p "> " choice; fi
        choice=${choice/#\~/$HOME}; choice=${choice%/}
        is_game_dir "$choice" || { say_early "Essa pasta nao tem o deadspace2.exe."; return 1; }
    fi
    choice=$(readlink -f "$choice")
    printf '%s\n' "$choice" > "$GAME_FILE"
    say_early "Dead Space 2 encontrado em: $choice"
    say_early "(guardado em $GAME_FILE; para trocar: ./remaster.sh game)"
    GAME=$choice
}

resolve_game() {
    if [ -n "$GAME" ]; then
        is_game_dir "$GAME" && return 0
        say_early "GAME=$GAME nao tem o deadspace2.exe."; exit 1
    fi
    if [ -f "$GAME_FILE" ]; then
        GAME=$(head -1 "$GAME_FILE")
        is_game_dir "$GAME" && return 0
        say_early "A pasta guardada ($GAME) nao tem mais o jogo. Procurando de novo..."
    fi
    say_early "Procurando a pasta do Dead Space 2..."
    local dirs; mapfile -t dirs < <(find_game_dirs)
    pick_game_dir "${dirs[@]}" && return 0
    say_early "Nao achei o Dead Space 2. Rode de novo informando a pasta:"
    say_early "  ./remaster.sh game \"/caminho/para/Dead Space 2\""
    exit 1
}

case "${1:-}" in
    -h|--help|help) GAME=${GAME:-$(head -1 "$GAME_FILE" 2>/dev/null)} ;;
    game) ;;  # o comando game cuida disso sozinho
    *) resolve_game ;;
esac

TEXMOD="$GAME/texmod"
INI="$GAME/DS2TexInject.ini"
LOG="$WORK/remaster.log"
OPTS=(--game "$GAME" --work "$WORK" --scale "$SCALE" --mask-scale "$MASK_SCALE" --max-size "$MAX_SIZE" --pack-name "$PACK")
[ -n "$LIMIT" ] && OPTS+=(--limit "$LIMIT")
MODEL_OPTS=(--model "$MODEL")
[ -n "$GLOW_MODEL" ] && MODEL_OPTS+=(--glow-model "$GLOW_MODEL")
[ -n "$SOFT_MODEL" ] && MODEL_OPTS+=(--soft-model "$SOFT_MODEL")

say() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
die() { say "ERRO: $*"; notify "Remaster parou com erro" "$*"; exit 1; }
notify() { command -v notify-send >/dev/null && notify-send -a "DS2 Remaster" "$1" "$2" 2>/dev/null; true; }
# o processo do jogo no Wine aparece como "S:\steamapps\...\deadspace2.exe"
game_running() { pgrep -x deadspace2.exe >/dev/null || pgrep -f '^[A-Za-z]:\\.*deadspace2\.exe' >/dev/null; }

need_game_closed() {
    game_running && die "o Dead Space 2 esta aberto. Feche o jogo e rode de novo."
    true
}

set_dump() {
    [ -f "$INI" ] || die "nao achei $INI"
    sed -i "s/^DumpTextures=.*/DumpTextures=$1/" "$INI"
}

rebuild_cache() {
    say "preparando o cache do jogo (ds2tex.py)..."
    python3 "$GAME/DS2TexInject/ds2tex.py" "$TEXMOD" 2>&1 | tail -6 | tee -a "$LOG"
}

# baixa um modelo que ainda nao esta em models/ (um download interrompido nao conta como baixado)
ensure_model() {
    local path=$1 url=$2 what=$3
    [ -n "$path" ] || return 0
    [ -s "$path" ] && return 0
    mkdir -p "$(dirname "$path")"
    if [ -z "$url" ]; then die "o modelo $path nao existe e nao sei de onde baixar. Coloque o arquivo .pth la."; fi
    say "baixando o modelo $(basename "$path") ($what)"
    curl -fL --retry 3 -C - --progress-bar -o "$path.part" "$url" && mv "$path.part" "$path" \
        || die "falha ao baixar $(basename "$path"). Confira a internet e rode de novo (o download continua de onde parou)."
}

# modelos conhecidos: o URL vem do nome do arquivo, entao MODEL=models/4x-UltraSharp.pth tambem baixa sozinho
model_url() {
    case "$(basename "$1")" in
        4x-PBRify_UpscalerV4.pth) echo "$MODEL_URL" ;;
        4x-UltraSharp.pth) echo "$ULTRASHARP_URL" ;;
        *) [ "$1" = "$MODEL" ] && echo "$MODEL_URL" ;;
    esac
}

ensure_models() {
    ensure_model "$MODEL" "$(model_url "$MODEL")" "modelo principal"
    ensure_model "$GLOW_MODEL" "$(model_url "$GLOW_MODEL")" "luzes, brilhos e fumaca"
    ensure_model "$SOFT_MODEL" "$(model_url "$SOFT_MODEL")" "texturas lisas"
}

# o DS2TexInject e quem coloca as texturas no jogo; sem ele o pacote nao aparece
check_injector() {
    if [ -f "$GAME/DS2TexInject.ini" ] && [ -f "$GAME/d3d9.dll" ]; then
        say "DS2TexInject: instalado em $GAME"
    else
        say "AVISO: o DS2TexInject nao esta instalado em $GAME. Sem ele o remaster nao aparece no jogo."
        say "       Baixe em https://github.com/sidnei-almeida/dead-space-2-texmod-linux"
    fi
}

cmd_game() {
    shift
    if [ $# -gt 0 ]; then
        local d=${1%/}
        is_game_dir "$d" || die "essa pasta nao tem o deadspace2.exe: $d"
        pick_game_dir "$d"
    else
        say_early "Procurando o Dead Space 2 em todos os discos (pode levar um minuto)..."
        local dirs; mapfile -t dirs < <(find_game_dirs --deep)
        pick_game_dir "${dirs[@]}" || die "nao achei. Informe a pasta: ./remaster.sh game \"/caminho/para/Dead Space 2\""
    fi
    GAME=$(head -1 "$GAME_FILE"); check_injector
}

cmd_setup() {
    mkdir -p "$WORK"
    if [ ! -x "$PY" ]; then
        say "criando ambiente Python em .venv"
        python3 -m venv .venv || die "falha ao criar o .venv"
    fi
    if ! "$PY" -c "import torch" 2>/dev/null; then
        say "instalando PyTorch (Intel Arc / XPU)..."
        "$PY" -m pip install -q torch torchvision --index-url https://download.pytorch.org/whl/xpu || die "falha ao instalar o PyTorch"
    fi
    "$PY" -m pip install -q -r requirements.txt || die "falha ao instalar as dependencias"
    ensure_models
    check_injector
    "$PY" -c "import torch; print('GPU:', torch.xpu.get_device_name(0) if torch.xpu.is_available() else 'NAO ENCONTRADA (vai usar a CPU, bem mais lento)')"
}

# uma linha que se atualiza no terminal: barra, contagem e tempo restante
show_progress() {
    local j="$WORK/status.json" pct done total left bar
    [ -f "$j" ] && [ "$(stat -c %Y "$j")" -ge "$START" ] || { printf '\r\e[K  preparando a IA...'; return; }
    pct=$(sed -n 's/.*"porcentagem": \([0-9.]*\).*/\1/p' "$j")
    done=$(sed -n 's/.*"feitas": \([0-9]*\).*/\1/p' "$j")
    total=$(sed -n 's/.*"total": \([0-9]*\).*/\1/p' "$j")
    left=$(sed -n 's/.*"faltam": "\([^"]*\)".*/\1/p' "$j")
    pct=${pct:-0}
    bar=$(printf '%*s' "$(( ${pct%.*} / 5 ))" '' | tr ' ' '#')
    printf '\r\e[K  [%-20s] %5s%%  %s/%s texturas  faltam ~%s' "$bar" "$pct" "$done" "$total" "$left"
}

# roda o upscale vigiando o status.json; se ficar parado, mata e recomeca (o que ja foi feito e pulado)
upscale_with_watchdog() {
    local tries=0 pid last now
    while :; do
        "$PY" ds2remaster.py upscale "${OPTS[@]}" "${MODEL_OPTS[@]}" >> "$LOG" 2>&1 &
        pid=$!
        while kill -0 "$pid" 2>/dev/null; do
            sleep 2
            [ -t 1 ] && show_progress
            game_running && { kill "$pid"; wait "$pid" 2>/dev/null; die "o jogo foi aberto durante o processamento; rode de novo depois de fechar"; }
            last=$(stat -c %Y "$WORK/status.json" 2>/dev/null || echo 0)
            [ "$last" -lt "$START" ] && last=$START
            now=$(date +%s)
            if [ $((now - last)) -gt "$STALL_SECONDS" ]; then
                say "sem progresso ha $((now - last))s (GPU travada?). Reiniciando..."
                kill "$pid"; sleep 5; kill -9 "$pid" 2>/dev/null
                break
            fi
        done
        [ -t 1 ] && echo
        if wait "$pid" 2>/dev/null; then return 0; fi
        tries=$((tries + 1))
        [ "$tries" -gt "$MAX_RESTARTS" ] && die "o upscale falhou $tries vezes. Veja $LOG"
        say "tentativa $((tries + 1)) de $((MAX_RESTARTS + 1))"
        START=$(date +%s)
    done
}

cmd_run() {
    need_game_closed
    [ -x "$PY" ] || die "ambiente nao instalado. Rode primeiro: ./remaster.sh setup"
    ensure_models
    mkdir -p "$WORK"
    exec 9> "$WORK/.lock"
    flock -n 9 || die "ja tem uma rodada em andamento (./remaster.sh status)"
    START=$(date +%s)
    say "===== remaster: inicio ====="
    say "1/5 lendo o dump"
    "$PY" ds2remaster.py scan "${OPTS[@]}" 2>&1 | tail -8 | tee -a "$LOG" || die "scan falhou"
    # resultados antigos em que a IA inventou textura (luzes com chuvisco) sao descartados e refeitos
    "$PY" ds2remaster.py recheck "${OPTS[@]}" "${MODEL_OPTS[@]}" 2>&1 | tail -1 | tee -a "$LOG" || die "recheck falhou"
    say "2/5 upscale com IA (pode levar horas na primeira vez; acompanhe com ./remaster.sh status)"
    upscale_with_watchdog
    tail -1 "$LOG"
    need_game_closed
    say "3/5 gerando DDS com mipmaps"
    "$PY" ds2remaster.py encode "${OPTS[@]}" 2>&1 | tail -1 | tee -a "$LOG" || die "encode falhou"
    say "4/5 montando o pacote"
    # o pacote de teste antigo e substituido pelo completo
    [ -f "$TEXMOD/zy_ai_teste.zip" ] && mkdir -p "$TEXMOD/_ai_off" && mv "$TEXMOD/zy_ai_teste.zip" "$TEXMOD/_ai_off/"
    rm -f "$TEXMOD/_ai_off/$PACK"
    "$PY" ds2remaster.py pack "${OPTS[@]}" 2>&1 | sed -n 2p | tee -a "$LOG" || die "pack falhou"
    need_game_closed
    say "5/5 instalando no jogo"
    rebuild_cache
    local mins=$(( ($(date +%s) - START) / 60 ))
    say "===== pronto em ${mins} min. Pode abrir o jogo. ====="
    notify "Remaster pronto" "Terminou em ${mins} min. Pode abrir o Dead Space 2."
}

cmd_status() {
    if [ -f "$WORK/status.json" ]; then
        "$PY" ds2remaster.py status --work "$WORK" 2>/dev/null | tail -5
    else
        echo "nenhuma rodada registrada ainda"
    fi
    if [ -f "$WORK/.lock" ] && ! flock -n "$WORK/.lock" true; then
        echo "situacao: RODANDO"
    else
        echo "situacao: parado"
    fi
    [ -f "$LOG" ] && { echo "--- ultimas linhas do log ($LOG):"; grep -v '^\s*\[' "$LOG" | tail -5; }
}

cmd_preview() {
    [ -x "$PY" ] || die "ambiente nao instalado. Rode primeiro: ./remaster.sh setup"
    "$PY" ds2remaster.py preview "${OPTS[@]}" 2>&1 | tail -1
    echo "Abra no navegador: $(readlink -f "$WORK/preview.html")"
    echo "Para tirar uma textura do remaster: coloque o hash dela em $WORK/rejected.txt e rode ./remaster.sh"
}

cmd_on() {
    need_game_closed
    if [ -f "$TEXMOD/_ai_off/$PACK" ]; then mv "$TEXMOD/_ai_off/$PACK" "$TEXMOD/"; fi
    [ -f "$TEXMOD/$PACK" ] || die "pacote $PACK nao existe ainda. Rode ./remaster.sh primeiro."
    rebuild_cache
    say "remaster ATIVADO"
}

cmd_off() {
    need_game_closed
    mkdir -p "$TEXMOD/_ai_off"
    for z in "$TEXMOD"/*_ai_*.zip; do [ -f "$z" ] && mv "$z" "$TEXMOD/_ai_off/"; done
    rebuild_cache
    say "remaster DESATIVADO (so os seus .tpf)"
}

# ---------------------------------------------------------------- menu interativo

STEAM_APPID=47780

# cores (so quando ha terminal)
if [ -t 1 ]; then
    C_ACC=$'\e[38;5;45m'; C_OK=$'\e[38;5;84m'; C_WARN=$'\e[38;5;214m'; C_BAD=$'\e[38;5;203m'
    C_DIM=$'\e[38;5;244m'; C_B=$'\e[1m'; C_0=$'\e[0m'
else
    C_ACC=''; C_OK=''; C_WARN=''; C_BAD=''; C_DIM=''; C_B=''; C_0=''
fi

dump_is_on() { grep -q '^DumpTextures=1' "$INI" 2>/dev/null; }
pack_is_on() { [ -f "$TEXMOD/$PACK" ]; }
run_active() { [ -f "$WORK/.lock" ] && ! flock -n "$WORK/.lock" true; }

# texturas que a proxima rodada vai processar: as do dump ainda nao analisadas + as analisadas e na fila
# (nao puladas, nao cobertas por .tpf, nao rejeitadas) que ainda nao tem resultado em work/up
count_new() {
    "$PY" - "$TEXMOD/_dump" "$WORK" 2>/dev/null <<'PY' || echo "?"
import json, os, sys
dump, work = sys.argv[1], sys.argv[2]
manp = os.path.join(work, 'manifest.json')
man = json.load(open(manp)) if os.path.exists(manp) else {}
rej = os.path.join(work, 'rejected.txt')
rejected = {l.strip() for l in open(rej)} if os.path.exists(rej) else set()
files = [f[:10].upper().replace('0X', '0x') for f in os.listdir(dump) if f.lower().endswith('.dds')] if os.path.isdir(dump) else []
n = sum(1 for h in files if h not in man)
n += sum(1 for h, e in man.items() if e['class'] != 'skip' and not e['covered'] and h not in rejected
         and not os.path.exists(os.path.join(work, 'up', h + '.png')))
print(n)
PY
}

# quantas texturas o manifest marcou como puladas (pequenas/cor unica) e cobertas pelos .tpf
count_left_out() {
    "$PY" - "$WORK/manifest.json" 2>/dev/null <<'PY' || echo "? ?"
import json, os, sys
m = json.load(open(sys.argv[1])) if os.path.exists(sys.argv[1]) else {}
cov = sum(1 for e in m.values() if e.get('covered'))
skip = sum(1 for e in m.values() if not e.get('covered') and e.get('class') == 'skip')
print(skip, cov)
PY
}

count_files() { [ -d "$1" ] && find "$1" -maxdepth 1 -type f -name "$2" | wc -l || echo 0; }

last_run() {  # "[22:17:31] ===== pronto em 2 min. Pode abrir o jogo. =====" -> "as 22:17, levou 2 min"
    local l
    l=$(grep -h "pronto em" "$LOG" 2>/dev/null | tail -1)
    if [ -n "$l" ]; then echo "$l" | sed -E 's/^\[([0-9]{2}:[0-9]{2}):[0-9]{2}\].*pronto em ([^.]*)\..*/as \1, levou \2/'
    else echo "nenhuma ainda"; fi
}

line() { printf '  %-20s %s\n' "$1" "$2"; }
model_label() {  # "PBRify_UpscalerV4 + UltraSharp nas luzes"
    local m; m=$(basename "$MODEL" .pth); m=${m#4x-}
    [ -n "$GLOW_MODEL" ] && m="$m + $(basename "${GLOW_MODEL#*4x-}" .pth) nas luzes"
    [ -n "$SOFT_MODEL" ] && m="$m + $(basename "${SOFT_MODEL#*4x-}" .pth) nas lisas"
    printf '%s' "$m"
}

menu_header() {
    local new dump_n done_n pack_sz skip_n cov_n
    NEW_COUNT=$(count_new)
    read -r skip_n cov_n < <(count_left_out)
    dump_n=$(count_files "$TEXMOD/_dump" '*.dds')
    done_n=$(count_files "$WORK/up" '*.png')
    pack_sz=$(du -h "$TEXMOD/$PACK" 2>/dev/null | cut -f1)
    clear
    printf '\n  %s%sDEAD SPACE 2%s  %sAI TEXTURE REMASTER%s\n' "$C_B" "$C_ACC" "$C_0" "$C_ACC" "$C_0"
    printf '  %s%s%s\n\n' "$C_DIM" "────────────────────────────────────────────────────" "$C_0"
    if game_running; then line "Jogo" "${C_BAD}● aberto${C_0} ${C_DIM}(feche antes de remasterizar)${C_0}"
    else line "Jogo" "${C_OK}○ fechado${C_0}"; fi
    if pack_is_on; then line "Remaster no jogo" "${C_OK}● ativo${C_0} ${C_DIM}(${pack_sz:-?})${C_0}"
    else line "Remaster no jogo" "${C_DIM}○ desativado${C_0}"; fi
    if dump_is_on; then line "Coleta" "${C_WARN}● LIGADA${C_0} ${C_DIM}(o jogo salva cada textura nova)${C_0}"
    else line "Coleta" "${C_DIM}○ desligada${C_0}"; fi
    if run_active; then line "Rodada" "${C_ACC}● em andamento${C_0}"
    else line "Ultima rodada" "${C_DIM}$(last_run)${C_0}"; fi
    echo
    line "Texturas coletadas" "$dump_n"
    line "Ja remasterizadas" "$done_n"
    line "Puladas" "${C_DIM}${skip_n}  (pequenas demais ou de cor unica)${C_0}"
    line "Dos seus mods" "${C_DIM}${cov_n}  (seus .tpf ja cuidam delas)${C_0}"
    if [ "$NEW_COUNT" = "0" ]; then line "Esperando" "${C_DIM}0${C_0}"
    else line "Esperando" "${C_WARN}${NEW_COUNT}${C_0} ${C_DIM}na fila, ainda nao processadas${C_0}"; fi
    line "Modelo" "${C_DIM}$(model_label), ${SCALE}x, ate ${MAX_SIZE}px${C_0}"
    printf '\n'
}

pause() { echo; read -rp "  ${C_DIM}Enter para voltar ao menu...${C_0}" _ </dev/tty; }
msg() { printf '\n  %s\n' "$*"; }

ask() {  # ask "pergunta?" -> 0 se sim
    if [ "$HAS_GUM" = 1 ]; then gum confirm --affirmative "Sim" --negative "Nao" --prompt.foreground 45 "$1"
    else read -rp "$1 [s/N] " r </dev/tty; [[ "$r" =~ ^[sSyY] ]]; fi
}

with_spinner() {  # with_spinner "titulo" comando... (mostra o fim da saida depois)
    local title=$1; shift
    if [ "$HAS_GUM" = 1 ]; then
        gum spin --spinner dot --spinner.foreground 45 --title " $title" --show-output -- "$@"
    else
        echo "  $title"; "$@"
    fi
}

progress_bar() {  # progress_bar porcentagem largura
    local pct=${1%.*} w=$2 fill
    [ -z "$pct" ] && pct=0
    fill=$(( pct * w / 100 ))
    printf '%s%s%s%s%s' "$C_ACC" "$(printf '%*s' "$fill" '' | sed 's/ /█/g')" "$C_DIM" "$(printf '%*s' "$((w - fill))" '' | sed 's/ /░/g')" "$C_0"
}

# painel que se redesenha durante a rodada: etapas, barra, contagem por tipo
draw_dashboard() {
    local from=$1 state=$2 spin=$3 step=0 i j pct done total left el err cls
    local names=("Ler as texturas coletadas" "Remasterizar com IA ($(model_label))" "Gerar DDS com mipmaps" "Montar o pacote" "Instalar no jogo")
    local newlog
    newlog=$(tail -n +"$((from + 1))" "$LOG" 2>/dev/null)
    for i in 1 2 3 4 5; do grep -q "\] $i/5 " <<<"$newlog" && step=$i; done
    printf '\e[H\e[J'
    printf '\n  %s%sDEAD SPACE 2%s  %sAI TEXTURE REMASTER%s   %s%s%s\n' "$C_B" "$C_ACC" "$C_0" "$C_ACC" "$C_0" "$C_DIM" "$state" "$C_0"
    printf '  %s%s%s\n\n' "$C_DIM" "────────────────────────────────────────────────────" "$C_0"
    for i in 1 2 3 4 5; do
        if [ "$i" -lt "$step" ] || [ "$state" = "concluida" ]; then printf '  %s✔%s  %s\n' "$C_OK" "$C_0" "${names[$((i-1))]}"
        elif [ "$i" -eq "$step" ]; then printf '  %s%s%s  %s%s%s\n' "$C_ACC" "$spin" "$C_0" "$C_B" "${names[$((i-1))]}" "$C_0"
        else printf '  %s·  %s%s\n' "$C_DIM" "${names[$((i-1))]}" "$C_0"; fi
    done
    echo
    j="$WORK/status.json"
    if [ -f "$j" ] && [ "$(stat -c %Y "$j")" -ge "$DASH_START" ]; then
        pct=$(sed -n 's/.*"porcentagem": \([0-9.]*\).*/\1/p' "$j"); done=$(sed -n 's/.*"feitas": \([0-9]*\).*/\1/p' "$j")
        total=$(sed -n 's/.*"total": \([0-9]*\).*/\1/p' "$j"); left=$(sed -n 's/.*"faltam": "\([^"]*\)".*/\1/p' "$j")
        el=$(sed -n 's/.*"decorrido": "\([^"]*\)".*/\1/p' "$j"); err=$(sed -n 's/.*"erros": \([0-9]*\).*/\1/p' "$j")
        cls=$(tr -d '\n ' < "$j" | sed -n 's/.*"por_classe":{\([^}]*\)}.*/\1/p' | sed 's/"diffuse":/cor /; s/"mask":/mascaras /; s/"normal_ag":/normal maps /; s/"normal":/normal RGB /; s/"smooth":/suaves /; s/"glow":/luzes /; s/"//g; s/,/   /g')
        printf '  %s  %s%5s%%%s   %s / %s texturas\n' "$(progress_bar "$pct" 34)" "$C_B" "$pct" "$C_0" "$done" "$total"
        printf '  %sdecorrido %s   faltam ~%s   erros %s%s\n' "$C_DIM" "$el" "$left" "${err:-0}" "$C_0"
        [ -n "$cls" ] && printf '  %s%s%s\n' "$C_DIM" "$cls" "$C_0"
    elif [ "$step" -le 2 ]; then
        printf '  %spreparando...%s\n' "$C_DIM" "$C_0"
    fi
    echo
    grep -E "ERRO|sem progresso|tentativa" <<<"$newlog" | tail -3 | sed "s/^/  ${C_BAD}/; s/$/${C_0}/"
    [ "$state" = "em andamento" ] && printf '\n  %sCtrl+C cancela (o que ja foi feito fica salvo)%s\n' "$C_DIM" "$C_0"
}

run_dashboard() {
    local from pid rc frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) k=0 cancelled=0
    if game_running; then msg "${C_BAD}O jogo esta aberto.${C_0} Feche o Dead Space 2 antes de remasterizar."; return; fi
    if run_active; then msg "${C_WARN}Ja tem uma rodada em andamento.${C_0} Veja em 'Ver o progresso'."; return; fi
    if [ "$NEW_COUNT" = "0" ]; then
        ask "Nao ha texturas novas no dump. Rodar mesmo assim (refaz o pacote e o cache)?" || return
    fi
    from=$(wc -l < "$LOG" 2>/dev/null || echo 0)
    DASH_START=$(date +%s)
    set -m
    ( cmd_run ) >/dev/null 2>&1 &
    pid=$!
    set +m
    trap 'cancelled=1; kill -TERM -- -$pid 2>/dev/null' INT
    tput civis 2>/dev/null
    while kill -0 "$pid" 2>/dev/null; do
        draw_dashboard "$from" "em andamento" "${frames[$((k % 10))]}"
        k=$((k + 1)); sleep 0.5
    done
    wait "$pid"; rc=$?
    trap - INT
    tput cnorm 2>/dev/null
    if [ "$cancelled" = 1 ]; then
        draw_dashboard "$from" "cancelada" "■"
        msg "${C_WARN}Rodada cancelada.${C_0} O que ja foi feito fica salvo; da proxima vez continua de onde parou."
    elif [ "$rc" = 0 ]; then
        draw_dashboard "$from" "concluida" "✔"
        msg "${C_OK}${C_B}Pronto!${C_0} $(grep -h "pronto em" "$LOG" | tail -1 | sed 's/.*pronto em/Terminou em/; s/ =====//')"
    else
        draw_dashboard "$from" "com erro" "✖"
        msg "${C_BAD}A rodada parou com erro.${C_0} Detalhes em $LOG"
    fi
}

play_game() {
    if run_active; then
        ask "Tem uma rodada em andamento, e abrir o jogo vai interrompe-la. Abrir mesmo assim?" || return
    fi
    if game_running; then msg "O jogo ja esta aberto."; return; fi
    if [[ "$GAME" != */steamapps/common/* ]]; then
        msg "${C_WARN}Este Dead Space 2 nao e da Steam.${C_0} Abra pelo launcher que voce usa (Heroic, Lutris, Bottles...)."
        dump_is_on && msg "${C_DIM}A coleta esta ligada: as texturas novas vao ser salvas enquanto voce joga.${C_0}"
        return
    fi
    msg "${C_ACC}Abrindo o Dead Space 2 pelo Steam...${C_0}"
    dump_is_on && msg "${C_DIM}A coleta esta ligada: as texturas novas vao ser salvas enquanto voce joga.${C_0}"
    (xdg-open "steam://rungameid/$STEAM_APPID" >/dev/null 2>&1 || steam "steam://rungameid/$STEAM_APPID" >/dev/null 2>&1) &
}

open_preview() {
    with_spinner "Gerando a comparacao original x IA..." "$SELF" preview
    command -v xdg-open >/dev/null && (xdg-open "$(readlink -f "$WORK/preview.html")" >/dev/null 2>&1 &)
}

cmd_menu() {
    command -v gum >/dev/null && HAS_GUM=1 || HAS_GUM=0
    while :; do
        menu_header
        local o_play="▶  Jogar Dead Space 2"
        local o_run="✦  Remasterizar as texturas novas"
        [ "$NEW_COUNT" != "0" ] && [ "$NEW_COUNT" != "?" ] && o_run="✦  Remasterizar as texturas novas ($NEW_COUNT esperando)"
        local o_dump o_pack
        if dump_is_on; then o_dump="◉  Desligar a coleta de texturas (agora esta LIGADA)"
        else o_dump="○  Ligar a coleta de texturas (agora esta desligada)"; fi
        if pack_is_on; then o_pack="◐  Desativar o remaster no jogo (agora esta ATIVO)"
        else o_pack="◑  Ativar o remaster no jogo (agora esta desativado)"; fi
        local o_prev="⇄  Comparar original x IA (abre no navegador)"
        local o_log="≡  Ver o log da ultima rodada"
        local o_setup="⚙  Instalar ou consertar o ambiente"
        local o_help="?  Ajuda"
        local o_quit="✕  Sair"
        local opts=("$o_play" "$o_run" "$o_dump" "$o_pack" "$o_prev" "$o_log" "$o_setup" "$o_help" "$o_quit") choice
        if [ "$HAS_GUM" = 1 ]; then
            choice=$(gum choose --header "  O que voce quer fazer? (setas + Enter, Esc sai)" --cursor "  ➜ " \
                --header.foreground 244 --cursor.foreground 45 --selected.foreground 45 "${opts[@]}") || break
        else
            PS3="Escolha um numero: "
            select choice in "${opts[@]}"; do [ -n "$choice" ] && break; done </dev/tty
        fi
        case "$choice" in
            "$o_play") play_game; pause ;;
            "$o_run") run_dashboard; pause ;;
            "$o_dump")
                if dump_is_on; then ( set_dump 0 ) && msg "${C_OK}Coleta desligada.${C_0} O jogo nao salva mais texturas novas."
                else ( set_dump 1 ) && msg "${C_WARN}Coleta ligada.${C_0} Abra o jogo e jogue: cada textura nova vai para o dump."; fi
                pause ;;
            "$o_pack")
                if game_running; then msg "${C_BAD}Feche o jogo antes.${C_0} O cache de texturas nao pode mudar com o jogo aberto."
                elif pack_is_on; then ask "Desativar o remaster? O jogo fica so com os seus pacotes .tpf." && with_spinner "Desativando e refazendo o cache do jogo..." "$SELF" off
                else with_spinner "Ativando e refazendo o cache do jogo..." "$SELF" on; fi
                pause ;;
            "$o_prev") open_preview; pause ;;
            "$o_log") clear; grep -Ev '^\s+\[' "$LOG" 2>/dev/null | tail -40 || echo "sem log ainda"; pause ;;
            "$o_setup") ( cmd_setup ); pause ;;
            "$o_help") cmd_help | ${PAGER:-less -R} ;;
            *) break ;;
        esac
    done
    clear
}

cmd_help() {
    local b='' n=''
    [ -t 1 ] && { b=$'\e[1m'; n=$'\e[0m'; }
    cat <<AJUDA
${b}remaster.sh${n} - remaster das texturas do Dead Space 2 com IA, em um comando.

O jogo entrega as texturas originais (coleta), a IA refaz cada uma e o resultado
vira um pacote que o DS2TexInject carrega no jogo. Seus pacotes .tpf sempre tem
prioridade: as texturas que eles cobrem ficam de fora. Nenhum arquivo do jogo e
modificado, e o F10 compara original e remaster durante o jogo.

${b}USO${n}
  ./remaster.sh             abre o menu (o jeito mais facil)
  ./remaster.sh [comando]   roda um comando direto

${b}COMANDOS${n}
  menu            Menu interativo: escolha com as setas e Enter.
  run             Processa so as texturas novas do dump e instala no jogo.
                  Pode ficar rodando sozinho: retoma de onde parou (Ctrl+C e
                  seguro), reinicia se a GPU travar, para se o jogo for aberto
                  e avisa com uma notificacao no fim.
  status          Progresso de uma rodada em andamento (use em outro terminal).
  preview         Gera uma pagina com original e IA lado a lado. Para tirar uma
                  textura do remaster, coloque o hash dela em
                  $WORK/rejected.txt e rode ./remaster.sh de novo.
  dump-on         Liga a coleta: jogue normalmente e cada textura nova vai para
                  texmod/_dump. O jogo pode engasgar um pouco enquanto salva.
  dump-off        Desliga a coleta.
  on              Ativa o pacote da IA no jogo.
  off             Desativa o pacote da IA (ficam so os seus .tpf).
  setup           Instala o ambiente Python (PyTorch, spandrel), baixa os modelos
                  que faltam e confere se o DS2TexInject esta no jogo.
  game [pasta]    Procura o Dead Space 2 de novo em todos os discos, ou usa a
                  pasta informada. Na primeira vez isso e feito sozinho.
  -h, --help      Mostra esta ajuda.

${b}FLUXO TIPICO${n} (tudo isso tambem esta no menu)
  ./remaster.sh setup       uma vez
  ./remaster.sh dump-on     depois jogue um pouco
  ./remaster.sh dump-off    ao terminar de jogar
  ./remaster.sh run         com o jogo fechado

${b}CONFIGURACAO ATUAL${n} (edite no topo deste arquivo)
  modelo        $MODEL
  nas luzes     ${GLOW_MODEL:-(o mesmo)}   luzes, brilhos e fumaca, e tudo em que o modelo principal inventar textura
  nas lisas     ${SOFT_MODEL:-(o mesmo)}   opcional, para texturas de pouco detalhe; degrades puros nao passam por IA
  escala        ${SCALE}x cor e normal maps, ${MASK_SCALE}x mascaras e mapas de luz
  lado maximo   ${MAX_SIZE}px
  trabalho      $WORK
  jogo          ${GAME:-(ainda nao encontrado)}   guardado em $GAME_FILE

${b}ARQUIVOS${n}
  $LOG    log da rodada
  texmod/$PACK    pacote instalado no jogo
AJUDA
}

mkdir -p "$WORK"
if [ $# -eq 0 ]; then
    if [ -t 0 ] && [ -t 1 ]; then set -- menu; else set -- run; fi
fi
case "$1" in
    menu) cmd_menu ;;
    run) cmd_run ;;
    status) cmd_status ;;
    preview) cmd_preview ;;
    dump-on) set_dump 1; say "coleta LIGADA: jogue normalmente, as texturas novas vao para texmod/_dump" ;;
    dump-off) set_dump 0; say "coleta DESLIGADA" ;;
    on) cmd_on ;;
    off) cmd_off ;;
    setup) cmd_setup ;;
    game) cmd_game "$@" ;;
    -h|--help|help) cmd_help ;;
    *) echo "comando desconhecido: $1" >&2; echo "veja: ./remaster.sh --help" >&2; exit 1 ;;
esac
