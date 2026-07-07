# 本地修改版构建与运行

这份说明针对当前本地修改版 CodexIsland。这个版本在原项目基础上增加了键盘控制：

- 单按 `Option`：呼出或收回 CodexIsland。
- 展开状态下按 `Left` / `Right`：切换上一页 / 下一页。
- 展开状态下按 `Space`：刷新当前页面数据。
- 展开时会临时聚焦 CodexIsland 以接收 `Space` 和方向键；收回后会尝试恢复到之前的前台应用。

## 构建并安装到 Applications

在仓库目录运行：

```sh
cd /Users/uqxqiao2/Documents/Codex/2026-07-04/providers-md-https-github-com-steipete/codex-island
pkill -x CodexIsland || true
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" ./build.sh
rm -rf /Applications/CodexIsland.app
cp -R build/CodexIsland.app /Applications/CodexIsland.app
xattr -dr com.apple.quarantine /Applications/CodexIsland.app 2>/dev/null || true
open /Applications/CodexIsland.app
```

`CLANG_MODULE_CACHE_PATH` 把 Swift/Clang 模块缓存放到项目目录，避免某些受限环境不能写 `~/.cache/clang`。

## 带调试日志运行

如果要看 `Option`、方向键、空格键的触发日志，用这个命令启动：

```sh
cd /Users/uqxqiao2/Documents/Codex/2026-07-04/providers-md-https-github-com-steipete/codex-island
pkill -x CodexIsland || true
CODEX_ISLAND_INPUT_DEBUG=1 /Applications/CodexIsland.app/Contents/MacOS/CodexIsland
```

配合系统日志过滤：

```sh
/usr/bin/log stream --style syslog --info --predicate 'process == "CodexIsland" && (eventMessage CONTAINS[c] "InputMonitor" || eventMessage CONTAINS[c] "InputState" || eventMessage CONTAINS[c] "OptionToggle" || eventMessage CONTAINS[c] "OverlayAction" || eventMessage CONTAINS[c] "Focus")'
```

## 推到自己的 GitHub 仓库

先在 GitHub 上创建一个空仓库，例如：

```text
git@github.com:<your-user>/codex-island.git
```

然后在本地设置 remote 并推送：

```sh
cd /Users/uqxqiao2/Documents/Codex/2026-07-04/providers-md-https-github-com-steipete/codex-island
git status --short
git add Sources/Window/IslandWindowController.swift Sources/Views/IslandRootView.swift README.zh-CN.md docs/LOCAL_BUILD_AND_RUN.zh-CN.md
git commit -m "Add keyboard controls for CodexIsland"
git remote rename origin upstream
git remote add origin git@github.com:<your-user>/codex-island.git
git push -u origin main
```

如果你的 GitHub remote 使用 HTTPS，把最后两行换成：

```sh
git remote add origin https://github.com/<your-user>/codex-island.git
git push -u origin main
```

如果已经有自己的 remote，不要重复 `remote add`，改用：

```sh
git remote set-url origin git@github.com:<your-user>/codex-island.git
git push -u origin main
```

## 重新从自己的仓库拉取

```sh
git clone git@github.com:<your-user>/codex-island.git
cd codex-island
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" ./build.sh
open build/CodexIsland.app
```
