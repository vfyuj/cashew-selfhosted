import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;

html.InputElement? _keyboardPrimer;
Timer? _keyboardPrimerTimeout;

void primeIOSWebKeyboard() {
  if (!kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;

  final existingPrimer = _keyboardPrimer;
  if (existingPrimer != null) {
    _keyboardPrimerTimeout?.cancel();
    existingPrimer.focus();
    _keyboardPrimerTimeout = Timer(const Duration(seconds: 3), () {
      existingPrimer.blur();
      _removeKeyboardPrimer(existingPrimer);
    });
    return;
  }

  final body = html.document.body;
  if (body == null) return;

  final primer = html.InputElement()
    ..type = 'text'
    ..tabIndex = -1;
  primer.style
    ..position = 'fixed'
    ..left = '0'
    ..top = '0'
    ..transform = 'translate(-9999px, -9999px)'
    ..opacity = '0'
    ..fontSize = '16px';

  // Keep focus in the tap gesture until Flutter's text input takes over.
  body.append(primer);
  _keyboardPrimer = primer;
  primer.onBlur.listen((_) => _removeKeyboardPrimer(primer));
  primer.focus();
  _keyboardPrimerTimeout = Timer(const Duration(seconds: 3), () {
    primer.blur();
    _removeKeyboardPrimer(primer);
  });
}

void _removeKeyboardPrimer(html.InputElement primer) {
  if (!identical(_keyboardPrimer, primer)) return;

  _keyboardPrimerTimeout?.cancel();
  _keyboardPrimerTimeout = null;
  primer.remove();
  _keyboardPrimer = null;
}