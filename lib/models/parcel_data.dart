class ParcelData {
  final String trackingNumber;
  final String cartonCurrent;
  final String cartonTotal;
  final List<String> addressLines;
  final String prefix;

  ParcelData({
    required this.trackingNumber,
    required this.cartonCurrent,
    required this.cartonTotal,
    required this.addressLines,
    required this.prefix,
  });

  String get newTrackingNumber =>
      '$prefix$trackingNumber-$cartonCurrent';

  String get cartonDisplay => '$cartonCurrent/$cartonTotal';

  String get addressDisplay => addressLines.join('\n');

  ParcelData copyWith({
    String? trackingNumber,
    String? cartonCurrent,
    String? cartonTotal,
    List<String>? addressLines,
    String? prefix,
  }) {
    return ParcelData(
      trackingNumber: trackingNumber ?? this.trackingNumber,
      cartonCurrent: cartonCurrent ?? this.cartonCurrent,
      cartonTotal: cartonTotal ?? this.cartonTotal,
      addressLines: addressLines ?? this.addressLines,
      prefix: prefix ?? this.prefix,
    );
  }
}
