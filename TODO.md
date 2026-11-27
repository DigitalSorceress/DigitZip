# DigitZip TODO

## Next up

- [ ] Password option when creating (likely part of the Add to Archive… dialog)
- [ ] Progress and Cancel for big archives (creating and extracting)

## Later

- [ ] **Archive window (GUI)**
  - [ ] Open Archive: browse inside an archive like a folder, then extract selected items or drag them out
  - [ ] Add to Archive…: a dialog with format, compression level, password and split size, like 7-Zip's “Add to archive” dialog
  - [ ] Show progress and allow canceling for long extractions
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
- [x] About panel with credits, author and source links
- [x] Add to “name.zip” / “name.7z”: 7-Zip naming, never overwrites, skips macOS junk
