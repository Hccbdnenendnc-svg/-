# desktop-brightness

像笔记本一样调节台式机显示器亮度的 Windows 命令行工具。

台式机外接显示器没有笔记本那种系统级背光控制，这个项目通过显示器的 **DDC/CI 协议**（VCP code 0x10，亮度指令）直接向显示器发送亮度命令——不需要装任何驱动或第三方软件，Windows 自带的 `dxva2.dll` 高级监视器配置 API 就是全部依赖。

## 功能

- 读取/设置/增减一台或多台显示器的物理亮度
- `bright.cmd` 包装器，支持 `bright 40`、`bright +10`、`bright -10` 这种直觉用法
- 可选的 AutoHotkey v2 热键脚本：`Ctrl+Alt+↑/↓` 调亮度，`Ctrl+Alt+0~9` 直接跳到 0%~90%，体验和笔记本 Fn 键一致
- 一键安装脚本：把 `bright` 命令注册进用户 PATH

## 环境要求

- Windows 10 / 11
- 显示器支持 DDC/CI（绝大多数 2010 年后的台式机显示器都支持，部分需要在 OSD 菜单里手动开启）
- 热键功能需要 [AutoHotkey v2](https://www.autohotkey.com)

## 安装

```powershell
git clone https://github.com/<你的用户名>/desktop-brightness.git
cd desktop-brightness
.\install.ps1
```

`install.ps1` 会把 `bright` 命令复制到 `%LOCALAPPDATA%\BrightnessDDC\bin` 并加入用户 PATH，开个新终端即可使用。脚本还会询问是否开机自启热键。

不想安装的话，直接跑 `src\bright.ps1` 也行。

## 用法

```text
bright              查看所有显示器当前亮度
bright 40           所有显示器设为 40%
bright +10          所有显示器加 10
bright -10          所有显示器减 10
bright set 40 2     只把 2 号显示器设为 40%
bright get 2        查看 2 号显示器亮度
bright list         列出检测到的显示器
```

在「运行」对话框（Win+R）里输入 `bright 30` 也能用，前提是装过了。

### 热键（可选）

| 快捷键 | 功能 |
|---|---|
| `Ctrl+Alt+↑` | 亮度 +10 |
| `Ctrl+Alt+↓` | 亮度 −10 |
| `Ctrl+Alt+0~9` | 亮度设为 0%~90% |

需要 `bright_hotkeys.ahk` 与 AutoHotkey v2，`install.ps1` 可配置开机自启。

## 原理

Windows 提供一组 High-Level Monitor Configuration API：

1. `EnumDisplayMonitors` 枚举所有显示输出
2. `GetPhysicalMonitorsFromHMONITOR` 拿到物理监视器句柄
3. `GetMonitorBrightness` / `SetMonitorBrightness` 读写亮度（底层即 DDC/CI 的 VCP 0x10）

每台显示器有自己的最小值/最大值/当前值区间，脚本会换算成百分比并做边界钳制。

## 开了 HDR 怎么调亮度？

Windows 打开 HDR 后，DDC/CI 的亮度通道会被系统锁死（这是系统限制，所有工具都一样）。此时有两种办法：

**1. 调"SDR 内容亮度"（推荐）**

设置 → 系统 → 屏幕 → HDR → **SDR 内容亮度**。桌面、浏览器、编辑器都属于 SDR 内容，这个滑块等效于笔记本亮度条。仅 HDR 全屏游戏/视频不受它控制（HDR 内容的亮度由内容本身决定）。

**2. 软件调暗（本项目支持）**

```text
bright dim 60    屏幕压暗到 60%
bright dim       默认压暗到 50%
bright undim     恢复正常
```

原理是修改显卡伽马表（`SetDeviceGammaRamp`），不经过 DDC/CI，HDR 开着也有效。**限制**：Windows 图形驱动出于安全考虑拒绝偏离线性过大的伽马表，实测调暗下限约 50%，`dim` 值低于 50 会自动钳到 50%。显示器重启/睡眠后伽马会复位，跑一次 `undim` 再重新 `dim` 即可。

日常建议：桌面工作用 SDR + `bright`（真亮度、无损画质）；看 HDR 片子/玩 HDR 游戏时才开 HDR，桌面亮度交给"SDR 内容亮度"滑块。

## 故障排查

- **提示 no DDC/CI**：先进显示器 OSD 菜单找 "DDC/CI" 选项并开启；部分型号（尤其部分 LG / 三星）默认关闭。
- **远程桌面 (RDP) 下无效**：RDP 会话里枚举到的是虚拟显示器，摸不到物理 DDC/CI 通道，请在本机控制台会话使用。
- **核显驱动问题**：很老的集显驱动可能不支持该 API，更新显卡驱动即可。
- **只调了一台**：多显示器下每台的支持情况独立，用 `bright list` 确认。

## License

MIT
