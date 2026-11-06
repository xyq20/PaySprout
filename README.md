# PaySprout · 薪芽

每一分努力，都在悄悄发芽。

A gentle macOS desktop companion that tracks your daily earnings and counts down to clock-out.

原生 SwiftUI macOS 横版悬浮小窗，需要 Apple Silicon、macOS 26 或更新版本。暖白与鼠尾草绿配色，显示今日已赚、下班倒数和陪你成长的小薪芽。

首次使用请按下方「编译与检查」步骤构建，然后双击 `build/上班鼓励器.app` 启动。

## 窗口与大小

- 顶部 **AA**：选择 80%、100%、120%、140% 大小，文字、控件和窗口一起缩放。
- 顶部 **收拢箭头**：进入紧凑模式，只显示小薪芽、已赚金额和下班进度；右侧展开按钮可返回完整模式。
- 紧凑模式的 **…**：打开设置、调整大小、收起或退出。
- 大小和完整 / 紧凑模式自动保存在本机，重启后恢复。切换时保留窗口左上角位置，并尽量保持在当前屏幕可见区域。
- 完整模式拖动标题栏空白处；紧凑模式拖动窗口顶部留白处。
- **减号** 收起到菜单栏。点击菜单栏太阳图标可再次显示，也可以切换模式和大小；**×** 退出应用。

## 薪资与陪伴

顶部设置按钮（`⌘,`）可修改日薪和上下班时间。保存才生效，取消（`Esc`）或返回会丢弃草稿；`Return` 保存有效设置。支持 `⌘A/C/V/X` 文本编辑快捷键。

今日已赚按「日薪 × 班次已完成比例」估算，包含班次内的休息时间，不作实际工资结算。支持跨午夜班次，下班时间标注 `+1` / `次日`；不区分工作日和节假日。拒绝无效、负数、超出 10000000 的金额及相同的上下班时间。

点击小薪芽收下一句鼓励；发芽、半程、开花随实际班次进度变化，点击不会改变工资估算。尊重系统减少动态效果选项，使用原生矢量图形和 SF Symbols，不依赖网络字体或图片。

## 编译与检查

需要安装 Xcode Command Line Tools（`xcode-select --install`），然后执行：

```sh
git clone https://github.com/xyq20/PaySprout.git
cd PaySprout
./scripts/build.sh --test
open 'build/上班鼓励器.app'
```

构建脚本完成 Swift 编译与本地签名。若 Command Line Tools 同时含有两个 `SwiftBridging` 模块声明，会使用仅本次构建生效的临时文件映射，不修改系统工具链。`--test` 同时检查上班前、开始、半程、结束、下班后与跨夜的工资进度计算。

设计参考：

- [Sheepo Desktop](https://apps.apple.com/us/app/sheepo-desktop-focus-break/id6754293545)：轻量桌面陪伴思路，小薪芽为本项目原创绘制。
- [Apple Layout](https://developer.apple.com/design/human-interface-guidelines/layout)：控件分组与视觉层次。
