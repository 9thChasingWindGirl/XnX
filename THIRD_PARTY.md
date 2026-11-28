# 第三方组件（构建仓）

本仓不放业务源码，只在构建时暂存分仓产物。

| 组件 | 来源 | 版本/修订 | 许可 | 位置 |
|---|---|---|---|---|
| 上游 mpv 链接库 | Stremio/stremio-shell-ng | commit `e148e2a6801b4af3afd143262f2280a866da7c87` | LGPL（mpv 项目） | 构建时下载到 `deps/`，缓存 |
| 上游 ffmpeg DLL (`bin/`) | 同上 | 同上 | 上游 | **不再获取、不再打包** |

分仓内的第三方代码各自的 `THIRD_PARTY.md` 记录。构建产物不含上游服务端 `server.js`。
