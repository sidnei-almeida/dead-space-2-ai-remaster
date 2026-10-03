# Luzes e fumaça no UltraSharp — retomar em 2026-10-04

## O problema
O remaster com o PBRify_UpscalerV4 ficou excelente, menos nas texturas de luz e fumaça:
painéis luminosos, brilhos de lâmpada, fachos e nuvens de poeira/fumaça saíram com chuvisco
e bordas duras (manchas escuras no ar na captura do refeitório). Não é questão de alpha:
das 668 texturas da classe, 560 não têm transparência. O padrão é forma suave com pouco
detalhe fino: o PBRify trata o ruído DXT do degradê como detalhe a "restaurar".

## O que foi feito hoje (tudo só no disco, NADA commitado)
- `ds2remaster.py`
  - classe nova `glow` (luz/brilho/fumaça): detalhe < 0.02, suavidade < 0.12 e no máximo
    2 matizes (cinza ou uma cor só). Vai para `--glow-model` (UltraSharp).
  - checagem anti-invenção depois do modelo principal: resultado reduzido ao tamanho do
    original, detalhe fino comparado ao do original. Acima de `--invent-max` (1.15) refaz
    com o `--glow-model`. Fica anotado no manifesto (`invent`, `model`).
  - comando `recheck`: aplica a checagem nos resultados antigos e apaga os reprovados
    para a próxima rodada refazer. Entra no `all` e no `remaster.sh run`.
  - `CLASSIFIER_VERSION` (agora 3): mudou o classificador, o scan reclassifica tudo e
    refaz o que mudou de classe.
- `remaster.sh`: `GLOW_MODEL=models/4x-UltraSharp.pth` por padrão (`GLOW_MODEL=` desliga),
  download no setup, `recheck` no passo 1, rótulo "PBRify + UltraSharp nas luzes".
- READMEs (en e pt-BR): classe, checagem, flags, créditos e nota de licença
  (UltraSharp é CC BY-NC-SA: pacote padrão não pode ser vendido).
- Imagens de análise em `work/comparacoes/`:
  `luzes_fumaca_pbrify_x_ultrasharp.png` (Lanczos | PBRify | UltraSharp, 14 casos),
  `piores_do_pbrify_original_x_ia.png`, `classe_glow_amostra_96_de_668.png`.

## Números
- 10326 texturas no dump, 9712 na fila (sem puladas e cobertas por .tpf).
- Refeitas com UltraSharp: 668 da classe glow + 100 reprovadas na checagem = 768.
  As outras 8944 ficaram como estavam (PBRify).
- Nos 14 casos de teste: invenção do PBRify 1.7 a 5.2, do UltraSharp 0.6 a 1.04.
- Rodada de 03/10 (disparada pelo menu às 02:43): 1350 texturas = 768 + novas do dump,
  ~35 min. Verificar no `remaster.log` se terminou com "pronto em".

## Pendente para amanhã
1. Conferir que a rodada terminou sem erro: `./remaster.sh status` e fim do
   `work/pbrify2x/remaster.log`.
2. Rodar `./remaster.sh run` mais uma vez (curta, ~5 min). O classificador versão 3
   devolve ao PBRify 71 texturas coloridas (fotos, cartazes) que a regra anterior tinha
   mandado para o UltraSharp. Refaz pacote e cache.
3. Testar no jogo: refeitório da captura (luzes do teto, lâmpadas azuis, poeira no ar).
   F10 compara original x remaster. Conferir também fumaça/vapor em alguma área.
4. Se ficou bom: `git add -A && git commit` (ds2remaster.py, remaster.sh, READMEs, planning/).
   Se alguma luz ainda ficar ruim: `./remaster.sh preview`, achar o hash, ver o campo
   "invencao" e "modelo" na legenda; ajustar `GLOW_*`/`INVENT_MAX` ou pôr em `rejected.txt`.

## Decisões / ideias discutidas
- Encadear PBRify -> UltraSharp em tudo ("tchan"): não recomendado como regra (detalhe
  sobre detalhe inventado, halo, horas de GPU, o jogo come o ganho com mipmaps).
  Alternativas: ReShade CAS/LumaSharpen, ou teste pequeno com ~20 texturas de uma área
  num pacote separado, comparando com F10. Montar se o usuário quiser.
- A coleta (dump) continua: texturas novas entram na próxima rodada com a mesma regra.
