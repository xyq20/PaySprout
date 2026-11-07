# PaySprout · 薪芽 v0.1.0

第一版桌面上班鼓励器，支持 macOS 与 Windows。

- 今日收入按日薪和班次进度累计，固定显示 4 位小数。
- 下班倒数、跨午夜班次、随进度成长的小薪芽和点击鼓励。
- 带薪充电计时与休息期间估算收入，下班收入封顶。
- 原窗口下班彩蛋、烟花预览与减少动态效果支持。
- 完整 / 紧凑模式、界面缩放、自定义大小、窗口置顶和菜单栏 / 托盘收起。
- 设置保存在本机，无需注册账号。

| 下载 | 系统要求 |
| --- | --- |
| `PaySprout-0.1.0-macOS-universal.dmg` | macOS 26+，Apple Silicon 与 Intel；拖入 Applications |
| `PaySprout-0.1.0-macOS-universal.zip` | 同上，解压后使用 |
| `PaySprout-0.1.0-Windows-x64.zip` | Windows 10/11 x64，完整解压后启动 `PaySprout.exe`；自带 .NET 10 运行时 |

首版尚无 Apple 开发者公证与 Windows 商业代码签名，系统可能提示未知发布者或阻止首次打开。请确认下载来自本仓库，并按安装包中的「首次打开说明」操作。发布附件 `SHA256SUMS.txt` 可用于校验文件完整性。

验证范围：Swift 生产模型测试、macOS 双架构编译与签名校验；Windows 47 项模型检查、Windows runner 中实际 WPF 发布包启动/界面交互检查及截图。未覆盖所有真实 Windows 设备、Intel Mac 实机和系统安全提示的人工验收。

收入含班次内休息时间，仅为估算，不代表实际工资结算；不区分工作日与节假日。
