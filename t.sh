echo "========== ACTIVE ACCOUNT =========="
cat account.name

echo
echo "========== OUTER .git =========="
echo "--- HEAD ---"
git --git-dir="$PWD/.git" symbolic-ref -q HEAD || \
git --git-dir="$PWD/.git" rev-parse HEAD

echo "--- REMOTES ---"
git --git-dir="$PWD/.git" remote -v

echo "--- BRANCHES ---"
git --git-dir="$PWD/.git" branch -a

echo "--- LAST 5 COMMITS ---"
git --git-dir="$PWD/.git" log --oneline --decorate -5

echo
echo "========== INNER .git =========="
echo "--- HEAD ---"
git --git-dir="$PWD/.git/.git" symbolic-ref -q HEAD || \
git --git-dir="$PWD/.git/.git" rev-parse HEAD

echo "--- REMOTES ---"
git --git-dir="$PWD/.git/.git" remote -v

echo "--- BRANCHES ---"
git --git-dir="$PWD/.git/.git" branch -a

echo "--- LAST 5 COMMITS ---"
git --git-dir="$PWD/.git/.git" log --oneline --decorate -5
