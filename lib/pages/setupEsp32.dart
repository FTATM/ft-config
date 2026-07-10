import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ftconfig/pages/wifiConnect.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});
  @override
  State<SetupPage> createState() => _SetupPageState();
}

Future<void> requestPermission() async {
  await Permission.location.request();

  if (await Permission.nearbyWifiDevices.isDenied) {
    await Permission.nearbyWifiDevices.request();
  }
}

Future<List<WiFiAccessPoint>> scanWifi() async {
  final can = await WiFiScan.instance.canStartScan();

  if (can == CanStartScan.yes) {
    await WiFiScan.instance.startScan();

    await Future.delayed(const Duration(seconds: 3));

    return await WiFiScan.instance.getScannedResults();
  }

  return [];
}

class _SetupPageState extends State<SetupPage> {
  List<WiFiAccessPoint> wifiList = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadWifi();
  }

  Future<void> checkConnection() async {
    Map<String, dynamic> statusData = {};
    String _statusError = "";
    try {
      final res = await http.get(Uri.parse('192.168.4.1/api/status')).timeout(Duration(seconds: 15));
      if (!mounted) return;

      if (res.statusCode == 200) {
        setState(() {
          statusData = jsonDecode(res.body) as Map<String, dynamic>;
        });
      } else {
        setState(() {
          _statusError = 'สถานะผิดพลาด (${res.statusCode})';
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _statusError = 'หมดเวลาเชื่อมต่อ';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusError = 'เกิดข้อผิดพลาด: $e';
      });
    }
    print(statusData);
    print(_statusError);
  }

  Future<void> loadWifi() async {
    setState(() {
      isLoading = true;
    });

    await checkConnection();

    await requestPermission();

    wifiList = await scanWifi();
    wifiList = wifiList.where((e) => e.ssid.isNotEmpty).toList();
    wifiList.sort((a, b) => b.level.compareTo(a.level));

    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Wifi Scan")),

        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [CircularProgressIndicator(), SizedBox(height: 16), Text("กำลังค้นหาเครือข่าย WiFi...")],
          ),
        ),
      );
    }

    if (wifiList.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Wifi Scan"),
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: loadWifi)],
        ),

        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off, size: 64),
              const SizedBox(height: 16),
              const Text("ไม่พบเครือข่าย WiFi"),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: loadWifi, child: const Text("ค้นหาอีกครั้ง")),
            ],
          ),
        ),
      );
    }

    return Scaffold(
        appBar: AppBar(
          title: const Text("Wifi Scan"),
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: loadWifi)],
        ),

      body: ListView.builder(
        itemCount: wifiList.length,

        itemBuilder: (context, index) {
          final wifi = wifiList[index];

          return ListTile(
            leading: const Icon(Icons.wifi),
            title: Text(wifi.ssid),
            subtitle: Text(
              "RSSI: ${wifi.level} dBm\n${wifi.capabilities}",
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => WifiConnectPage(accessPoint: wifi)));
            },
          );
        },
      ),
    );
  }
}
