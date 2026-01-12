// ไฟล์: lib/pages/login_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
 import 'register_page.dart';
 import 'locker_selection_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ฟังก์ชัน Validation Email
  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'กรุณากรอกอีเมล';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'รูปแบบอีเมลไม่ถูกต้อง';
    }
    return null;
  }

  // ฟังก์ชัน Validation Password
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'กรุณากรอกรหัสผ่าน';
    }
    if (value.length < 6) {
      return 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';
    }
    return null;
  }

  // ฟังก์ชันตรวจสอบ Role และนำทางไปหน้าที่เหมาะสม
  Future<void> _checkRoleAndNavigate(String uid) async {
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(uid).get();
      
      if (userDoc.exists) {
        String role = userDoc.get('role') ?? 'user';
        if (mounted) {
          if (role == 'admin') {
            // นำทางไปหน้า Admin
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('เข้าสู่ระบบสำเร็จ - ผู้ดูแลระบบ'),
                backgroundColor: Colors.green,
              ),
            );
            // TODO: สร้างหน้า AdminPage แล้ว uncomment บรรทัดนี้
            // Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => AdminPage()));
          } else {
            // นำทางไปหน้า User
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('เข้าสู่ระบบสำเร็จ - ผู้ใช้ทั่วไป'),
                backgroundColor: Colors.green,
              ),
            );
            // TODO: สร้างหน้า UserPage แล้ว uncomment บรรทัดนี้
            //  Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => UserPage()));
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LockerSelectionPage(userId: uid)));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการตรวจสอบสิทธิ์: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ฟังก์ชันเข้าสู่ระบบด้วย Firebase
  Future<void> _signIn() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        UserCredential userCredential = await _auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        
        // ตรวจสอบ Role และนำทาง
        await _checkRoleAndNavigate(userCredential.user!.uid);
      } on FirebaseAuthException catch (e) {
        String message = 'เกิดข้อผิดพลาด';
        if (e.code == 'user-not-found') {
          message = 'ไม่พบผู้ใช้งานนี้';
        } else if (e.code == 'wrong-password') {
          message = 'รหัสผ่านไม่ถูกต้อง';
        } else if (e.code == 'invalid-email') {
          message = 'รูปแบบอีเมลไม่ถูกต้อง';
        } else if (e.code == 'invalid-credential') {
          message = 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 8,
            shadowColor: Colors.black26,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(32.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ไอคอนโลโก้
                    Icon(
                      Icons.lock_outline,
                      size: 80,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(height: 16),
                    
                    // หัวข้อ
                    Text(
                      'เข้าสู่ระบบ',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                    ),
                    const SizedBox(height: 32),
                    
                    // ช่องกรอก Email
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      validator: _validateEmail,
                      decoration: InputDecoration(
                        labelText: 'อีเมล',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // ช่องกรอก Password
                    TextFormField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      validator: _validatePassword,
                      decoration: InputDecoration(
                        labelText: 'รหัสผ่าน',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPasswordVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // ปุ่มเข้าสู่ระบบ
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _signIn,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'เข้าสู่ระบบ',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // ปุ่มไปหน้าลงทะเบียน
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const RegisterPage()),
                        );
                      },
                      child: Text(
                        'ยังไม่มีบัญชี? ลงทะเบียน',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}