# PhoneVideoTweak

独立的越狱 iOS 投屏插件，为 GoScrcpy 提供 USB H.264 视频流。与 `mks_tweak` 同时安装；不修改、不链接、不替换 mks_tweak 的任何文件或接口。触摸、键盘、Home 等操作仍由电脑端通过原有 mks_tweak 接口完成。

当前是需要真机验证的实验实现，目标设备包括 iOS 15.6。源代码完成和 CI 编译通过都不等于已经验证实际画面、硬件编码状态或流畅度。

## 工作方式

```
SpringBoard 全屏采集 → IOSurface / CVPixelBuffer 池
                    → VideoToolbox H.264 → USBMux → GoScrcpy WebCodecs
电脑触摸/键盘       → USBMux → 原 mks_tweak :8081
```

- 只注入 SpringBoard。没有桌面图标或新界面。
- 手机视频服务绑定 `127.0.0.1:27184`，电脑通过 USBMux 直接打开该手机端口，不依赖 Wi-Fi，也不监听电脑的固定端口。
- 不生成 UIImage/JPEG；复用最多 3 个采集缓冲区。需要缩放时用复用的 Core Image 上下文，未缩放时直接提交采集缓冲区。
- 使用系统 VideoToolbox H.264 编码器、实时模式、Baseline、禁止帧重排，尝试关闭帧延迟；一次最多提交一帧，超时停止，避免形成无界帧队列。
- 每台手机最多一个视频客户端；不同手机拥有各自独立的 USB 连接。重复连接会被拒绝，不抢占已有投屏。
- 静态画面减少采集，每秒至少发送一帧。断开连接即释放编码器和缓冲池。
- 电脑端自动优先使用 PhoneVideo；未安装或端口打不开时继续使用原截图方式。端口已连接但插件启动失败会明确报错，避免误把截图当作 H.264 效果。

## GitHub Actions 编译

把**本项目目录作为独立 GitHub 仓库的根目录**推送。工作流必须位于仓库根目录下的 `.github/workflows/build.yml`，不要把整个 PhoneManager 或 mks_tweak 推上去。

1. 推送到 `main` / `master`，或在 Actions 中选择 **Build PhoneVideo packages → Run workflow**。
2. 工作流使用 macOS 15、Xcode 16.4、RootHide Theos 和 iOS 16.5 SDK，与 mks_tweak 的构建方式一致。
3. 完成后在该次运行的 Artifacts 下载适合越狱类型的包：

| Artifact | 架构 | 用途 |
| --- | --- | --- |
| `PhoneVideo-rootful` | arm64 | 传统有根环境，最低 iOS 14 |
| `PhoneVideo-rootless` | arm64、arm64e | rootless，最低 iOS 15 |
| `PhoneVideo-roothide` | arm64、arm64e | RootHide，最低 iOS 15 |

每个 Artifact 包含 deb 和 SHA256 校验值，构建日志单独保留 14 天。没有上传源码的第三方编译服务、不需要 Apple 开发者证书或 GitHub Secrets，也不在 CI 安装到手机。

在手机上用已有包管理器安装匹配的 deb，重启 SpringBoard，然后运行更新后的 GoScrcpy。保留原有 mks_tweak。插件包名为 `com.phonemanager.phonevideo`，卸载它即可恢复只使用截图。

本地已有 Theos 的 macOS / Linux 环境也可以执行：

```sh
make TYPE=1 ARCHS="arm64 arm64e" clean package
```

`TYPE=0` 为 rootful，`TYPE=1` 为 rootless，`TYPE=2` 为 RootHide。RootHide 使用对应 Theos fork。

## 真机验证

先以 30 FPS、4–8 Mbps、最长边 1280 或 1920 测试，再尝试 60 FPS。60 是请求上限，不是保证帧率。电脑端日志应出现 `PhoneVideo / USBMux → device :27184 / H.264`；若仍显示 `/screenshot?quality=0.1`，实际走的是截图回退。

检查主屏与应用画面、连续拖动、文字输入、Home、停止后重连、多台设备同时投屏。对比时使用相同分辨率、相同手机场景，同时观察窗口实际 FPS、拖动延迟、CPU 和手机温度。

在手机系统日志中过滤 `[PhoneVideo]`，可以看到端口启动、编码配置错误和连接结束后的发送帧率/码率。这里的 FPS 是发送吞吐量，不是电脑实际显示帧率。`global display capture unavailable`、`encoder create/prepare failed`、`encode timeout/error` 都表示尚未通过真机验证。

### 当前边界

- 使用私有 `CARenderServerRenderDisplay` 全局采集。不同 iOS / 越狱可能拒绝采集或返回黑屏，必须真机确认；DRM 等受保护画面不作保证。
- 保持与现有 mks_tweak 相同的竖屏坐标空间，尚未实现随系统旋转重新配置编码器。
- iOS 16.5 SDK 中硬件编码选择/查询常量对旧版 iOS 不可用，本实现不会直接链接这些仅限新版的符号。使用系统 H.264 编码路径，不能把设置成功视为已验证硬件编码状态。
- 这次只新增视频插件；单独安装它不提供输入控制，需要原有 mks_tweak。

## 协议 v1

全部多字节整数为大端。手机只接受一个 16 字节启动请求，之后只向电脑发送数据。

| 请求偏移 | 内容 |
| --- | --- |
| 0 | ASCII `PMV1`，4 字节 |
| 4 | uint32 最大 FPS，1–60 |
| 8 | uint32 码率，100000–100000000 bit/s |
| 12 | uint32 最长边，0 为原始尺寸，其他值 64–8192 |

响应先发送 76 字节元数据：64 字节 UTF-8 设备名称（NUL 补齐）、4 字节 `h264`、uint32 宽、uint32 高。之后每包是 12 字节头和 Annex B 负载：uint64 时间戳/标志 + uint32 长度，最高位表示 SPS/PPS 配置，次高位表示关键帧，低 62 位是连接起始后的微秒时间戳。负载限制 16 MiB，与 GoScrcpy / scrcpy 解码包格式兼容。

`Tests/wire_test.c` 在 CI 直接测试与插件共用的协议编码、非法请求和 AVCC → Annex B 边界；GoScrcpy 中的集成测试覆盖双手机 USB 视频、原有输入连接、缩放坐标、断线释放和旧版回退。
