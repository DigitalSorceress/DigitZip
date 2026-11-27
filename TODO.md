# DigitZip TODO

## Next up

- [ ] **Create .tar.gz / .tgz / .tar.xz / .tar.bz2**
  - [ ] Add these formats to Add to Archive… (7zz can't do it in one step: tar → gzip/xz/bzip2 pipeline)
  - [ ] Maybe a quick “Add to name.tar.gz” menu item too
- [ ] Pass passwords to 7zz without putting them on the command line (visible to `ps` while running)

## Archive browser (“Open Archive”)

A window that shows an archive's contents like a Finder folder, similar to 7-Zip's File Manager.

- [ ] Browse folders inside the archive: name, size, packed size, modified date, encrypted flag
- [ ] Extract selected items, or drag them out to Finder
- [ ] Quick Look and open a single file (extract to a temp folder first)
- [ ] Password prompt for encrypted archives and encrypted file names
- [ ] Later: add, delete and rename inside the archive
- [ ] DigitZip ▸ **Open Archive** menu item
- [ ] **Double-click opens archives in DigitZip**
  - [ ] Declare archive document types (zip, 7z, rar, tar, gz…) in the app's Info.plist
  - [ ] Show in the Dock with a menu bar while a browser window is open, and go back to background-only after
  - [ ] Settings: “Make DigitZip the default for archives” button (macOS asks the user to confirm), and “Double-click: open in browser / extract like Archive Utility”

## Installing

- [ ] `scripts/build.sh --install` option to install to `/Applications` (shared by all users) as well as `~/Applications`
- [ ] Release build (optimized, not Debug) for everyday use
- [ ] Drag-to-install `.dmg` with an Applications shortcut, background image and app icon (see Distribution for signing and notarizing)
- [ ] Uninstall instructions: quit DigitZip, turn off the extension, delete the app, optionally `defaults delete com.digitalsorceress.DigitZip`
- [ ] Optional later: in-app update checks, e.g. Sparkle or checking GitHub Releases

## Later

- [ ] Settings: overwrite default (ask / keep both / replace), and whether to turn smart folder on or off
- [ ] App icon

## Distribution (if/when sharing it)

- [ ] Release build plus a signed and notarized download. Needs a paid Apple Developer account, or users have to approve the app manually.
- [ ] Ship the 7-Zip license text alongside the bundled `7zz`

## Done

- [x] DigitZip ▸ Extract Here / Extract to “name/” in Finder's right-click menu
- [x] Password prompt with retry
- [x] Keep Both / Replace / Skip when files already exist
- [x] One-step .tar.gz / .tgz / .tar.xz
- [x] Smart folder: no name/name/ doubling
- [x] About panel with credits, author and source links
- [x] Progress window with Cancel / Cancel All. It appears only for jobs longer than about 0.6 s, and canceled jobs clean up after themselves.
- [x] Add to Archive… dialog: name and editable folder, format (7z/zip/tar), level, split, update and path modes, Mac-junk and move-to-Trash options, encryption, plus Advanced (method, dictionary, word size, solid block, threads, parameters). Remembers settings.
- [x] Add to “name.zip” / “name.7z”: 7-Zip naming, never overwrites, skips macOS junk
