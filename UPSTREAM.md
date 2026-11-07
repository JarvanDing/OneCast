# Merging author updates

This fork keeps Chinese UI strings in the `zhcn` branch. The author's repository is `upstream` (fetch only — do not push).

```text
git checkout zhcn
git fetch upstream
git merge upstream/main
# Resolve conflicts, then keep using zhcn
```

Do not run `git push upstream`. Add your own remote if you want a backup.
