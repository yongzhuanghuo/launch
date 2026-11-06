# launch DMG 安装引导素材

`scripts/create-dmg.sh` 会读取本目录下的三个可选文件：

| 文件 | 用途 | 建议尺寸 |
|---|---|---|
| `background.png` | DMG 窗口背景，上方放 launch 标题/图标 | 660×420 |
| `install-guide.png` | 左侧安装说明图（拖入 Applications、首次打开、试用/激活、支持邮箱） | 300×260 |
| `.DS_Store` | Finder 图标位置：左侧教程图、右侧 `launch.app` + `Applications` | 在 macOS 上用 Finder 调整一次后复制 |

没有素材时脚本仍能生成可用 DMG，只是没有自定义背景和教程图。

`install-guide.png` 建议包含：

1. 将 `launch.app` 拖到 Applications；
2. 首次打开如被系统拦截，右键打开或在“系统设置 → 隐私与安全性”放行；
3. 可选择 14 天试用，或输入激活码；
4. 找回/支持邮箱：`huoyongzhuang@qq.com`。
