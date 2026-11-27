# DigitZip TODO

## Next up

- [ ] **Create archives from Finder.** In DigitZip ▸ on any files or folders:
  - [ ] Add to “name.zip”
  - [ ] Add to “name.7z”
  - [ ] Decide naming for multiple selections. 7-Zip on Windows uses the parent folder's name, e.g. “Archive.zip”.
  - [ ] Skip macOS junk when compressing (`.DS_Store`, `._*`, no `__MACOSX`)

- [ ] Set `AboutInfo.repositoryURL` once the GitHub repo is public

## Later

- [ ] **Archive window (GUI)**
  - [ ] Open Archive: browse inside an archive like a folder, then extract selected items or drag them out
  - [ ] Add to Archive…: a dialog with format, compression level, password and split size, like 7-Zip's “Add to archive” dialog
  - [ ] Show progress and allow cancelling for long extractions
- [ ] Menu items in DigitZip ▸ for the new features
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
- [x] About panel with credits
