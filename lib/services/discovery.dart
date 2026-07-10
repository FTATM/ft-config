import 'dart:async';
import 'package:ftconfig/services/wifi_native.dart';
import 'package:multicast_dns/multicast_dns.dart';


class Esp32Device {
  final String hostname; // "esp-sensor-g1.local"
  final String ip;
  final int port;

  Esp32Device({required this.hostname, required this.ip, required this.port});

  @override
  String toString() => '$hostname -> $ip:$port';
}

class Esp32Discovery {
  static const _serviceType = '_http._tcp.local';
  static const _hostnamePrefix = 'esp-'; // ต้องตรงกับ getMdnsHostname() ฝั่ง ESP32

  /// สแกนหา ESP32 ทุกตัวใน WLAN เดียวกันที่ประกาศ mDNS service แบบ _http._tcp
  /// และมี hostname ขึ้นต้นด้วย "esp-" (กรองทิ้งพวก printer/NAS/อุปกรณ์อื่นที่ก็มัก
  /// ประกาศ _http._tcp เหมือนกัน แต่ไม่ใช่ ESP32 ของเรา)
  static Future<List<Esp32Device>> discover({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // ต้อง acquire multicast lock ก่อนเสมอบน Android ไม่งั้นจะไม่มี response กลับมาเลย
    await WifiNative.acquireMulticastLock();

    final MDnsClient client = MDnsClient();
    final Map<String, Esp32Device> found = {}; // dedupe ด้วย hostname

    try {
      await client.start();

      await for (final PtrResourceRecord ptr in client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(_serviceType),
          )
          .timeout(timeout, onTimeout: (sink) => sink.close())) {
        // แต่ละ PTR คือ 1 service instance ที่เจอ ต้อง resolve ต่อเป็น SRV (หา hostname+port)
        await for (final SrvResourceRecord srv in client
            .lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName),
            )
            .timeout(const Duration(seconds: 2), onTimeout: (sink) => sink.close())) {
          final hostname = srv.target;

          if (!hostname.startsWith(_hostnamePrefix)) {
            continue; // ไม่ใช่ ESP32 ของเรา (เช่นเป็นเครื่องพิมพ์/NAS ที่ประกาศ _http._tcp เหมือนกัน)
          }

          // resolve hostname เป็น IP จริง (A record)
          await for (final IPAddressResourceRecord ip in client
              .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(hostname),
              )
              .timeout(const Duration(seconds: 2), onTimeout: (sink) => sink.close())) {
            found[hostname] = Esp32Device(
              hostname: hostname,
              ip: ip.address.address,
              port: srv.port,
            );
          }
        }
      }
    } finally {
      client.stop();
      // release ทันทีหลังสแกนเสร็จ ไม่ถือ lock ค้างไว้กินแบตฯ
      await WifiNative.releaseMulticastLock();
    }

    return found.values.toList();
  }
}