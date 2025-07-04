// File generated by FlutterFire CLI.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDlB9_NLlDtan4I-N2Q93_Z5TdDsHYPKHs',
    appId: '1:1064590405120:web:320031f74532221348f2e5',
    messagingSenderId: '1064590405120',
    projectId: 'food-stock-management-app',
    authDomain: 'food-stock-management-app.firebaseapp.com',
    storageBucket: 'food-stock-management-app.firebasestorage.app',
    measurementId: 'G-V1Q686JFZR',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBb0A3Oi5MZ7sbZJWcWl7XFmRXLbz3PdTw',
    appId: '1:1064590405120:android:12a8550f07c6f42448f2e5',
    messagingSenderId: '1064590405120',
    projectId: 'food-stock-management-app',
    storageBucket: 'food-stock-management-app.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAqDigFWWaA4tet5dWLL6wgHMJQEsA9WHI',
    appId: '1:1064590405120:ios:42df77f9f9278bb948f2e5',
    messagingSenderId: '1064590405120',
    projectId: 'food-stock-management-app',
    storageBucket: 'food-stock-management-app.firebasestorage.app',
    iosClientId: '1064590405120-rb2qjah2918uhk98srbgl2fk3n8f7cu2.apps.googleusercontent.com',
    iosBundleId: 'com.example.myApp',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAqDigFWWaA4tet5dWLL6wgHMJQEsA9WHI',
    appId: '1:1064590405120:ios:42df77f9f9278bb948f2e5',
    messagingSenderId: '1064590405120',
    projectId: 'food-stock-management-app',
    storageBucket: 'food-stock-management-app.firebasestorage.app',
    iosClientId: '1064590405120-rb2qjah2918uhk98srbgl2fk3n8f7cu2.apps.googleusercontent.com',
    iosBundleId: 'com.example.myApp',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDlB9_NLlDtan4I-N2Q93_Z5TdDsHYPKHs',
    appId: '1:1064590405120:web:bc254c23f4af0ef348f2e5',
    messagingSenderId: '1064590405120',
    projectId: 'food-stock-management-app',
    authDomain: 'food-stock-management-app.firebaseapp.com',
    storageBucket: 'food-stock-management-app.firebasestorage.app',
    measurementId: 'G-T86BHN5W2T',
  );
}
