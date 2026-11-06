# 缓芽 Windows 版

适用于 Windows 11 x64（Intel / AMD 64 位）。提供喝水、护眼、起身活动提醒，以及作息计划和健康统计。

当前版本为 **2.0.0 Preview 1**，尚未完成 Windows 实机兼容性验证，未提供数字签名。

[下载预览版](https://github.com/goseeen/huanya/releases/tag/windows-v2.0.0-preview.1) · [反馈问题](https://github.com/goseeen/huanya/issues)

## 功能

- 喝水、护眼、拉伸独立提醒，自定义间隔与休息时长。
- 提前预告、合并提醒、延后、跳过、手动暂停和忙碌模式。
- 每周分段作息、长休息、固定时间提醒。
- 饮水快捷记录与撤销，拉伸动作卡片自动和手动切换。
- 今日统计、周月回顾、小时图表、记录更正及 CSV 导出。
- 系统托盘、通知、全局快捷键、开机启动、指定前台应用和空闲暂停。

休息倒计时结束后，确认完成才计入统计。使用时长为估算，不监测实际坐姿。

## 使用

下载 ZIP 后完整解压，双击 `Huanya.exe`。程序已包含运行环境，无需另装 .NET。关闭窗口后继续在系统托盘运行；完全退出请使用托盘菜单「退出缓芽」。

全局快捷键可在设置中开启：

| 快捷键 | 操作 |
| --- | --- |
| `Ctrl + Alt + Shift + W` | 记录默认杯量 |
| `Ctrl + Alt + Shift + R` | 开始拉伸休息 |

指定应用暂停按可执行文件路径匹配：应用处于前台时保留剩余时间，切换离开后继续倒计时。应用安装路径改变后需重新选择。该功能不检测会议状态。

## 数据与更新

设置和记录保存在 `%LOCALAPPDATA%\Huanya\state.json`。保存时保留上一份 `state.json.bak`；读取失败不会覆盖原文件。可在设置中备份全部记录或导出每日统计。

更新前先从托盘退出，再替换完整程序文件夹，保留数据目录。暂不支持从 Mac 版一键迁移数据。

## 从源码构建

使用 .NET 10 SDK，在仓库根目录执行：

```sh
dotnet run --project Windows/Huanya.Tests -c Release
dotnet run --project Windows/Huanya.Desktop
```

Windows x64 打包：

```powershell
powershell -File Windows/scripts/publish.ps1 -Runtime win-x64
```

macOS / Linux 交叉构建：

```sh
sh Windows/scripts/publish.sh win-x64
```

输出目录为 `dist/windows`，包含 ZIP 和 SHA-256 校验文件。构建脚本支持指定其他架构，但当前仅提供 x64 预览包。

使用演示数据预览界面：

```sh
dotnet run --project Windows/Huanya.Desktop -- --preview
dotnet run --project Windows/Huanya.Tests -c Release -- --ui --screenshots .build/windows-ui
```

演示模式不读取或保存个人记录，不注册通知、快捷键或启动项。非 Windows 系统只运行演示模式。

## 代码结构与许可

- `Huanya.Core`：计时规则、作息计划、统计和数据存储。
- `Huanya.Desktop`：界面与 Windows 系统集成。
- `Huanya.Tests`：功能回归测试与界面检查。

使用 C#、.NET 10 和 Avalonia。项目代码与自制图形采用 MIT 许可；第三方依赖与声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
