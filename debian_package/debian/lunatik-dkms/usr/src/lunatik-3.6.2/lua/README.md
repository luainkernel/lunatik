# Lua in Kernel

This is a fork of the Lua repository. For more information about Lua in Kernel, visit the [Lunatik repository](https://github.com/luainkernel/lunatik).

Here is a small guide on how to keep track of upstream changes:
```
export VERSION_BRANCH="v5.4"
export HEAD="e0efebdbe4e4053c6fb78588c546f1dc23aa964a" #v5.4.7-rc2

git fetch upstream ${VERSION_BRANCH}
git fetch origin lunatik

git checkout ${VERSION_BRANCH}-kernel
git pull origin ${VERSION_BRANCH}-kernel

git rebase origin/lunatik

git checkout -b tmp/${VERSION_BRANCH}
git branch -f ${VERSION_BRANCH}-kernel upstream/${VERSION_BRANCH}
git rebase --onto tmp/${VERSION_BRANCH} ${HEAD}~1 ${VERSION_BRANCH}-kernel

git branch -D tmp/${VERSION_BRANCH}

git checkout lunatik
git merge --ff-only ${VERSION_BRANCH}-kernel
```
