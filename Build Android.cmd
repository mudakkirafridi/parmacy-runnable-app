@echo off

cd /d "%~dp0"

flutter build apk --release --dart-define-from-file=config/production.android.json

pause

