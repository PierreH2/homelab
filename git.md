```bash
gh auth login
git remote add origin git@github.com:PierreH2/X.git
gh repo create name --public --source=. --remote=origin
git branch -M main
git push -u origin main
```