<p align="center"><img src="assets/dead-space-2-ai-remaster-banner.png" alt="Dead Space 2 AI Texture Remaster" width="100%"></p>

<h1 align="center">Dead Space 2 AI Texture Remaster</h1>

<p align="center"><b>Remaster every Dead Space 2 texture with open source AI, on your own GPU. One command, then walk away.</b><br>
Linux · Intel Arc · NVIDIA · PyTorch · Works with DS2TexInject</p>

<p align="center">
  <img alt="Linux" src="https://img.shields.io/badge/Linux-supported-3dffb0?style=for-the-badge&logo=linux&logoColor=white&labelColor=0d1a1f">
  <img alt="Intel Arc" src="https://img.shields.io/badge/Intel%20Arc-tested-5ad8ff?style=for-the-badge&logo=intel&logoColor=white&labelColor=0d1a1f">
  <img alt="AI runs locally" src="https://img.shields.io/badge/AI-runs%20locally-5ad8ff?style=for-the-badge&labelColor=0d1a1f">
  <img alt="License MIT" src="https://img.shields.io/badge/license-MIT-ff5a3c?style=for-the-badge&labelColor=0d1a1f">
</p>

<p align="center"><i>"Twinkle, twinkle, little star..."</i> The Sprawl, rebuilt one texel at a time.</p>

<p align="center">🇧🇷 <b><a href="README.pt-BR.md">Leia em português →</a></b></p>

---

## What is this?

Dead Space 2 came out in 2011, and most of its textures are 128 to 512 pixels wide, squeezed with DXT compression. Up close, walls turn to mush and metal looks like blocky paint.

**This tool remasters them with AI.** It takes the original textures straight from the game, runs each one through an upscaler trained on old game textures, and packs the result so the game loads it in place of the original. No game files are modified, and one key (**F10**) switches between original and remaster while you play.

