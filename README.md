# PhoneVideoTweak

为越狱 iPhone/iPad 提供 USB 投屏和控制的 Theos 插件，是 **[GoScrcpy](https://github.com/wwangmc/GoScrcpy)** 的 iOS 配套项目。

**[下载 deb](https://github.com/wwangmc/PhoneVideoTweak/releases/latest)** · **[下载 GoScrcpy](https://github.com/wwangmc/GoScrcpy/releases/latest)** · **[编译工作流](https://github.com/wwangmc/PhoneVideoTweak/actions)**

## 功能

- H.264 视频：全屏采集后通过 VideoToolbox 编码，经 USBMux 传给 GoScrcpy。
- JPEG 截图：提供截图投屏方式及静态画面无变化响应。
- 触摸与按键：点击、单点拖动、Home、任务、电源、Enter/Tab。
- 文字输入：Unicode 文字、删除、左右光标，由独立键盘组件传递到当前应用。
- 设备信息和系统设置：屏幕尺寸、设备信息、语言、地区和时区。
- Shell 辅助：用于 GoScrcpy 的 OpenSSH 状态检测、安装页面跳转等请求。

从 0.2.0 起，插件独立包含 GoScrcpy main 所需的原 mks_tweak 功能，不要求同时安装 mks_tweak。GoScrcpy 仍保留旧插件兼容：优先连接 PhoneVideoTweak，新控制端口不可用时回退 mks_tweak `8081`。

一键地区设置**只操作系统语言、地区和时区**，不读写 GPT 应用配置，不处理运营商参数。

## 下载与安装

从 [Releases](https://github.com/wwangmc/PhoneVideoTweak/releases/latest) 下载一个与越狱环境匹配的 deb：

| 包类型 | 文件架构后缀 | 编译架构 | 最低 iOS |
| --- | --- | --- | --- |
| rootful | `iphoneos-arm.deb` | arm64 | 14 |
| rootless | `iphoneos-arm64.deb` | arm64、arm64e | 15 |
| RootHide | `iphoneos-arm64e.deb` | arm64、arm64e | 15 |

1. 根据实际越狱类型安装一个 deb，不能只按 CPU 名称选包。
2. 重启 SpringBoard；已运行的应用需要重新打开，才能加载键盘组件。
3. 电脑安装并运行 [GoScrcpy](https://github.com/wwangmc/GoScrcpy)，使用 USB 连接并信任电脑。
4. 在 GoScrcpy 中连接手机；投屏设置可选择截图或 USB H.264。

插件没有桌面图标。包名为 `com.phonemanager.phonevideo`。卸载后，GoScrcpy 仍可通过手机上已有的 mks_tweak 工作。

0.1.0 为视频专用版本，不含独立控制组件；需要本项目完整功能时使用 0.2.0+。

## 连接与组件

| 手机端口 | 用途 |
| --- | --- |
| `127.0.0.1:27184` | H.264 视频协议 |
| `127.0.0.1:27185` | HTTP API 与控制 WebSocket |

新服务只监听手机回环地址，由电脑通过 USBMux 连接，不依赖 Wi-Fi，不要求在电脑创建固定端口转发。

| 安装组件 | 作用 |
| --- | --- |
| `PhoneVideo.dylib` | 注入 SpringBoard，提供视频、截图和控制服务 |
| `PhoneVideoKeyboard.dylib` | 注入 UIKit 应用，接收文字、删除和光标操作 |
| `phonevideo-roothelp` | 执行 Shell 辅助命令的权限工具 |

键盘通知及自有类/函数使用 PhoneVideo 命名，辅助程序不覆盖旧插件的 `roothelp`。同一 API/投屏会话固定控制来源，失败命令不会跨插件重放。每台手机最多一个 H.264 视频客户端，断开后释放编码器和缓冲池。

文件管理继续依赖 iOS AFC/AFC2/共享应用文档服务，交互式 Shell 继续依赖 OpenSSH；本插件不会安装这两个服务。

## 控制 API

HTTP 和 WebSocket 使用 `27185`。HTTP 成功响应使用 `{"status":"success"}`，需要数据时带 `data` 字段；无变化截图返回 HTTP 204。

| 功能 | 接口 |
| --- | --- |
| 设备/屏幕信息 | `GET /deviceInfo?type=30`、`type=1` |
| 截图 | `GET /screenshot?quality=0.1`、`GET /screenshot_original` |
| 触摸 | `POST /touch`：`type` 为 down/move/up，坐标使用竖屏像素空间 |
| Home / 任务 / 电源 | `/pressHome`、`/doublePressHome`、`/pressPowerBtn` |
| 输入 / 按键 / 删除 / 光标 | `/input`、`/keypress`、`/del`、`/moveCursor` |
| 系统设置 | `POST /setAllSetting?timeZone=...&locale=...&lang=...`，JSON 对象请求体 |
| Shell 辅助 | `POST /runShell`，请求体 `{"cmd":"..."}` |

控制 WebSocket 位于 `/`，使用 `{"type":"...","data":...}` 消息，支持 `touch`、`inputText`、`backspace` 和 `moveCursor`。还保留设置查询、单项设置和键盘隐藏接口。

视频数据格式见 [协议说明](docs/PROTOCOL.md)。移植范围、改名与依赖库校验见 [源码来源](Sources/Control/PROVENANCE.md)。未加入 GoScrcpy main 未使用的定位、钥匙串、广告标识符和账号切换接口。

## 编译

GitHub Actions 在推送 main/master 或手动运行 **Build PhoneVideo packages** 后，为三种越狱类型生成 deb 和 SHA256。工作流使用 macOS、Xcode 16.4、RootHide Theos 和 iOS 16.5 SDK。

本地 macOS/Linux 需要对应 Theos 环境和 SDK，在仓库根目录执行：

```sh
make TYPE=0 ARCHS="arm64" clean package          # rootful
make TYPE=1 ARCHS="arm64 arm64e" clean package   # rootless
make TYPE=2 ARCHS="arm64 arm64e" clean package   # RootHide
```

RootHide 使用对应 Theos fork。产物位于 `packages/`，无需 Apple 开发者证书。

## 检查与排障

```sh
python3 Tests/check_control.py
clang -std=c11 -Wall -Wextra -Werror Tests/wire_test.c -o /tmp/phonevideo-wire-test
/tmp/phonevideo-wire-test
```

CI 会检查视频协议、控制依赖与库 SHA256，再编译所有组件。GoScrcpy 的测试覆盖多手机 USB、视频模式切换、旧插件回退、输入坐标及断开释放。

- 在手机日志中过滤 `[PhoneVideo]`，检查视频和控制端口是否启动。
- GoScrcpy 日志显示 `PhoneVideoTweak :27185` 表示使用新控制服务，`mks_tweak :8081` 表示旧服务回退；H.264 视频端口为 `27184`。
- 文字无法输入时，确认手机已聚焦输入框，并在安装后重新打开该应用。
- 本实现使用私有全屏采集，视频保持竖屏坐标；不同 iOS/越狱、屏幕旋转及受保护画面的效果需实际验证。60 FPS 是请求上限。

编译成功与协议测试通过不等于所有真机功能均已验证。新增控制组件仍需在目标手机上检查触摸、键盘、系统设置及重连。

## 来源

控制实现移植自 [mks_tweak](https://github.com/wwangmc/mks_tweak)，保留原作者声明。HID 源码保留 TrollVNC 的 GPL-2.0 声明，许可全文见 [GPL-2.0](licenses/GPL-2.0.txt)；HTTP/WebSocket 依赖保留 GCDWebServer 头文件中的许可证。具体文件与版本见 [PROVENANCE.md](Sources/Control/PROVENANCE.md)。
