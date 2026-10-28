# Transaction attachments

Files: `app/lib/struct/uploadAttachment.dart` (pick/upload/download),
`app/lib/struct/selfHostedClient.dart` (authenticated HTTP and URL recognition),
`app/lib/pages/addTransactionPage.dart` (note links and preview),
`server/lib/src/attachments/attachment_routes.dart` (API). Storage layout and dataset
scoping: [../server/storage.md](../server/storage.md).

## Adding a file

The transaction notes area offers a camera photo, a gallery image, or a picked file (including
PDFs). The app reads the selected bytes, prefixes the filename with a local timestamp in
`yyyy-MM-dd-HHmmss` format, and sanitizes it to a bare URL-safe filename. It sends the bytes via
authenticated `PUT /attachments/<filename>` and appends the returned
`<serverUrl>/attachments/<filename>` URL to the transaction note. The link, not the file bytes,
travels with the transaction when notes sync to other devices.

Uploading requires a signed-in server session and a reachable server; there is no local attachment
queue or offline fallback. A cancelled pick adds no link. Upload errors are shown in a snackbar;
no link is added on failure. The timestamp reduces collisions but is only precise to the second,
so uploads with the same original filename in the same second can overwrite the same stored file.

## Storage and authorization

The server exposes `GET /attachments/list` and `PUT`, `GET`, `DELETE`
`/attachments/<filename>` behind Bearer-token authentication. Files are stored unchanged in the
`attachments/<datasetId>/` namespace: members of the same dataset can retrieve the same file,
whereas another dataset cannot. A download is served as `application/octet-stream`, with no
PDF conversion, thumbnail, or content-type-specific processing. See
[../server/api.md](../server/api.md) for the route inventory and
[../server/storage.md](../server/storage.md) for filename validation and deletion on account removal.

The server has a deletion endpoint, but the transaction form's **Remove** control only removes the
URL from the note. It does **not** call `DELETE /attachments/<filename>`; the stored bytes remain.
Conversely, a note link is not an independently managed attachment record: removing or editing
the text can disconnect the transaction from a file without deleting that file.

## Opening and previewing

Links extracted from the note appear as rows labeled with the URL's domain. A link recognized as
belonging to the currently signed-in server's `/attachments/` namespace also gets a photo-preview
button. Recognition is a prefix check against the current session's server URL; signed-out users,
links to another server, and ordinary links do not get this authenticated preview button.

The preview button fetches the bytes through `SelfHostedClient` with the session's Bearer token,
then passes them to Flutter's `Image.memory`. Images that the decoder accepts display in a bottom
sheet. A PDF is uploaded and downloaded just like any other file, but it is **not** rendered as a
PDF: image decoding fails and the sheet shows “failed to preview image” with an **Open link**
fallback. If the authenticated fetch itself fails, the app attempts to open the link directly.

Tapping the link row, or **Open link** after a preview error, calls `openUrl` in
`app/lib/functions.dart`: it launches the raw URL in an external application without the session
token or an `Authorization` header. The protected endpoint therefore normally returns `401` in
the browser. **Open link is not a working authenticated PDF-viewing path** on a standard deployment;
there is currently no in-app PDF viewer or authenticated external-file handoff. This limitation
also applies to other files that cannot be decoded as images.

---

Why the fork stores files on its own server rather than Google Drive:
`specs/03-stage-1-kill-google.md`. For the current file layout and household scope, use the
storage page linked above rather than the older stage specification.