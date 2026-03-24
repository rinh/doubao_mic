# VoiceInput TDD 总结（UI / XCUITest / 可测试性）

## 1. 当前测试现状（与本项目实现对应）

### 1.1 逻辑层单测（不依赖 UI）
- `WaveformModel` 纯逻辑测试：`doubao_mic/Tests/WaveformModel.test.swift`
  - 覆盖点：输入裁剪、最小/最大高度、中心柱增益、attack/release 平滑、reset 行为。
- 录音会话状态机测试：`doubao_mic/Tests/RecognitionSessionController.test.swift`
  - 覆盖点：`recording -> awaitingFinal -> finalized/failed`，二遍最终结果门控与超时释放。
- 文本注入策略测试：`doubao_mic/Tests/TextInserter.test.swift`
  - 覆盖点：`AX -> KeyEvents` 顺序、AX 写后校验、失败码与回退路径。

### 1.2 UI 组件单测（UI 层，但不跑全应用）
- `MicView` 组件测试：`doubao_mic/Tests/MicView.test.swift`
  - 覆盖点：4 柱创建、`updateLevel` 映射结果、`reset` 回静音高度。
  - 特点：测试对象是 View 本身，不依赖热键、权限弹窗、ASR 网络。

### 1.3 官方 XCUITest（端到端装配验证）
- `WaveformUITests`：`doubao_mic/UITests/WaveformUITests.swift`
  - `test_waveformFixture_drivesAccessibilityValue_lowHighLow`
    - 启动参数 `--ui-test-waveform` + 预设音频 `waveform_fixture.wav`。
    - 通过可访问性探针值断言“低->高->低”波形变化。
  - `test_draftWindowWidth_resetsToDefaultAtNextSessionStart`
    - 启动参数 `--ui-test-draft-window`。
    - 断言草稿窗宽度在下一次会话开始时回到默认值（360）。


## 2. 本项目的 TDD 原则（针对 UI 与功能解耦）

### 原则 A：先拆边界，再写测试
- 先把“可变业务逻辑”从 UI 中拆出来（如 `WaveformModel`）。
- UI 只做渲染与绑定，避免在 View 内写复杂算法。
- 含义：同一逻辑可被快速、稳定、无 UI 依赖地覆盖。

### 原则 B：三层测试分工明确
- 逻辑单测：验证规则正确性（快、稳定、定位准）。
- UI 组件单测：验证“模型输出 -> 视图状态”映射。
- XCUITest：验证真实装配、启动参数、可见行为。
- 含义：每层只测自己责任，不把所有风险压在慢而脆的 E2E 上。

### 原则 C：无人值守（No Manual Intervention）
- UI 测试不依赖真实麦克风、热键操作、系统权限弹窗。
- 用 fixture + launch args 进入测试路径，自动完成输入与断言。
- 含义：可重复、可在 CI 稳定运行，避免“人肉点点点”。

### 原则 D：测试注入仅在测试模式生效
- 通过 `--ui-test-*` 参数切换测试源（如 `FixtureAudioLevelSource`）。
- 默认运行路径保持生产行为，不被测试逻辑污染。
- 含义：测试能力增强与线上行为稳定两者兼得。

### 原则 E：可观测性优先于视觉猜测
- 给 UI 暴露只读探针（accessibility identifier/value）。
- 测试读结构化值，不做脆弱的像素截图比对。
- 含义：断言稳定、失败可诊断。

### 原则 F：状态机驱动，不靠时序偶然
- 录音与识别流程由显式状态机驱动（如 `idle/recording/awaitingFinal/finalized/failed`）。
- 测试围绕状态迁移与事件门控写，不依赖隐式时序。
- 含义：减少竞态和“偶现通过”。


## 3. 以 Wave UI 测试为例说明 TDD 的意义

### 3.1 需求
- 说话时，麦克风图标下 4 柱波形应有明显动态变化。
- 该验证需要无人值守、可重复，不能要求人工说话。

### 3.2 设计（解耦）
- 把电平算法放进 `WaveformModel`（纯逻辑）。
- `MicView` 只负责把高度渲染成 4 根 bar layer。
- 新增 `AudioLevelSource` 抽象，测试时注入 `FixtureAudioLevelSource`。

### 3.3 测试策略
- 单测先锁定 `WaveformModel` 的数学行为（红->绿）。
- 组件测锁定 `MicView` 渲染映射。
- XCUITest 用 `waveform_fixture.wav` 驱动真 App，读取 probe 值断言“低->高->低”。

### 3.4 结果价值
- 发现问题时能快速定位：算法错、渲染错、还是装配错。
- UI 迭代（动画/样式调整）不会轻易破坏业务逻辑。
- 测试可长期自动跑，减少回归成本与联调摩擦。


## 4. 落地检查清单（后续新增 UI 功能建议沿用）
- 新 UI 行为是否有对应纯逻辑模型？
- 是否有“逻辑单测 + 组件单测 + XCUITest”三层覆盖？
- XCUITest 是否完全无人值守（无权限弹窗/人工输入依赖）？
- 测试注入是否仅在 `--ui-test-*` 参数下生效？
- 是否提供了稳定 probe 供断言与排障？
- 是否存在先失败后通过的测试提交证据（Red/Green）？
- 是否存在对应 XCUITest 的 launch args + probe 断言链路？

## 5. TDD 强制门禁（新增功能）
- 必须执行 `Red -> Green -> Refactor`，禁止“先实现后补测”。
- 每个新增交互链路必须提供无人值守 XCUITest：
  - 真实启动 App；
  - 通过 launch args 注入测试输入；
  - 通过 probe（accessibilityValue）做稳定断言；
  - 不依赖人工操作或系统权限弹窗。
