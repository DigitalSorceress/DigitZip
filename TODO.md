# DigitZip TODO

## Next up

- [ ] tar.gz / tar.xz in Add to Archive… (needs a tar → gzip/xz pipeline)
- [ ] Pass passwords to 7zz without putting them on the command line (visible to `ps` while running)
- [ ] Progress and Cancel for big archives (creating and extracting)

## Later

- [ ] **Archive window (GUI)**
  - [ ] Open Archive: browse inside an archive like a folder, then extract selected items or drag them out
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
- [x] Add to Archive… dialog: name and editable folder, format (7z/zip/tar), level, split, update and path modes, Mac-junk and move-to-Trash options, encryption, plus Advanced (method, dictionary, word size, solid block, threads, parameters). Remembers settings.
- [x] Add to “name.zip” / “name.7z”: 7-Zip naming, never overwrites, skips macOS junk
