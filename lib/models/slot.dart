import '../utils/espo_date.dart';

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
  final bool? isPartner; // Serverseitig ermittelt: Externe Partnerfirma
  final bool? isIntern; // Serverseitig ermittelt: Intern MB-SCC
  final bool? isEinsatzleiterServer; // Serverseitig ermittelt: Einsatzleiter oder Zuweisungs-Berechtigung
  final String? ersatzNotiz; // Vor-Ort-Ersatz / Tausch / Springer-Notiz
  final bool? isManualSpringer; // Manuell erfasster Springer ohne Profil

  // DGUV V23 Alleinarbeiterschutz
  final bool isAlleinarbeit;
  final int alleinarbeitIntervallMinuten;
  String? alleinarbeitConsentAt;

  bool get isSpringer => isManualSpringer == true || (ersatzNotiz != null && ersatzNotiz!.trim().isNotEmpty);

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
    this.isPartner,
    this.isIntern,
    this.isEinsatzleiterServer,
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
    this.ersatzNotiz,
    this.isManualSpringer,
    this.isAlleinarbeit = false,
    this.alleinarbeitIntervallMinuten = 10,
    this.alleinarbeitConsentAt,
  });

  factory Slot.fromJson(Map<String, dynamic> json) {
    final rawErsatz = json['ersatzNotiz']?.toString() ?? json['ersatz_notiz']?.toString();
    String? empName = json['angestellteName']?.toString();
    String? bwrId = json['bewacherID']?.toString() ?? json['bewacherId']?.toString();
    bool isManual = json['isManualSpringer'] == true || (rawErsatz != null && rawErsatz.contains('[Manuell erfasst]'));

    if (rawErsatz != null && rawErsatz.isNotEmpty) {
      if (empName == null || empName.trim().isEmpty) {
        final mName = RegExp(r'Name:\s*([^\|\n\r]+)').firstMatch(rawErsatz);
        if (mName != null) {
          final candName = mName.group(1)?.trim();
          if (candName != null && candName.isNotEmpty) {
            empName = candName;
            isManual = true;
          }
        }
      }
      if (bwrId == null || bwrId.trim().isEmpty) {
        final mBwr = RegExp(r'Bewacher-ID:\s*([^\|\n\r]+)').firstMatch(rawErsatz);
        if (mBwr != null) {
          final cand = mBwr.group(1)?.trim();
          if (cand != null && cand.isNotEmpty && cand != 'Keine') {
            bwrId = cand;
          }
        }
      }
    }

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
      angestellteName: empName,
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
      isPartner: json['isPartner'] == true,
      isIntern: json['isIntern'] == true,
      isEinsatzleiterServer: json['isEinsatzleiter'] == true || json['canAssignEmployee'] == true,
      stundenanzahl: _parseDouble(json['stundenanzahl']),
      latk: _parseDouble(json['latk']),
      lonK: _parseDouble(json['lonK']),
      geofenceRadius: int.tryParse(json['geofenceRadius']?.toString() ?? '') ?? int.tryParse(json['rad']?.toString() ?? ''),
      rad: int.tryParse(json['rad']?.toString() ?? '') ?? int.tryParse(json['geofenceRadius']?.toString() ?? ''),
      bewacherID: bwrId,
      personalausweisnummer: json['personalausweisnummer'],
      kleidung: json['kleidung'] == true,
      kleidungAnmerkungen: json['kleidungAnmerkungen']?.toString(),
      neueobjektkleidung: json['neueobjektkleidung']?.toString(),
      neueobjektkleidunganmerkung: json['neueobjektkleidunganmerkung']?.toString(),
      annahmeStatus: json['annahmeStatus']?.toString(),
      ersatzNotiz: rawErsatz,
      isManualSpringer: isManual,
      isAlleinarbeit: json['isAlleinarbeit'] == true || json['is_alleinarbeit'] == true || json['isAlleinarbeit'] == 1 || json['is_alleinarbeit'] == 1 || json['isAlleinarbeit'] == '1' || json['is_alleinarbeit'] == '1' || json['isAlleinarbeit'] == 'true' || json['is_alleinarbeit'] == 'true',
      alleinarbeitIntervallMinuten: int.tryParse(json['alleinarbeitIntervallMinuten']?.toString() ?? json['alleinarbeit_intervall_minuten']?.toString() ?? '') ?? 10,
      alleinarbeitConsentAt: json['alleinarbeitConsentAt']?.toString() ?? json['alleinarbeit_consent_at']?.toString(),
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
    bool? isPartner,
    bool? isIntern,
    bool? isEinsatzleiterServer,
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
    String? ersatzNotiz,
    bool? isManualSpringer,
    bool? isAlleinarbeit,
    int? alleinarbeitIntervallMinuten,
    String? alleinarbeitConsentAt,
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
      isPartner: isPartner ?? this.isPartner,
      isIntern: isIntern ?? this.isIntern,
      isEinsatzleiterServer: isEinsatzleiterServer ?? this.isEinsatzleiterServer,
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
      ersatzNotiz: ersatzNotiz ?? this.ersatzNotiz,
      isManualSpringer: isManualSpringer ?? this.isManualSpringer,
      isAlleinarbeit: isAlleinarbeit ?? this.isAlleinarbeit,
      alleinarbeitIntervallMinuten: alleinarbeitIntervallMinuten ?? this.alleinarbeitIntervallMinuten,
      alleinarbeitConsentAt: alleinarbeitConsentAt ?? this.alleinarbeitConsentAt,
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
    if (isEinsatzleiterServer == true) return true;
    if (currentAngestellteId == null || currentAngestellteId.isEmpty) return false;
    return einsatzleiterId == currentAngestellteId;
  }

  /// Prüft, ob der Nutzer (als Admin oder zuständiger Einsatzleiter) die Ordnernummer ändern darf.
  bool canUserEditOnr(String? currentAngestellteId, {bool isAdmin = false}) {
    if (isAdmin) return true;
    if (canEditOnr == true) return true;
    return isEinsatzleiter(currentAngestellteId);
  }

  /// Gibt an, ob diese Schicht von einer externen Partnerfirma besetzt ist
  bool get isExternalPartner {
    if (isPartner != null) return isPartner!;
    final kId = kooperationspartnerId;
    if (kId == null || kId.isEmpty) return false;
    return kId != '69e9f2a93910fbbbc' && kId != '6a05b9091aed30701';
  }

  /// Gibt an, ob diese Schicht intern durch MB-SCC besetzt ist
  bool get isInternalEmployee => !isExternalPartner;

  /// Gibt den ursprünglich geplanten Namen zurück, falls ein Schichttausch/Ersatz stattfand
  String? get originalGeplantName {
    if (ersatzNotiz == null || ersatzNotiz!.isEmpty) return null;
    final m = RegExp(r'Ursprünglich geplant:\s*([^\|\n\r]+)').firstMatch(ersatzNotiz!);
    if (m != null) {
      final name = m.group(1)?.trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return null;
  }

  /// Gibt den manuell erfassten Springer-Namen zurück, falls vorhanden
  String? get springerName {
    if (ersatzNotiz == null || ersatzNotiz!.isEmpty) return null;
    final m = RegExp(r'Name:\s*([^\|\n\r]+)').firstMatch(ersatzNotiz!);
    if (m != null) {
      final name = m.group(1)?.trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return null;
  }

  /// Gibt die manuell erfasste Bewacher-ID aus der Ersatznotiz zurück
  String? get springerBewacherId {
    if (ersatzNotiz == null || ersatzNotiz!.isEmpty) return null;
    final m = RegExp(r'Bewacher-ID:\s*([^\|\n\r]+)').firstMatch(ersatzNotiz!);
    if (m != null) {
      final bId = m.group(1)?.trim();
      if (bId != null && bId.isNotEmpty && bId != 'Keine') return bId;
    }
    return null;
  }

  /// Liefert den effektiven Mitarbeiternamen für die Anzeige (egal ob regulär oder Springer)
  String? get effectiveEmployeeName {
    if (angestellteName != null && angestellteName!.trim().isNotEmpty) {
      return angestellteName!.trim();
    }
    return springerName;
  }

  /// Gibt an, ob ein Ersatz/Tausch oder Springer auf dieser Schicht aktiv ist
  bool get hasErsatzOderTausch {
    return isSpringer || originalGeplantName != null || springerName != null;
  }

  /// Prüft, ob diese Schicht eine Nachtschicht ist (Name/Bezeichnung enthält "Nacht",
  /// Beginn ab 19:00 oder vor 05:00 Uhr, oder Überschreiten von Mitternacht).
  bool get isNachtschicht {
    final text = '${name} ${schichtbezeichnung ?? ''}'.toLowerCase();
    if (text.contains('nacht')) {
      return true;
    }

    if (dateStart != null && dateStart!.trim().isNotEmpty) {
      try {
        final startLocal = espoUtcToLocal(dateStart!);
        final startHour = startLocal.hour;

        if (startHour >= 19 || startHour < 5) {
          return true;
        }

        if (dateEnd != null && dateEnd!.trim().isNotEmpty) {
          final endLocal = espoUtcToLocal(dateEnd!);

          if (endLocal.day != startLocal.day || endLocal.isBefore(startLocal)) {
            return true;
          }

          if (endLocal.hour <= 7 && startHour >= 18) {
            return true;
          }
        }
      } catch (_) {}
    }

    return false;
  }

  /// Alleinarbeiterschutz greift STRIKT nur, wenn Alleinarbeit aktiviert UND es eine Nachtschicht ist!
  bool get isAlleinarbeitNachtschicht => isAlleinarbeit && isNachtschicht;
}
