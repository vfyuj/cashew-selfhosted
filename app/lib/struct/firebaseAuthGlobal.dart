import 'package:cashew_selfhosted/firebase_options.dart';
import 'package:cashew_selfhosted/struct/settings.dart';
import 'package:cashew_selfhosted/widgets/accountAndBackup.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;

OAuthCredential? _credential;

Future<bool>? _firebaseInitialization;

/// Initializes Firebase on first use, never at launch.
///
/// This used to be an unconditional `await Firebase.initializeApp()` in
/// `main()`. On web that is a blocking network dependency: `firebase_core_web`
/// injects `https://www.gstatic.com/firebasejs/.../firebase-*.js` script tags
/// from inside `initializeApp` and awaits them, so the app could not start
/// without reaching Google's CDN -- breaking an offline load
/// (`specs/01-local-first-invariant.md`) and pinging Google on every launch,
/// for features that are opt-in and off by default.
///
/// Every Firebase use in this fork goes through the two functions below, so
/// this is the only place initialization needs to happen. Returns false rather
/// than throwing when it can't initialize (offline, or an unsupported
/// platform); callers already treat a null database as "cloud unavailable".
Future<bool> ensureFirebaseInitialized() {
  return _firebaseInitialization ??= () async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      return true;
    } catch (e) {
      print("There was an error initializing firebase");
      print(e.toString());
      // Usually just "no network right now" -- let the next opt-in use retry.
      // Re-initializing with identical options is a no-op if it did partly
      // succeed, firebase_core returns the existing default app.
      _firebaseInitialization = null;
      return false;
    }
  }();
}

Future<FirebaseFirestore?> firebaseGetDBInstanceAnonymous() async {
  if (await ensureFirebaseInitialized() == false) return null;
  try {
    await FirebaseAuth.instance.signInAnonymously();
    return FirebaseFirestore.instance;
  } catch (e) {
    print("There was an error with firebase login");
    print(e.toString());
    return null;
  }
}

// returns null if authentication unsuccessful
Future<FirebaseFirestore?> firebaseGetDBInstance() async {
  if (await ensureFirebaseInitialized() == false) return null;
  if (_credential != null) {
    try {
      await FirebaseAuth.instance.signInWithCredential(_credential!);
      updateSettings(
        "currentUserEmail",
        FirebaseAuth.instance.currentUser!.email,
        pagesNeedingRefresh: [],
        updateGlobalState: false,
      );
      return FirebaseFirestore.instance;
    } catch (e) {
      print("There was an error with firebase login");
      print(e.toString());
      print("will retry with a new credential");
      _credential = null;
      googleUser = null;
      return await firebaseGetDBInstance();
    }
  } else {
    try {
      if (googleUser == null) {
        await signInGoogle(silentSignIn: true);
      }
      // GoogleSignInAccount? googleUser = googleUser;

      GoogleSignInAuthentication? googleAuth = await googleUser?.authentication;

      _credential = GoogleAuthProvider.credential(
        accessToken: googleAuth?.accessToken,
        idToken: googleAuth?.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(_credential!);
      updateSettings(
          "currentUserEmail", FirebaseAuth.instance.currentUser!.email,
          updateGlobalState: true);
      return FirebaseFirestore.instance;
    } catch (e) {
      print("There was an error with firebase login and possibly google");
      print(e.toString());
      return null;
    }
  }
}