- 🧠 **Open source AI, running locally.** Default model: [4x-PBRify_UpscalerV4](https://openmodeldb.info/models/4x-PBRify-UpscalerV4), trained on 2000s game textures: it removes DXT compression and brings back real surface detail. Heavier than an ESRGAN, but worth every minute.
- 🎨 **Faithful to the original.** A color lock keeps the original colors and lighting; the AI only adds fine detail. No redesigns, no hallucinated logos.
- 🧩 **Your mods come first.** Textures already covered by your `.tpf` packs (4K suits, Return to Titan...) are skipped and stay exactly as their authors made them.
- 🛌 **Set and forget.** One command does everything, survives GPU hangs, resumes where it stopped and sends a desktop notification when it is done.

---

## Before and after

Every pair below is a zoomed crop of the same region: the game's original texture on the left, the AI result on the right. Nothing was retouched by hand. Press **F10** in game to flip between the two.

<p align="center"><img src="assets/comparacoes/necromorph-flesh.jpg" alt="Necromorph flesh and bone, 256×256 → 1024×1024. The gore is where the model shines: every tendon and rib gets real structure." width="100%"><br><sub>Necromorph flesh and bone, 256×256 → 1024×1024. The gore is where the model shines: every tendon and rib gets real structure.</sub></p>
<p align="center"><img src="assets/comparacoes/paper-handwriting.jpg" alt="Handwritten document, 256×256 → 1024×1024. The typed lines and the ink strokes become legible." width="100%"><br><sub>Handwritten document, 256×256 → 1024×1024. The typed lines and the ink strokes become legible.</sub></p>
<p align="center"><img src="assets/comparacoes/terminal-text.jpg" alt="Terminal screen, 256×256 → 1024×1024. Pixel text turns into clean glyphs without changing the font." width="100%"><br><sub>Terminal screen, 256×256 → 1024×1024. Pixel text turns into clean glyphs without changing the font.</sub></p>
<p align="center"><img src="assets/comparacoes/metal-wall.jpg" alt="Metal wall with grating, 256×256 → 1024×1024. Rivets, grime and vents stop being a blur." width="100%"><br><sub>Metal wall with grating, 256×256 → 1024×1024. Rivets, grime and vents stop being a blur.</sub></p>
<p align="center"><img src="assets/comparacoes/normal-unitology-relief.jpg" alt="Normal map of a Unitology relief, 256×256 → 1024×1024, rendered with a light to show the bumps. Normal maps go through their own model (4x-Normal-RG0), never through a photo upscaler." width="100%"><br><sub>Normal map of a Unitology relief, 256×256 → 1024×1024, rendered with a light to show the bumps. Normal maps go through their own model (4x-Normal-RG0), never through a photo upscaler.</sub></p>
<p align="center"><img src="assets/comparacoes/normal-machine-panel.jpg" alt="Normal map of a machine panel, 512×256 → 2048×1024, lit. Bevels and screws come back as real relief." width="100%"><br><sub>Normal map of a machine panel, 512×256 → 2048×1024, lit. Bevels and screws come back as real relief.</sub></p>

<details>
<summary><b>More comparisons</b> (9 more: posters, labels, stained glass, pipes, fabric and four more normal maps)</summary>
<br>

<p align="center"><img src="assets/comparacoes/unitology-poster.jpg" alt="Unitology posters, 256×256 → 1024×1024." width="100%"><br><sub>Unitology posters, 256×256 → 1024×1024.</sub></p>
<p align="center"><img src="assets/comparacoes/isc-label.jpg" alt="Industrial cleaner label, 256×256 → 1024×1024." width="100%"><br><sub>Industrial cleaner label, 256×256 → 1024×1024.</sub></p>
<p align="center"><img src="assets/comparacoes/stained-glass.jpg" alt="Stained glass, 256×512 → 1024×2048." width="100%"><br><sub>Stained glass, 256×512 → 1024×2048.</sub></p>
<p align="center"><img src="assets/comparacoes/pipes.jpg" alt="Pipes and conduits, 256×256 → 1024×1024." width="100%"><br><sub>Pipes and conduits, 256×256 → 1024×1024.</sub></p>
<p align="center"><img src="assets/comparacoes/red-fabric.jpg" alt="Red fabric, 256×256 → 1024×1024." width="100%"><br><sub>Red fabric, 256×256 → 1024×1024.</sub></p>
<p align="center"><img src="assets/comparacoes/normal-spiral-ornament.jpg" alt="Normal map, spiral ornament, lit." width="100%"><br><sub>Normal map, spiral ornament, lit.</sub></p>
<p align="center"><img src="assets/comparacoes/normal-figures-relief.jpg" alt="Normal map, figures in relief, 512×256 → 2048×1024, lit." width="100%"><br><sub>Normal map, figures in relief, 512×256 → 2048×1024, lit.</sub></p>
<p align="center"><img src="assets/comparacoes/normal-bulky-panels.jpg" alt="Normal map, bulky panels, lit." width="100%"><br><sub>Normal map, bulky panels, lit.</sub></p>
<p align="center"><img src="assets/comparacoes/normal-circuit.jpg" alt="Normal map, circuit traces, lit." width="100%"><br><sub>Normal map, circuit traces, lit.</sub></p>

</details>

**How many textures is that?** A full playthrough of the campaign hands over about **15,000 unique textures**. The default run remasters **14,400** of them (the rest are 1 to 7 pixel strips, single-color fills and textures already covered by your `.tpf` packs). By kind, in the run that produced the images above:

| Kind | Textures | What was done |
|---|---:|---|
| Color (diffuse) | 4,764 | 4x with PBRify_UpscalerV4, or UltraSharp when the invention check fails |
| Masks, specular, light maps | 5,982 | 2x, careful resampling |
| Normal maps | 1,515 | 4x with 4x-Normal-RG0 |
| Smooth gradients | 1,198 | 4x resampling, no AI (there is nothing to recover) |
| Lights, glows, smoke | 822 | 4x with UltraSharp |

Up to 4096 px a side, full mipmap chains, **18 GB** on disk, about 9 hours on an Intel Arc B580.

---

## Don't want to run the AI? Download the pack

The pack from the run above is on the [**Releases**](https://github.com/sidnei-almeida/dead-space-2-ai-remaster/releases/latest) page: 14,400 textures, 18 GB, split into parts of under 2 GB because of GitHub's file size limit. You need about **36 GB free** (the pack plus the cache DS2TexInject builds from it), no GPU required.

> **Return to Titan is required.** This pack was built as a complement to the *Return to Titan* texture mod: the 250 textures it already covers (and the 4K suit packs) were left out on purpose, so without it those stay original. Install Return to Titan's `.tpf` files in `texmod` first.

1. Install [DS2TexInject](https://github.com/sidnei-almeida/dead-space-2-texmod-linux) and run the game once.
2. Download **every** `zz_ai_remaster.zip.0NN` part and `zz_ai_remaster.sha256` into the game's `texmod` folder.
3. Join the parts, check them and build the cache, with the game closed:

```sh
cd "$HOME/.local/share/Steam/steamapps/common/Dead Space 2/texmod"
cat zz_ai_remaster.zip.0* > zz_ai_remaster.zip && rm zz_ai_remaster.zip.0*
sha256sum -c zz_ai_remaster.sha256          # optional, takes a minute
python3 ../DS2TexInject/ds2tex.py .
```

4. Play. **F10** flips between original and remaster. Your `.tpf` packs always keep priority over this one.

The pack is shared under **CC BY-NC-SA 4.0** (one of the models requires it, see [License](#license)): credit, same license, never sold.

---

## Quick start

| Step | What to do |
|:---:|---|
| 1 | Install **[DS2TexInject](https://github.com/sidnei-almeida/dead-space-2-texmod-linux)**. It loads the textures into the game. |
| 2 | Clone this repo and run **`./remaster.sh setup`**. |
| 3 | Run **`./remaster.sh dump-on`** and **play** for a while. The game hands over its textures. |
| 4 | Close the game, run **`./remaster.sh`** and pick **Remasterizar**. Go get a coffee. |
| 5 | **Play.** Press **F10** to compare before and after. |

Each step is explained below. Or skip the AI entirely and [download the ready-made pack](#dont-want-to-run-the-ai-download-the-pack).

---

## The menu

Not a fan of typing commands? Just run:

```sh
./remaster.sh
```

and a menu opens. Pick with the arrow keys and press Enter:

```
  DEAD SPACE 2  AI TEXTURE REMASTER
  ────────────────────────────────────────────────────

  Jogo                 ○ fechado
  Remaster no jogo     ● ativo (1.3G)
  Coleta               ● LIGADA (o jogo salva cada textura nova)
  Ultima rodada        as 22:17, levou 2 min

  Texturas coletadas   5292
  Ja remasterizadas    3458
  Puladas              831  (pequenas demais ou de cor unica)
  Dos seus mods        86  (seus .tpf ja cuidam delas)
  Esperando            917 novas, ainda nao processadas
  Modelo               PBRify_UpscalerV4 + UltraSharp nas luzes + Normal-RG0 no relevo, 4x, ate 4096px

  O que voce quer fazer? (setas + Enter, Esc sai)
  ➜ ▶  Jogar Dead Space 2
    ✦  Remasterizar as texturas novas (917 esperando)
    ◉  Desligar a coleta de texturas (agora esta LIGADA)
    ◐  Desativar o remaster no jogo (agora esta ATIVO)
    ⇄  Comparar original x IA (abre no navegador)
    ≡  Ver o log da ultima rodada
    ⚙  Instalar ou consertar o ambiente
    ?  Ajuda
    ✕  Sair
```

While remastering, a live dashboard shows each step, a progress bar, time left and how many textures of each kind are done:

```
  ✔  Ler as texturas coletadas
  ⠹  Remasterizar com IA (PBRify_UpscalerV4 + UltraSharp nas luzes + Normal-RG0 no relevo)
  ·  Gerar DDS com mipmaps
  ·  Montar o pacote
  ·  Instalar no jogo

  ██████████████░░░░░░░░░░░░░░░░░░░░   43.2%   396 / 917 texturas
  decorrido 1m12s   faltam ~1m35s   erros 0
  cor 201   mascaras 160   normal maps 35

  Ctrl+C cancela (o que ja foi feito fica salvo)
```

The panel shows the current state in color, the on/off options say what they will do, and **▶ Jogar** launches the game from Steam. Everything below can be done from the menu. `./remaster.sh --help` explains every command.

---

## Step 1: Install DS2TexInject

This project creates the textures. **[DS2TexInject](https://github.com/sidnei-almeida/dead-space-2-texmod-linux)** is the plugin that puts them in the game, and it also collects the original textures for the AI.

<a href="https://github.com/sidnei-almeida/dead-space-2-texmod-linux"><img alt="Get DS2TexInject" src="https://img.shields.io/badge/Get-DS2TexInject-3dffb0?style=for-the-badge&labelColor=0d1a1f&logo=github&logoColor=white"></a>

Follow its guide until the game runs with it. Your `.tpf` packs are optional, but they are respected if you have them.

## Step 2: Install this tool

```sh
git clone https://github.com/sidnei-almeida/dead-space-2-ai-remaster
cd dead-space-2-ai-remaster
./remaster.sh setup
```

`setup` creates a Python environment in `.venv`, installs PyTorch and [spandrel](https://github.com/chaiNNer-org/spandrel), downloads any missing AI models, finds the game and tells you which GPU it found:

```
Dead Space 2 encontrado em: /home/you/.local/share/Steam/steamapps/common/Dead Space 2
DS2TexInject: instalado em /home/you/.local/share/Steam/steamapps/common/Dead Space 2
GPU: Intel(R) Arc(TM) B580 Graphics
```

**The game folder is found automatically.** It looks in every Steam library (native, Flatpak and Snap), Heroic (GOG, Epic and manually added games), Lutris, Bottles and Wine prefixes. If nothing turns up, it scans the whole disk. If it finds more than one copy, it asks which one you play. The choice is saved in `.game-path`. To change it later:

```sh
./remaster.sh game                              # search all disks again
./remaster.sh game "/where/is/Dead Space 2"     # or give the folder
```

**Models are downloaded automatically too.** If a `.pth` goes missing from `models/`, the next run downloads it again before starting. An interrupted download resumes where it stopped.

> **Intel Arc:** PyTorch also needs Intel's compute driver. On Arch: `sudo pacman -S intel-compute-runtime level-zero-loader`
>
> **NVIDIA:** edit the PyTorch line in `cmd_setup` inside `remaster.sh` to use the regular `pip install torch torchvision`.
>
> **No supported GPU:** it falls back to the CPU. It works, just much slower.

## Step 3: Collect the textures

The AI works on the textures exactly as the game uses them, so the game has to hand them over:

```sh
./remaster.sh dump-on
```

Now **play normally.** Every texture that shows up on screen is saved once to `texmod/_dump/`. The game may hiccup a little while it saves.

You don't need to finish the game. Most textures (UI, Isaac, weapons, Necromorphs, common walls) load in the first minutes, and after that only new areas add more. In testing, **25 minutes of play gave 4,375 textures.** Chapter saves are a quick way to visit every area.

When you're done:

```sh
./remaster.sh dump-off
```

## Step 4: Remaster

Close the game, open the menu (`./remaster.sh`) and pick **Remasterizar as texturas novas**, or run it directly:

```sh
./remaster.sh run
```

That's it. A progress bar keeps updating on screen. It reads the dump, runs the AI, builds the DDS files, packs them and installs them in the game. You can leave it alone:

- ⏱️ **The first run takes a while** (about 15 to 30 minutes on an Intel Arc B580). Later runs only process textures that are new in the dump.
- 🔁 **Stop anytime** with Ctrl+C. Run it again and it continues where it stopped.
- 🛡️ **If the GPU hangs**, it notices the missing progress, restarts and carries on.
- 🎮 **If you open the game mid-run**, it stops instead of fighting the game for the GPU.
- 🔔 **A desktop notification** tells you when it's done.

Check on it from another terminal:

```
$ ./remaster.sh status
upscale [#########...........] 46.2%  1422/3079
decorrido 31m05s | faltam ~36m12s | erros 0 | modelo 4x-PBRify_UpscalerV4.pth
por classe: diffuse 702, mask 611, normal_ag 109
situacao: RODANDO
```

## Step 5: Play

Launch Dead Space 2 from Steam as usual.

- Press **F10** to toggle between original and remastered textures.
- Walk up to walls, floors and doors with your flashlight on. That's where the difference shows.

---

## All commands

| Command | What it does |
|---|---|
| `./remaster.sh` | Opens the menu. Without a terminal (background, scheduled), it does the same as `run`. |
| `./remaster.sh run` | Processes new textures and installs the result in the game. |
| `./remaster.sh status` | Progress, time left and errors of a running job. |
| `./remaster.sh preview` | Builds a page with original and AI side by side, to spot and reject bad results. |
| `./remaster.sh dump-on` / `dump-off` | Starts or stops collecting textures while you play. |
| `./remaster.sh off` | Turns the remaster off (only your `.tpf` packs stay). |
| `./remaster.sh on` | Turns it back on. |
| `./remaster.sh setup` | Installs or repairs the environment, downloads missing models and checks DS2TexInject. |
| `./remaster.sh game [folder]` | Searches all disks for the game again, or uses the given folder. |

## Settings

They live at the top of `remaster.sh`:

| Setting | Default | What it does |
|---|---|---|
| `MODEL` | `4x-PBRify_UpscalerV4` | Any model [spandrel](https://github.com/chaiNNer-org/spandrel) can load: ESRGAN, SPAN, DAT, HAT... Browse [OpenModelDB](https://openmodeldb.info). |
| `SCALE` | `4` | Upscale factor for color textures and normal maps. |
| `MASK_SCALE` | `2` | Factor for masks, specular and light maps. They gain little and use a lot of memory. |
| `MAX_SIZE` | `4096` | Largest side of any texture. |
| `GLOW_MODEL` | `4x-UltraSharp` | Model for lights, glows, light beams and smoke (the `glow` class), and for any texture where the main model invents detail that wasn't there. `GLOW_MODEL=` turns both off. |
| `NORMAL_MODEL` | `4x-Normal-RG0` | Model for normal maps, trained only on normal maps. `NORMAL_MODEL=` falls back to Lanczos resampling. |
| `SOFT_MODEL` | empty | Optional second, more conservative model (e.g. `models/4x-UltraSharp.pth`) for low-detail textures. |
| `GAME` | found automatically | Game folder. Usually not needed: it is discovered and saved in `.game-path`. |
| `WORK` | `work/pbrify4x` | Working folder (`work/pbrify<SCALE>x`). Change it when you change the model, so results don't mix. |

---

## Troubleshooting

| Problem | Fix |
|---|---|
| **`GPU: NAO ENCONTRADA`** | PyTorch can't see the GPU. On Intel Arc, install `intel-compute-runtime` and `level-zero-loader`. |
| **The game crashes when entering new areas, or after a long session** | Dead Space 2 is a 32-bit program and can run out of memory. Lower `MAX_SIZE` to `1024`, run `./remaster.sh run` again, or set `Pool=default` in `DS2TexInject.ini`. |
| **Some texture looks wrong** | Press **F10** to confirm. Run `./remaster.sh preview`, open the page it prints, find the texture, and add its hash to `work/pbrify4x/rejected.txt`. The next run leaves it out. |
| **The game stutters when entering new areas** | Make sure DS2TexInject is up to date and Pillow is installed (`sudo pacman -S python-pillow`), then run `./remaster.sh on`. Textures will be loaded game-ready. |
| **Anything else** | Check `work/pbrify4x/remaster.log` and open an issue with it. |

<p align="center"><a href="https://github.com/sidnei-almeida/dead-space-2-ai-remaster/issues"><img alt="Need help? Open an issue" src="https://img.shields.io/badge/Need%20help%3F-Open%20an%20issue-ff5a3c?style=for-the-badge&labelColor=0d1a1f&logo=github&logoColor=white"></a></p>

---

## How it works

You don't need this part to use the tool.

```
the game (DumpTextures=1) ──► texmod/_dump/0xHASH.dds        original textures, named by their TexMod hash
        │
        ▼  scan        sort each texture: color, normal map, mask, too small, single color
        ▼  upscale     AI for color textures and normal maps, careful resampling for masks
        ▼  encode      back to the original format (DXT1, DXT5, ARGB) with a full mipmap chain
        ▼  pack        texmod/zz_ai_remaster.zip  (+ texmod.def)
        ▼  ds2tex.py   texmod/_cache, where DS2TexInject finds it while you play
```

**Every kind of texture gets its own treatment:**

| Kind | What happens |
|---|---|
| Color (diffuse) | AI upscale with wrap padding so tiling textures don't get seams, then a color lock: low frequencies come from the original, so colors and lighting stay true. |
| Normal map (DXT5nm, X in alpha and Y in green) | Never goes through a photo model. Upscaled with a model trained only on normal maps (`NORMAL_MODEL`, 4x-Normal-RG0), renormalized, and the unused red and blue channels are kept as the game expects. |
| Masks, specular, light maps | Clean resampling. AI would create seams between light map patches. |
| Alpha | Upscaled separately. In DXT1 it goes back to 1-bit cut-outs (grates, foliage). |
| Smooth (pure gradients) | Clean resampling only. There is no detail to recover, and AI models invent texture there: rings and wrinkles that show up in the flashlight beam. |
| Lights, glows, light beams, smoke and dust (`glow`) | Soft shapes with little fine detail. PBRify hardens their edges and fills them with speckle, so they go to `GLOW_MODEL` (UltraSharp), which respects the gradient. |
| Any texture, after the main model | An invention check: the result is shrunk back to the original size and its fine detail compared with the original's. Around 1.0 it is faithful; above `--invent-max` (1.15) the model made up texture, and that one is redone with `GLOW_MODEL`. `recheck` applies the same test to results from earlier runs. |
| Any texture, flat regions | A local guard: where the original is a pure gradient (the flat background of a sign, a glow around a light) the AI is faded out and clean resampling is used. Crates, smooth walls and plastic still get the full AI. `--detail-lo`/`--detail-hi` tune it, `--no-detail-guard` turns it off. |
| Tiny or single-color | Skipped. Nothing to gain. |

**Why the original textures come from the running game:** DS2TexInject finds textures by the CRC32 hash of the bytes the game sends to Direct3D. Dumping at runtime gives every file the right name for free. Pulling them out of EA's `.DAT` archives would mean reverse engineering the format and still reproducing the exact hash.

**Why mipmaps matter:** without them, the plugin would build mipmaps the first time each texture appears, in the middle of the game. Dozens of 2048px textures at once meant drops from 100 to 40 FPS when entering a new area. Shipping full mipmap chains removes that work.

<details>
<summary><b>Using <code>ds2remaster.py</code> directly</b></summary>

`remaster.sh` drives `ds2remaster.py`, which can also run step by step:

```sh
.venv/bin/python ds2remaster.py all --model models/4x-PBRify_UpscalerV4.pth --limit 20
```

| Option | Default | What it does |
|---|---|---|
| `--model` | none | Upscale model. Without it, plain Lanczos (useful to test the pipeline). |
| `--cleanup` | none | Optional 1x model run first to clean compression artifacts. |
| `--scale` / `--mask-scale` | 2 | Upscale factors. |
| `--max-size` | 2048 | Largest side of any texture. |
| `--tile` | 544 | Size of each GPU tile. A 1024px texture becomes 4 tiles. On Intel Arc, 1088px tiles caused GPU faults. |
| `--only` | all | Only some kinds: `diffuse`, `normal`, `normal_ag`, `mask`. |
| `--recent N` | all | Only textures dumped in the last N minutes of play. Great for testing one area. |
| `--limit N` | all | At most N textures. |
| `--pack-name` | `zz_ai_remaster.zip` | Pack file name (must end in `.zip` and contain `_ai_`). |
| `--ai-alpha` | off | Also run the AI on alpha channels. |
| `--no-ai-masks` | off | Masks and specular maps with plain resampling instead of AI. |
| `--glow-model` | none | Model for the `glow` class (lights, glows, smoke) and for results that fail the invention check. |
| `--invent-max` | `1.15` | Above this much invented fine detail, the main model's result is replaced by `--glow-model`. `--no-invent-check` turns the check off. |
| `--soft-model` | none | Second, conservative model for textures with little detail overall (`--soft-below`, default 0.016). |
| `--no-color-lock` | off | Let the AI change colors. |
| `--force` | off | Redo what already exists. |

Steps: `scan`, `recheck`, `upscale`, `encode`, `pack`, `preview`, `all`, `status`. `preview` writes `work/preview.html` with original and AI side by side, plus the model used and the invention score of each texture.
</details>

---

## Credits

- **[4x-PBRify_UpscalerV4](https://openmodeldb.info/models/4x-PBRify-UpscalerV4)** by Kim2091: the default upscaler (DAT2, runs in bf16).
- **[4x-UltraSharp](https://openmodeldb.info/models/4x-UltraSharp)** by Kim2091: handles lights, glows and smoke (`GLOW_MODEL`), where PBRify invents texture.
- **[4x-Normal-RG0](https://openmodeldb.info/models/4x-Normal-RG0)** by RunDevelopment: upscales the normal maps (`NORMAL_MODEL`), the single biggest gain in depth.
- **[spandrel](https://github.com/chaiNNer-org/spandrel)** by the chaiNNer team: loads almost any upscaling architecture.
- **[OpenModelDB](https://openmodeldb.info)**: the catalog of community models.
- **[DS2TexInject](https://github.com/sidnei-almeida/dead-space-2-texmod-linux)**: dumps the original textures and loads the remastered ones.

**Tested on:** Arch Linux, Intel Arc B580 (PyTorch XPU), GE-Proton 11, DXVK, ReShade and MarkerPatch.

## License

[MIT](LICENSE). The AI models are not part of this project and keep their own licenses: 4x-PBRify_UpscalerV4 and 4x-Normal-RG0 are CC0, so packs made with them alone can be shared freely. 4x-UltraSharp is CC BY-NC-SA 4.0, and the default setup uses it for lights and glows: packs made with the defaults can be shared with credit, under the same license and never sold. Run with `GLOW_MODEL=` for a pack that is PBRify only. Check the license of any other model before sharing packs made with it. Dead Space 2 and its textures belong to Electronic Arts.
