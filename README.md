# PaySprout · 薪芽

每一分努力，都在悄悄发芽。

A gentle desktop companion for macOS and Windows that tracks daily earnings and counts down to clock-out.

横版桌面悬浮小窗，暖白与鼠尾草绿配色，显示今日已赚、下班倒数和陪你成长的小薪芽。macOS 使用 SwiftUI，Windows 使用 WPF。设置只保存在本机，无需账号。

## 下载与启动

在 [Releases](https://github.com/xyq20/PaySprout/releases/latest) 下载首版 **v0.1.0**：

| 平台 | 下载文件 | 要求 / 启动方式 |
| --- | --- | --- |
| macOS | `PaySprout-0.1.0-macOS-universal.dmg` 或 `.zip` | macOS 26+，Apple Silicon / Intel；将「上班鼓励器.app」拖入 Applications |
| Windows | `PaySprout-0.1.0-Windows-x64.zip` | Windows 10/11 x64；完整解压后双击 `PaySprout.exe`；自带 .NET 运行时 |

首版未做 Apple 开发者公证或 Windows 商业代码签名，首次运行可能出现系统拦截。请核对官方仓库下载来源及发布页 `SHA256SUMS.txt`；具体打开步骤见 [Mac 说明](docs/INSTALL-macOS.txt) / [Windows 说明](docs/INSTALL-Windows.txt)。

以下交互说明主要以 Mac 为例。Windows 用 `Ctrl+,` 打开设置，托盘薪芽图标替代菜单栏太阳，双击托盘图标恢复；`Enter` 保存，`Esc` 取消。Windows 两种模式均可拖动右下角、通过 AA / 更多菜单选择缩放或自定义尺寸。两个平台分别使用系统原生控件，动画绘制与细节略有区别。

## 窗口与大小

- 顶部 **AA**：选择 80%、100%、120%、140% 大小；也可选择「自定义大小…」输入窗口宽高。
- 拖动窗口右下角的斜线手柄，可独立拉伸长宽。窗口边缘也支持原生缩放；拉宽后信息区会延展，缩小时文字会适配，并设有最小尺寸以避免裁切。
- 顶部 **收拢箭头**：进入紧凑模式，只显示小薪芽、已赚金额和下班进度；右侧展开按钮可返回完整模式。
- 紧凑模式的 **…**：打开设置、调整大小、收起或退出。
- 自定义尺寸和完整 / 紧凑模式自动保存在本机，两种模式分别记忆大小，重启后恢复。重新选择预设比例会重置当前模式的自定义尺寸。切换时保留窗口左上角位置，并尽量保持在当前屏幕可见区域。
- 完整模式按住顶部标题、标语或空白处拖动（右侧工具按钮除外）；紧凑模式按住窗口顶部留白处拖动。可拖动区域显示手形光标。
- **减号** 收起到菜单栏。点击菜单栏太阳图标可再次显示，也可以切换模式和大小；**×** 退出应用。

## 薪资与陪伴

顶部设置按钮（`⌘,`）可修改日薪和上下班时间。保存才生效，取消（`Esc`）或返回会丢弃草稿；`Return` 保存有效设置。支持 `⌘A/C/V/X` 文本编辑快捷键。

所有收入金额固定显示 **4 位小数**，主金额由独立的高频时钟匀速累计，速率固定为日薪除以班次秒数；控件、菜单和窗口拉伸不改变累计速率。显示保留 4 位小数，刷新频率仍取决于屏幕与系统调度。上班期间额外显示「每秒入账」估算。今日已赚按「日薪 × 班次已完成比例」估算，包含班次内的休息时间，不作实际工资结算。支持跨午夜班次，下班时间标注 `+1` / `次日`，跨夜班次结束后保留完成状态和收入直到下一次上班；不区分工作日和节假日。拒绝无效、负数、超出 10000000 的金额及相同的上下班时间。

小薪芽随真实上班进度变化：

- 上班前：闭眼蓄力，轻轻呼吸。
- 0–50%：发芽轻摆，25% 时长出第二片叶子。
- 50–85%：叶片舒展，身边出现轻盈光点。
- 85–100%：长出花苞，准备迎接下班。
- 下班后：开花、轻跳，点点星光作为今天的小奖励。

点击小薪芽仍可收下一句鼓励；动画和点击不会改变工资估算。系统开启「减少动态效果」时保留静态成长阶段，停止持续动画；窗口收起后暂停桌宠动画。使用原生矢量图形和 SF Symbols，不依赖网络字体或图片。

### 带薪充电

点击底部「带薪充电」后，小薪芽进入金色爆气形态：叶片和花盆变成金色，身后升起火焰状气场、电弧和上浮能量粒子。按钮同步变成金色的「爆气中 + 计时」，陪伴卡片变成暖金色。再次点击充电按钮结束休息，会收到休息时长和期间估算收入的小卡片。紧凑模式可在 **…** 菜单操作。休息计时不会暂停工资增长，也不会多计收入；跨过下班时间只计算到该班次结束。休息期间按开始时的日薪和班次计算；这次临时休息记录在退出应用后结束。

### 下班彩蛋

真实班次结束后，原窗口切换为深紫夜色、玫瑰微光与星点背景，烟花直接在页面中绽放约 12 秒。已赚金额变成玫瑰粉，原倒数区域变为下班祝福，小薪芽开花；庆祝不另开弹窗。同一班次自动庆祝一次；完整模式顶部的礼花按钮、紧凑模式 **…** 和菜单栏均可随时「预览下班彩蛋」。预览明确标注，可在原页面「结束预览」，不改变收入、班次进度或自动庆祝记录；也可点击「再放一次烟花」重播。

开启系统「减少动态效果」时，爆气形态和下班背景仍保留，持续动态停止；烟花显示为静态装饰。所有动画均无声，窗口收起后暂停。

## 从源码编译与检查

### macOS

需要安装 Xcode Command Line Tools（`xcode-select --install`），然后执行：

```sh
git clone https://github.com/xyq20/PaySprout.git
cd PaySprout
./scripts/build.sh --test --universal
open 'build/上班鼓励器.app'
```

构建脚本完成 Swift 编译与本地签名。若 Command Line Tools 同时含有两个 `SwiftBridging` 模块声明，会使用仅本次构建生效的临时文件映射，不修改系统工具链。`--test` 直接使用生产模型，检查上班前、开始、半程、结束、下班后与跨夜的进度、4 位小数格式、成长阶段、拉伸尺寸边界、内容适配，匀速增长、庆祝去重，以及跨下班时间的休息收益上限。

执行 `./scripts/package-macos.sh` 可生成通用 ZIP / DMG 到 `dist/`。

### Windows

安装 [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)，在仓库根目录执行：

```powershell
dotnet run --project Windows/PaySprout.Tests -c Release
dotnet run --project Windows/PaySprout.Windows
dotnet publish Windows/PaySprout.Windows -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o dist/windows
```

模型测试可在其他系统执行；WPF 应用需要 Windows 运行。GitHub Actions 在 Windows runner 中启动实际发布包，以 `--smoke-test` 检查收入显示、设置校验和保存、带薪充电、彩蛋预览、紧凑模式与收起恢复，并生成截图证据。此检查不等同于真实用户电脑上的兼容性测试。配置保存在 `%LOCALAPPDATA%\PaySprout\settings.json`，临时休息记录在退出后结束。

应用图标为原创图形；重新生成图标需安装 Pillow，再运行 `python3 scripts/generate-icons.py`。

设计参考：

- [Sheepo Desktop](https://apps.apple.com/us/app/sheepo-desktop-focus-break/id6754293545)：轻量桌面陪伴思路，小薪芽为本项目原创绘制。
- [Apple Layout](https://developer.apple.com/design/human-interface-guidelines/layout)：控件分组与视觉层次。
