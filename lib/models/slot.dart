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
  final String? accountId;
  final String? accountName;
  final String? salesOrderName;
  final String? positionsname;
  final String? firmaFarbcode;
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
  final String? bewacherID;
  final String? personalausweisnummer;
  final bool? kleidung;
  final String? kleidungAnmerkungen;
  final String? neueobjektkleidung;
  final String? neueobjektkleidunganmerkung;

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
    this.accountId,
    this.accountName,
    this.salesOrderName,
    this.positionsname,
    this.firmaFarbcode,
    this.kooperationspartnerName,
    this.stundenanzahl,
    this.checkin,
    this.checkout,
    this.neueobjektstrasse,
    this.neueobjektplz,
    this.neueobjektort,
    this.firmastrasse,
    this.firmaplz,
    this.firmaort,
    this.latk,
    this.lonK,
    this.bewacherID,
    this.personalausweisnummer,
    this.kleidung,
    this.kleidungAnmerkungen,
    this.neueobjektkleidung,
    this.neueobjektkleidunganmerkung,
  });

  factory Slot.fromJson(Map<String, dynamic> json) {
    return Slot(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      status: json['status'] ?? '',
      dateStart: json['dateStart'],
      dateEnd: json['dateEnd'],
      schichtbezeichnung: json['schichtbezeichnung'],
      objekteId: json['objekteId'],
      objekteName: json['objekteName'],
      angestellteId: json['angestellteId'],
      angestellteName: json['angestellteName'],
      accountId: json['accountId'],
      accountName: json['accountName'],
      salesOrderName: json['salesOrderName'],
      positionsname: json['positionsname'],
      firmaFarbcode: json['firmaFarbcode'],
      kooperationspartnerName: json['kooperationspartnerName'],
      neueobjektstrasse: json['neueobjektstrasse'],
      neueobjektplz: json['neueobjektplz'],
      neueobjektort: json['neueobjektort'],
      firmastrasse: json['firmastrasse'],
      firmaplz: json['firmaplz'],
      firmaort: json['firmaort'],
      checkin: json['checkin'],
      checkout: json['checkout'],
      stundenanzahl: json['stundenanzahl'] != null
          ? (json['stundenanzahl'] as num).toDouble()
          : null,
      latk: json['latk'] != null ? (json['latk'] as num).toDouble() : null,
      lonK: json['lonK'] != null ? (json['lonK'] as num).toDouble() : null,
      bewacherID: json['bewacherID'],
      personalausweisnummer: json['personalausweisnummer'],
      kleidung: json['kleidung'] == true,
      kleidungAnmerkungen: json['kleidungAnmerkungen']?.toString(),
      neueobjektkleidung: json['neueobjektkleidung']?.toString(),
      neueobjektkleidunganmerkung: json['neueobjektkleidunganmerkung']?.toString(),
    );
  }
}
