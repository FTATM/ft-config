import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// หน้าตั้งค่า RS485 / Modbus ทั้งหมด แบ่งเป็น 3 ส่วน:
/// 1. การตั้งค่า Serial port (rx/tx/de pin, baud, parity, slave id, function code, poll interval)
/// 2. Register mapping (label -> address เช่น "temperature" -> "M100")
/// 3. Destination URL ที่จะ POST ผลลัพธ์ไปให้ + ปุ่มทดสอบอ่านค่าทันที
///
/// วิธีใช้: เรียกจากหน้าอื่นด้วย
///   Navigator.push(context, MaterialPageRoute(
///     builder: (_) => Rs485SetupPage(baseUrl: _baseUrl), // ใช้ _baseUrl เดียวกับที่ dashboard ใช้อยู่
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

  // ---------- Destination ----------
  final _destUrlController = TextEditingController();

  // ---------- Registers ----------
  final List<_RegisterRow> _registerRows = [];

  bool _loadingConfig = true;
  bool _loadingRegisters = true;
  bool _loadingDestination = true;
  bool _savingConfig = false;
  bool _savingRegisters = false;
  bool _savingDestination = false;
  bool _testing = false;

  String? _configError;
  String? _registersError;
  String? _destinationError;
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
    _destUrlController.dispose();
    for (final row in _registerRows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadConfig(), _loadRegisters(), _loadDestination()]);
  }

  // =====================================================
  // GET /api/rs485/config
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

  // =====================================================
  // POST /api/rs485/config
  // =====================================================
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
  // GET /api/rs485/registers
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

  // =====================================================
  // POST /api/rs485/registers  (ส่งทั้งชุด แทนที่ของเดิมทั้งหมด)
  // =====================================================
  Future<void> _saveRegisters() async {
    setState(() => _savingRegisters = true);

    final Map<String, dynamic> body = {};
    for (final row in _registerRows) {
      final label = row.labelController.text.trim();
      final address = row.addressController.text.trim();
      if (label.isEmpty || address.isEmpty) continue; // ข้ามแถวที่กรอกไม่ครบ

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

  void _addRegisterRow() {
    setState(() {
      _registerRows.add(_RegisterRow(label: '', address: ''));
    });
  }

  void _removeRegisterRow(int index) {
    setState(() {
      _registerRows.removeAt(index).dispose();
    });
  }

  // =====================================================
  // GET/POST /api/rs485/destination
  // =====================================================
  Future<void> _loadDestination() async {
    setState(() {
      _loadingDestination = true;
      _destinationError = null;
    });

    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/api/rs485/destination')).timeout(_timeout);

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _destUrlController.text = data['url']?.toString() ?? '';
        setState(() => _loadingDestination = false);
      } else {
        setState(() {
          _destinationError = 'โหลดปลายทางไม่สำเร็จ (${res.statusCode})';
          _loadingDestination = false;
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _destinationError = 'หมดเวลาเชื่อมต่อ';
        _loadingDestination = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _destinationError = 'เกิดข้อผิดพลาด: $e';
        _loadingDestination = false;
      });
    }
  }

  Future<void> _saveDestination() async {
    final url = _destUrlController.text.trim();

    if (url.isEmpty) {
      _showMessage('กรุณากรอก URL ปลายทาง');
      return;
    }

    setState(() => _savingDestination = true);

    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/rs485/destination'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({"url": url}),
          )
          .timeout(_timeout);

      if (!mounted) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      final success = res.statusCode == 200 && data?['success'] == true;

      _showMessage(success ? 'บันทึกปลายทางสำเร็จ' : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingDestination = false);
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
      // poll_now ฝั่ง ESP32 จะบล็อกจนกว่าจะอ่าน+ส่งเสร็จ (มีหน่วง 50ms ต่อ register)
      // เผื่อเวลาไว้มากกว่า request ปกติ
      final res = await http
          .post(Uri.parse('${widget.baseUrl}/api/rs485/poll_now'))
          .timeout(const Duration(seconds: 15));

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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
            _buildDestinationCard(),
            const SizedBox(height: 16),
            _buildTestCard(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // Card 1: Serial config
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
  // Card 2: Register mapping
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
  // Card 3: Destination
  // ---------------------------------------------------
  Widget _buildDestinationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("ปลายทางส่งข้อมูล (Destination)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            if (_loadingDestination)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_destinationError != null) ...[
                Text(_destinationError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: _destUrlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: "Destination URL",
                  hintText: "http://192.168.1.50:3000/api/sensor_data",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingDestination ? null : _saveDestination,
                  icon: _savingDestination
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text("บันทึกปลายทาง"),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // Card 4: Test
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
              "สั่งให้ ESP32 อ่านค่าจาก Modbus ตาม register ที่ตั้งไว้ทันที แล้ว POST ไปที่ปลายทางเลย โดยไม่ต้องรอ interval",
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
