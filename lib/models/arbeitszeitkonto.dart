class Arbeitszeitkonto {
  final String id;
  final String? name;
  final String? monat;
  final int? jahr;
  final String? angestellteName;
  final String? angestellteId;

  final double? sollStunden;
  final double? istStunden;
  final double? ueberstunden;
  final double? nachtStunden;
  final double? feiertagStunden;
  final double? samstagStunden;
  final double? sonntagStunden;
  final double? elStunden;
  final double? bruttoStunden;
  final double? istStundenKorrektur;

  final int? krankTage;
  final int? krankTageMitSchicht;
  final int? krankTageOhneSchicht;
  final int? urlaubsTage;
  final int? arbeitsTage;
  final int? verstossAnzahl;
  final int? einsatzorte;
  final int? pausenMinutenGesamt;
  final int? krankTageKorrektur;
  final int? urlaubsTageKorrektur;

  final double? durchschnPuenktlichkeit;
  final double? krankheitsTagessatz;
  final double? referenzStundenProTag;

  final bool freigegeben;
  final String? freigegebenAm;
  final String? notizen;

  Arbeitszeitkonto({
    required this.id,
    this.name,
    this.monat,
    this.jahr,
    this.angestellteName,
    this.angestellteId,
    this.sollStunden,
    this.istStunden,
    this.ueberstunden,
    this.nachtStunden,
    this.feiertagStunden,
    this.samstagStunden,
    this.sonntagStunden,
    this.elStunden,
    this.bruttoStunden,
    this.istStundenKorrektur,
    this.krankTage,
    this.krankTageMitSchicht,
    this.krankTageOhneSchicht,
    this.urlaubsTage,
    this.arbeitsTage,
    this.verstossAnzahl,
    this.einsatzorte,
    this.pausenMinutenGesamt,
    this.krankTageKorrektur,
    this.urlaubsTageKorrektur,
    this.durchschnPuenktlichkeit,
    this.krankheitsTagessatz,
    this.referenzStundenProTag,
    this.freigegeben = false,
    this.freigegebenAm,
    this.notizen,
  });

  factory Arbeitszeitkonto.fromJson(Map<String, dynamic> json) {
    return Arbeitszeitkonto(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString(),
      monat: json['monat']?.toString(),
      jahr: json['jahr'] is int ? json['jahr'] : int.tryParse(json['jahr']?.toString() ?? ''),
      angestellteName: json['angestellteName']?.toString(),
      angestellteId: json['angestellteId']?.toString(),
      sollStunden: (json['sollStunden'] as num?)?.toDouble(),
      istStunden: (json['istStunden'] as num?)?.toDouble(),
      ueberstunden: (json['ueberstunden'] as num?)?.toDouble(),
      nachtStunden: (json['nachtStunden'] as num?)?.toDouble(),
      feiertagStunden: (json['feiertagStunden'] as num?)?.toDouble(),
      samstagStunden: (json['samstagStunden'] as num?)?.toDouble(),
      sonntagStunden: (json['sonntagStunden'] as num?)?.toDouble(),
      elStunden: (json['elStunden'] as num?)?.toDouble(),
      bruttoStunden: (json['bruttoStunden'] as num?)?.toDouble(),
      istStundenKorrektur: (json['istStundenKorrektur'] as num?)?.toDouble(),
      krankTage: json['krankTage'] is int ? json['krankTage'] : int.tryParse(json['krankTage']?.toString() ?? ''),
      krankTageMitSchicht: json['krankTageMitSchicht'] is int ? json['krankTageMitSchicht'] : int.tryParse(json['krankTageMitSchicht']?.toString() ?? ''),
      krankTageOhneSchicht: json['krankTageOhneSchicht'] is int ? json['krankTageOhneSchicht'] : int.tryParse(json['krankTageOhneSchicht']?.toString() ?? ''),
      urlaubsTage: json['urlaubsTage'] is int ? json['urlaubsTage'] : int.tryParse(json['urlaubsTage']?.toString() ?? ''),
      arbeitsTage: json['arbeitsTage'] is int ? json['arbeitsTage'] : int.tryParse(json['arbeitsTage']?.toString() ?? ''),
      verstossAnzahl: json['verstossAnzahl'] is int ? json['verstossAnzahl'] : int.tryParse(json['verstossAnzahl']?.toString() ?? ''),
      einsatzorte: json['einsatzorte'] is int ? json['einsatzorte'] : int.tryParse(json['einsatzorte']?.toString() ?? ''),
      pausenMinutenGesamt: json['pausenMinutenGesamt'] is int ? json['pausenMinutenGesamt'] : int.tryParse(json['pausenMinutenGesamt']?.toString() ?? ''),
      krankTageKorrektur: json['krankTageKorrektur'] is int ? json['krankTageKorrektur'] : int.tryParse(json['krankTageKorrektur']?.toString() ?? ''),
      urlaubsTageKorrektur: json['urlaubsTageKorrektur'] is int ? json['urlaubsTageKorrektur'] : int.tryParse(json['urlaubsTageKorrektur']?.toString() ?? ''),
      durchschnPuenktlichkeit: (json['durchschnPuenktlichkeit'] as num?)?.toDouble(),
      krankheitsTagessatz: (json['krankheitsTagessatz'] as num?)?.toDouble(),
      referenzStundenProTag: (json['referenzStundenProTag'] as num?)?.toDouble(),
      freigegeben: json['freigegeben'] == true,
      freigegebenAm: json['freigegebenAm'],
      notizen: json['notizen'],
    );
  }

  // Effective Ist-Stunden including correction
  double get istStundenEffektiv => (istStunden ?? 0) + (istStundenKorrektur ?? 0);

  // Effective sick days including correction
  int get krankTageEffektiv => (krankTage ?? 0) + (krankTageKorrektur ?? 0);

  // Whether this record has any detailed sick day breakdown
  bool get hasKrankDetail =>
      (krankTageMitSchicht ?? 0) > 0 || (krankTageOhneSchicht ?? 0) > 0;

  // Effective vacation days including correction
  int get urlaubsTageEffektiv => (urlaubsTage ?? 0) + (urlaubsTageKorrektur ?? 0);

  static const _monatMap = {
    'January': 'Januar', 'February': 'Februar', 'March': 'März',
    'April': 'April', 'May': 'Mai', 'June': 'Juni',
    'July': 'Juli', 'August': 'August', 'September': 'September',
    'October': 'Oktober', 'November': 'November', 'December': 'Dezember',
  };

  String get monatLabel => _monatMap[monat] ?? monat ?? '';
}
