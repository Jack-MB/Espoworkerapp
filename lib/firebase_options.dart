// File configured for MB-Security Worker App with Firebase
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
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
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCWzF3XFp__s5IPv1_fDLb-tW9cu41n3Es',
    appId: '1:426875516268:web:b1d83ceb98d249f0',
    messagingSenderId: '426875516268',
    projectId: 'espocrm-worker-app',
    authDomain: 'espocrm-worker-app.firebaseapp.com',
    storageBucket: 'espocrm-worker-app.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCWzF3XFp__s5IPv1_fDLb-tW9cu41n3Es',
    appId: '1:426875516268:android:df808040204face42a2f49',
    messagingSenderId: '426875516268',
    projectId: 'espocrm-worker-app',
    storageBucket: 'espocrm-worker-app.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCWzF3XFp__s5IPv1_fDLb-tW9cu41n3Es',
    appId: '1:426875516268:ios:df808040204face42a2f49',
    messagingSenderId: '426875516268',
    projectId: 'espocrm-worker-app',
    storageBucket: 'espocrm-worker-app.firebasestorage.app',
    iosBundleId: 'com.mbsecurity.worker',
  );
}
