# showreel-output — шоурил Beepy

Ролик 1920×1080, 42.5 с: вступление, семь функций приложения по одной,
итоговый список и логотип. Собран на Hyperframes 0.8.46 2026-09-24.

| Время | Что на экране |
|---|---|
| 0–4 | «Beepy» и «Семь вещей, которые умеет приложение» |
| 4–10 | 01 Диагностика по звуку: «Слушать» → «Стоп» → шторка «Вот что мы нашли» |
| 10–14 | 02 Машина по госномеру: номерная рамка, «Это ваш автомобиль?» |
| 14–20 | 03 История обслуживания: бланк заказ-наряда разбирается в форму ТО, «Всего потрачено» |
| 20–24 | 04 Напоминание о ТО: полоса до ТО краснеет, приходит уведомление «Пора на ТО» |
| 24–28 | 05 Рыночная цена: шторка «Цена авто», «средняя по рынку» |
| 28–32 | 06 Карта: парковки, шиномонтаж, СТО, карточка места, маршрут |
| 32–34.5 | 07 Всё на телефоне: без регистрации, данные на устройстве |
| 34.5–38 | Список всех семи |
| 38–42.5 | «Beepy. Слушает мотор. Помнит ТО.» |

Экраны в телефоне — HTML по макету Figma `9GXgWezTGI6TjklsnuBns2` (главная
`46225:7788`, «Ошибки» `46096:2551`, шторки `46102:3005`, `45854:2936`,
`46225:7551`, `46261:4222`). Готовые рендеры макета не годились: в них
заглушки — «Mercedes-Benz GL-класс» над Lexus, «9 000 000 км», пять
одинаковых находок. Тексты взяты из кода: находки — `IssuesScreen.swift`,
уведомление — `ServiceReminder` + `ServiceMath.reminderText`, пороги цвета
полосы — `ServiceMath.urgency` (жёлтая < 5 000 км, красная < 1 000 км),
цена — `PriceInfoSheet.swift`, типы мест — `Place.swift`. Карты в макете нет,
она нарисована условно.

## Что лежит в git

Только `composition/index.html` (единственный исходник: иконки и звуковые
дорожки в нём уже развёрнуты, править прямо его), `hyperframes.json`,
`meta.json`, `package.json` и этот файл. Медиа и рендер восстанавливаются.

## Пересборка (на маке: Node 22, ffmpeg, Python с numpy, pillow, pillow-heif)

```bash
cd showreel-output/composition
mkdir -p assets/img assets/fonts assets/music assets/sfx vendor
python3 - <<'PY'
import pillow_heif; pillow_heif.register_heif_opener()
from PIL import Image
Image.open("../../AppMVP/Resources/CarCatalog/lexus-rx.heic").convert("RGB").save("assets/img/lexus-rx.png")
PY
cp ../../AppMVP/Resources/Assets.xcassets/SoundOrbBase.imageset/orb.png assets/img/orb-base.png
# шрифты и GSAP — те же, что у /brag
cp ../../brag-output/composition/assets/fonts/*.woff2 assets/fonts/
cp ../../brag-output/composition/vendor/gsap.min.js vendor/   # или: npm i gsap@3.14.2
# музыка: трек vol-1 с 10-й секунды, чтобы дроп пришёлся на логотип (38.02)
M=../../.claude/skills/brag/assets/music/happy-beats-business-moves-vol-1-by-ende-dot-app.mp3
ffmpeg -y -ss 10 -t 43 -i "$M" -c:a libmp3lame -b:a 192k assets/music/bed.mp3
S=../../.claude/skills/brag/assets/sfx
cp $S/interface/{click_003,bong_001,drop_002,select_008}.ogg \
   $S/impact/{impactSoft_medium_001,impactSoft_medium_004,impactBell_heavy_000,impactGlass_light_001}.ogg \
   $S/casino/{card-slide-1,card-slide-3,card-place-2}.ogg \
   $S/keyboard/keypress-{003,007,012}.wav $S/ui/switch3.ogg assets/sfx/
# аудио-данные для дыхания шара (30 fps, 42.5 с)
python3 ~/.claude/skills/hyperframes-creative/scripts/extract-audio-data.py assets/music/bed.mp3 --fps 30 --bands 8 -o /tmp/bed.json
python3 -c "import json;d=json.load(open('/tmp/bed.json'));d['frames']=d['frames'][:1275];d['totalFrames']=1275;open('assets/audio-data.js','w').write('window.AUDIO_DATA='+json.dumps(d)+';')"
npx hyperframes@0.8.46 check && npx hyperframes@0.8.46 render --quality delivery --output ../showreel.mp4
# постер: кадр 37.2 с (весь список функций) вклеивается первым кадром —
# иначе превью в мессенджере будет чёрным
cd .. && ffmpeg -y -ss 37.2 -i showreel.mp4 -frames:v 1 poster.png
ffmpeg -y -i showreel.mp4 -loop 1 -i poster.png -filter_complex "[0:v][1:v]overlay=0:0:enable='eq(n,0)':shortest=1,format=yuv420p[v]" \
  -map "[v]" -map 0:a -c:v libx264 -crf 14 -preset slow -r 30 -c:a copy -movflags +faststart showreel.tmp.mp4 && mv showreel.tmp.mp4 showreel.mp4
```

Проверка перед рендером — `npx hyperframes check`. Одна пометка о контрасте
остаётся сознательно: приглушённая подпись «RUS» на номерной рамке, в
приложении она такого же цвета (`Figma.labelsTertiary`).
