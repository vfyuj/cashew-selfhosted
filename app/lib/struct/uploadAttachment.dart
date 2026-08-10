import 'dart:io';
import 'package:cashew_selfhosted/struct/selfHostedClient.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/globalSnackbar.dart';
import 'package:cashew_selfhosted/widgets/openPopup.dart';
import 'package:cashew_selfhosted/widgets/openSnackbar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

/// Transaction attachments, stored on this fork's own server instead of the
/// user's Google Drive. See specs/03-stage-1-kill-google.md.
///
/// Same contract as the Drive version it replaces: pick a file, upload it,
/// return a URL string that the caller appends to the transaction note. The
/// URL needs the session to fetch (as the Drive link needed a Google login),
/// so the preview in addTransactionPage reads it back through the client.

Future<String?> getPhotoAndUpload({required ImageSource source}) async {
  dynamic result = await openLoadingPopupTryCatch(() async {
    final ImagePicker picker = ImagePicker();
    final XFile? photo = await picker.pickImage(source: source);
    if (photo == null) {
      if (source == ImageSource.camera) throw ("no-photo-taken".tr());
      if (source == ImageSource.gallery) throw ("no-file-selected".tr());
      throw ("error-getting-photo");
    }
    return await uploadAttachmentToServer(
      fileBytes: await photo.readAsBytes(),
      fileName: photo.name,
    );
  }, onError: (e) {
    _reportAttachmentError(e);
  });
  if (result is String) return result;
  return null;
}

Future<String?> getFileAndUpload() async {
  dynamic result = await openLoadingPopupTryCatch(() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null) throw ("no-file-selected".tr());

    Uint8List fileBytes;
    if (kIsWeb) {
      fileBytes = result.files.single.bytes!;
    } else {
      File file = File(result.files.single.path ?? "");
      fileBytes = await file.readAsBytes();
    }

    return await uploadAttachmentToServer(
      fileBytes: fileBytes,
      fileName: result.files.single.name,
    );
  }, onError: (e) {
    _reportAttachmentError(e);
  });
  if (result is String) return result;
  return null;
}

void _reportAttachmentError(dynamic e) {
  openSnackbar(
    SnackbarMessage(
      title: "error-attaching-file".tr(),
      description: e.toString(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.error_outlined
          : Icons.error_rounded,
    ),
  );
}

/// Uploads to the signed-in server's attachment namespace and returns the URL
/// to record in the note. Throws when signed out -- unlike sync, there is no
/// sensible local fallback for "put this file somewhere the other device can
/// see it", so the user is told rather than silently losing the attachment.
Future<String> uploadAttachmentToServer({
  required Uint8List fileBytes,
  required String fileName,
}) async {
  // Timestamp prefix mirrors the Drive naming, and keeps two receipts picked
  // with the same camera-assigned name from overwriting each other.
  final String timestamp =
      DateFormat("yyyy-MM-dd-HHmmss").format(DateTime.now());
  final String storedName = _sanitizeFilename("$timestamp-$fileName");

  try {
    return await uploadAttachmentBytes(storedName, fileBytes);
  } on SelfHostedSignedOutException {
    throw ("attachment-requires-account".tr());
  }
}

/// The server rejects anything that isn't a bare filename. Strip separators
/// and anything else awkward in a URL here so a picked file with an odd name
/// fails at upload time rather than silently 400ing.
String _sanitizeFilename(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[\\/\s]+'), '-')
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
  return cleaned.isEmpty ? 'attachment' : cleaned;
}

/// Fetches an attachment previously uploaded by [uploadAttachmentToServer],
/// for the in-app image preview. Returns null on any failure -- the caller
/// falls back to opening the raw link.
Future<List<int>?> getServerAttachmentData(String url) async {
  final filename = attachmentFilenameFromUrl(url);
  if (filename == null) return null;
  dynamic result = await openLoadingPopupTryCatch(
    () async => await downloadAttachmentBytes(filename),
    onError: (error) {
      print(error);
    },
  );
  if (result is List<int>) return result;
  return null;
}
