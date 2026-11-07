# 合并上游作者更新

本 fork 在 `zhcn` 分支维护中文界面字符串。作者仓库为 `upstream`（仅拉取——不要推送）。

```text
git checkout zhcn
git fetch upstream
git merge upstream/main
# 解决冲突后继续使用 zhcn
```

不要执行 `git push upstream`。如需备份，请添加你自己的远程仓库。
