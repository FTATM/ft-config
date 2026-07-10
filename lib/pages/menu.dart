import 'package:flutter/material.dart';
import 'package:ftconfig/pages/configurationEsp32.dart';
import 'package:ftconfig/pages/setupEsp32.dart';

class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ESP32 Config"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),

            const Icon(
              Icons.memory,
              size: 80,
              color: Colors.blue,
            ),

            const SizedBox(height: 16),

            const Text(
              "เลือกโหมดการเชื่อมต่อ",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              "เลือกวิธีการเชื่อมต่อกับ ESP32",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 40),

            Card(
              elevation: 3,
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.wifi_find),
                ),
                title: const Text(
                  "Setup ESP32",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  "เชื่อมต่อ Wi-Fi AP ของ ESP32\nเพื่อกำหนดค่า Wi-Fi ให้กับอุปกรณ์",
                ),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SetupPage(),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            Card(
              elevation: 3,
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.router),
                ),
                title: const Text(
                  "Configuration ESP32",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  "เชื่อมต่อผ่าน IP Address\nเพื่อสื่อสารกับ ESP32 ผ่าน REST API",
                ),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => configurationEsp32Page(),
                      ),
                    );
                },
              ),
            ),

            const Spacer(),

            const Text(
              "Setup : สำหรับอุปกรณ์ใหม่\n"
              "Configuration : สำหรับอุปกรณ์ที่เชื่อมต่อ Router แล้ว",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}