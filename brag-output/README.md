# brag-output — launch-видео Canary

Собрано навыком `/brag` (`.claude/skills/brag`) поверх Hyperframes 2026-09-17.
В git лежат `brag-plan.md`, `composition-brief.md`, `composition/index.html`,
`share-copy.txt`. Медиа и рендер не хранятся — восстанавливаются так
(на маке нужны Node 22, ffmpeg, Python с pillow и pillow-heif):

```bash
cd brag-output/composition
mkdir -p assets/img assets/fonts assets/music assets/sfx/interface assets/sfx/impact assets/sfx/casino vendor
# кадры каталога → PNG
python3 - <<'PY'
import pillow_heif; pillow_heif.register_heif_opener()
from PIL import Image
for s in ("lexus-rx","mercedes-gl","toyota-camry-70","bmw-3-f30","hyundai-solaris","lada-vesta"):
    Image.open(f"../../AppMVP/Resources/CarCatalog/{s}.heic").convert("RGB").save(f"assets/img/{s}.png")
PY
cp ../../AppMVP/Resources/Assets.xcassets/SoundOrbBase.imageset/orb.png assets/img/orb-base.png
B=../../.claude/skills/brag/assets
cp $B/music/happy-beats-business-moves-vol-1-by-ende-dot-app.mp3 assets/music/
cp $B/sfx/interface/click_003.ogg $B/sfx/interface/bong_001.ogg assets/sfx/interface/
cp $B/sfx/impact/impactSoft_medium_001.ogg $B/sfx/impact/impactSoft_medium_004.ogg $B/sfx/impact/impactBell_heavy_000.ogg assets/sfx/impact/
cp $B/sfx/casino/card-slide-1.ogg assets/sfx/casino/
npm i gsap@3.14.2 && cp node_modules/gsap/dist/gsap.min.js vendor/
# Inter (латиница + кириллица) — с Google Fonts, положить как inter-latin.woff2 / inter-cyrillic.woff2
# аудио-данные для дыхания шара:
python3 ~/.claude/skills/hyperframes-creative/scripts/extract-audio-data.py assets/music/*.mp3 --fps 30 --bands 8 -o /tmp/a.json
python3 -c "import json;d=json.load(open('/tmp/a.json'));d['frames']=d['frames'][:602];d['totalFrames']=602;open('assets/audio-data.js','w').write('window.AUDIO_DATA='+json.dumps(d)+';')"
npx hyperframes check && npx hyperframes render --quality delivery --output ../brag.mp4
```
