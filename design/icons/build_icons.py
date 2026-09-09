from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent
DEFS = '''<defs>
<linearGradient id="base" x1="0" y1="0" x2="0.85" y2="1"><stop stop-color="#2865DA"/><stop offset=".52" stop-color="#2047AE"/><stop offset="1" stop-color="#142B6F"/></linearGradient>
<linearGradient id="accent" x1="0" y1="1" x2="1" y2="0"><stop stop-color="#70DEFA"/><stop offset="1" stop-color="#BCF7FF"/></linearGradient>
<linearGradient id="edge" x1="0" y1="0" x2="0" y2="1"><stop stop-color="white" stop-opacity=".3"/><stop offset="1" stop-color="white" stop-opacity=".04"/></linearGradient>
<filter id="shadow" x="-.2" y="-.2" width="1.4" height="1.5"><feDropShadow dx="0" dy="12" stdDeviation="13" flood-color="#081D52" flood-opacity=".24"/></filter>
</defs>'''
BASE = '''<rect x="64" y="64" width="896" height="896" rx="202" fill="url(#base)"/>
<rect x="67" y="67" width="890" height="890" rx="199" fill="none" stroke="url(#edge)" stroke-width="6"/>'''

def symbol(variant, mono=False):
    white = '#171D29' if mono else '#F5FAFF'
    cyan = white if mono else 'url(#accent)'
    muted = white if mono else '#7395D9'
    if variant == 'A':
        return f'''<path d="M 627 328 A 220 220 0 1 0 627 696" fill="none" stroke="{white}" stroke-width="88" stroke-linecap="round"/>
<path d="M 482 512 H 760 M 678 430 L 760 512 L 678 594" fill="none" stroke="{cyan}" stroke-width="76" stroke-linecap="round" stroke-linejoin="round"/>'''
    return f'''<path d="M 392 512 C 486 512 466 686 586 686 H 729" fill="none" stroke="{muted}" stroke-width="72" stroke-linecap="round"/>
<path d="M 699 649 L 736 686 L 699 723" fill="none" stroke="{muted}" stroke-width="58" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M 278 512 H 382 C 486 512 466 338 586 338 H 746 M 672 264 L 746 338 L 672 412" fill="none" stroke="{cyan}" stroke-width="80" stroke-linecap="round" stroke-linejoin="round"/>
<circle cx="278" cy="512" r="46" fill="{white}"/>'''

def svg(variant, mono=False):
    # Menu glyphs have their own tight artboard, instead of inheriting app tile margins.
    vb = '200 200 620 620' if mono else '0 0 1024 1024'
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="{vb}" role="img" aria-label="OpenBy {variant}">{DEFS if not mono else ''}{BASE if not mono else ''}<g {'filter="url(#shadow)"' if not mono else ''}>{symbol(variant,mono)}</g></svg>'''

for variant in ('A', 'B'):
    for mono in (False, True):
        name = f'OpenBy-{variant}' + ('-menu' if mono else '')
        src = ROOT / (name + '.svg')
        src.write_text(svg(variant, mono))
        for size in ([16,18,32,36] if mono else [16,32,64,128,256,512,1024]):
            subprocess.run(['rsvg-convert','-w',str(size),'-h',str(size),str(src),'-o',str(ROOT / f'{name}-{size}.png')],check=True)
        if not mono:
            subprocess.run(['rsvg-convert','-f','pdf',str(src),'-o',str(ROOT/f'{name}.pdf')],check=True)

# Self-contained vector comparison sheet; the exact master artwork is embedded.
def placed(variant,x,y,size,mono=False):
    inner=svg(variant,mono).replace('width="1024" height="1024"',f'x="{x}" y="{y}" width="{size}" height="{size}"',1)
    # Isolate gradient/filter IDs across repeated instances.
    suffix=f'{variant}{x}{y}{size}'
    for name in ('base','accent','edge','shadow'):
        inner=inner.replace(f'id="{name}"',f'id="{name}{suffix}"').replace(f'url(#{name})',f'url(#{name}{suffix})')
    return inner
parts=['''<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="1060" viewBox="0 0 1440 1060"><rect width="1440" height="1060" fill="#F3F5F9"/><g font-family="Helvetica Neue,Arial,sans-serif"><text x="76" y="78" fill="#17243D" font-size="32" font-weight="600">OpenBy / Icon studies</text><text x="76" y="112" fill="#718098" font-size="16">VECTOR CONCEPTS     /     01     /     SEPTEMBER 2026</text>''']
for v,x,title,desc in [('A',64,'Open ring','Open, then hand off.'),('B',744,'Selected path','One rule. The right destination.')]:
    parts.append(f'<rect x="{x}" y="156" width="632" height="838" rx="24" fill="white"/><text x="{x+32}" y="202" font-size="16" fill="#718098">CONCEPT {v}</text><text x="{x+32}" y="244" font-size="29" font-weight="600" fill="#17243D">{title}</text><text x="{x+32}" y="275" font-size="17" fill="#718098">{desc}</text>')
    parts.append(placed(v,x+126,298,380))
    parts.append(f'<path d="M {x+32} 704 H {x+600}" stroke="#E9EDF3"/><text x="{x+32}" y="738" font-size="13" fill="#718098">ACTUAL SIZE / px</text>')
    for dx,s in [(40,16),(112,32),(204,64),(340,128)]:
        parts.append(placed(v,x+dx,770,s))
        parts.append(f'<text x="{x+dx+s/2}" y="928" text-anchor="middle" font-size="12" fill="#718098">{s}</text>')
    parts.append(f'<text x="{x+32}" y="974" font-size="13" fill="#718098">MENU BAR</text>')
    parts.append(placed(v,x+148,957,18,True))
    parts.append(placed(v,x+190,953,24,True))
parts.append('</g></svg>')
(ROOT/'comparison.svg').write_text(''.join(parts))
subprocess.run(['rsvg-convert',str(ROOT/'comparison.svg'),'-o',str(ROOT/'comparison.png')],check=True)
(ROOT/'preview.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>OpenBy 图标设计方案</title><style>body{margin:0;background:#f3f5f9;font:16px system-ui;color:#17243d}main{max-width:1440px;margin:auto}img{width:100%;display:block}p{padding:0 5%;line-height:1.8}a{color:#2053c0}</style><main><img src="comparison.svg" alt="OpenBy A 开口圆环和 B 分流路径的矢量图标对比及实际尺寸预览"><p>A：开口圆环＋穿出箭头，强调品牌和打开动作。B：两条分支＋高亮路径，强调按规则选择。两版采用同一蓝色底板与青色强调色。</p><p><a href="OpenBy-A.svg">A 矢量源文件</a> · <a href="OpenBy-B.svg">B 矢量源文件</a> · <a href="OpenBy-A.pdf">A PDF</a> · <a href="OpenBy-B.pdf">B PDF</a></p></main></html>''')
