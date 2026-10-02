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
        "$PY" ds2remaster.py upscale "${OPTS[@]}" --model "$MODEL" >> "$LOG" 2>&1 &
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

# ---------------------------------------------------------------- menu interativo

dump_is_on() { grep -q '^DumpTextures=1' "$INI" 2>/dev/null; }
pack_is_on() { [ -f "$TEXMOD/$PACK" ]; }
run_active() { [ -f "$WORK/.lock" ] && ! flock -n "$WORK/.lock" true; }

# texturas no dump que ainda nao foram analisadas (estimativa rapida do que a proxima rodada vai fazer)
count_new() {
    "$PY" - "$TEXMOD/_dump" "$WORK/manifest.json" 2>/dev/null <<'PY' || echo "?"
import json, os, sys
dump, man = sys.argv[1], sys.argv[2]
known = set(json.load(open(man))) if os.path.exists(man) else set()
files = [f[:10].upper().replace('0X', '0x') for f in os.listdir(dump) if f.lower().endswith('.dds')] if os.path.isdir(dump) else []
print(sum(1 for h in files if h not in known))
PY
}

menu_header() {
    local game dump pack new run
    game_running && game="ABERTO (feche antes de processar)" || game="fechado"
    pack_is_on && pack="ATIVO" || pack="desativado"
    dump_is_on && dump="LIGADA" || dump="desligada"
    run_active && run="RODANDO" || run="parada"
    new=$(count_new)
    local txt="DS2 AI Texture Remaster

Jogo:              $game
Remaster no jogo:  $pack
Coleta:            $dump
Texturas novas:    $new esperando
Rodada:            $run
Modelo:            $(basename "$MODEL" .pth), ${SCALE}x"
    if [ "$HAS_GUM" = 1 ]; then
        gum style --border rounded --border-foreground 45 --padding "0 2" --margin "1 0" "$txt"
    else
        printf '\n%s\n\n' "$txt"
    fi
}

pause() {
    echo
    read -rp "Enter para voltar ao menu..." _ </dev/tty
}

open_preview() {
    cmd_preview
    command -v xdg-open >/dev/null && xdg-open "$(readlink -f "$WORK/preview.html")" >/dev/null 2>&1 &
}

cmd_menu() {
    command -v gum >/dev/null && HAS_GUM=1 || HAS_GUM=0
    while :; do
        clear
        menu_header
        local o_run="Remasterizar as texturas novas"
        local o_status="Ver o progresso"
        local o_dump o_pack
        dump_is_on && o_dump="Desligar a coleta de texturas" || o_dump="Ligar a coleta de texturas (depois jogue)"
        pack_is_on && o_pack="Desativar o remaster no jogo" || o_pack="Ativar o remaster no jogo"
        local o_prev="Comparar original x IA (abre no navegador)"
        local o_setup="Instalar ou consertar o ambiente"
        local o_help="Ajuda"
        local o_quit="Sair"
        local opts=("$o_run" "$o_status" "$o_dump" "$o_pack" "$o_prev" "$o_setup" "$o_help" "$o_quit") choice
        if [ "$HAS_GUM" = 1 ]; then
            choice=$(gum choose --header "O que voce quer fazer? (setas + Enter)" --cursor "> " "${opts[@]}") || break
        else
            PS3="Escolha um numero: "
            select choice in "${opts[@]}"; do [ -n "$choice" ] && break; done </dev/tty
        fi
        case "$choice" in
            "$o_run") ( cmd_run ); pause ;;
            "$o_status") cmd_status; pause ;;
            "$o_dump") ( if dump_is_on; then set_dump 0; say "coleta DESLIGADA"; else set_dump 1; say "coleta LIGADA: jogue normalmente, as texturas novas vao para texmod/_dump"; fi ); pause ;;
            "$o_pack") if pack_is_on; then ( cmd_off ); else ( cmd_on ); fi; pause ;;
            "$o_prev") ( open_preview ); pause ;;
            "$o_setup") ( cmd_setup ); pause ;;
            "$o_help") cmd_help | ${PAGER:-less -R}; ;;
            *) break ;;
        esac
    done
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
  setup           Instala o ambiente Python (PyTorch, spandrel) e baixa o modelo.
  -h, --help      Mostra esta ajuda.

${b}FLUXO TIPICO${n} (tudo isso tambem esta no menu)
  ./remaster.sh setup       uma vez
  ./remaster.sh dump-on     depois jogue um pouco
  ./remaster.sh dump-off    ao terminar de jogar
  ./remaster.sh run         com o jogo fechado

${b}CONFIGURACAO ATUAL${n} (edite no topo deste arquivo)
  modelo        $MODEL
  escala        ${SCALE}x cor e normal maps, ${MASK_SCALE}x mascaras e mapas de luz
  lado maximo   ${MAX_SIZE}px
  trabalho      $WORK
  jogo          $GAME

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
    -h|--help|help) cmd_help ;;
    *) echo "comando desconhecido: $1" >&2; echo "veja: ./remaster.sh --help" >&2; exit 1 ;;
esac
