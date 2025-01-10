import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'package:xyz/RegisterScreen.dart';
import 'student_dashboard.dart'; // Replace with your actual import
import 'driver_location_marker.dart'; // Replace with your actual import

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    return androidInfo.id;
  }

  Future<void> _login() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showSnackBar('Please fill in all fields.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      if (!userDoc.exists) {
        _showSnackBar('User data not found. Please register again.');
        return;
      }

      final role = userDoc['role'];
      if (role == 'driver') {
        String deviceId = await getDeviceId();

        if (!userDoc.data()!.containsKey('deviceId')) {
          await _saveDeviceId(userCredential.user!.uid);
          _showSnackBar('Device ID registered successfully.');
        } else {
          if (userDoc['deviceId'] != deviceId) {
            _showSnackBar('This account is already logged in on another device.');
            return;
          }
        }

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DriverLocationMarker()),
        );
      } else if (role == 'student') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const StudentDashboard()),
        );
      } else {
        _showSnackBar('Unknown role. Please contact support.');
      }
    } on FirebaseAuthException catch (e) {
      _showSnackBar('Login failed: ${e.message}');
    } catch (e) {
      _showSnackBar('Error: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveDeviceId(String uid) async {
    String deviceId = await getDeviceId();
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'deviceId': deviceId,
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Welcome Back',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(15),
                        textStyle: const TextStyle(fontSize: 18),
                      ),
                      onPressed: _login,
                      child: const Text('Login'),
                    ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RegistrationScreen()),
                  );
                },
                child: const Text('Don’t have an account? Register'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}