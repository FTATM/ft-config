import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// หน้าตั้งค่า RS485 / Modbus ทั้งหมด แบ่งเป็น:
/// 1. การตั้งค่า Serial port (rx/tx/de/re pin, baud, parity, slave id, function code, poll interval)
/// 2. Register mapping (label -> address เช่น "temperature" -> "M100")
/// 3. โหมดส่งออกข้อมูล เลือกได้ 3 แบบ: HTTP API / MQTT / UDP (แต่ละแบบมี config แยกกัน)
/// 4. ปุ่มทดสอบอ่านค่า+ส่งทันที
///
/// วิธีใช้: เรียกจากหน้าอื่นด้วย
///   Navigator.push(context, MaterialPageRoute(
///     builder: (_) => Rs485SetupPage(baseUrl: _baseUrl),
///   ));
class Rs485SetupPage extends StatefulWidget {
  const Rs485SetupPage({super.key, this.baseUrl = 'http://192.168.4.1'});

  final String baseUrl;

  @override
  State<Rs485SetupPage> createState() => _Rs485SetupPageState();
}

/// ข้อมูล 1 แถวของ register mapping พร้อม controller ของแต่ละ field
class _RegisterRow {
  _RegisterRow({required String label, required String address, String type = 'uint16', String scale = '1', bool swapWords = false})
      : labelController = TextEditingController(text: label),
        addressController = TextEditingController(text: address),
        scaleController = TextEditingController(text: scale),
        type = type,
        swapWords = swapWords;

  final TextEditingController labelController;
  final TextEditingController addressController;
  final TextEditingController scaleController;
  String type; // uint16 / int16 / uint32 / int32 / float32
  bool swapWords;

  void dispose() {
    labelController.dispose();
    addressController.dispose();
    scaleController.dispose();
  }
}

/// 1 แถวของ HTTP header (key/value)
class _HeaderRow {
  _HeaderRow({String key = '', String value = ''})
      : keyController = TextEditingController(text: key),
        valueController = TextEditingController(text: value);

  final TextEditingController keyController;
  final TextEditingController valueController;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

class _Rs485SetupPageState extends State<Rs485SetupPage> {
  static const _timeout = Duration(seconds: 5);
  static const _dataTypes = ['uint16', 'int16', 'uint32', 'int32', 'float32'];

  // ---------- Serial config controllers ----------
  final _rxPinController = TextEditingController();
  final _txPinController = TextEditingController();
  final _dePinController = TextEditingController();
  final _rePinController = TextEditingController();
  final _baudController = TextEditingController();
  final _slaveIdController = TextEditingController();
  final _pollIntervalController = TextEditingController();
  String _parity = 'N';
  int _stopBits = 1;
  int _functionCode = 3;

  bool _loadingConfig = true;
  bool _savingConfig = false;
  String? _configError;

  // ---------- Registers ----------
  final List<_RegisterRow> _registerRows = [];
  bool _loadingRegisters = true;
  bool _savingRegisters = false;
  String? _registersError;

  // ---------- Output mode ----------
  String _outputMode = 'http'; // 'http' | 'mqtt' | 'udp'
  bool _loadingOutputMode = true;
  bool _savingOutputMode = false;

  // ---------- HTTP output ----------
  final _httpUrlController = TextEditingController();
  String _httpMethod = 'POST';
  final List<_HeaderRow> _httpHeaders = [];
  bool _loadingHttpOutput = true;
  bool _savingHttpOutput = false;
  String? _httpOutputError;

  // ---------- MQTT output ----------
  final _mqttHostController = TextEditingController();
  final _mqttPortController = TextEditingController(text: '1883');
  final _mqttClientIdController = TextEditingController();
  final _mqttUsernameController = TextEditingController();
  final _mqttPasswordController = TextEditingController();
  final _mqttTopicController = TextEditingController();
  bool _mqttRetain = false;
  bool _loadingMqttOutput = true;
  bool _savingMqttOutput = false;
  String? _mqttOutputError;

  // ---------- UDP output ----------
  final _udpHostController = TextEditingController();
  final _udpPortController = TextEditingController();
  bool _loadingUdpOutput = true;
  bool _savingUdpOutput = false;
  String? _udpOutputError;

  // ---------- Test ----------
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _rxPinController.dispose();
    _txPinController.dispose();
    _dePinController.dispose();
    _rePinController.dispose();
    _baudController.dispose();
    _slaveIdController.dispose();
    _pollIntervalController.dispose();

