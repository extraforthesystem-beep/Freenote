# Auto-Backup/Third-Party Backup Guide

Use Auto-Backup/Third-Party Backup to back up your notes to one of several cloud storage services.

This is a one-way backup. Deleting a note in Notability does not delete the backup copy. Similarly, deleting a backup does not delete the original note in Notability.

For a two-way sync across devices: [iCloud Syncing](https://intercom.help/notability/*/articles/16300116). If multiple devices are synced through iCloud, you can only use Auto-Backup/Third-Party Backup on one of them.

# Enable Auto-Backup/Third-Party Backup

1. In Notability's Library, tap ![](https://downloads.intercomcdn.com/i/o/qft13i0t/2638621380/2be3594bfc86831e5d0f4ee0f029/lib-btn-settings.png?expires=1794582000&amp;signature=922c5a2cb41d3655a4466d5037524da94547e8806dfd30eefce505953e944a4f&amp;req=diYkHs98nIJXWfMW3Hu4gW6DaHfoDLSg281a1PydNnUZMUwBgGA%2B%2FmFLNxhS%0AiQ%3D%3D%0A).

2. Tap **Connected Services**

3. Enable Auto-Backup/Third-Party Backup

4. Tap a cloud service to select it:

  - Box

  - Dropbox

  - Google Drive

  - OneDrive

  - WebDAV servers

5. Tap **Backup Off** to disable Auto-Backup/Third-Party Backup.

# Destination Folder

Backups go to a folder named **Notability** by default, but you can choose a different folder.

1. In Third-Party Backup's settings, tap **Destination**.

2. Navigate to the desired destination folder.

3. Tap **Back Up To [folder's name]**.

# Folders to Back Up

By default, Auto-Backup/Third-Party Backup does not back up password-protected notes. You can enable backups for password-protected notes and disable backups for other notes.

1. In Auto-Backup/Third-Party Backup's settings, tap **Folders to Back Up**.

2. Tap a folder to check or uncheck it.

3. If a folder is locked, type in its password and tap **OK**.

# File Format Options

You can back up your notes in one of several file formats.

1. In Auto-Backup/Third-Party Backup's settings, tap **File Format**.

2. Tap a format:

  - **Note**
This is Notability's custom file format. It includes audio recordings and keeps everything in a note editable if you import the file back into the app. This is a good way to share notes with others who use Notability.

  - **PDF**
To include background lines and colors, enable the **Paper** toggle after you select PDF as your file format. Bookmarks and audio recordings will not be included.

  - **PDF + Recording**
This makes .zip files that contain a PDF and a folder of .m4a audio files. This is a good way to share recordings with people who don't use Notability. Notability can't open .zip files, so you'll have to unzip them to import their contents back into Notability.

  - **RTF**
This is a good way to export typed text that you want to edit in another app.

  - **RTF + Recording**
This makes files that contain an RTF and a folder of .m4a audio files. Notability can't open .rtfd files, so you'll have to unzip them to import their contents back into Notability.

# Restoring Backups

Notability can't restore folders from a backup automatically, so they must be remade manually. You can import an entire folder of backup files into Notability at once by following [this guide](https://intercom.help/notability/*/articles/16300142).

# FAQ

**If I delete a note in Notability, is the backup copy deleted?**

No. The backup copy stays in your backup service.

**When are notes backed up?**

- When you enable Auto-Backup/Third-Party Backup or change its settings, all of your notes are backed up.

- When you edit a note and return to the Library, that note is backed up.

**Can notes be backed up to iCloud?**

Auto-Backup/Third-Party Backup only integrates with Box, Dropbox, Google Drive, OneDrive, and WebDAV servers. You cannot create a one-way Notability backup with iCloud. You can sync notes across multiple devices via iCloud Sync.