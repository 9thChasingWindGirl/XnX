# XnX Player 构建仓

> 本仓是 **XnX 自研的构建脚本与 workflow**，不包含任何上游源码，也不存放业务源码。
> 业务代码分别位于四个改造分支：`XnX_core`（基于 Stremio/core）、`XnX_ui`（基于 Stremio web）、
> `XnX_shell`（基于 stremio-shell-ng）、`XnX_providers`（XnX 自研）。

只负责**组装与打包**，不存放任何业务源码。业务代码在 `XnX_core / XnX_ui / XnX_shell / XnX_providers` 四个分仓。

## 两种构建模式（`workflow_dispatch`）

| 模式 | 行为 | 用途 |
|---|---|---|
| `fast`（默认） | 下载各分仓 CI 产出的未加密 artifact，只 clone providers，打包 | 日常发布 |
| `full` | 从四个分仓 clone 源码，编译 core-web / UI / shell，再打包 | 产物缺失时的兜底 |

`obfuscate` 已移除：providers 是公开仓、明文 JS，不混淆。

## 关键脚本

- `scripts/fetch-artifacts.ps1`：从三个分仓取最新 `ui-build-* / shell-exe-* / core-web-*`，写入 `bundle/build-manifest.json`（repo + commit + run id）
- `scripts/assemble-full.ps1`：clone + staging；`XNX_STAGE_ONLY=1` 时只处理 providers
- `.github/workflows/xnx-full.yml`：品牌门禁（上游 updater 端点硬失败）→ providers 打包 → mpv 依赖 staging → zip
- `.github/workflows/mirror-deps.yml`：**已删除**

## 依赖

- mpv 链接库 pin 在上游 commit `e148e2a…`，用 Actions 缓存；`bin/`（82MB ffmpeg）不再获取
- 跨仓读取产物需要 secret `PAT`（`actions:read` / `contents:read`）
- artifact 保留 7 天；过期后需回退 `full` 模式

## 许可

见 `THIRD_PARTY.md`。