    _httpUrlController.dispose();
    for (final h in _httpHeaders) {
      h.dispose();
    }

    _mqttHostController.dispose();
    _mqttPortController.dispose();
    _mqttClientIdController.dispose();
    _mqttUsernameController.dispose();
    _mqttPasswordController.dispose();
    _mqttTopicController.dispose();

    _udpHostController.dispose();
    _udpPortController.dispose();

    for (final row in _registerRows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadConfig(),
      _loadRegisters(),
      _loadOutputMode(),
      _loadHttpOutput(),
      _loadMqttOutput(),
      _loadUdpOutput(),
    ]);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // =====================================================
  // GET/POST /api/rs485/config
  // =====================================================
  Future<void> _loadConfig() async {
    setState(() {
      _loadingConfig = true;
      _configError = null;
    });

    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/api/rs485/config')).timeout(_timeout);
      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;

        _rxPinController.text = '${data['rx_pin'] ?? 16}';
        _txPinController.text = '${data['tx_pin'] ?? 17}';
        _dePinController.text = '${data['de_pin'] ?? -1}';
        _rePinController.text = '${data['re_pin'] ?? -1}';
        _baudController.text = '${data['baud'] ?? 9600}';
        _slaveIdController.text = '${data['slave_id'] ?? 1}';
        _pollIntervalController.text = '${data['poll_interval_ms'] ?? 5000}';

        setState(() {
          _parity = (data['parity']?.toString().isNotEmpty ?? false) ? data['parity'].toString() : 'N';
          _stopBits = int.tryParse('${data['stop_bits'] ?? 1}') ?? 1;
          _functionCode = int.tryParse('${data['function_code'] ?? 3}') ?? 3;
          _loadingConfig = false;
        });
      } else {
        setState(() {
          _configError = 'โหลดค่าไม่สำเร็จ (${res.statusCode})';
          _loadingConfig = false;
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _configError = 'หมดเวลาเชื่อมต่อ';
        _loadingConfig = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _configError = 'เกิดข้อผิดพลาด: $e';
        _loadingConfig = false;
      });
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _savingConfig = true);

