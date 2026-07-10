import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ftconfig/pages/infomation.dart';
import 'package:http/http.dart' as http;


class AuthDevicePage extends StatefulWidget {
  const AuthDevicePage({super.key});

  @override
  State<AuthDevicePage> createState() => _AuthDevicePageState();
}

class _AuthDevicePageState extends State<AuthDevicePage> {
  String status = "กำลังตรวจสอบอุปกรณ์...";

  @override
  void initState() {
    super.initState();
    authDevice();
  }

  Future<void> authDevice() async {
    try {
      final response = await http.post(
        Uri.parse("http://192.168.4.1/api/auth"),

        headers: {"Content-Type": "application/json"},

        body: jsonEncode({"username": "admin", "password": "1234"}),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const InfomationPage()));
      } else {
        setState(() {
          status = "Authentication Failed";
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        status = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Authenticating")),

      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [const CircularProgressIndicator(), const SizedBox(height: 20), Text(status)],
        ),
      ),
    );
  }
}
