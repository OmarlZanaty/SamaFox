# G2 — direct-download APKs

Drop the release APK here and the `/download.html` page picks it up on its own.

```bash
cd app
./build-release.sh apk
cp build/app/outputs/flutter-apk/app-release.apk \
   ../backend/public/downloads/samafox-1.0.18.apk
```

Name it `samafox-<version>.apk`. The newest file by modification time is the one
served, so an older build left behind is harmless — but delete it anyway to keep
the folder honest.

APKs are gitignored: they are build output, not source.
