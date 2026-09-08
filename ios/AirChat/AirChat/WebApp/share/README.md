# share/

Staging folder for things the embedded web server hands out to devices connected to this
phone. It lives inside `WebApp/` because that whole folder is a bundle **folder
reference**, so anything dropped here ships in the .app with no project-file change.

Served by the iOS host at `GET /download-app/<name>`:

| File | Who uses it |
| --- | --- |
| `AirChat.apk` | Android friends install the native app from the hotspot (mirrors the Android app serving its own package). |
| `AirChat-unsigned.ipa` | iPhone friends re-sign it with their own free Apple ID (Sideloadly / AltStore / SideStore). |
| `INSTALL.txt` | Plain-text version of the guide also rendered at `/install.html`. |

Nothing here is committed (`../../../.gitignore`); run `scripts/stage_artifacts.sh`
before a release build. `/download-app` falls back to the install guide when a file is
missing, so an empty folder is not an error.
