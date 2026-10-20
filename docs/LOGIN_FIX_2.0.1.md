# Pharmacy Hisab 2.0.1 - login fix

Install/update Pharmacy-Hisab-v2.0.1-Login-Fix.apk over the previous app. Do not clear app storage or uninstall to apply this update. The package and development signing key remain the same.

Fixed causes:
- Successful authentication could dispose the login page before pending code used its widget/provider references. The login flow now captures dependencies first and binds the authenticated device lock before continuing.
- A Firestore/cache error was treated as a login failure and explicitly signed the user out. Sync failures now preserve authentication and local PIN/fingerprint state.
- Serial per-register network reads blocked login and cold startup. Independent Firestore reads now run concurrently, and startup restores local state/PIN without waiting for remote data.
- Sync has a 15-second deadline, a clear Retry action, correct cache/no-cache messages, duplicate-refresh protection and stale-response protection after sign-out/session change.

Validation: all 22 Flutter tests passed, including seven new login/sync regression tests. Analyzer: no issues. Connected Android debug APK built as 2.0.1, versionCode 3. Physical-device installation/fingerprint verification was not executed because no Android device was connected. Existing financial posting rules and database records were not modified by this fix.

Manual retest: install Update, login once, complete PIN setup, wait for records, then close and reopen. Turn internet off and tap Retry: loading must stop within 15 seconds and the session must remain signed in. Restore internet and Retry again. The active user/store cache stays isolated and a delayed response cannot reload a signed-out workspace.
