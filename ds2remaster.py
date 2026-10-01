#!/usr/bin/env python3
"""
ds2remaster.py - remaster de texturas do Dead Space 2 com IA.

Le as texturas originais salvas pelo DS2TexInject (DumpTextures=1, texmod/_dump/0xHASH.dds),
classifica, refaz com um modelo de upscale (ESRGAN/SPAN/etc. via spandrel) e gera um pacote
texmod/zz_ai_remaster.zip que o ds2tex.py do DS2TexInject ja sabe ler.

Etapas (cada uma pode rodar sozinha; o que ja foi feito e pulado):
  scan      le o dump, classifica e grava work/manifest.json
  upscale   gera work/up/0xHASH.png
  encode    converte para DDS (DXT1/DXT5/RGBA) em work/dds/
  pack      cria texmod/zz_ai_remaster.zip (+ texmod.def)
  preview   cria work/preview.html (original x IA lado a lado)
  all       scan + upscale + encode + pack + preview

Uso:  python3 ds2remaster.py all --game "~/.local/share/Steam/steamapps/common/Dead Space 2" \\
          --model models/4x-UltraSharp.pth --limit 20
"""
import argparse, html, io, json, os, struct, sys, time, zipfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_GAME = os.path.expanduser('~/.local/share/Steam/steamapps/common/Dead Space 2')
PACK_NAME = 'zz_ai_remaster.zip'  # "zz_": fica por ultimo, pacotes feitos a mao tem prioridade
CLASSES = ('diffuse', 'normal', 'normal_ag', 'mask')


# ---------------------------------------------------------------- utilidades

def log(*a):
    print(*a, flush=True)


def dds_info(path):
    """(largura, altura, formato) a partir do cabecalho DDS."""
    with open(path, 'rb') as f:
        data = f.read(128)
    if len(data) < 128 or data[:4] != b'DDS ':
        return None
    h = struct.unpack('<31I', data[4:128])
    hgt, wid, pf_flags, fourcc, bits = h[2], h[3], h[19], h[20], h[21]
    if pf_flags & 4:
        fmt = struct.pack('<I', fourcc).decode('latin1')
    else:
        fmt = 'RGBA' if pf_flags & 1 else 'RGB'
    return wid, hgt, fmt


def load_rgba(path):
    return np.asarray(Image.open(path).convert('RGBA'), dtype=np.float32) / 255.0


def save_png(arr, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img = Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8))
    tmp = path + '.tmp.png'
    img.save(tmp, optimize=False)
    os.replace(tmp, path)


def is_own_pack(name):
    return name.endswith('.zip') and '_ai_' in name


def covered_hashes(game):
    """Hashes ja cobertos pelos pacotes .tpf (index.txt gerado pelo ds2tex.py)."""
    idx = os.path.join(game, 'texmod', '_cache', 'index.txt')
    out = set()
    if os.path.exists(idx):
        for line in open(idx, encoding='utf-8', errors='ignore'):
            parts = line.strip().split('|')
            # ignora os pacotes gerados por esta ferramenta (zz_ai_remaster.zip, zy_ai_teste.zip...)
            if len(parts) >= 2 and parts[0].startswith('0x') and not is_own_pack(parts[1]):
                out.add(parts[0].upper().replace('0X', '0x'))
    return out


# ---------------------------------------------------------------- classificacao

