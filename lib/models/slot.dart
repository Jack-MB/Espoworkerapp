class Slot {
  final String id;
  final String name;
  final String status;
  final String? dateStart;
  final String? dateEnd;
  final String? schichtbezeichnung;
  final String? objekteId;
  final String? objekteName;
  final String? angestellteId;
  final String? angestellteName;
  final String? angestelltePhone;
  final String? accountId;
  final String? accountName;
  final String? salesOrderName;
  final String? positionsname;
  final String? firmaFarbcode;
  final String? color; // Direkte Schichtfarbe (= EspoCRM Kalenderfarbe)
  final String? kooperationspartnerId;
  final String? kooperationspartnerName;
  final double? stundenanzahl;
  final String? checkin;
  final String? checkout;
  final String? neueobjektstrasse;
  final String? neueobjektplz;
  final String? neueobjektort;
  final String? firmastrasse;
  final String? firmaplz;
  final String? firmaort;
  final double? latk;
  final double? lonK;
  final int? geofenceRadius;
  final int? rad;
  final String? bewacherID;
  final String? personalausweisnummer;
  final bool? kleidung;
  final String? kleidungAnmerkungen;
  final String? neueobjektkleidung;
  final String? neueobjektkleidunganmerkung;
  // Schicht-Annahme
  final String? annahmeStatus; // 'Wartend' | 'Angenommen' | 'Abgelehnt' | 'Rückgabe_Beantragt' | null

  // Einsatzleiter
  final String? einsatzleiterId;
  final String? einsatzleiterName;

  // Pünktlichkeit & Check-In
  final String? cI; // '🟢' | '🟡' | '🔴' | '⚪'
  final String? oNr; // Ordnernummer (z. B. "0071", "42", "99")
  final String? empDefaultOnr; // Standard-Ordnernummer des Mitarbeiters aus Profil
  final bool? canEditOnr; // Serverseitig berechnet: Darf der Nutzer die oNr bearbeiten?

  Slot({
    required this.id,
    required this.name,
    required this.status,
    this.dateStart,
    this.dateEnd,
    this.schichtbezeichnung,
    this.objekteId,
    this.objekteName,
    this.angestellteId,
    this.angestellteName,
    this.angestelltePhone,
    this.einsatzleiterId,
    this.einsatzleiterName,
    this.accountId,
    this.accountName,
    this.salesOrderName,
    this.positionsname,
    this.firmaFarbcode,
    this.color,
    this.kooperationspartnerId,
    this.kooperationspartnerName,
    this.stundenanzahl,
    this.checkin,
    this.checkout,
    this.cI,
    this.oNr,
    this.empDefaultOnr,
    this.canEditOnr,
    this.neueobjektstrasse,
    this.neueobjektplz,
    this.neueobjektort,
    this.firmastrasse,
    this.firmaplz,
    this.firmaort,
    this.latk,
    this.lonK,
    this.geofenceRadius,
    this.rad,
    this.bewacherID,
    this.personalausweisnummer,
    this.kleidung,
    this.kleidungAnmerkungen,
    this.neueobjektkleidung,
    this.neueobjektkleidunganmerkung,
    this.annahmeStatus,
  });

  factory Slot.fromJson(Map<String, dynamic> json) {
    return Slot(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      status: json['status'] ?? '',
      dateStart: json['dateStart'],
      dateEnd: json['dateEnd'],
      schichtbezeichnung: json['schichtbezeichnung'],
      objekteId: json['serviceObjectId'] ?? json['objekteId'],
      objekteName: json['serviceObjectName'] ?? json['objekteName'],
      angestellteId: json['angestellteId'],
      angestellteName: json['angestellteName'],
      angestelltePhone: json['angestelltePhone']?.toString(),
      einsatzleiterId: json['einsatzleiterId'],
      einsatzleiterName: json['einsatzleiterName'],
      accountId: json['accountId'],
      accountName: json['accountName'],
      salesOrderName: json['salesOrderName'],
      positionsname: json['positionsname'],
      firmaFarbcode: json['firmaFarbcode'],
      color: json['color'],
      kooperationspartnerId: json['kooperationspartnerId'] ?? json['kooperationspartner_id'],
      kooperationspartnerName: json['kooperationspartnerName'],
      neueobjektstrasse: json['neueobjektstrasse'],
      neueobjektplz: json['neueobjektplz'],
      neueobjektort: json['neueobjektort'],
      firmastrasse: json['firmastrasse'],
      firmaplz: json['firmaplz'],
      firmaort: json['firmaort'],
      checkin: json['checkin'],
      checkout: json['checkout'],
      cI: json['cI']?.toString() ?? json['c_i']?.toString(),
      oNr: json['oNr']?.toString() ?? json['o_nr']?.toString(),
      empDefaultOnr: json['empDefaultOnr']?.toString() ?? json['empPersonalnummer']?.toString(),
      canEditOnr: json['canEditOnr'] == true,
      stundenanzahl: _parseDouble(json['stundenanzahl']),
      latk: _parseDouble(json['latk']),
      lonK: _parseDouble(json['lonK']),
      geofenceRadius: int.tryParse(json['geofenceRadius']?.toString() ?? '') ?? int.tryParse(json['rad']?.toString() ?? ''),
      rad: int.tryParse(json['rad']?.toString() ?? '') ?? int.tryParse(json['geofenceRadius']?.toString() ?? ''),
      bewacherID: json['bewacherID'],
      personalausweisnummer: json['personalausweisnummer'],
      kleidung: json['kleidung'] == true,
      kleidungAnmerkungen: json['kleidungAnmerkungen']?.toString(),
      neueobjektkleidung: json['neueobjektkleidung']?.toString(),
      neueobjektkleidunganmerkung: json['neueobjektkleidunganmerkung']?.toString(),
      annahmeStatus: json['annahmeStatus']?.toString(),
    );
  }

  Slot copyWith({
    String? id,
    String? name,
    String? status,
    String? dateStart,
    String? dateEnd,
    String? schichtbezeichnung,
    String? objekteId,
    String? objekteName,
    String? angestellteId,
    String? angestellteName,
    String? angestelltePhone,
    String? einsatzleiterId,
    String? einsatzleiterName,
    String? accountId,
    String? accountName,
    String? salesOrderName,
    String? positionsname,
    String? firmaFarbcode,
    String? color,
    String? kooperationspartnerId,
    String? kooperationspartnerName,
    double? stundenanzahl,
    String? checkin,
    String? checkout,
    String? cI,
    String? oNr,
    String? empDefaultOnr,
    bool? canEditOnr,
    String? neueobjektstrasse,
    String? neueobjektplz,
    String? neueobjektort,
    String? firmastrasse,
    String? firmaplz,
    String? firmaort,
    double? latk,
    double? lonK,
    int? geofenceRadius,
    int? rad,
    String? bewacherID,
    String? personalausweisnummer,
    bool? kleidung,
    String? kleidungAnmerkungen,
    String? neueobjektkleidung,
    String? neueobjektkleidunganmerkung,
    String? annahmeStatus,
  }) {
    return Slot(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      dateStart: dateStart ?? this.dateStart,
      dateEnd: dateEnd ?? this.dateEnd,
      schichtbezeichnung: schichtbezeichnung ?? this.schichtbezeichnung,
      objekteId: objekteId ?? this.objekteId,
      objekteName: objekteName ?? this.objekteName,
      angestellteId: angestellteId ?? this.angestellteId,
      angestellteName: angestellteName ?? this.angestellteName,
      angestelltePhone: angestelltePhone ?? this.angestelltePhone,
      einsatzleiterId: einsatzleiterId ?? this.einsatzleiterId,
      einsatzleiterName: einsatzleiterName ?? this.einsatzleiterName,
      accountId: accountId ?? this.accountId,
      accountName: accountName ?? this.accountName,
      salesOrderName: salesOrderName ?? this.salesOrderName,
      positionsname: positionsname ?? this.positionsname,
      firmaFarbcode: firmaFarbcode ?? this.firmaFarbcode,
      color: color ?? this.color,
      kooperationspartnerId: kooperationspartnerId ?? this.kooperationspartnerId,
      kooperationspartnerName: kooperationspartnerName ?? this.kooperationspartnerName,
      stundenanzahl: stundenanzahl ?? this.stundenanzahl,
      checkin: checkin ?? this.checkin,
      checkout: checkout ?? this.checkout,
      cI: cI ?? this.cI,
      oNr: oNr ?? this.oNr,
      empDefaultOnr: empDefaultOnr ?? this.empDefaultOnr,
      canEditOnr: canEditOnr ?? this.canEditOnr,
      neueobjektstrasse: neueobjektstrasse ?? this.neueobjektstrasse,
      neueobjektplz: neueobjektplz ?? this.neueobjektplz,
      neueobjektort: neueobjektort ?? this.neueobjektort,
      firmastrasse: firmastrasse ?? this.firmastrasse,
      firmaplz: firmaplz ?? this.firmaplz,
      firmaort: firmaort ?? this.firmaort,
      latk: latk ?? this.latk,
      lonK: lonK ?? this.lonK,
      geofenceRadius: geofenceRadius ?? this.geofenceRadius,
      rad: rad ?? this.rad,
      bewacherID: bewacherID ?? this.bewacherID,
      personalausweisnummer: personalausweisnummer ?? this.personalausweisnummer,
      kleidung: kleidung ?? this.kleidung,
      kleidungAnmerkungen: kleidungAnmerkungen ?? this.kleidungAnmerkungen,
      neueobjektkleidung: neueobjektkleidung ?? this.neueobjektkleidung,
      neueobjektkleidunganmerkung: neueobjektkleidunganmerkung ?? this.neueobjektkleidunganmerkung,
      annahmeStatus: annahmeStatus ?? this.annahmeStatus,
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.'));
    return null;
  }

  /// Helper to get a color/icon for the current annahmeStatus
  bool get isPending    => annahmeStatus == 'Wartend';
  bool get isAccepted   => annahmeStatus == 'Angenommen';
  bool get isRejected   => annahmeStatus == 'Abgelehnt';
  bool get isRueckgabe  => annahmeStatus == 'Rückgabe_Beantragt';
  bool get hasAnnahmeStatus => annahmeStatus != null && annahmeStatus!.isNotEmpty;

  /// Helper: Ist der angegebene Mitarbeiter der Einsatzleiter für diese Schicht?
  bool isEinsatzleiter(String? currentAngestellteId) {
    if (currentAngestellteId == null || currentAngestellteId.isEmpty) return false;
    return einsatzleiterId == currentAngestellteId;
  }

  /// Prüft, ob der Nutzer (als Admin oder zuständiger Einsatzleiter) die Ordnernummer ändern darf.
  bool canUserEditOnr(String? currentAngestellteId, {bool isAdmin = false}) {
    if (isAdmin) return true;
    if (canEditOnr == true) return true;
    return isEinsatzleiter(currentAngestellteId);
  }
}
