# 修复 ChatGPT Chrome 侧边栏连接

社区维护的 Codex skill，面向 Windows 桌面应用升级后出现的 Chrome 连接问题。**v0.2.1** · MIT · [English](README.md)

典型错误：`Codex app-server manifest entry is missing required path nodePath`。

## 适用环境

Windows x64、64 位 Windows PowerShell 5.1，以及包含 Chrome 插件的 `OpenAI.Codex` AppX 安装包。其他安装方式和 ARM64 不在本版支持范围内。这是社区修复工具；桌面应用未来变更内部结构时可能需要更新。

## 安装与使用

让 Codex 的 Skill Installer 安装仓库 `https://github.com/Francis-moon/repair-chatgpt-chrome` 的 `v0.2.1` 标签版本，然后输入 `$repair-chatgpt-chrome` 并描述错误。

也可以克隆该版本，从仓库目录手动运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Repair-ChatGPTChrome.ps1 -Mode Diagnose -Json
```

确认诊断结果并同意修复后：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Repair-ChatGPTChrome.ps1 -Mode Repair -Force -Json
```

修复后再次诊断，并在 Chrome 点击 **Try again** 或重新打开侧边栏。退出码 0 表示六项配置检查全部通过，1 表示检查失败，2 表示环境不支持或执行错误。配置检查通过后，还需要实际确认侧边栏能正常使用。

## v0.2.1 实测修正

修复 Windows PowerShell 5.1 调用安装器时丢失引号的问题，改用临时 UTF-8 模块文件执行，并增加真实 Node 调用测试。在一次中断修复中应用此修正后，六项检查全部通过，用户确认 Chrome 侧边栏恢复正常。此结果代表一次真实环境验证，不代表所有桌面版本均已验证。

## 可靠性改进

- JSON 损坏、字段缺失时仍能输出诊断结果。
- 识别仍然存在的旧运行时路径，避免误报正常。
- 修改前检查环境，遇到异常目录重定向、损坏清单或未知格式时停止。
- 健康环境跳过修复，防止多个修复同时运行。
- 保留旧缓存、配置备份、原注册表值和目录链接目标。
- 提供结构化输出、隔离回归测试和 Windows 自动验证。

脚本不会关闭 Chrome、删除浏览器资料或修改扩展源码。修复中断后可能需要根据备份手动恢复，本版不提供自动事务回滚。详见[故障与恢复说明](references/troubleshooting.md)。

## 反馈

请在 [Issues](https://github.com/Francis-moon/repair-chatgpt-chrome/issues) 提供版本、系统架构、失败检查项与脱敏后的错误。诊断 JSON 和备份包含本机路径，请勿原样公开上传。

本版测试使用临时目录与模拟系统信息，不能代表所有桌面版本均已完成真实浏览器验证。[参考方法与测试说明](references/design-sources.md)记录了设计依据。
