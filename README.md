# DigitZip

7-Zip-style **Extract Here** and **Extract to “name/”** in Finder's right-click menu on macOS.

## How it works

```
Finder right-click → DigitZipFinder (Finder Sync extension, sandboxed: just draws the menu)
                          │  digitzip://extract?mode=…&files=…
                          ▼
                     DigitZip.app (background app, no Dock icon) → bundled 7zz → notification
```

- **App/**: the background app. It receives requests, asks about passwords or existing files, and runs 7-Zip.
- **FinderExtension/**: the Finder Sync extension that adds the menu items.
- **Shared/**: archive-type rules and the request URL format, used by both.
- **project.yml**: the XcodeGen spec. `DigitZip.xcodeproj` is generated from it and isn't committed.

## Behaviour

- **Extract Here** extracts next to the archive. If items already exist, it asks: Keep Both / Replace / Skip Existing / Cancel.
- **Extract to “name/”** creates a new folder. If `name/` already exists, it uses `name 2/` and never overwrites.
- If several archives are selected, each one is extracted.
- Password-protected archives prompt for the password and retry if it's wrong.
- `.tar.gz`, `.tgz`, `.tar.xz` and similar unpack in one step, straight to the files.
- macOS metadata junk (`__MACOSX/`, `._*`) is skipped.

## Building

Requirements: Xcode, plus `brew install xcodegen sevenzip`.

```sh
scripts/build.sh            # generate project + build into ./build
scripts/build.sh --install  # also copy to ~/Applications and launch
```

Or run `xcodegen generate` and open `DigitZip.xcodeproj` in Xcode.

Signing: copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` (git-ignored) and set `DEVELOPMENT_TEAM` to your team ID. A free Personal Team from adding your Apple ID in Xcode → Settings → Accounts is enough for your own Mac.

Then turn on the extension in **System Settings → General → Login Items & Extensions → Finder**. Opening DigitZip.app shows whether it's on.

## License

DigitZip is released under the [MIT License](LICENSE).

### 7-Zip

DigitZip bundles the unmodified `7zz` binary from [7-Zip](https://www.7-zip.org) by Igor Pavlov. 7-Zip is licensed under the GNU LGPL with the unRAR restriction: the RAR code may be used to extract RAR archives but not to create a RAR compressor.
