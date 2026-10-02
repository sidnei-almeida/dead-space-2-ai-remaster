#!/bin/bash
# remaster.sh - tudo do remaster do Dead Space 2 em um comando.
#
#   ./remaster.sh            processa as texturas novas do dump e instala no jogo (pode deixar rodando)
#   ./remaster.sh status     mostra o progresso de uma rodada em andamento
#   ./remaster.sh preview    gera uma pagina com original x IA lado a lado (para rejeitar texturas ruins)
#   ./remaster.sh dump-on    liga a coleta de texturas (jogue normalmente depois)
#   ./remaster.sh dump-off   desliga a coleta
#   ./remaster.sh on         ativa o pacote da IA no jogo
#   ./remaster.sh off        desativa o pacote da IA (fica so com os seus .tpf)
#   ./remaster.sh setup      instala o ambiente Python (PyTorch, spandrel) e baixa o modelo
#
# As configuracoes ficam logo abaixo. Para mudar, edite este arquivo.

GAME="${GAME:-$HOME/.local/share/Steam/steamapps/common/Dead Space 2}"
MODEL="${MODEL:-models/4x-UltraSharp.pth}"
MODEL_URL="https://huggingface.co/Kim2091/UltraSharp/resolve/main/4x-UltraSharp.pth"
SCALE=2            # texturas de cor e normal maps
MASK_SCALE=2       # mascaras, specular e mapas de luz (ganham pouco e ocupam muita memoria)
MAX_SIZE=2048      # lado maximo de qualquer textura
WORK="${WORK:-work/ultrasharp2x}"
PACK="zz_ai_remaster.zip"
STALL_SECONDS=300  # sem progresso por esse tempo = GPU travada: reinicia e continua de onde parou
MAX_RESTARTS=5
LIMIT="${LIMIT:-}"  # so para testes: processa no maximo N texturas

set -u -o pipefail
cd "$(dirname "$(readlink -f "$0")")" || exit 1
PY=.venv/bin/python
TEXMOD="$GAME/texmod"
INI="$GAME/DS2TexInject.ini"
LOG="$WORK/remaster.log"
OPTS=(--game "$GAME" --work "$WORK" --scale "$SCALE" --mask-scale "$MASK_SCALE" --max-size "$MAX_SIZE" --pack-name "$PACK")
[ -n "$LIMIT" ] && OPTS+=(--limit "$LIMIT")

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
    if [ ! -f "$MODEL" ]; then
        say "baixando o modelo $(basename "$MODEL")"
        curl -fL --progress-bar -o "$MODEL.part" "$MODEL_URL" && mv "$MODEL.part" "$MODEL" || die "falha ao baixar o modelo"
    fi
    "$PY" -c "import torch; print('GPU:', torch.xpu.get_device_name(0) if torch.xpu.is_available() else 'NAO ENCONTRADA (vai usar a CPU, bem mais lento)')"
}

# roda o upscale vigiando o status.json; se ficar parado, mata e recomeca (o que ja foi feito e pulado)
upscale_with_watchdog() {
    local tries=0 pid last now
    while :; do
        "$PY" ds2remaster.py upscale "${OPTS[@]}" --model "$MODEL" >> "$LOG" 2>&1 &
        pid=$!
        while kill -0 "$pid" 2>/dev/null; do
            sleep 10
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
        if wait "$pid" 2>/dev/null; then return 0; fi
        tries=$((tries + 1))
        [ "$tries" -gt "$MAX_RESTARTS" ] && die "o upscale falhou $tries vezes. Veja $LOG"
        say "tentativa $((tries + 1)) de $((MAX_RESTARTS + 1))"
        START=$(date +%s)
    done
}

cmd_run() {
    need_game_closed
    [ -x "$PY" ] && [ -f "$MODEL" ] || die "ambiente nao instalado. Rode primeiro: ./remaster.sh setup"
    mkdir -p "$WORK"
    exec 9> "$WORK/.lock"
    flock -n 9 || die "ja tem uma rodada em andamento (./remaster.sh status)"
    START=$(date +%s)
    say "===== remaster: inicio ====="
    say "1/5 lendo o dump"
    "$PY" ds2remaster.py scan "${OPTS[@]}" 2>&1 | tail -8 | tee -a "$LOG" || die "scan falhou"
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
    "$PY" ds2remaster.py pack "${OPTS[@]}" 2>&1 | head -2 | tail -1 | tee -a "$LOG" || die "pack falhou"
    need_game_closed
    say "5/5 instalando no jogo"
    rebuild_cache
    local mins=$(( ($(date +%s) - START) / 60 ))
    say "===== pronto em ${mins} min. Pode abrir o jogo. ====="
    notify "Remaster pronto" "Terminou em ${mins} min. Pode abrir o Dead Space 2."
}

cmd_status() {
    if [ -f "$WORK/status.json" ]; then
        "$PY" ds2remaster.py status --work "$WORK" 2>/dev/null | tail -4
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

mkdir -p "$WORK"
case "${1:-run}" in
    run) cmd_run ;;
    status) cmd_status ;;
    preview) cmd_preview ;;
    dump-on) set_dump 1; say "coleta LIGADA: jogue normalmente, as texturas novas vao para texmod/_dump" ;;
    dump-off) set_dump 0; say "coleta DESLIGADA" ;;
    on) cmd_on ;;
    off) cmd_off ;;
    setup) cmd_setup ;;
    *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
