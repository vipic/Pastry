# Pastry

macOS 剪贴板管理工具

![macOS](https://img.shields.io/badge/macOS-26.0-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/License-MIT-green)


## 简而言之

Vibe 的产物，但细节是经过打磨的，基本上每个点都是 "开发-使用-调优” 这么迭代而来的。因为比较喜欢 [Paste](https://pasteapp.io/)，所以参考了对方的布局，功能是按需个人需要开发的。还是开头所说，Vibe 来的，产物不重要，过程挺重要，加上个人感觉最终产物也不是一点价值没有，有兴趣的可以让自己的 Agent 继续开发使用。欢迎 Star 支持。

以下内容均为 LLM 生成，经过人工校对修正。

## 特性

基本符合记录了历史剪贴板，后续可以调用查看。添加收藏也能额外补充个备注，记录添加的原因。不建议常用的内容都放在剪贴板的收藏里面，常用的东西还是放在文本扩展软件比较好，作者另外一个软件 [TextFlash](https://github.com/vipic/TextFlash) 就是实现这个的，也有一些动态指令等，有需求可以查看。

## 构建

开发版一键部署：

```bash
git clone https://github.com/vipic/Pastry.git
cd Pastry
./deploy.sh
```

这会编译 debug 版本、组装并签名 `~/Applications/Pastry Dev.app`，然后启动应用。

需要生成可安装的 DMG 时使用：

```bash
./release.sh 1.2.3
```

之后双击 `dist/Pastry-1.2.3.dmg`，将 `Pastry.app` 拖入 `/Applications`。

发布流程见 [RELEASE.md](RELEASE.md)。

本机冒烟检查：

```bash
./smoke.sh
```

脚本会部署开发版、填充剪贴板样本、唤出面板并把截图和日志保存到 `dist/smoke/`。它不进 CI，适合发布前人工确认菜单栏、面板和卡片行为。

测试命令速查见 [docs/TESTING.md](docs/TESTING.md)。如果使用 `mise`，统一入口见 [docs/MISE.md](docs/MISE.md)：

```bash
mise run check
mise run deploy
mise run release-auto
```

不依赖第三方包管理下载；SQLCipher 静态库已 vendored 到仓库内。仅支持 macOS 26+ (至少作者的要求是这样)。

> **首次编译须知**：macOS 的辅助功能权限绑定到应用签名。Pastry 必须使用稳定代码签名：自签名代码签名证书或开发者账号证书都可以；不要使用 ad-hoc 签名。ad-hoc 每次重新编译都可能改变代码身份，导致辅助功能授权反复失效，使用体验非常差。解决方法是创建或复用一张作者级自签名证书：
> ```
> Keychain Access → 证书助理 → 创建证书
> 名称: Nekutai(名称由使用者定义)  |  身份类型: 自签名根  |  证书类型: 代码签名
> export CODESIGN_IDENTITY="Nekutai"
> ```
> 之后 `./deploy.sh` 和 `./release.sh` 都会使用同一张证书签名，辅助功能和钥匙串授权会跟随稳定的代码身份保留。脚本默认使用 `Nekutai`，也可以通过 `CODESIGN_IDENTITY` 改成你自己的自签名或开发者账号证书名；如果证书不存在或签名失败，脚本会直接停止。
>
> 这不是 Pastry 特有的问题，所有从源码编译的 macOS 应用都面临这个限制——Apple 的安全模型要求 TCC 权限绑定到固定的代码身份。

## 快捷键

- 默认 Command(⌘)+ Shift(⇧) + V，也可在设置中修改
- Command (⌘) + F 也可以打开搜索栏，键入任意非修饰键也会打开
- Command (⌘) + 数字(1-9) 可以快速将对应位置的卡片应用到当前活跃的程序
- 左右上下光标可以移动选中卡片，回车可以应用当前卡片，Delete 可以删除当前卡片。多选 Delete 会删除多个条目，但是 Enter 只会应用首个条目
- 右键菜单可以预览对应卡片，如果是文件也可以打开对应文件位置


## 项目结构

```
Sources/Pastry/
├── Core/           # ClipboardItem 模型、剪贴板监听
├── Persistence/    # SQLite 数据库、StoreManager
├── UI/             # 面板、卡片、菜单、预览
└── Utils/          # 热键、图标、常量
```

完整架构说明见 [AGENTS.md](AGENTS.md)。

## 许可

MIT © [vipic](https://github.com/vipic)
