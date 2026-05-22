# ===== Git Push Script - Ash Pure ERP =====
# Run this file in PowerShell inside the project folder

Set-Location "e:\New folder (2)"

Write-Host "=== Staging all changes ===" -ForegroundColor Cyan
git add -A

Write-Host "`n=== Committing ===" -ForegroundColor Cyan
git commit -m "feat: Full Responsive PWA Refactor - Mobile Sidebar Drawer, Bottom Sheet POS Cart, Responsive Tables to Cards, Print Media Queries, Service Worker and Manifest"

Write-Host "`n=== Setting remote URL with token ===" -ForegroundColor Cyan
git remote set-url origin https://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@github.com/mohandhassan22/Ash.git

Write-Host "`n=== Pushing to GitHub ===" -ForegroundColor Cyan
git push origin main
if ($LASTEXITCODE -ne 0) {
    Write-Host "Trying 'master' branch..." -ForegroundColor Yellow
    git push origin master
}

Write-Host "`n=== Done! ===" -ForegroundColor Green
