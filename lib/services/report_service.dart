import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pingit/models/device_model.dart';

class ReportService {
  Future<File> generateWeeklyUptimeReport(List<Device> devices) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final startDate = now.subtract(const Duration(days: 7));
    final dateFormat = DateFormat('yyyy-MM-dd');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (pw.Context context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(bottom: 20),
          child: pw.Text('PingIT Infrastructure Health Report', 
              style: pw.TextStyle(color: PdfColors.grey700, fontSize: 10)),
        ),
        footer: (pw.Context context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 20),
          child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(color: PdfColors.grey700, fontSize: 10)),
        ),
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Weekly Uptime Summary', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 24)),
                pw.Text('${dateFormat.format(startDate)} to ${dateFormat.format(now)}'),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text('Infrastructure Overview', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          _buildSummaryTable(devices),
          pw.SizedBox(height: 30),
          pw.Text('Detailed Node Performance', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          ...devices.map((d) => _buildDeviceSection(d)),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/PingIT_Report_${DateFormat('yyyyMMdd').format(now)}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  pw.Widget _buildSummaryTable(List<Device> devices) {
    final onlineCount = devices.where((d) => d.status == DeviceStatus.online).length;
    final offlineCount = devices.where((d) => d.status == DeviceStatus.offline).length;
    final degradedCount = devices.where((d) => d.status == DeviceStatus.degraded).length;

    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headers: ['Total Nodes', 'Online', 'Degraded', 'Offline', 'Avg. SLA'],
      data: [
        [
          devices.length.toString(),
          onlineCount.toString(),
          degradedCount.toString(),
          offlineCount.toString(),
          '${_calculateGlobalSLA(devices).toStringAsFixed(2)}%',
        ]
      ],
    );
  }

  pw.Widget _buildDeviceSection(Device d) {
    final uptime = d.stabilityScore;
    final color = uptime >= 99 ? PdfColors.green : (uptime >= 95 ? PdfColors.orange : PdfColors.red);

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 15),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(d.name, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              pw.Text('${uptime.toStringAsFixed(2)}% Uptime', style: pw.TextStyle(color: color, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 5),
          pw.Text('Address: ${d.address} | Type: ${d.type.name.toUpperCase()}'),
          pw.Text('Recent Latency: ${d.lastLatency?.toStringAsFixed(1) ?? "N/A"}ms'),
        ],
      ),
    );
  }

  double _calculateGlobalSLA(List<Device> devices) {
    if (devices.isEmpty) return 100.0;
    return devices.map((d) => d.stabilityScore).reduce((a, b) => a + b) / devices.length;
  }
}
