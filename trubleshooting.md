# Troubleshooting

## ak.yaml 配置键（当前版本）

- 必填：`appId`、`accessToken`
- 可选：`seedApiKey`（仅语音整理热键需要）
- 不需要且应移除：`appKey`、`secretKey`

示例：

```yaml
appId: your_app_id
accessToken: your_access_token
seedApiKey: your_seed_api_key
```

## macOS 回写失败：权限明明勾选了，第二天又失效

### 现象

- 语音识别正常返回，但文本无法回写到原输入框。
- 日志出现类似：
  - `Accessibility trust is not granted for current app binary`
- 系统设置里看起来已经勾选了权限，但实际仍不生效。

### 根因（本项目已确认）

- 之前工程模板里签名配置是：
  - `CODE_SIGN_STYLE: Manual`
  - `CODE_SIGN_IDENTITY: "-"`
  - `DEVELOPMENT_TEAM: ""`
- 这会导致开发阶段经常变成 ad-hoc 签名，TCC 对应用身份匹配不稳定，出现“昨天可用、今天失效”。
- 另外如果直接从 `DerivedData` 启动，也会放大该问题。

### 已落地修复

- 项目签名模板已改为稳定配置（见 `doubao_mic/project.yml`）：
  - `CODE_SIGN_STYLE: Automatic`
  - `CODE_SIGN_IDENTITY: Apple Development`
  - `DEVELOPMENT_TEAM: <YOUR_TEAM_ID>`
- 统一使用固定路径启动：`/Applications/VoiceInput.app`
- 提供开发脚本：`doubao_mic/scripts/dev-run.sh`
  - 自动构建、部署到 `/Applications`、启动并输出权限/签名自检信息。

### 一次性修复步骤（本机）

1. 重置 TCC（仅此 bundle）：

```bash
tccutil reset Accessibility com.voiceinput.app
tccutil reset ListenEvent com.voiceinput.app
tccutil reset PostEvent com.voiceinput.app
```

2. 重启应用并重新授权：

- 打开 `/Applications/VoiceInput.app`
- 在系统设置中重新勾选：
  - `隐私与安全性 -> 辅助功能`
  - `隐私与安全性 -> 输入监控`

3. 验证签名不是 ad-hoc：

```bash
codesign -dvv /Applications/VoiceInput.app
```

期望看到：

- `Authority=Apple Development: ...`
- `TeamIdentifier=<YOUR_TEAM_ID>`
- 不应出现 `Signature=adhoc`

### 日常开发建议

- 不要直接运行 `DerivedData/.../VoiceInput.app` 做权限相关联调。
- 用以下命令启动开发联调：

```bash
cd doubao_mic
./scripts/dev-run.sh
```

## AX 返回成功但未实际回填（AX no-effect）

### 现象

- 日志显示 `AX set selected text succeeded`，但用户侧输入框没有出现文本。
- 同一会话中切换到 `KeyEvents` 后可成功回填。

### 结论

- 这类问题在 Electron/Web 富文本控件上常见：AX API 可能返回 success，但目标控件内部并未真正提交文本变更。
- 当前项目已实现治理：`AX(写后校验) -> KeyEvents`，且不使用 Paste。

### 已落地行为

- AX 写入后立即校验（读取焦点元素状态前后差异）：
  - 命中则判定 `axVerified`
  - 未命中则判定 `axNoEffect` 并自动回退 `KeyEvents`
- 若 `Input Monitoring` 未授权，回退会失败并给出明确提示：`failedKeyEventsDenied`。

### 关键日志特征

- `AX verify result: AXNoEffect ... fallback=KeyEvents`
- `Text insertion strategy succeeded: KeyEvents ...`
- 或（权限缺失时）`Text insertion strategy failed: KeyEventsDenied ...`

### 排查建议

1. 确认权限：`辅助功能 + 输入监控 + 麦克风` 都已授权。  
2. 用 `scripts/dev-run.sh` 启动，确认签名与 TCC 记录稳定。  
3. 若同一控件长期 `AXNoEffect`，可视为控件兼容性限制，不再将其视为本端逻辑错误。  
