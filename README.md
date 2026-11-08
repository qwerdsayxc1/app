# NOVA AI

Нативный голосовой AI-ассистент для macOS (Apple Silicon, macOS 14+). Управляет Mac голосом и выполняет реальные действия: запускает и закрывает приложения, открывает сайты и поиск, меняет громкость, сообщает заряд батареи и свободное место, переключает окна, открывает проекты в Xcode или IntelliJ.

Стек: Swift 6, SwiftUI (+ AppKit), Speech, AVFoundation, AVSpeechSynthesizer, Claude API (tool use в strict-режиме), AppleScript, Accessibility API, Keychain, SwiftData. Без Electron и без веба.

> ⚠️ **Статус сборки.** Код написан на Windows, где нет Xcode и Swift toolchain, поэтому **ни разу не компилировался и не запускался**. Мы аккуратно сверялись с API Apple и строгой конкурентностью Swift 6, но при первой сборке на Mac возможны мелкие ошибки компиляции (см. «Известные риски»). Начните с `swift test`, затем соберите приложение в Xcode.

---

## Возможности

| Область | Что умеет |
|---|---|
| Голос | Push-to-talk кнопкой и горячей клавишей **⌥Space** (удерживать). Языки: ru, uk, en, de. Распознавание по возможности на устройстве. Ответ озвучивается через AVSpeechSynthesizer. Нажатие во время ответа перебивает ассистента |
| AI Brain | Claude API с tool use: строгие JSON-схемы (`strict: true`), проверка аргументов на клиенте, белый список инструментов, многошаговые цепочки. Произвольный shell не выполняется никогда |
| Приложения | Открыть, закрыть (с подтверждением), переключить, список запущенных. Понимает «телеграм», «интеллидж», «VS Code» и т.п. |
| Браузер | Safari, Chrome или браузер по умолчанию: любой http(s)-URL, YouTube, GitHub, поиск в Google, YouTube и GitHub |
| Система | Громкость (абсолютная, ±N %, mute), батарея, свободное место, информация о системе, уведомления |
| Окна | Активное приложение и окно, список окон, переключение окна (Accessibility API) |
| Проекты | «Открой мой проект NOVA AI в Xcode»: ищет папку проекта в заданных каталогах и открывает .xcworkspace / .xcodeproj / Package.swift / папку |
| Память | История диалогов, последние команды, контекст разговора, настройки (SwiftData + UserDefaults), кнопка очистки |
| UI | Тёмный футуристичный интерфейс, анимированный AI Orb, светящаяся звуковая волна, glassmorphism, статус Idle / Listening / Thinking / Executing / Speaking. Плавающая панель поверх окон (NSPanel) и иконка в строке меню (MenuBarExtra) |

### Сценарии (логика покрыта тестами; на Mac не запускалось)

«Открой YouTube» · «Открой Telegram» · «Запусти IntelliJ IDEA» · «Найди на YouTube видео про Python» · «Открой GitHub в браузере» · «Увеличь громкость на 20 процентов» · «Выключи звук» · «Сколько процентов батареи осталось?» · «Какие приложения сейчас открыты?» · «Открой Safari и перейди на сайт Apple» · «Найди в Google информацию про Claude API» · «Открой мой проект NOVA AI в Xcode».

Формулировки разбирает Claude, поэтому подходят и варианты вроде «сделай погромче на двадцать», «mach lauter», «відкрий телеграм».

---

## Архитектура

```
Голос ─► SpeechRecognition ─► AssistantViewModel ─► AIEngine ─► ClaudeService ─► Claude API
(⌥Space / кнопка)  (Speech)          (MVVM)            │  ▲  tool_result
                                                       ▼  │
                                                   ToolManager
                         белый список → валидация → подтверждение → обработчик
                                                       │
  ApplicationManager · BrowserController · SystemManager · AccessibilityService · ProjectOpener · NotificationService
  (NSWorkspace)        (NSWorkspace)       (IOKit, osascript) (AXUIElement)

  ответ ─► SpeechSynthesis            MemoryManager (SwiftData)
```

