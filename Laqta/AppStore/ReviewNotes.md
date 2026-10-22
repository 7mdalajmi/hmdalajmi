# App Review Information — Laqta 1.0

Paste into App Store Connect → Version 1.0 → App Review Information → Notes.

---

Laqta has no account or sign-in. It starts with an empty library.

HOW TO TRY IT
1. Tap Import (bottom of the home screen) and pick a few photos, a video or a PDF, or paste a web link in the Link tab. Choose a suggested folder and tap Save.
2. The share extension: in Photos or Safari tap Share → Laqta (it may be under More). The same Save to Laqta sheet appears.
3. Open an item and tap the sparkles button to see what Laqta found (text, dates, places). Summaries need Apple Intelligence; without it Laqta shows a simpler reading.
4. Private folders: create a folder and turn on "Lock with Face ID".

FEATURES THAT NEED EXPLAINING
• "Delete original from Photos" is off unless the user turns it on. Deletion always goes through the iOS confirmation dialog, and deleted photos go to the Photos Recently Deleted album.
• YouTube links: Laqta reads a video's title, channel and thumbnail from YouTube's public oEmbed endpoint (no API key, no sign-in) and opens YouTube to watch. It never downloads or plays YouTube media and never stores thumbnails.
• iCloud Sync and iCloud Backups are optional (Settings → iCloud). They use the user's private CloudKit database and the app's iCloud Drive container.
• Background tasks (BGProcessingTask and BGContinuedProcessingTask) empty Recently Deleted, finish analysis, load details for YouTube links saved offline and run scheduled backups. A long backup started by the user shows the system progress UI.
• Location is requested only when the user asks for travel time to a place.
• Camera is used only by the document scanner (Import → Files → Scan Documents).

PRIVACY
Laqta doesn't collect data. Analysis runs on device with Apple frameworks. See Settings → About → Privacy Policy.
