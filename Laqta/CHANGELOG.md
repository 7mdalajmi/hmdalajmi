# Laqta — Versions

The number in Settings → About is read from the bundle, never typed into a view.
So whatever it says under the wordmark is exactly what is running on the phone.

**The build number goes up with every fix.** `CURRENT_PROJECT_VERSION` is raised
by one whenever anything in the project changes — not only when a build is
uploaded. Raise it in the same edit as the fix, never afterwards, so a build can
always be told apart from the one before it.

**The version number goes up per store update.** `MARKETING_VERSION` steps one
place per release: `1.0 → 1.1 → 1.2 → …`. `2.0` is reserved for something the
people already using it would call a different app.

---

## v1.0

### build 7

Saving into a folder inside a folder straight from the share sheet, and a share
sheet that comes and goes faster.

- **Folders inside folders, from the share sheet.** "All Folders" lists the
  folders on Home, as Home does. A folder that holds folders says so ("2 folders
  · …") and is the only row with a chevron; a tap opens it in place, with the way
  back at the top, the folder itself as a "Save Here" card, the folders inside it,
  and "New Folder Inside". A folder with nothing inside saves at once, as before.
  Before, every folder sat in one flat list by date, so a subfolder turned up
  somewhere in the middle with nothing to say which folder it was in. The app's
  Import uses the same sheet and gets the same list. Private folders read "Locked"
  there instead of what they hold, as on Home.
- **It comes up alongside the system, in 0.3 s.** The card used to wait for
  `viewDidAppear`: the system's presentation ran first with nothing to see, then
  the card took another 0.42 s. It now starts rising in `viewWillAppear`.
- **A save never waits for the reading.** A folder tapped while the shot was still
  being analyzed was held until the analysis finished — on-device text reading,
  and a place lookup of up to 4 s per photo. It now saves the moment it is
  tapped; only items still being copied in hold it, and only until they are in.
  Anything saved before its analysis finished stays pending, and the app reads it,
  so nothing is lost.
- **It leaves sooner.** "Saved to …" stays 0.6 s instead of 1.3 s (1.2 s instead
  of 2.2 s when there is a line worth reading), a tap on it closes it at once, and
  the system's dismissal starts together with the card's slide, not after it.
- The folder counts arrive once the card has settled instead of during its motion,
  and until then a folder shows its date rather than "Empty".

### build 6

No code changed. Sixteen non-Swift files had gone missing from the project since
the backup taken before yesterday's round — every parent directory carries the
same 07:28 timestamp from this morning, long after that round ended, so iCloud's
re-sync removed them rather than anything in the project. Thirteen are restored
from that backup and md5-verified; the three left out are Xcode's own window
state, which it writes again on open.

- **The app icon is back.** `AppIcon.png`, `AppIcon-Dark.png`,
  `AppIcon-Tinted.png` and the `Contents.json` that names them had all gone, and
  so had `Assets.xcassets/Contents.json` and the whole `AccentColor.colorset` —
  an asset catalog with no manifest builds, silently, with no icon at all.
- **The three fonts are back.** `Amiri-Bold`, `CormorantGaramond-Bold` and
  `CormorantGaramond-SemiBold`. `UIAppFonts` in both Info.plists had survived and
  still names them, so without the files every folder title and every wordmark
  would have fallen back to the system font.
- **Both `PrivacyInfo.xcprivacy` files are back** — the upload is refused without
  them — and so are `Config/Laqta.storekit` (no local purchase testing without it)
  and the shared `Laqta.xcscheme` (no agreed scheme between the two Macs).

Only the resources went. Every one of the 105 Swift files survived, because they
live in folders Xcode synchronizes and are listed in the project; the resources
are the part iCloud drops first. From here the file tree gets compared against
the last pre-round backup at the end of every round, not just the files that round
touched.

### build 5

The five structural problems held back from the build 4 review, each found by
reading rather than by a crash.

- **A reminder could be dropped while it was still set.** Home's `comingUp` list
  applies the "show what's coming" switch, the lock filter and a cap of five —
  and `ReminderCenter.prune` was being handed that same shortened list, so it
  cancelled the scheduled notification for every dated shot below the cap, behind
  a lock, or hidden by the switch. The walk is split now: `allDated` is the
  unfiltered set and is what prune and the fingerprint see; `comingUp` is what the
  strip draws.
- **A tapped reminder now opens its shot.** Nothing was ever reading
  `UNUserNotificationCenter`'s delegate, so a notification tapped from the lock
  screen just opened Home, and one that fired while the app was open was never
  shown at all. `ReminderRouter` handles both, and a shot inside a locked folder
  opens that folder's gate instead of the shot.
- **The analysis cache no longer empties itself.** It had no bound, so it grew
  until the app was killed. It holds 4,000 entries and drops the oldest quarter
  when full, rather than clearing everything.
- **A trashed folder no longer takes a live item with it.** Deleting a folder for
  good walked its descendants and deleted every row under them, trashed or not.
  It now removes only the rows already in the trash, and keeps any folder that
  still holds something live.
- **A backup can no longer write outside its own folder.** File names come out of
  a backup manifest, and `../` in one would have been followed. Both the restore
  and the delete path check the name is a plain file name first.

### build 4

Found by a full read of all 105 source files. Each of these is a small, isolated
change; the structural ones from that review are deliberately not in this build.

- **A saved link could crash the app for good.** A web page declares its own video
  length in `og:video:duration`, and `Double("inf")` and `Double("nan")` both parse.
  `LaqtaFormat.duration` then did `max(0, Int(seconds.rounded()))` — but `Int(_:)`
  **traps** on a non-finite Double, before `max` ever runs. Saving such a link meant
  every later draw of that folder's grid crashed, the item could not be deleted from
  the UI, and with iCloud on it reached the other devices too. Clamped now at both
  ends: the parser refuses anything non-finite or longer than a week, and
  `duration`, `spokenDuration` and `travelTime` are total functions.
- **The share sheet stops loading columns it never reads.** `FolderStatsLoader.stats`
  fetched every live row whole — analysis blobs, OCR text, notes — inside a process
  with a hard memory limit. It now fetches the eight properties the counts and the
  cover actually use, the same list Home has always used.
- **Opening a photo no longer builds the whole folder.** The filmstrip was a plain
  `HStack`, so it created a thumbnail view — and started its load task — for every
  photo in the folder the moment the viewer opened. It is a `LazyHStack` now.
- **No more a save per swipe.** `markViewed` ran a synchronous `context.save()` the
  first time each photo was seen; each save refetched every live `@Query` and queued
  a CloudKit export. The main context autosaves, so the stamp is just set.

Note: build 3's changes ship in this build. The project file was reverted from 3 to
2 by iCloud between the edit and this one — see the working rule about keeping Xcode
closed on the second Mac.

### build 3

- **No dim behind the card at all.** The backdrop was painting black at 42%, which
  read as a haze over the app you shared from. It is now fully clear — the view
  stays only so a tap outside the sheet still cancels. `UIView` hit testing does
  not care about a clear background colour, so nothing is lost.
- The on-screen `sheet · library · folders` readout is gone. The marks still reach
  DebugLog in a Debug build, so the numbers are there if they are ever needed
  again; nothing is drawn on the sheet.

### build 2

- **Share sheet: the app you shared from is visible again.** Everything above the
  card was flat black. iOS presents an extension as a `pageSheet` by default —
  that is where the rounded corner at the top of the black came from — and the
  sheet's own backing is opaque, so a clear background on our view changed
  nothing. `modalPresentationStyle = .overFullScreen`, set in `init` because it
  has no effect once the system has presented us, plus clearing the view chain up
  to the window in `viewWillAppear` / `viewDidAppear`, lets the host app through
  at 42% dim.
- The card is a little taller as a result: 62% is now measured against the whole
  screen rather than against the system's sheet.

### build 1 — first release

The whole app: share a screenshot into Laqta, it reads what is inside, offers a
folder or takes the one you pick, turns a date it finds into a reminder the day
before, and locks anything important behind Face ID.

- Share Extension: opens on the bottom 62% of the screen, in the first frame
- On-device reading — text, places, prices, dates — nothing leaves the phone
- 56 cover moods, chosen from the folder's own name
- Folders, subfolders, locked folders
- Ask the library a question in plain words
- What's coming up, with a reminder a day early
- iCloud backup and restore
- Free for thirty days, then bought once

---

<!-- The next store update starts here.

## v1.1 — …

-->