- **`Sources/NOVACore`** — Swift Package без UI и AppKit: модели, `JSONValue`, клиент Claude (запрос, парсинг, ретраи), `AIEngine` (агентный цикл), `ToolCatalog` (белый список и схемы), `ToolArgumentValidator`, `ToolManager`, обработчики инструментов поверх протоколов, `MemoryManager`, настройки, проверка API-ключа, поиск проектов, алиасы приложений, URL.
- **`App/`** — macOS-приложение (XcodeGen), реализует протоколы ядра на системных API (DIP).

| Модуль | Файлы |
|---|---|
| NOVAApp | `App/NOVAApp/` — `NOVAApp`, `AppDelegate`, `AppEnvironment` (корень композиции, DI) |
| UI | `App/UI/` — `MainView`, `HistorySidebar`, `OnboardingView`, `FloatingPanel`, `MenuBarView`, `Settings/`, `Components/` |
| ViewModels | `App/ViewModels/` — `AssistantViewModel`, `SettingsViewModel` |
| VoiceEngine | `App/VoiceEngine/` — push-to-talk, перебивание, точка расширения `WakeWordDetecting`, `HotkeyManager` |
| SpeechRecognition / SpeechSynthesis | `App/SpeechRecognition/`, `App/SpeechSynthesis/` |
| AIEngine | `Sources/NOVACore/AI/` |
| ClaudeService | `Sources/NOVACore/Claude/` |
| ToolManager | `Sources/NOVACore/Tools/` |
| MacAutomation | `App/MacAutomation/` — `AppleScriptRunner`, `AccessibilityService`, `NotificationService`, `WorkspaceLauncher` |
| BrowserAutomation | `App/BrowserAutomation/` |
| ApplicationManager | `App/ApplicationManager/` (+ `ProjectOpener`) |
| SystemManager | `App/SystemManager/` |
| MemoryManager | `Sources/NOVACore/Memory/`, `App/MemoryManager/SwiftDataMemoryStore.swift` |
| Settings | `Sources/NOVACore/Settings/` |
| Security | `Sources/NOVACore/Security/`, `App/Security/` (Keychain, разрешения) |
| Models | `Sources/NOVACore/Models/` |

### Как работает AI Brain

1. Распознанная фраза добавляется в историю. История ведётся append-only: блоки ассистента (включая `thinking`) возвращаются в API без изменений. Длинная история не редактируется, а пересоздаётся из текстовых реплик памяти.
2. Запрос `POST /v1/messages`: `anthropic-version: 2026-10-21`, модель `claude-opus-5-5` (в настройках можно выбрать `claude-sonnet-5-5`), `output_config.effort` (по умолчанию `low` для быстрых голосовых ответов), `tool_choice: auto`, strict-инструменты, кеширование системного промпта, серверный fallback при отказе (`fallbacks: "default"`).
3. Пока `stop_reason == tool_use`, каждый вызов проходит через `ToolManager`: белый список → валидация аргументов (типы, enum, диапазоны, длина, управляющие символы, только http(s)-URL) → подтверждение опасных действий → выполнение. Все `tool_result` хода возвращаются одним сообщением; ошибки — с `is_error: true`.
4. Финальный текст озвучивается и сохраняется в память. При ошибке или отмене незавершённый хвост истории откатывается.

Опасные действия подтверждаются голосом («да/нет», «так/ні», «yes/no», «ja/nein») или кнопкой. Сейчас это `quit_application`. Если подтвердить некому — действие отклоняется (fail closed). Удаления, отправки сообщений и покупок в белом списке нет вообще.

---

## Требования

