import 'package:easy_localization/easy_localization.dart';
import 'package:cashew_selfhosted/widgets/textWidgets.dart';
import 'package:flutter/material.dart';

/// The bookkeeping every account form does: a submit that cannot be
/// double-tapped, and one error line under the fields.
///
/// Four forms had their own copy of this -- sign-in/setup, edit profile, change
/// password, add user. The copies had already diverged: the credentials form
/// grew its own [ServerCallResult] mapper that dropped the `forbidden` case,
/// which the shared one handles (see `messageForServerCallResult` in
/// accountSheets.dart). Sharing the mechanism is what keeps them saying the
/// same thing about the same failure.
///
/// A mixin rather than a wrapper widget, because the state has to sit with the
/// controllers and focus nodes it belongs to -- and each form's `build` stays
/// its own, since what differs between them is the fields, which is the part
/// worth reading.
mixin AccountFormState<T extends StatefulWidget> on State<T> {
  /// True while a submit is in flight. Disables the submit button.
  bool submitting = false;

  /// The message under the fields, or null when there is nothing wrong.
  String? errorText;

  /// Runs one submit attempt.
  ///
  /// [action] validates and does the work, returning the message to show or
  /// null when it succeeded; any success side effects (a snackbar, popping the
  /// sheet) belong inside it, before it returns null. Returns whether it
  /// succeeded, for the rare caller that needs to know.
  ///
  /// Re-entry is refused rather than queued: these all submit on the keyboard's
  /// done action *and* on a button, so a double tap is ordinary rather than
  /// exotic.
  Future<bool> submitForm(Future<String?> Function() action) async {
    if (submitting) return false;
    setState(() {
      submitting = true;
      errorText = null;
    });
    String? message;
    try {
      message = await action();
    } catch (e) {
      // An account form must not throw into the void: an unexpected failure
      // still has to leave the button usable and say something.
      print("Account form submit failed: $e");
      message = "server-error".tr();
    }
    // The sheet may have closed itself on success, which is the normal path.
    if (!mounted) return message == null;
    // `submitting` is cleared on success too, not just on failure. The
    // sign-in form used to leave it true forever and rely on the caller
    // unmounting the form to make the dead button moot; if that unmount is
    // delayed or never happens, the button should still recover.
    setState(() {
      submitting = false;
      errorText = message;
    });
    return message == null;
  }

  /// Shows [message] without running a submit -- for validation a caller does
  /// before it has anything to send.
  void showFormError(String message) {
    setState(() => errorText = message);
  }
}

/// The error line under an account form's fields.
class AccountFormError extends StatelessWidget {
  const AccountFormError(this.text, {this.maxLines = 3, super.key});

  final String? text;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 12),
      child: TextFont(
        text: text!,
        textColor: Theme.of(context).colorScheme.error,
        textAlign: TextAlign.center,
        maxLines: maxLines,
      ),
    );
  }
}
