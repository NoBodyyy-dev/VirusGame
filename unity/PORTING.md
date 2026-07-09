# Порт VirusGame: Godot 4.7 → Unity 6 (URP)

Перенос кооп-хакинг-роглайта с Godot (GDScript) на Unity (C#). Godot-оригинал
живёт в `../project/` и остаётся рабочим; этот каталог — отдельная ветка `unity-port`.

## Как открыть

1. Unity Hub → Add → выбрать `unity/VirusGame` (Unity 6000.0.x, см. `ProjectVersion.txt`).
2. При первом открытии Unity сам подтянет пакеты из `Packages/manifest.json`
   (URP, Input System, TextMeshPro) и сгенерирует `Library/`, `.csproj`, `.meta`.
3. Создать URP-ассет (Assets → Create → Rendering → URP Asset) и назначить его в
   Project Settings → Graphics (окружение/пост-обработка — см. TODO).
4. Сцены (`.unity`) в репозиторий не входят — их собирают в редакторе (ниже).

## Что портировано и ПРОВЕРЕНО компиляцией (.NET 8)

Движко-независимое **ядро правил** собрано `dotnet build` через шимы UnityEngine
(`_verify/`) — **0 ошибок**:

| Файл | Из Godot | Статус |
|---|---|---|
| `Core/GameData.cs` | таблицы game_state.gd (TIERS, ROOMS, SERVERS, цвета) | ✅ верифицировано |
| `Core/GameState.cs` | правила: кампания, зоны, флаги, Оракул, конфиг рейда | ✅ верифицировано |

## Что СОБРАНО и ЗАПУЩЕНО на Unity 6000.3.19f1

Проект открыт в реальном Unity, скомпилирован (0 ошибок) и **собран в
Standalone-плеер, который запускается с нуля исключений** (Player.log чист,
Direct3D 11, мир строится, игрок/камера спавнятся, HUD и текст рисуются).
Рендер — встроенный конвейер (без URP-ассета); материалы Mats работают и там.

| Файл | Из Godot | Примечание |
|---|---|---|
| `Core/GameStateBehaviour.cs` | автолоад GameState | синглтон + DontDestroyOnLoad |
| `Util/Mats.cs` | mats.gd | материалы через Standard-шейдер (RP-агностик), NoiseTexture→PerlinNoise |
| `Util/Build.cs` | хелперы _mesh_box/_collide/_label3d/_omni | GameObject+компоненты; текст на legacy `TextMesh` + шрифт ОС |
| `Util/Interactable.cs` | взаимодействие по дистанции + [E] | компонент + менеджер |
| `Player/VirusPlayer.cs` | player.gd | CharacterController (move_and_slide→Move) |
| `World/GridWorld.cs` | grid_world.gd (каркас) | комнаты, обучение, серверы, вход |
| `UI/Hud.cs` | grid_hud.gd | uGUI `UnityEngine.UI.Text` + шрифт ОС |
| `App/Boot.cs`, `App/SceneFlow.cs` | _ready / change_scene | бутстрап и переходы |
| `Net/NetStub.cs` | net.gd | ЗАГЛУШКА (см. ниже) |
| `Editor/UnityBuild.cs` | — | headless-сборка: сцена+Build Settings, always-included `Standard`, билд плеера |

### Как собрать/запустить из командной строки (batchmode, без GUI)
```
UNITY="C:/Program Files/Unity/Hub/Editor/6000.3.19f1/Editor/Unity.exe"
"$UNITY" -batchmode -quit -nographics -projectPath unity/VirusGame \
  -executeMethod Virus.EditorTools.UnityBuild.BuildWindows -logFile -
# → unity/Build/VirusUnity.exe
```

### Известные ограничения текущего среза (не баги сборки)
- Рендер на встроенном конвейере: нет SSAO/SSR/bloom/объёмного тумана (это URP).
- Материалы на Standard: без триплана и без реалистичных шумовых текстур Godot.
- Построен только каркас Грида + обучающий этап 0; вход в сервер грузит сцену
  `Level`, которой пока нет (см. стадии ниже).

## Ещё НЕ портировано (стадии дальше)

Порядок по ценности/риску:

1. **Рейд `level.gd` (~3100 строк)** — ядро геймплея внутри сервера: СИСТЕМА,
   роботы-охотники, ловушки, лут-физика, полевые задачи, эвакуация. Самый большой
   отдельный кусок. → `World/Level*.cs` + `Loot.cs` (RigidBody) + `SystemDirector.cs`.
2. **Интерактив Грида целиком** — в срезе только каркас+обучение. Осталось:
   провода/генераторы/рычаги/лифты (AnimatableBody3D→кинематик Rigidbody),
   переносные блоки (карри+снап), лазерные ловушки, падающие потолки, зип-лайны,
   весь зал Оракула (пилоны, территории, стойки, ядро, побег).
3. **Головоломка `puzzle_ui.gd`** → `UI/PuzzleUI.cs` (uGUI-сетка 4×4).
4. **Туннель победы `victory_tunnel.gd`** → `World/VictoryTunnel.cs`.
5. **Дерево эволюции / меню / результаты** (evolution_ui, main_menu, results_ui,
   hud рейда) → uGUI/UI Toolkit.
6. **КООП `net.gd` — редизайн, не перевод.** Встроенного эквивалента
   высокоуровневого мультиплеера Godot в Unity нет. Взять **Netcode for GameObjects**
   (или Mirror/Fish-Net) и переложить модель «хост владеет состоянием»:
   `@rpc` → `[ServerRpc]/[ClientRpc]`, синки → `NetworkVariable`/`NetworkTransform`,
   `players`/`scores` → `NetworkList`. Хук `GameState.SendFlag` уже выведен наружу
   под это. Самая рискоёмкая стадия.
7. **Шейдеры** `.gdshader` (hologram/floor_grid/vignette) → Shader Graph/HLSL.
   Триплан материалов (в Godot из коробки) — тоже Shader Graph.
8. **Окружение**: WorldEnvironment (SSAO/SSR/glow/объёмный туман/тонемап) →
   URP Volume (Bloom/SSAO/Fog/Tonemapping). Сейчас в `BuildEnvironment` только
   базовый свет+ambient через RenderSettings.
9. **Аудио** `sfx.gd` → `AudioSource`-пул. **Частицы** (дождь/пыль) → VFX Graph.

## Сцены для Build Settings (создать в редакторе)

`MainMenu`, `GridWorld`, `Level`, `VictoryTunnel` — каждая с пустым GameObject и
компонентом-бутстрапом (`GridWorld` → `App/Boot.cs`). Имена должны совпадать с
константами в `App/SceneFlow.cs`.

## Проверка ядра локально

```
cd unity/_verify && dotnet build      # компилирует Core через шимы UnityEngine
```

`_verify/` и шимы в Unity не используются — это только офлайн-контроль логики.
