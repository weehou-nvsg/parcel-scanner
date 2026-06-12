import 'drivers/honeywell_cpcl_driver.dart';
import 'drivers/hprt_zpl_driver.dart';
import 'drivers/paperang_p1_driver.dart';
import 'printer_driver.dart';

/// One entry in the supported-printer registry.
class PrinterModelInfo {
  final String id;
  final String name;
  final String description;
  final PrinterDriver Function() createDriver;

  const PrinterModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.createDriver,
  });
}

/// Registry of supported printer models. To add a model: write a
/// `PrinterDriver` (usually extending `SppPrinterDriver`) and add an entry
/// here — the Settings selector and `PrinterService` pick it up automatically.
class PrinterModels {
  static const String prefKey = 'printer_model';

  /// Model used when no `printer_model` pref is set — matches the behavior
  /// the app shipped with before model selection existed.
  static const String defaultId = honeywellRp4b;

  static const String hprtHmT3 = 'hprt_hm_t3';
  static const String honeywellRp4b = 'honeywell_rp4b';
  static const String paperangP1 = 'paperang_p1';

  static final List<PrinterModelInfo> all = [
    PrinterModelInfo(
      id: hprtHmT3,
      name: 'HPRT HM-T3 Pro',
      description: 'ZPL · 75×50 mm label stock',
      createDriver: () => HprtZplDriver(),
    ),
    PrinterModelInfo(
      id: honeywellRp4b,
      name: 'Honeywell RP4B',
      description: 'CPCL · 100×150 mm label stock',
      createDriver: () => HoneywellCpclDriver(),
    ),
    PrinterModelInfo(
      id: paperangP1,
      name: 'Paperang P1',
      description: 'Raster · 57 mm receipt paper',
      createDriver: () => PaperangP1Driver(),
    ),
  ];

  static PrinterModelInfo byId(String id) => all.firstWhere(
        (m) => m.id == id,
        orElse: () => all.firstWhere((m) => m.id == defaultId),
      );
}