    final body = {
      "rx_pin": int.tryParse(_rxPinController.text.trim()) ?? 16,
      "tx_pin": int.tryParse(_txPinController.text.trim()) ?? 17,
      "de_pin": int.tryParse(_dePinController.text.trim()) ?? -1,
      "re_pin": int.tryParse(_rePinController.text.trim()) ?? -1,
      "baud": int.tryParse(_baudController.text.trim()) ?? 9600,
      "parity": _parity,
      "stop_bits": _stopBits,
      "slave_id": int.tryParse(_slaveIdController.text.trim()) ?? 1,
      "function_code": _functionCode,
      "poll_interval_ms": int.tryParse(_pollIntervalController.text.trim()) ?? 5000,
    };

    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/rs485/config'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      final success = res.statusCode == 200 && data?['success'] == true;
      _showMessage(success ? 'บันทึกการตั้งค่า RS485 สำเร็จ' : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingConfig = false);
    }
  }

  // =====================================================
  // GET/POST /api/rs485/registers
  // =====================================================
  Future<void> _loadRegisters() async {
    setState(() {
      _loadingRegisters = true;
      _registersError = null;
    });

    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/api/rs485/registers')).timeout(_timeout);
      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;

        for (final row in _registerRows) {
          row.dispose();
        }
        _registerRows.clear();

        data.forEach((label, value) {
          final v = value as Map<String, dynamic>;
          _registerRows.add(
            _RegisterRow(
              label: label,
              address: v['address']?.toString() ?? '',
              type: v['type']?.toString() ?? 'uint16',
              scale: '${v['scale'] ?? 1}',
              swapWords: v['swap_words'] == true,
            ),
          );
        });

        setState(() => _loadingRegisters = false);
      } else {
        setState(() {
          _registersError = 'โหลด register ไม่สำเร็จ (${res.statusCode})';
          _loadingRegisters = false;
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _registersError = 'หมดเวลาเชื่อมต่อ';
        _loadingRegisters = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _registersError = 'เกิดข้อผิดพลาด: $e';
        _loadingRegisters = false;
      });
    }
  }

  Future<void> _saveRegisters() async {
    setState(() => _savingRegisters = true);

    final Map<String, dynamic> body = {};
    for (final row in _registerRows) {
      final label = row.labelController.text.trim();
      final address = row.addressController.text.trim();
      if (label.isEmpty || address.isEmpty) continue;

      body[label] = {
        "address": address,
        "type": row.type,
        "scale": double.tryParse(row.scaleController.text.trim()) ?? 1.0,
        "swap_words": row.swapWords,
      };
    }

    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/rs485/registers'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      final success = res.statusCode == 200 && data?['success'] == true;
      _showMessage(success ? 'บันทึก Register สำเร็จ (${body.length} รายการ)' : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingRegisters = false);
    }
  }

  void _addRegisterRow() => setState(() => _registerRows.add(_RegisterRow(label: '', address: '')));
  void _removeRegisterRow(int index) => setState(() => _registerRows.removeAt(index).dispose());

  // =====================================================
  // GET/POST /api/rs485/output_mode
  // =====================================================
  Future<void> _loadOutputMode() async {
    setState(() => _loadingOutputMode = true);
    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/api/rs485/output_mode')).timeout(_timeout);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _outputMode = data['mode']?.toString() ?? 'http';
          _loadingOutputMode = false;
        });
      } else {
        setState(() => _loadingOutputMode = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingOutputMode = false);
    }
  }

  Future<void> _changeOutputMode(String? mode) async {
    if (mode == null || mode == _outputMode) return;

    setState(() => _savingOutputMode = true);

    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/rs485/output_mode'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({"mode": mode}),
          )
          .timeout(_timeout);

      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;

      if (res.statusCode == 200 && data?['success'] == true) {
        setState(() => _outputMode = mode);
      } else {
        _showMessage(data?['message']?.toString() ?? 'เปลี่ยนโหมดไม่สำเร็จ');
      }
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingOutputMode = false);
    }
  }

  // =====================================================
  // GET/POST /api/rs485/output_http
  // =====================================================
  Future<void> _loadHttpOutput() async {
    setState(() {
      _loadingHttpOutput = true;
      _httpOutputError = null;
    });

    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/api/rs485/output_http')).timeout(_timeout);
      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;

        _httpUrlController.text = data['url']?.toString() ?? '';

        for (final h in _httpHeaders) {
          h.dispose();
        }
        _httpHeaders.clear();

        final headers = (data['headers'] as Map<String, dynamic>?) ?? {};
        headers.forEach((k, v) => _httpHeaders.add(_HeaderRow(key: k, value: v?.toString() ?? '')));

        setState(() {
          _httpMethod = (data['method']?.toString().isNotEmpty ?? false) ? data['method'].toString() : 'POST';
          _loadingHttpOutput = false;
        });
      } else {
        setState(() {
          _httpOutputError = 'โหลดค่าไม่สำเร็จ (${res.statusCode})';
          _loadingHttpOutput = false;
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _httpOutputError = 'หมดเวลาเชื่อมต่อ';
        _loadingHttpOutput = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _httpOutputError = 'เกิดข้อผิดพลาด: $e';
        _loadingHttpOutput = false;
      });
    }
  }

  Future<void> _saveHttpOutput() async {
    setState(() => _savingHttpOutput = true);

    final Map<String, dynamic> headers = {};
    for (final row in _httpHeaders) {
      final key = row.keyController.text.trim();
      if (key.isEmpty) continue;
      headers[key] = row.valueController.text.trim();
    }

    final body = {
      "url": _httpUrlController.text.trim(),
      "method": _httpMethod,
      "headers": headers,
    };

    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/rs485/output_http'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      final success = res.statusCode == 200 && data?['success'] == true;
      _showMessage(success ? 'บันทึกการตั้งค่า HTTP สำเร็จ' : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingHttpOutput = false);
    }
  }

  void _addHeaderRow() => setState(() => _httpHeaders.add(_HeaderRow()));
  void _removeHeaderRow(int index) => setState(() => _httpHeaders.removeAt(index).dispose());

  // =====================================================
  // GET/POST /api/rs485/output_mqtt
  // =====================================================
  Future<void> _loadMqttOutput() async {
    setState(() {
      _loadingMqttOutput = true;
      _mqttOutputError = null;
    });

    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/api/rs485/output_mqtt')).timeout(_timeout);
      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;

        _mqttHostController.text = data['host']?.toString() ?? '';
        _mqttPortController.text = '${data['port'] ?? 1883}';
        _mqttClientIdController.text = data['client_id']?.toString() ?? '';
        _mqttUsernameController.text = data['username']?.toString() ?? '';
        _mqttTopicController.text = data['topic']?.toString() ?? '';
        // password ไม่ถูกส่งกลับมาจาก ESP32 ด้วยเหตุผลด้านความปลอดภัย เว้นช่องนี้ว่างไว้เสมอ

        setState(() {
          _mqttRetain = data['retain'] == true;
          _loadingMqttOutput = false;
        });
      } else {
        setState(() {
          _mqttOutputError = 'โหลดค่าไม่สำเร็จ (${res.statusCode})';
          _loadingMqttOutput = false;
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _mqttOutputError = 'หมดเวลาเชื่อมต่อ';
        _loadingMqttOutput = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mqttOutputError = 'เกิดข้อผิดพลาด: $e';
        _loadingMqttOutput = false;
      });
    }
  }

  Future<void> _saveMqttOutput() async {
    if (_mqttHostController.text.trim().isEmpty) {
      _showMessage('กรุณากรอก Broker Host');
      return;
    }

    setState(() => _savingMqttOutput = true);

    final body = {
      "host": _mqttHostController.text.trim(),
      "port": int.tryParse(_mqttPortController.text.trim()) ?? 1883,
      "client_id": _mqttClientIdController.text.trim(),
      "username": _mqttUsernameController.text.trim(),
      "topic": _mqttTopicController.text.trim(),
      "retain": _mqttRetain,
      // ส่ง password เฉพาะตอนที่ผู้ใช้พิมพ์ค่าใหม่เท่านั้น ไม่งั้น ESP32 จะคงรหัสเดิมไว้ให้
      if (_mqttPasswordController.text.isNotEmpty) "password": _mqttPasswordController.text,
    };

    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/rs485/output_mqtt'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      final success = res.statusCode == 200 && data?['success'] == true;

      if (success) {
        _mqttPasswordController.clear(); // เคลียร์ช่อง password ทิ้งหลังบันทึกสำเร็จ กันค้างบนจอ
      }
      _showMessage(success ? 'บันทึกการตั้งค่า MQTT สำเร็จ' : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingMqttOutput = false);
    }
  }

  // =====================================================
  // GET/POST /api/rs485/output_udp
  // =====================================================
  Future<void> _loadUdpOutput() async {
    setState(() {
      _loadingUdpOutput = true;
      _udpOutputError = null;
    });

    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/api/rs485/output_udp')).timeout(_timeout);
      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _udpHostController.text = data['host']?.toString() ?? '';
        _udpPortController.text = '${data['port'] ?? ''}';
        setState(() => _loadingUdpOutput = false);
      } else {
        setState(() {
          _udpOutputError = 'โหลดค่าไม่สำเร็จ (${res.statusCode})';
          _loadingUdpOutput = false;
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _udpOutputError = 'หมดเวลาเชื่อมต่อ';
        _loadingUdpOutput = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _udpOutputError = 'เกิดข้อผิดพลาด: $e';
        _loadingUdpOutput = false;
      });
    }
  }

  Future<void> _saveUdpOutput() async {
    if (_udpHostController.text.trim().isEmpty) {
      _showMessage('กรุณากรอก Host ปลายทาง');
      return;
    }

    setState(() => _savingUdpOutput = true);

    final body = {
      "host": _udpHostController.text.trim(),
      "port": int.tryParse(_udpPortController.text.trim()) ?? 0,
    };

    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/rs485/output_udp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      final success = res.statusCode == 200 && data?['success'] == true;
      _showMessage(success ? 'บันทึกการตั้งค่า UDP สำเร็จ' : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingUdpOutput = false);
    }
  }

  // =====================================================
  // POST /api/rs485/poll_now
  // =====================================================
  Future<void> _testPollNow() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });

    try {
      final res = await http.post(Uri.parse('${widget.baseUrl}/api/rs485/poll_now')).timeout(const Duration(seconds: 15));
      if (!mounted) return;

      if (res.statusCode == 200) {
        setState(() => _testResult = 'สั่งอ่าน+ส่งข้อมูลแล้ว ตรวจผลลัพธ์ที่ปลายทางที่ตั้งไว้ (ดู log บน Serial Monitor ของ ESP32 ได้ด้วย)');
      } else {
        setState(() => _testResult = 'ทดสอบไม่สำเร็จ (${res.statusCode})');
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _testResult = 'หมดเวลารอผลทดสอบ');
    } catch (e) {
      if (!mounted) return;
      setState(() => _testResult = 'เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ตั้งค่า RS485 / Modbus"),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll)],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSerialConfigCard(),
            const SizedBox(height: 16),
            _buildRegistersCard(),
            const SizedBox(height: 16),
            _buildOutputModeCard(),
            const SizedBox(height: 16),
            if (_outputMode == 'mqtt')
              _buildMqttOutputCard()
            else if (_outputMode == 'udp')
              _buildUdpOutputCard()
            else
              _buildHttpOutputCard(),
            const SizedBox(height: 16),
            _buildTestCard(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // Card: Serial config
  // ---------------------------------------------------
  Widget _buildSerialConfigCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("การเชื่อมต่อ RS485", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            if (_loadingConfig)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_configError != null) ...[
                Text(_configError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _rxPinController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "RX Pin", border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _txPinController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "TX Pin", border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dePinController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "DE Pin",
                        helperText: "-1 ถ้าไม่ใช้ขานี้",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _rePinController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "RE Pin",
                        helperText: "บอร์ดที่แยกขา RE ให้กรอกที่นี่",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _baudController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Baud Rate", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _parity,
                      decoration: const InputDecoration(labelText: "Parity", border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'N', child: Text("None (N)")),
                        DropdownMenuItem(value: 'E', child: Text("Even (E)")),
                        DropdownMenuItem(value: 'O', child: Text("Odd (O)")),
                      ],
                      onChanged: (v) => setState(() => _parity = v ?? 'N'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _stopBits,
                      decoration: const InputDecoration(labelText: "Stop Bits", border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text("1")),
                        DropdownMenuItem(value: 2, child: Text("2")),
                      ],
                      onChanged: (v) => setState(() => _stopBits = v ?? 1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _slaveIdController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Slave ID", border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _functionCode,
                      decoration: const InputDecoration(labelText: "Function Code", border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 3, child: Text("FC3 (Holding)")),
                        DropdownMenuItem(value: 4, child: Text("FC4 (Input)")),
                      ],
                      onChanged: (v) => setState(() => _functionCode = v ?? 3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pollIntervalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Poll Interval (ms)",
                  helperText: "ความถี่ในการอ่านค่า+ส่งข้อมูลอัตโนมัติ",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingConfig ? null : _saveConfig,
                  icon: _savingConfig
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text("บันทึกการตั้งค่า"),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // Card: Register mapping
  // ---------------------------------------------------
  Widget _buildRegistersCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Register Mapping", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(icon: const Icon(Icons.add_circle), tooltip: "เพิ่มแถว", onPressed: _addRegisterRow),
              ],
            ),
            const SizedBox(height: 8),
            if (_loadingRegisters)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_registersError != null) ...[
                Text(_registersError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              if (_registerRows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text("ยังไม่มี register — กด + เพื่อเพิ่ม", style: TextStyle(color: Colors.grey)),
                ),
              ..._registerRows.asMap().entries.map((entry) => _buildRegisterRow(entry.key, entry.value)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingRegisters ? null : _saveRegisters,
                  icon: _savingRegisters
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text("บันทึก Register ทั้งหมด"),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRegisterRow(int index, _RegisterRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: row.labelController,
                    decoration: const InputDecoration(labelText: "Label", hintText: "temperature", isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: row.addressController,
                    decoration: const InputDecoration(labelText: "Address", hintText: "M100", isDense: true),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _removeRegisterRow(index),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: row.type,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: "Type", isDense: true),
                    items: _dataTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) => setState(() => row.type = v ?? 'uint16'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: row.scaleController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: "Scale", isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Swap", style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Checkbox(
                      value: row.swapWords,
                      onChanged: (v) => setState(() => row.swapWords = v ?? false),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // Card: Output mode selector
  // ---------------------------------------------------
  Widget _buildOutputModeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("โหมดการส่งออกข้อมูล", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            if (_loadingOutputMode)
              const Center(child: CircularProgressIndicator())
            else
              Column(
                children: [
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("HTTP API"),
                    subtitle: const Text("ยิง REST API ปลายทาง เลือก method และใส่ header เองได้"),
                    value: 'http',
                    groupValue: _outputMode,
                    onChanged: _savingOutputMode ? null : _changeOutputMode,
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("MQTT"),
                    subtitle: const Text("Publish ข้อมูลไปที่ MQTT broker"),
                    value: 'mqtt',
                    groupValue: _outputMode,
                    onChanged: _savingOutputMode ? null : _changeOutputMode,
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("UDP"),
                    subtitle: const Text("ส่งเป็น UDP datagram ดิบๆ เร็วที่สุด ไม่การันตีถึงปลายทาง"),
                    value: 'udp',
                    groupValue: _outputMode,
                    onChanged: _savingOutputMode ? null : _changeOutputMode,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // Card: HTTP output config
  // ---------------------------------------------------
  Widget _buildHttpOutputCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("ตั้งค่า HTTP API", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            if (_loadingHttpOutput)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_httpOutputError != null) ...[
                Text(_httpOutputError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: _httpUrlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: "URL ปลายทาง",
                  hintText: "http://192.168.1.50:3000/api/sensor_data",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _httpMethod,
                decoration: const InputDecoration(labelText: "Method", border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'POST', child: Text("POST")),
                  DropdownMenuItem(value: 'PUT', child: Text("PUT")),
                  DropdownMenuItem(value: 'PATCH', child: Text("PATCH")),
                  DropdownMenuItem(value: 'GET', child: Text("GET")),
                ],
                onChanged: (v) => setState(() => _httpMethod = v ?? 'POST'),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Headers", style: TextStyle(fontWeight: FontWeight.w600)),
                  IconButton(icon: const Icon(Icons.add_circle), tooltip: "เพิ่ม header", onPressed: _addHeaderRow),
                ],
              ),
              if (_httpHeaders.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    "ไม่มี header เพิ่มเติม (Content-Type: application/json ถูกใส่ให้อัตโนมัติ)",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ..._httpHeaders.asMap().entries.map((e) => _buildHeaderRow(e.key, e.value)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingHttpOutput ? null : _saveHttpOutput,
                  icon: _savingHttpOutput
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text("บันทึกการตั้งค่า HTTP"),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow(int index, _HeaderRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: row.keyController,
              decoration: const InputDecoration(labelText: "Key", hintText: "Authorization", isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: row.valueController,
              decoration: const InputDecoration(labelText: "Value", hintText: "Bearer xxxxx", isDense: true),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () => _removeHeaderRow(index),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------
  // Card: MQTT output config
  // ---------------------------------------------------
  Widget _buildMqttOutputCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("ตั้งค่า MQTT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            if (_loadingMqttOutput)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_mqttOutputError != null) ...[
                Text(_mqttOutputError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _mqttHostController,
                      decoration: const InputDecoration(
                        labelText: "Broker Host",
                        hintText: "192.168.1.50 หรือ broker.hivemq.com",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _mqttPortController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Port", border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _mqttClientIdController,
                decoration: const InputDecoration(
                  labelText: "Client ID",
                  hintText: "เว้นว่างได้ (จะ generate จาก MAC ให้อัตโนมัติ)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _mqttUsernameController,
                decoration: const InputDecoration(labelText: "Username (ถ้ามี)", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _mqttPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Password (ถ้ามี)",
                  helperText: "เว้นว่างไว้ = ใช้รหัสเดิมที่เคยตั้งไว้ (ไม่แสดงค่าเดิมด้วยเหตุผลด้านความปลอดภัย)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _mqttTopicController,
                decoration: const InputDecoration(
                  labelText: "Topic",
                  hintText: "sensors/farm-box-1",
                  border: OutlineInputBorder(),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Retain message"),
                value: _mqttRetain,
                onChanged: (v) => setState(() => _mqttRetain = v ?? false),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingMqttOutput ? null : _saveMqttOutput,
                  icon: _savingMqttOutput
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text("บันทึกการตั้งค่า MQTT"),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // Card: UDP output config
  // ---------------------------------------------------
  Widget _buildUdpOutputCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("ตั้งค่า UDP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            if (_loadingUdpOutput)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_udpOutputError != null) ...[
                Text(_udpOutputError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _udpHostController,
                      decoration: const InputDecoration(
                        labelText: "Host ปลายทาง",
                        hintText: "192.168.1.50",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _udpPortController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Port", border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingUdpOutput ? null : _saveUdpOutput,
                  icon: _savingUdpOutput
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text("บันทึกการตั้งค่า UDP"),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // Card: Test
  // ---------------------------------------------------
  Widget _buildTestCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("ทดสอบ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            const Text(
              "สั่งให้ ESP32 อ่านค่าจาก Modbus ตาม register ที่ตั้งไว้ทันที แล้วส่งออกตามโหมดที่เลือกไว้ด้านบน โดยไม่ต้องรอ interval",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _testing ? null : _testPollNow,
                icon: _testing
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text(_testing ? "กำลังทดสอบ..." : "ทดสอบอ่านค่าตอนนี้"),
              ),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 12),
              Text(_testResult!),
            ],
          ],
        ),
      ),
    );
  }
}