- Mac на Apple Silicon, **macOS 14 Sonoma** или новее.
- **Xcode 16** или новее (Swift 6).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
- API-ключ Anthropic: [platform.claude.com](https://platform.claude.com).

## Сборка и запуск

```bash
cd NOVA-AI
```

```bash
swift test
```

```bash
xcodegen generate
```

```bash
open NOVA.xcodeproj
```

1. В Xcode: схема **NOVA** → *Signing & Capabilities* → выберите свою команду (Team). С «Sign to Run Locally» разрешения macOS сбрасываются после каждой пересборки.
2. ⌘R — запуск. ⌘U — тесты (`NOVACoreTests` включён в схему).
3. Сборка из терминала:

```bash
xcodebuild -project NOVA.xcodeproj -scheme NOVA -configuration Release -destination 'platform=macOS,arch=arm64' build
```

## Первый запуск

1. **API-ключ.** Вставьте `sk-ant-…` на экране приветствия или в Настройках → AI. Ключ проверяется по формату и хранится **только в Keychain** (generic password, сервис `ai.nova.assistant`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). В коде, UserDefaults и файлах его нет.
2. **Согласие.** Включите «Разрешаю отправлять текст команд в Claude API». Без согласия NOVA не обращается к сети.
3. **Разрешения** запрашиваются тогда, когда нужны, с объяснением:

| Разрешение | Когда нужно | Где включить вручную |
|---|---|---|
| Микрофон | первое нажатие микрофона или ⌥Space | Системные настройки › Конфиденциальность и безопасность › Микрофон |
| Распознавание речи | там же | … › Распознавание речи |
| Универсальный доступ | только для команд про окна | … › Универсальный доступ |
| Уведомления | первое уведомление от NOVA | Системные настройки › Уведомления |

Права администратора не нужны. Громкость меняется через Standard Additions (`set volume`). App Sandbox выключен, потому что Accessibility API и управление чужими приложениями в песочнице не работают; распространение — Developer ID + нотаризация.

Если после пересборки пропал доступ:

```bash
tccutil reset Accessibility ai.nova.assistant
```

## Использование

- **Удерживайте ⌥Space**, скажите команду, отпустите. Или нажмите на микрофон / Orb, затем ещё раз, чтобы закончить.
- Нажатие во время ответа **перебивает** NOVA.
- Команду можно ввести текстом в поле внизу.
- Плавающая панель — ⇧⌘N или из меню в строке меню.
- История справа: команду можно повторить, 🗑 очищает всю память.

## Безопасность и приватность

- Белый список из 19 инструментов (`ToolName`); любое другое имя отклоняется до выполнения.
- AppleScript — только фиксированные скрипты из `AppleScriptRunner`, данные передаются через `argv`, в текст скрипта ничего не подставляется.
- URL: только http/https с хостом, без `user:pass@`; `file:`, `javascript:` и URL-схемы приложений отклоняются.
- В Claude уходит только текст команды и краткая история. Аудио, файлы и экран не отправляются.
- Результаты инструментов (например, заголовки окон) в системном промпте помечены как данные, а не инструкции.
- Микрофон работает только между нажатием и отпусканием; постоянного прослушивания нет.

## Расширение: wake word

`VoiceEngine` содержит протокол `WakeWordDetecting` и `ListeningTrigger.wakeWord`. Реализуйте протокол (например, на `SFSpeechRecognizer` с коротким окном или на Core ML), присвойте `voiceEngine.wakeWordDetector` и включайте только по явному переключателю в настройках. Остальной конвейер менять не нужно.

## Тесты

`Tests/NOVACoreTests` (XCTest):

- парсинг ответов Claude и tool calls, HTTP-ошибки, ретраи, форма запроса и заголовки;
- белый список и strict-схемы всех инструментов;
- валидация аргументов: типы, обязательные/лишние поля, enum, диапазоны, длина, управляющие символы, URL;
- `ToolManager`: подтверждения (fail closed), громкость, браузер, приложения, окна, батарея — на фейках;
- `AIEngine`: многошаговый цикл, неизменные thinking-блоки, откат при ошибке/отказе, лимит шагов, согласие;
- память: запись, порядок, лимиты, очистка, контекст разговора;
- алиасы приложений, URL, поиск проектов во временных каталогах, настройки, API-ключ, голосовое «да/нет».

## Известные риски первой сборки

Код не компилировался; если Xcode выдаст ошибку, вероятнее всего она здесь:

- **Аннотации изоляции и `Sendable` в SDK** (`NSWorkspace`, `AVAudioNodeTapBlock`, `UNUserNotificationCenter`). Колбэки создаются в `nonisolated`-функциях и передают наружу только Sendable-значения; если SDK помечает API иначе, правки точечные.
- **IOKit Power Sources** (`SystemManager.batteryStatus`): константы `kIOPS…Key` при необходимости заменяются строками `"Current Capacity"`, `"Max Capacity"` и т.д.
- **`test:` с пакетным таргетом в `project.yml`** зависит от версии XcodeGen. Если схема не генерируется — удалите блок `test:` и запускайте `swift test`.
- **Liquid Glass (macOS 26)** не используется из-за минимальной версии macOS 14; стекло сделано на `.ultraThinMaterial`.
