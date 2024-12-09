import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class SecureStorage {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _keyNote = "secure_note";
  static const _key = "secure_key";

  Future<Uint8List> getKey() async {
    final storedKey = await _storage.read(key: _key);
    if (storedKey != null) {
      return Uint8List.fromList(const Base64Decoder().convert(storedKey));
    }
    final newKey = _generateSecureKey();
    await _storage.write(key: _key, value: const Base64Encoder().convert(newKey));
    return newKey;
  }

  Uint8List _generateSecureKey() {
    final random = Random.secure();
    final key = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      key[i] = random.nextInt(256);
    }
    return key;
  }

  Future<void> saveAndEncryptNote(String note) async {
    final key = encrypt.Key(await getKey());
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final encryptedNote = encrypter.encrypt(note, iv: iv);

    final data = '${encryptedNote.base64}:${iv.base64}';
    await _storage.write(key: _keyNote, value: data);
  }

  Future<String?> getAndDecryptNote() async {
    final storedData = await _storage.read(key: _keyNote);
    if (storedData == null) {
      return null;
    }
    final parts = storedData.split(':');

    final encryptedNoteBase64 = parts[0];
    final ivBase64 = parts[1];

    final key = encrypt.Key(await getKey());
    final iv = encrypt.IV.fromBase64(ivBase64);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));

    final encrypted = encrypt.Encrypted.fromBase64(encryptedNoteBase64);
    final decryptedNote = encrypter.decrypt(encrypted, iv: iv);

    return decryptedNote;
  }
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SecureNotepadApp());
}

class SecureNotepadApp extends StatelessWidget {
  const SecureNotepadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.grey,
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: Colors.white30,
          selectionColor: Colors.grey,
          selectionHandleColor: Colors.black.withOpacity(0.0)
        )
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<void> _authenticate() async {
    try {
      final isAuthenticated = await _auth.authenticate(
        localizedReason: 'Skanuj Palucha',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (isAuthenticated) {
        if (mounted) {
          Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
        }
      } else if (mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Autoryzacja nieudana')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Błąd biometrii: $e')),
      );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: CustomGrayButton(
          onPressed: _authenticate,
          text: 'Zaloguj się',
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final SecureStorage _secureStorage = SecureStorage();
  final TextEditingController _noteController = TextEditingController();

  Future<void> _loadNote() async {
    final note = await _secureStorage.getAndDecryptNote();
    if (note != null) {
      setState(() {
        _noteController.text = note;
      });
    }
  }

  Future<void> _saveNote() async {
    await _secureStorage.saveAndEncryptNote(_noteController.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notatka zapisana pomyślnie i bezpiecznie.')),
    );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bezpieczny Notatnik'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _noteController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  hintText: 'Zacznij pisać swoją notatkę...',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[800],
                ),
              ),
            ),
          ),
          CustomGrayButton(
            onPressed: _saveNote,
            text: 'Zapisz notatkę',
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}


class CustomGrayButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;

  const CustomGrayButton({
    super.key,
    required this.text,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey[800],
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
        ),
      ),
    );
  }
}
