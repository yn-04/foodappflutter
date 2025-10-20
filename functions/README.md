Firebase Functions: cleanupFamily

This folder contains a callable Cloud Function `cleanupFamily` that performs admin-side cleanup of a family document and related collections/subcollections. Use this if your Firestore rules prevent client deletion of cross-collection documents.

Files:
- package.json: Node dependencies (firebase-admin, firebase-functions)
- index.js: Callable function `cleanupFamily`

Deploy
1. Install Firebase CLI and login:
   npm install -g firebase-tools
   firebase login

2. From this `functions` folder run:
   npm install
   firebase deploy --only functions:cleanupFamily

Call from Flutter (example):
- Add dependency: cloud_functions: ^4.0.0 (or newer) in your pubspec.yaml
- Example call:

```dart
import 'package:cloud_functions/cloud_functions.dart';

final funcs = FirebaseFunctions.instance;

Future<void> callCleanup(String familyId) async {
  try {
    final callable = funcs.httpsCallable('cleanupFamily');
    final resp = await callable.call(<String, dynamic>{'familyId': familyId});
    print('cleanup result: ${resp.data}');
  } catch (e) {
    print('cleanup error: $e');
  }
}
```

Notes
- The function requires the caller to be authenticated. You may tighten this by checking context.auth.token for custom claims (e.g., admin). Adjust to your security needs.
- The function performs best-effort deletes and returns counts and any errors encountered.
