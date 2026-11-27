# DigitZip

7-Zip-style archive tools in the macOS Finder's right-click menu: **Extract Here**, **Extract to “name/”**, quick **Add to “name.7z” / “name.zip”**, and a full **Add to Archive…** dialog. It's powered by the official [7-Zip](https://www.7-zip.org) engine.

Created and maintained by [DigitalSorceress](https://digitalsorceress.com). DigitZip is an independent project, not affiliated with or endorsed by 7-Zip.

## The menu

Right-click files, folders or archives in Finder and open **DigitZip ▸**:

```
DigitZip ▸   Extract Here                  ← archives only
             Extract to "Holiday Photos/"  ← archives only
             ──────────────
             Add to Archive…               ← options dialog
             Add to "Holiday Photos.7z"    ← quick, no dialog
             Add to "Holiday Photos.zip"   ← quick, no dialog
             ──────────────
             About DigitZip
```

## Extracting

- **Extract Here** extracts next to the archive. If items already exist, it asks: Keep Both / Replace / Skip Existing / Cancel.
- **Extract to “name/”** creates a new folder. If `name/` already exists, it uses `name 2/` and never overwrites.
  - **Smart folder:** if the archive contains exactly one folder, that folder's contents go straight into `name/`, with no `name/name/` doubling. If it contains loose files, they're gathered into `name/`.
- If several archives are selected, each one is extracted.
- Password-protected archives prompt for the password and retry if it's wrong.
- `.tar.gz`, `.tgz`, `.tar.xz` and similar unpack in one step, straight to the files.
- macOS metadata junk (`__MACOSX/`, `._*`) is skipped.
- Supported formats include zip, 7z, rar, tar, gz, bz2, xz, zst, cab, iso, and split archives (`.001`, `.part1.rar`).

## Creating archives

### Quick: Add to “name.7z” / “name.zip”

One click, no questions, using 7-Zip's default settings.

- **Naming follows 7-Zip:** one file gives `report.zip` (extension dropped), one folder gives `Holiday Photos.zip`, and several items are named after the folder they're in.
- It never overwrites. If the name is taken, you get `name 2.zip`.
- `.DS_Store` and `._*` files are left out.
- It isn't offered when a single archive is selected, since that would read as "add into this archive". Use **Add to Archive…** for that.

### Add to Archive…

A Mac version of 7-Zip's “Add to Archive” dialog.

- **Archive name and folder.** The folder is an editable path (`~` works) with a **…** browse button. If you type a folder that doesn't exist, it offers to create it.
- **Format:** 7z, zip or tar. Changing the format updates the name's extension.
- **Compression level:** Store, Fastest, Fast, Normal, Maximum or Ultra.
- **Split into volumes:** type a size like `100M`, or pick a preset (CD, DVD, FAT, Blu-ray). This produces `name.7z.001`, `.002`, and so on.
- **Update mode:** add and replace, update and add, freshen, or synchronize. These apply when the archive already exists, and the button then says **Update**.
- **Path mode:** relative, full or absolute paths.
- **Options:**
  - Leave out macOS junk, on by default.
  - Move originals to Trash afterward. This is 7-Zip's “delete files after compression”, but you can undo it.
- **Encryption:** password with confirmation, and a show-password option.
  - 7z uses AES-256 and can encrypt file names, too.
  - For zip you choose between ZipCrypto and AES-256. ZipCrypto opens anywhere but is weak. AES-256 is strong, but macOS Archive Utility and Windows Explorer can't open it.
- **Advanced ▸** (collapsed by default): compression method, dictionary size, word size, solid block size, CPU threads, and extra 7-Zip parameters. Options that don't apply to the chosen format are grayed out.
- Your settings are remembered between uses. Passwords are not.

## Progress and canceling

Jobs that take more than a moment show a small floating window. It shows the file being worked on, a progress bar, and **Cancel**. When several jobs are queued, it shows "2 of 5" and the button becomes **Cancel All**. Quick jobs never flash the window.

What canceling leaves behind:
- **Extract to “name/”:** nothing. The temporary folder is removed.
- **Extract Here:** files already extracted stay, as in 7-Zip.
- **New archive (quick Add to, or Add to Archive…):** nothing. No partial archive or volumes are left.
- **Updating an existing archive:** the archive is left exactly as it was before.

## Installing and building

Requirements: macOS 14 or later, Xcode, and `brew install xcodegen sevenzip`.

```sh
scripts/build.sh            # generate the Xcode project and build into ./build
scripts/build.sh --install  # also install to ~/Applications and launch it
```

Or run `xcodegen generate` and open `DigitZip.xcodeproj` in Xcode. Edit `project.yml`, not the generated project.

**Signing:** copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` (git-ignored) and choose one option:
- your Apple Development team ID, or
- a code-signing certificate you created yourself in Keychain Access. `build.sh` signs with `codesign` directly, because Xcode rejects self-made certificates.

Either works for running DigitZip on your own Mac.

**Turn on the extension:** go to **System Settings → General → Login Items & Extensions**, find the Finder section, and turn on **DigitZip**. Opening DigitZip.app shows whether it's on, and has a button that takes you there.

### Troubleshooting

- **The DigitZip menu is missing or outdated:** relaunch Finder. Option-right-click Finder in the Dock and choose **Relaunch**, or run `killall Finder`.
- **No “Extracted…” notifications:** go to **System Settings → Notifications → DigitZip** and turn on **Allow Notifications**.
- **"DigitZip would like to access files in…":** the first time you use it in Desktop, Documents or Downloads, macOS asks for permission once. Click Allow.
- **Logs:** `log show --last 10m --info --predicate 'subsystem == "com.digitalsorceress.DigitZip"'`

## How it works

```
Finder right-click → DigitZipFinder (Finder Sync extension, sandboxed: only draws the menu)
                          │  digitzip://extract | compress | add-dialog | about
                          ▼
                     DigitZip.app (background app, no Dock icon)
                          → job queue → bundled 7zz → notification
```

- **App/**: the background app. It runs extract and compress jobs one at a time, shows the Add to Archive dialog, and asks about passwords and existing files.
- **FinderExtension/**: the Finder Sync extension that builds the **DigitZip ▸** menu.
- **Shared/**: archive-type rules, naming, and the request URL format, used by both.
- **project.yml**: the XcodeGen spec.

The app quits by itself about 30 seconds after its last job. Work in progress is written to hidden temporary files and renamed when complete, so half-finished archives or folders never appear.

See [TODO.md](TODO.md) for what's planned next.

## License

DigitZip is released under the [MIT License](LICENSE).

### 7-Zip

DigitZip bundles the unmodified `7zz` binary from [7-Zip](https://www.7-zip.org) by Igor Pavlov. 7-Zip is licensed under the GNU LGPL with the unRAR restriction: the RAR code may be used to extract RAR archives but not to create a RAR compressor.
