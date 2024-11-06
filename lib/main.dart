import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    await Firebase.initializeApp(
        options: FirebaseOptions(
            apiKey: "AIzaSyAqp3twrr2_6wT33h2o3ZrUZ4jGzTK0Ges",
            authDomain: "qrnotify-a5fbd.firebaseapp.com",
            databaseURL:
                "https://qrnotify-a5fbd-default-rtdb.europe-west1.firebasedatabase.app",
            projectId: "qrnotify-a5fbd",
            storageBucket: "qrnotify-a5fbd.appspot.com",
            messagingSenderId: "489104941464",
            appId: "1:489104941464:web:8b77a8e4c2e22eaab00bed",
            measurementId: "G-ENC671GREM"));
  } else {
    await Firebase.initializeApp();
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notification QR',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color.fromARGB(255, 68, 183, 58)),
        useMaterial3: true,
      ),
      home: const WelcomeScreen(), // Set the welcome screen as the home screen
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to QR Notify App'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Welcome to QR Notify App!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              const Text(
                'Tap the button below to start scanning QR codes and receive notifications.',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Start Scanning'),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const MyHomePage(title: 'QR Code Scanner'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  Barcode? result;
  QRViewController? controller;
  DateTime? lastScanTime;
  Duration scanCooldown = const Duration(seconds: 5); // Debounce duration
  AudioPlayer audioPlayer = AudioPlayer();

  // Define the expected QR code value here
  final String expectedQRCode = "Open The DOOR";

  @override
  void initState() {
    super.initState();

    _firebaseMessaging.requestPermission();

    FirebaseMessaging.instance.subscribeToTopic('door_notification').then((_) {
      print('Successfully subscribed to topic: door_notification');
    }).catchError((error) {
      print('Error subscribing to topic: $error');
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        print(
            'Foreground notification: ${message.notification!.title}, ${message.notification!.body}');
        showAlertDialog(
            context, message.notification!.title!, message.notification!.body!);
      }
    });

    listenToNotificationUpdates(); // Listen for changes in notification state
  }

  void showAlertDialog(BuildContext context, String title, String body) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                Future.delayed(Duration(milliseconds: 300), () {
                  controller
                      ?.resumeCamera(); // Resume scanning after a short delay
                });
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      controller?.pauseCamera();
    }
    controller?.resumeCamera();
  }

  @override
  void dispose() {
    controller?.dispose();
    audioPlayer
        .dispose(); // Dispose the audio player when the screen is disposed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'Scan a QR code to send notification:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: QRView(
                key: qrKey,
                onQRViewCreated: _onQRViewCreated,
                overlay: QrScannerOverlayShape(
                  borderColor: Colors.green,
                  borderRadius: 10,
                  borderLength: 30,
                  borderWidth: 10,
                  cutOutSize: 250,
                ),
              ),
            ),
            result != null
                ? Text('Scanned Data: ${result!.code}')
                : const Text('Scan a code'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          controller?.resumeCamera();
        },
        tooltip: 'Scan Again',
        child: const Icon(Icons.qr_code_scanner),
      ),
    );
  }

  void _onQRViewCreated(QRViewController qrController) {
    controller = qrController;
    controller!.scannedDataStream.listen((scanData) {
      final currentTime = DateTime.now();
      if (lastScanTime == null ||
          currentTime.difference(lastScanTime!) > scanCooldown) {
        setState(() {
          result = scanData;
          lastScanTime = currentTime; // Update timestamp for debounce

          // Validate the scanned QR code
          if (result?.code?.trim().toLowerCase() ==
              expectedQRCode.trim().toLowerCase()) {
            playKnockKnockSound(); // Play the audio when the correct QR code is scanned
            sendNotification(); // Send notification
          } else {
            print('Invalid QR Code: ${result?.code}');
            showAlertDialog(
                context, 'Invalid QR Code', 'This QR code is not allowed.');
          }
        });
      }
    });
  }

  Future<void> playKnockKnockSound() async {
    // Play the "knock knock" sound
    try {
      await audioPlayer.play(AssetSource('assets/knock_knock.mp3'));
    } catch (e) {
      print('Error playing sound: $e');
    }
  }

  Future<void> sendNotification() async {
    print('Sending notification...'); // Add this line to confirm it's called
    try {
      FirebaseFirestore.instance.collection('notifications').doc('door').set({
        'status': 'pending',
        'timestamp': DateTime.now(),
      });

      final response = await http.post(
        Uri.parse('http://192.168.1.9:3000/send-notification'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode({
          'message': 'QR code scanned',
          'data': result?.code,
        }),
      );

      if (response.statusCode == 200) {
        print('Notification sent successfully');
      } else {
        print('Failed to send notification: ${response.body}');
      }
    } catch (e) {
      if (e is SocketException) {
        print('Network error: ${e.message}');
      } else {
        print('Error sending notification: $e');
      }
    }
  }

  void dismissNotification() async {
    // Update notification status in Firestore
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc('door')
        .update({
      'status': 'dismissed',
    });

    // Optionally, notify other devices about dismissal
    final response = await http.post(
      Uri.parse('http://192.168.1.9:3000/send-dismiss-notification'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode({
        'message': 'Notification dismissed',
      }),
    );

    if (response.statusCode == 200) {
      print('Dismiss notification sent successfully');
    } else {
      print('Failed to send dismiss notification: ${response.body}');
    }
  }

  void listenToNotificationUpdates() {
    FirebaseFirestore.instance
        .collection('notifications')
        .doc('door')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && snapshot['status'] == 'dismissed') {
        // Dismiss the notification locally on other devices
        Navigator.of(context).pop();
      }
    });
  }
}