def classify(rgba):
    """Heuristica simples. Retorna (classe, tem_alpha)."""
    small = rgba[::max(1, rgba.shape[0] // 128), ::max(1, rgba.shape[1] // 128)]
    r, g, b, a = (small[..., i] for i in range(4))
    has_alpha = float(a.min()) < 0.98
    if small.reshape(-1, 4).std(0).max() < 0.01:
        return 'flat', False  # cor unica: nao ha o que melhorar

    # DXT5nm: X no alpha, Y no verde, R/B quase constantes
    if (r.std() < 0.03 and b.std() < 0.03 and abs(a.mean() - 0.5) < 0.12
            and abs(g.mean() - 0.5) < 0.12 and a.std() > 0.02):
        return 'normal_ag', False

    # normal map RGB: azulado, R/G centrados e vetores ~unitarios
    x, y, z = r * 2 - 1, g * 2 - 1, b * 2 - 1
    length = np.sqrt(x * x + y * y + z * z)
    if (b.mean() > 0.7 and abs(r.mean() - 0.5) < 0.1 and abs(g.mean() - 0.5) < 0.1
            and abs(length.mean() - 1) < 0.15 and (z > 0).mean() > 0.97):
        return 'normal', has_alpha

    # mascara/specular: tons de cinza
    if np.abs(r - g).mean() < 0.01 and np.abs(g - b).mean() < 0.01:
        return 'mask', has_alpha

    return 'diffuse', has_alpha


def cmd_scan(a):
    dump = a.dump or os.path.join(a.game, 'texmod', '_dump')
    if not os.path.isdir(dump):
        sys.exit('pasta de dump nao encontrada: %s\n'
                 'Ative DumpTextures=1 no DS2TexInject.ini e jogue um pouco.' % dump)
    covered = covered_hashes(a.game)
    man = load_manifest(a)
    files = sorted(f for f in os.listdir(dump) if f.lower().endswith('.dds') and f.startswith('0x'))
    n_new = 0
    for i, f in enumerate(files):
        h = f[:10].upper().replace('0X', '0x')
        src = os.path.join(dump, f)
        size = os.path.getsize(src)
        if h in man and man[h].get('src') == src and man[h].get('size') == size and not a.force:
            man[h]['covered'] = h in covered
            continue
        info = dds_info(src)
        if not info:
            continue
        w, hh, fmt = info
        e = {'src': src, 'size': size, 'w': w, 'h': hh, 'fmt': fmt, 'covered': h in covered}
        if min(w, hh) < a.min_size:
            e['class'] = 'skip'
            e['reason'] = 'pequena'
        else:
            try:
                e['class'], e['alpha'] = classify(load_rgba(src))
                if e['class'] == 'flat':
                    e['class'], e['reason'] = 'skip', 'cor unica'
            except Exception as ex:
                e['class'], e['reason'] = 'skip', 'erro lendo: %s' % ex
        man[h] = e
        n_new += 1
        if n_new % 200 == 0:
            log('  %d/%d' % (i + 1, len(files)))
    save_manifest(a, man)
    counts = {}
    for e in man.values():
        k = 'coberta por .tpf' if e['covered'] else e['class']
        counts[k] = counts.get(k, 0) + 1
    log('%d texturas no manifest (%d novas)' % (len(man), n_new))
    for k in sorted(counts):
        log('  %-18s %d' % (k, counts[k]))


# ---------------------------------------------------------------- upscale

class Upscaler:
    """Backend 'model' (spandrel + PyTorch: Intel XPU, CUDA ou CPU) ou 'lanczos' (sem IA)."""

    def __init__(self, model_path, tile, cleanup_path=None, color_lock=True):
        self.models, self.tile, self.color_lock = [], tile, color_lock
        if not model_path:
            self.device = None
            log('sem --model: usando Lanczos (sem IA), so para testar o pipeline')
            return
        try:
            import torch
            from spandrel import ModelLoader
        except ImportError:
            sys.exit('precisa de torch + spandrel (veja o README, secao Instalacao)')
        self.torch = torch
        if hasattr(torch, 'xpu') and torch.xpu.is_available():
            self.device = torch.device('xpu')
        elif torch.cuda.is_available():
            self.device = torch.device('cuda')
        else:
            self.device = torch.device('cpu')
        for p in (cleanup_path, model_path):
            if p:
                m = ModelLoader().load_from_file(p).to(self.device).eval()
                if self.device.type != 'cpu' and m.supports_half:
                    m.model.half()
                    m.half = True
                else:
                    m.half = False
                self.models.append(m)
                log('modelo: %s (%dx, %s) em %s' % (os.path.basename(p), m.scale, m.architecture.name, self.device))

    @property
    def scale(self):
        s = 1
        for m in self.models:
            s *= m.scale
        return s if self.models else 4

    def rgb(self, img, out_w, out_h):
        """img: float32 HxWx3 em [0,1]. Retorna HxWx3 em out_w x out_h."""
        if not self.models:
            return resize(img, out_w, out_h)
        pad = 16
        x = np.pad(img, ((pad, pad), (pad, pad), (0, 0)), mode='wrap')  # texturas costumam ser tileaveis
        for m in self.models:
            x = self._run(m, x)
        s = self.scale
        x = x[pad * s:x.shape[0] - pad * s, pad * s:x.shape[1] - pad * s]
        x = resize(x, out_w, out_h)
        if self.color_lock:
            x = color_lock(resize(img, out_w, out_h), x)
        return x

    def _run(self, m, img):
        torch = self.torch
        h, w, _ = img.shape
        s, t, ov = m.scale, self.tile, 16
        out = np.zeros((h * s, w * s, 3), np.float32)
        weight = np.zeros((h * s, w * s, 1), np.float32)
        dtype = torch.float16 if m.half else torch.float32
        with torch.inference_mode():
            for y0 in range(0, h, t - 2 * ov):
                for x0 in range(0, w, t - 2 * ov):
                    y1, x1 = min(y0 + t, h), min(x0 + t, w)
                    ys, xs = max(0, y1 - t), max(0, x1 - t)
                    tile = torch.from_numpy(np.ascontiguousarray(img[ys:y1, xs:x1].transpose(2, 0, 1)))
                    tile = tile.unsqueeze(0).to(self.device, dtype)
                    r = m(tile).float().clamp(0, 1)[0].permute(1, 2, 0).cpu().numpy()
                    out[ys * s:y1 * s, xs * s:x1 * s] += r
                    weight[ys * s:y1 * s, xs * s:x1 * s] += 1
                    if x1 == w:
                        break
                if y1 == h:
                    break
        return out / np.maximum(weight, 1)


def lowpass(img, factor):
    """Mantem so a baixa frequencia: reduz e amplia de volta."""
    h, w = img.shape[:2]
    small = resize(img, max(1, round(w / factor)), max(1, round(h / factor)), Image.BOX)
    return resize(small, w, h, Image.BICUBIC)


def color_lock(ref, ai):
    """Mantem as cores/iluminacao de baixa frequencia do original; a IA so entra com o detalhe."""
    f = max(4, max(ai.shape[:2]) // 128)
    return np.clip(ai - lowpass(ai, f) + lowpass(ref, f), 0, 1)


def resize(img, w, h, method=Image.LANCZOS):
    if img.shape[1] == w and img.shape[0] == h:
        return img
    chans = [np.asarray(Image.fromarray(np.ascontiguousarray(img[..., c], np.float32), "F").resize((w, h), method))
             for c in range(img.shape[2])]
    return np.clip(np.stack(chans, -1), 0, 1)


def target_size(e, a):
    s = a.mask_scale if e['class'] == 'mask' else a.scale
    w, h = e['w'] * s, e['h'] * s
    while max(w, h) > a.max_size and min(w, h) > 4:
        w, h = w // 2, h // 2
    return w, h


def renormalize(xy):
    x, y = xy[..., 0] * 2 - 1, xy[..., 1] * 2 - 1
    z = np.sqrt(np.clip(1 - x * x - y * y, 0, 1))
    n = np.sqrt(x * x + y * y + z * z) + 1e-6
    return np.stack([x / n, y / n, z / n], -1) * 0.5 + 0.5


def process(up, e, src, a):
    rgba = load_rgba(src)
    ow, oh = target_size(e, a)
    cls = e['class']
    if cls == 'normal':
        # normal map nunca passa pelo modelo de foto: Lanczos + renormalizacao
        rgb = renormalize(resize(rgba[..., :3], ow, oh))
    elif cls == 'normal_ag':
        # X no alpha, Y no verde. R e B nao sao normal (no DS2 valem 0; o shader pode usar):
        # ficam iguais ao original, so redimensionados.
        xy = resize(np.stack([rgba[..., 3], rgba[..., 1]], -1), ow, oh)
        n = renormalize(xy)
        rb = resize(np.stack([rgba[..., 0], rgba[..., 2]], -1), ow, oh)
        return np.stack([rb[..., 0], n[..., 1], rb[..., 1], n[..., 0]], -1)
    elif cls == 'mask' and not a.ai_masks:
        rgb = resize(rgba[..., :3], ow, oh)
    else:
        rgb = up.rgb(rgba[..., :3], ow, oh)
    if e.get('alpha'):
        al = rgba[..., 3:4]
        alpha = up.rgb(np.repeat(al, 3, -1), ow, oh).mean(-1, keepdims=True) if a.ai_alpha else resize(al, ow, oh)
        if e['fmt'] == 'DXT1':
            alpha = (alpha > 0.5).astype(np.float32)
    else:
        alpha = np.ones((oh, ow, 1), np.float32)
    return np.concatenate([rgb, alpha], -1)


def todo(man, a):
    cutoff = None
    if a.recent:
        # o dump grava na ordem em que o jogo carrega: os mais recentes sao da area do ultimo save
        times = {h: os.path.getmtime(e['src']) for h, e in man.items() if os.path.exists(e['src'])}
        cutoff = max(times.values()) - a.recent * 60
    for h, e in sorted(man.items()):
        if e['class'] == 'skip' or e['covered'] or h in a.rejected:
            continue
        if a.only and e['class'] not in a.only:
            continue
        if cutoff is not None and times.get(h, 0) < cutoff:
            continue
        yield h, e


def fmt_time(sec):
    sec = int(sec)
    if sec >= 3600:
        return '%dh%02dm' % (sec // 3600, sec % 3600 // 60)
    return '%dm%02ds' % (sec // 60, sec % 60)


def write_status(a, **st):
    st['atualizado'] = time.strftime('%H:%M:%S')
    p = os.path.join(a.work, 'status.json')
    json.dump(st, open(p + '.tmp', 'w'), indent=1)
    os.replace(p + '.tmp', p)


def cmd_upscale(a):
    man = load_manifest(a)
    jobs = list(todo(man, a))
    if a.limit:
        jobs = jobs[:a.limit]
    outdir = os.path.join(a.work, 'up')
    pending = [(h, e) for h, e in jobs if a.force or not os.path.exists(os.path.join(outdir, h + '.png'))]
    log('%d texturas na fila, %d ja feitas, %d para processar' % (len(jobs), len(jobs) - len(pending), len(pending)))
    if not pending:
        return
    up = Upscaler(a.model, a.tile, a.cleanup, not a.no_color_lock)
    t0, done, errors, total = time.time(), 0, 0, len(pending)
    by_class = {}
    for i, (h, e) in enumerate(pending, 1):
        t1 = time.time()
        try:
            save_png(process(up, e, e['src'], a), os.path.join(outdir, h + '.png'))
            done += 1
            by_class[e['class']] = by_class.get(e['class'], 0) + 1
        except Exception as ex:
            errors += 1
            log('  ERRO %s: %s' % (h, ex))
        el = time.time() - t0
        eta = el / i * (total - i)
        log('  [%*d/%d %5.1f%%] %s %-9s %4dx%-4d -> %4dx%-4d %5.1fs | decorrido %s | faltam ~%s%s' % (
            len(str(total)), i, total, 100.0 * i / total, h, e['class'], e['w'], e['h'], *target_size(e, a),
            time.time() - t1, fmt_time(el), fmt_time(eta), ' | erros %d' % errors if errors else ''))
        # a cada textura: o remaster.sh usa o horario deste arquivo para detectar GPU travada
        write_status(a, etapa='upscale', feitas=i, total=total, porcentagem=round(100.0 * i / total, 1),
                     erros=errors, decorrido=fmt_time(el), faltam=fmt_time(eta), atual=h, por_classe=by_class,
                     modelo=os.path.basename(a.model) if a.model else 'lanczos')
    log('%d texturas processadas em %s (%d erros)' % (done, fmt_time(time.time() - t0), errors))


def cmd_status(a):
    p = os.path.join(a.work, 'status.json')
    if not os.path.exists(p):
        sys.exit('nenhuma rodada registrada em %s' % a.work)
    st = json.load(open(p))
    bar = int(st['porcentagem'] / 5)
    log('%s [%s%s] %s%%  %d/%d' % (st['etapa'], '#' * bar, '.' * (20 - bar), st['porcentagem'], st['feitas'], st['total']))
    log('decorrido %s | faltam ~%s | erros %d | modelo %s' % (st['decorrido'], st['faltam'], st['erros'], st['modelo']))
    log('por classe: ' + ', '.join('%s %d' % kv for kv in sorted(st['por_classe'].items())))
    log('ultima atualizacao %s (textura %s)' % (st['atualizado'], st['atual']))


# ---------------------------------------------------------------- encode / pack

def mip_chain(img, binary_alpha=False):
    """Nivel 0 + reducoes 2x ate 1x1 (o plugin nao precisa gerar nada durante o jogo)."""
    levels = [img]
    while max(levels[-1].size) > 1:
        w, h = levels[-1].size
        m = levels[-1].resize((max(1, w // 2), max(1, h // 2)), Image.BOX)
        if binary_alpha:  # DXT1: alpha de 1 bit (grades, folhagem) continua recortado
            r, g, b, al = m.split()
            m = Image.merge('RGBA', (r, g, b, al.point(lambda v: 255 if v >= 128 else 0)))
        levels.append(m)
    return levels


def dds_bytes(img, fourcc, mips=True):
    """DDS com cabecalho igual ao dos pacotes TexMod (o do Pillow traz pitch/bits invalidos)
    e cadeia completa de mipmaps. fourcc: b'DXT1', b'DXT5' ou None (A8R8G8B8 sem compressao)."""
    w, h = img.size
    levels = mip_chain(img, fourcc == b'DXT1') if mips else [img]
    hd = [0] * 31
    hd[0] = 124
    hd[2], hd[3] = h, w
    hd[18] = 32                                   # tamanho do DDS_PIXELFORMAT
    hd[26] = 0x1000                               # DDSCAPS_TEXTURE
    if len(levels) > 1:
        hd[1] |= 0x20000                          # DDSD_MIPMAPCOUNT
        hd[6] = len(levels)
        hd[26] |= 0x400008                        # DDSCAPS_COMPLEX | DDSCAPS_MIPMAP
    payload = []
    if fourcc:
        block = 8 if fourcc == b'DXT1' else 16
        for lv in levels:
            lw, lh = lv.size
            size = max(1, (lw + 3) // 4) * max(1, (lh + 3) // 4) * block
            if lw % 4 or lh % 4:  # o encoder do Pillow quer multiplos de 4: completa o bloco
                pad = Image.new('RGBA', ((lw + 3) // 4 * 4, (lh + 3) // 4 * 4))
                pad.paste(lv, (0, 0))
                lv = pad
            buf = io.BytesIO()
            lv.save(buf, 'DDS', pixel_format=fourcc.decode())
            data = buf.getvalue()[128:]
            if len(data) != size:
                raise ValueError('Pillow gerou %d bytes, esperado %d (%dx%d)' % (len(data), size, lw, lh))
            payload.append(data)
        hd[1] |= 0x81007                          # CAPS|HEIGHT|WIDTH|PIXELFORMAT|LINEARSIZE
        hd[4] = len(payload[0])
        hd[19], hd[20] = 4, struct.unpack('<I', fourcc)[0]
    else:
        for lv in levels:
            r, g, b, al = lv.split()
            payload.append(Image.merge('RGBA', (b, g, r, al)).tobytes())  # BGRA = A8R8G8B8
        hd[1] |= 0x100F                           # CAPS|HEIGHT|WIDTH|PITCH|PIXELFORMAT
        hd[4] = w * 4
        hd[19], hd[21] = 0x41, 32                 # RGB | ALPHAPIXELS
        hd[22], hd[23], hd[24], hd[25] = 0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000
    return b'DDS ' + struct.pack('<31I', *hd) + b''.join(payload)


def cmd_encode(a):
    man = load_manifest(a)
    updir, ddsdir = os.path.join(a.work, 'up'), os.path.join(a.work, 'dds')
    os.makedirs(ddsdir, exist_ok=True)
    n = 0
    for h, e in todo(man, a):
        src, dst = os.path.join(updir, h + '.png'), os.path.join(ddsdir, h + '.dds')
        if not os.path.exists(src):
            continue
        if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src) and not a.force:
            continue
        img = Image.open(src).convert('RGBA')
        fmt = e['fmt']
        if fmt == 'DXT1':
            data = dds_bytes(img, b'DXT1')
        elif fmt in ('DXT3', 'DXT5', 'DXT2', 'DXT4'):
            data = dds_bytes(img, b'DXT5')
        else:
            data = dds_bytes(img, None)  # A8R8G8B8 sem compressao, igual a original
        with open(dst + '.tmp', 'wb') as f:
            f.write(data)
        os.replace(dst + '.tmp', dst)
        n += 1
    log('%d DDS gerados em %s' % (n, ddsdir))


def cmd_pack(a):
    man = load_manifest(a)
    ddsdir = os.path.join(a.work, 'dds')
    entries = [(h, os.path.join(ddsdir, h + '.dds')) for h, _ in todo(man, a)]
    entries = [(h, p) for h, p in entries if os.path.exists(p)]
    if not entries:
        sys.exit('nada para empacotar (rode upscale e encode antes)')
    dst = os.path.join(a.game, 'texmod', a.pack_name)
    tmp = dst + '.tmp'
    with zipfile.ZipFile(tmp, 'w', zipfile.ZIP_STORED) as z:
        z.writestr('texmod.def', ''.join('%s|%s.dds\r\n' % (h, h) for h, _ in entries))
        for h, p in entries:
            z.write(p, h + '.dds')
    os.replace(tmp, dst)
    log('%d texturas em %s' % (len(entries), dst))
    log('Agora rode: python3 "%s" "%s"' % (os.path.join(a.game, 'DS2TexInject', 'ds2tex.py'),
                                           os.path.join(a.game, 'texmod')))


# ---------------------------------------------------------------- preview

def cmd_preview(a):
    man = load_manifest(a)
    updir, thdir = os.path.join(a.work, 'up'), os.path.join(a.work, 'thumbs')
    os.makedirs(thdir, exist_ok=True)
    rows = []
    for h, e in todo(man, a):
        up = os.path.join(updir, h + '.png')
        if not os.path.exists(up):
            continue
        orig = os.path.join(thdir, h + '_orig.png')
        if not os.path.exists(orig):
            Image.open(e['src']).convert('RGBA').save(orig)
        rows.append((h, e, os.path.relpath(orig, a.work), os.path.relpath(up, a.work)))
    cards = '\n'.join(
        '<figure id="{h}"><figcaption><b>{h}</b> {c} {fmt} {w}x{hh}<label><input type=checkbox data-h="{h}"> rejeitar</label>'
        '</figcaption><div class=pair><img loading=lazy src="{o}"><img loading=lazy src="{u}"></div></figure>'.format(
            h=h, c=e['class'], fmt=e['fmt'], w=e['w'], hh=e['h'], o=html.escape(o), u=html.escape(u))
        for h, e, o, u in rows)
    page = PREVIEW_HTML.replace('{{CARDS}}', cards).replace('{{N}}', str(len(rows)))
    dst = os.path.join(a.work, 'preview.html')
    open(dst, 'w', encoding='utf-8').write(page)
    log('preview com %d texturas: %s' % (len(rows), dst))


PREVIEW_HTML = """<!doctype html><meta charset=utf-8><title>DS2 AI Remaster</title>
<style>
body{margin:0;background:#0d1214;color:#cfe;font:14px system-ui,sans-serif;padding:16px}
h1{font-size:18px}figure{margin:0 0 24px}figcaption{margin-bottom:6px;display:flex;gap:12px;align-items:center}
.pair{display:grid;grid-template-columns:1fr 1fr;gap:6px}.pair img{width:100%;image-rendering:auto;background:#222}
textarea{width:100%;height:80px;background:#000;color:#cfe}
</style>
<h1>{{N}} texturas: original (esquerda) x IA (direita)</h1>
<p>Marque as ruins e copie a lista para <code>work/rejected.txt</code>.</p>
<textarea id=out readonly></textarea>
{{CARDS}}
<script>
const out=document.getElementById('out');
document.addEventListener('change',()=>{out.value=[...document.querySelectorAll('input:checked')].map(i=>i.dataset.h).join('\\n')});
</script>
"""


# ---------------------------------------------------------------- manifest / cli

def load_manifest(a):
    p = os.path.join(a.work, 'manifest.json')
    if os.path.exists(p):
        return json.load(open(p))
    if a.cmd not in ('scan', 'all', 'status'):
        sys.exit('manifest nao encontrado em %s: rode "scan" antes' % a.work)
    return {}


def save_manifest(a, man):
    os.makedirs(a.work, exist_ok=True)
    p = os.path.join(a.work, 'manifest.json')
    json.dump(man, open(p + '.tmp', 'w'), indent=1, sort_keys=True)
    os.replace(p + '.tmp', p)


def main():
    ap = argparse.ArgumentParser(description='Remaster de texturas do Dead Space 2 com IA')
    ap.add_argument('cmd', choices=['scan', 'upscale', 'encode', 'pack', 'preview', 'all', 'status'])
    ap.add_argument('--game', default=DEFAULT_GAME, help='pasta do jogo')
    ap.add_argument('--dump', help='pasta do dump (padrao: <jogo>/texmod/_dump)')
    ap.add_argument('--work', default=os.path.join(HERE, 'work'), help='pasta de trabalho')
    ap.add_argument('--model', help='modelo de upscale (.pth/.safetensors, ex.: 4x-UltraSharp)')
    ap.add_argument('--cleanup', help='modelo 1x opcional aplicado antes (remove artefatos DXT)')
    ap.add_argument('--scale', type=int, default=2, help='fator final (padrao 2)')
    ap.add_argument('--mask-scale', type=int, help='fator para mascaras/mapas de luz (padrao: igual a --scale)')
    ap.add_argument('--max-size', type=int, default=2048, help='lado maximo (padrao 2048)')
    ap.add_argument('--min-size', type=int, default=64, help='ignora texturas menores que isso')
    ap.add_argument('--tile', type=int, default=544, help='tamanho do bloco na GPU')
    ap.add_argument('--only', nargs='+', choices=CLASSES, help='so estas classes')
    ap.add_argument('--recent', type=float, help='so texturas salvas nos ultimos N minutos do dump')
    ap.add_argument('--pack-name', default=PACK_NAME, help='nome do pacote (padrao %s)' % PACK_NAME)
    ap.add_argument('--limit', type=int, help='processa no maximo N texturas')
    ap.add_argument('--ai-alpha', action='store_true', help='usa o modelo tambem no canal alpha')
    ap.add_argument('--ai-masks', action='store_true', help='usa o modelo tambem em mascaras/specular')
    ap.add_argument('--no-color-lock', action='store_true', help='deixa a IA mudar as cores do original')
    ap.add_argument('--force', action='store_true', help='refaz mesmo o que ja existe')
    a = ap.parse_args()
    a.game, a.work = os.path.abspath(os.path.expanduser(a.game)), os.path.abspath(a.work)
    if a.mask_scale is None:
        a.mask_scale = a.scale
    if not is_own_pack(a.pack_name):
        sys.exit('--pack-name precisa terminar em .zip e conter "_ai_" (ex.: zy_ai_teste.zip)')
    rej = os.path.join(a.work, 'rejected.txt')
    a.rejected = {l.strip() for l in open(rej)} if os.path.exists(rej) else set()

    steps = ['scan', 'upscale', 'encode', 'pack', 'preview'] if a.cmd == 'all' else [a.cmd]
    for s in steps:
        log('== %s' % s)
        globals()['cmd_' + s](a)


if __name__ == '__main__':
    main()
