# Hyperframes Composition Brief: Canary

## Objective
Короткое launch-видео о Canary: iOS-приложение, которое слушает мотор и называет неисправность, ведёт ТО. Тон спокойный и премиальный, язык видео — русский.

## Output
- Composition directory: `brag-output/composition/`
- Rendered video: `brag-output/brag.mp4`
- Format: landscape — 1920x1080
- Duration: 20 s

## Source Material
- Project root: `/home/user/carapp228` (iOS-приложение на SwiftUI, не сайт)
- Primary files read: `README.md`, `AppMVP/Core/Design/Theme.swift` (токены Figma), `AppMVP/Features/Issues/IssuesScreen.swift` (экран «Ошибки», шторка находок), `AppMVP/Features/Main/CarMainView.swift` (главная, плитки), `AppMVP/Core/Pure/PartAdvice.swift`, `AppMVP/Core/Services/CarDiagnosis.swift`
- Product name: Canary
- Tagline / strongest claim: «Поднесите телефон к двигателю» (строка экрана прослушивания) и «Похоже на неисправность»
- Key UI or visual moment to recreate: шторка находок после прослушивания; карточка машины с белым кадром каталога на чёрном
- Copy that must appear verbatim:
  - «Поднесите телефон к двигателю»
  - «Слушать»
  - «Похоже на неисправность»
  - «Оценка «что-то не так» — 74 %. Ниже версии, что именно, по убыванию.»
  - «Подвеска и рулевое» / «модель ставит сюда 83 %»
  - «Проверить стойки, сайлентблоки и опоры на трассе со стыками»
  - «ТО через» / «3 500 км»; «Цена авто» / «≈ 3 900 000 ₽»
  - «Canary»

## Creative Direction
- Tone preset: polished
- Creative direction: тихий премиальный продуктовый фильм в чёрной студии
- Interpretation: 5 сцен, длинные выдержки, мягкие входы (0.4–0.6 с) и долгие холды; текста мало; движение точное, без тряски и вспышек
- Angle: продукт показан его же языком: чёрная студия, белые машины из каталога, зелёный шар-слушатель, тёмные шторки. Ничего не изобретается, всё узнаваемо из приложения.
- Hook: шар дышит под музыку, «Поднесите телефон к двигателю», нажатие «Слушать»
- Outro / punchline: «Canary» на сильном ударе, «Слушает мотор. Помнит ТО.», мелко «iOS · данные остаются на телефоне»
- Avoid:
  - Generic SaaS language
  - Abstract filler visuals
  - Unrelated visual redesign

## Visual Identity
- Background: #000000
- Text: #FFFFFF; вторичный #8E8E93; третичный rgba(235,235,245,0.6)
- Accent: #34C759; цвета шара #58F0A8 / #40D2E0 / #8474E8; оценка красным #FF383C
- Surfaces: шторка #1C1C1E радиус 38; карточки #1A1A1A радиус 26; контрол #2C2C2E
- Display font: Inter (локально `assets/fonts/inter-latin.woff2`, `inter-cyrillic.woff2`, variable 400–800); fallback system-ui
- Body font: Inter
- Visual references from the project: `assets/img/lexus-rx.png` (эталон каталога), `hyundai-solaris.png`, `toyota-camry-70.png`, `bmw-3-f30.png`, `lada-vesta.png`, `mercedes-gl.png`, `orb-base.png` (SoundOrb), `car-hero.png`

## Storyboard
Use the storyboard in `brag-output/brag-plan.md` as the creative contract.

Scene summary:
1. Слушатель — 4.0 s — шар дышит, «Поднесите телефон к двигателю», нажатие «Слушать» на 2.4 с
2. Находки — 5.0 s — шторка снизу, вердикт, две карточки версий на 4.53 и 5.53
3. Карточка машины — 4.0 s — Lexus RX в световом пятне, номер, плитки ТО и цены на 10.52 и 11.02
4. Каталог — 4.5 s — пять машин по битам 13.51–15.52, GL встаёт на 16.02, «Ваша модель уже нарисована»
5. Canary — 2.5 s — логотип на 17.52, тэглайн на 18.52, мелкая строка, музыка уходит

## Audio
- Audio role: warm bed, sparse professional accents
- Audio arc: тихий вход, один клик, мягкие слайды, бед плотнеет к карусели, сильные удары ведут финал, колокольчик и тишина
- Music: `assets/music/happy-beats-business-moves-vol-1-by-ende-dot-app.mp3`
- Music treatment: старт 0, fade-in 0.6 с, громкость 0.55, спад с 18.5 к 20.0
- Music cue guidance: `assets/music/happy-beats-business-moves-vol-1-by-ende-dot-app.music-cues.json`; strong cues 16.02 / 17.52 / 18.52; beat grid для карточек 4.53, 5.53; плиток 10.52, 11.02; машин 13.51–15.52
- Audio-reactive treatment: subtle; RMS → свечение шара (сцена 1) и яркость пятна под машиной (сцена 3)
- Audio-coupled moments:
  - нажатие «Слушать» — click
  - подъём шторки — soft impact
  - две карточки — card-slide на битах
  - пять машин — card-slide на битах, soft impact на остановке
  - «Canary» — bell на 17.52
- SFX selection guidance: только низкий HF-риск; `interface/click_003.ogg`, `impact/impactSoft_medium_001.ogg`, `impact/impactSoft_medium_004.ogg`, `casino/card-slide-1.ogg`, `impact/impactBell_heavy_000.ogg`, `interface/bong_001.ogg`
- SFX analysis guidance: `.claude/skills/brag/assets/sfx/sfx-analysis.md`
- Exact SFX choice: по факту анимации; файлы уже скопированы в `assets/sfx/`
- Audio files: `assets/music/`, `assets/sfx/`

## Hyperframes Instructions
Домены загружены: `hyperframes-core`, `hyperframes-animation`, `hyperframes-creative`, `hyperframes-keyframes`, `hyperframes-cli`. /brag — свой workflow, без intent interview.

Requirements:
- Show at least one real UI, copy, or visual element from the source project.
- Keep all text readable in the final render.
- Keep the video within 15-25 seconds.
- Include the planned music/SFX layer.
- Beat-lock 1–3 major reveals within ±0.15 s; sequential objects on the beat grid within ±0.10 s; text holds по правилу чтения.
- Audio-reactive: extract per-frame data via hyperframes-creative helper; если недоступно (нет python-зависимостей), задокументировать и не блокировать рендер.
- Use local assets only: GSAP из `vendor/gsap.min.js`, шрифты и медиа из `assets/`.
- Run `hyperframes check` before render — it is brag's single gate.
