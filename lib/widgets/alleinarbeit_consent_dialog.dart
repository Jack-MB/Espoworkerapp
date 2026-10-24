import 'package:flutter/material.dart';
import '../models/slot.dart';

/**
 * DGUV V23 & DSGVO-Einwilligungsdialog für Alleinarbeiterschutz.
 * Wird STRIKT nur angezeigt, wenn sich ein Mitarbeiter auf einer echten Nachtschicht
 * eincheckt, für die Alleinarbeiterschutz aktiviert ist.
 */
Future<bool?> showAlleinarbeitConsentDialog(BuildContext context, Slot slot) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Alleinarbeiterschutz',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade900.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade400.withOpacity(0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.gavel, color: Colors.blue.shade300, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Gemäß DGUV Vorschrift 23 § 8 & § 5 ArbSchG ist für diesen Einzelposten ein Schutz-Tracking angeordnet.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'Zu Ihrer persönlichen Sicherheit und schnellen Notfall-Lokalisierung übermittelt die App während dieser Schicht punktuell Ihren aktuellen Standort an die mobile Leitstelle.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade300, height: 1.4),
            ),
            const SizedBox(height: 14),
            _buildConsentFeatureRow(
              icon: Icons.battery_saver,
              title: 'Akkuschonendes Intervall',
              description: 'Punktuelles GPS-Wakeup alle ${slot.alleinarbeitIntervallMinuten} Min. (nur 5–10 Sek.), kein permanentes Dauer-GPS.',
            ),
            const SizedBox(height: 10),
            _buildConsentFeatureRow(
              icon: Icons.timer_outlined,
              title: 'Nur während aktiver Schicht',
              description: 'Startet automatisch beim Check-In und stoppt unwiderruflich beim Check-Out.',
            ),
            const SizedBox(height: 10),
            _buildConsentFeatureRow(
              icon: Icons.lock_clock_outlined,
              title: 'DSGVO-konforme Datenlöschung',
              description: 'Standortkoordinaten werden nach 14 Tagen automatisiert und unwiderruflich aus der Datenbank gelöscht.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Abbrechen', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Zustimmen & Einchecken'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    ),
  );
}

Widget _buildConsentFeatureRow({
  required IconData icon,
  required String title,
  required String description,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: const Color(0xFF10B981)),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400, height: 1.3),
            ),
          ],
        ),
      ),
    ],
  );
}
