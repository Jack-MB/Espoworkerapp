# Push-Benachrichtigungen mit EspoCRM, n8n und Firebase (FCM)

Damit du Benachrichtigungen (Push Notifications) aus EspoCRM vollautomatisch an die Mitarbeiter-Handys schicken kannst, benötigst du eine Brücke zwischen **EspoCRM** und **Firebase Cloud Messaging**. Hierfür ist **n8n** ideal, da es Webhooks entgegennimmt und die Firebase API sicher ansprechen kann.

Die App ist bereits so vorbereitet, dass sie bei jedem Login das FCM-Token des Geräts an EspoCRM schickt.

---

## 1. Vorbereitung in EspoCRM
Da die App den Identifikationsschlüssel (das _FCM Token_) des Handys direkt beim Login über die API im Benutzer-Profil speichert, musst du dieses Feld bereitstellen.

1. Gehe in EspoCRM zu **Administration > Entitäten-Manager > User > Felder**.
2. Erstelle ein neues Feld:
   - **Typ:** `varchar`
   - **Name:** `fcmToken` *(Achte exakt auf diese Schreibweise!)*
   - **Länge:** 255
3. Speichere und leere den Cache in EspoCRM.

> [!NOTE]
> Jedes Mal, wenn sich nun ein Mitarbeiter in der App einloggt, wird die App das FCM-Token automatisch in sein EspoCRM-Benutzerprofil schreiben.

---

## 2. Firebase Zugangsdaten abrufen
n8n benötigt Rechte, um in deinem Namen Firebase-Nachrichten zu versenden. Dafür wird ein Service Account benötigt.

1. Öffne die [Firebase Console](https://console.firebase.google.com) und wähle dein Projekt (`espocrm-worker-app`).
2. Klicke links oben auf das **Zahnrad-Symbol** -> **Projekteinstellungen**.
3. Wechsle auf den Reiter **Dienstkonten** (Service Accounts).
4. Klicke auf **Neuen privaten Schlüssel generieren** und lade die JSON-Datei herunter.

---

## 3. n8n konfigurieren (Der Workflow)
In n8n legst du nun einen Workflow an, der Signale von EspoCRM empfängt und an Firebase weiterleitet.

### Knoten 1: Webhook (Der Empfänger)
Füge einen `Webhook` Node hinzu:
- **Authentication:** None (oder nach Belieben per Header-Auth)
- **HTTP Method:** `POST`
- **Path:** z.B. `send-smartphone-push`
- *Notiere dir die Webhook-URL (Test & Production).*

### Credentials-Einrichtung in n8n
Bevor wir die Nachricht abschicken, füge deine Firebase-Zugangsdaten in n8n hinzu:
1. Gehe links in n8n auf **Credentials** -> **Add Credential**.
2. Suche nach **Google API**.
3. Wähle als Auth Type **Service Account**.
4. Kopiere den gesamten Inhalt aus deiner zuvor heruntergeladenen Firebase JSON-Datei und füge ihn ein.
5. Benenne die Credentials "Firebase FCM".

### Knoten 2: HTTP Request (Der Sender)
Führe den Webhook nun zu einem `HTTP Request` Node.
Diesen Node konfigurierst du so, dass er die neueste Firebase API v1 anspricht:

- **Authentication:** Generic Credential Type
- **Generic Credential Type:** **OAuth2 API** oder **Google API** (wähle hier deine eben erstellten 'Firebase FCM' Credentials aus).
  > **WICHTIG:** Wenn du nach Scopes gefragt wirst, trage `https://www.googleapis.com/auth/firebase.messaging` ein.
- **Method:** `POST`
- **URL:** `https://fcm.googleapis.com/v1/projects/espocrm-worker-app/messages:send` *(Passe ggf. deine Project ID an, sie steht oben in der JSON-Datei).*
- **Send Headers:** `Content-Type: application/json`
- **Send Body:** Wähle JSON und nutze folgenden Aufbau:

```json
{
  "message": {
    "token": "={{ $json.body.fcmToken }}",
    "notification": {
      "title": "={{ $json.body.title }}",
      "body": "={{ $json.body.message }}"
    },
    "data": {
      "click_action": "FLUTTER_NOTIFICATION_CLICK"
    }
  }
}
```
*(Die Expression `{{ $json.body.fcmToken }}` bedeutet n8n wertet hier aus dem vorherigen Webhook das Feld `fcmToken` aus.)*

---

## 4. Daten an n8n senden (Da du keine Workflows hast)

Da dir die EspoCRM *Advanced Pack* Workflows fehlen, hast du zwei gute Möglichkeiten, wie n8n an die Informationen kommt:

### Option A: EspoCRM Custom Hook (Empfohlen & Echtzeit)
Du kannst in EspoCRM mit wenigen Zeilen PHP-Code einen sogenannten "Hook" erstellen. Dieser sendet bei jeder Zuweisung (z.B. einer Schicht) sofort einen Request an deinen n8n Webhook.

1. Gehe per FTP/SSH oder Dateimanager auf deinen EspoCRM-Server.
2. Navigiere in den Ordner `custom/Espo/Custom/Hooks/Schicht/` *(Ersetze `Schicht` mit dem echten internen Namen deiner Entität. Achte auf Groß-/Kleinschreibung!)*. Wenn der Ordner nicht existiert, erstelle ihn.
3. Erstelle dort eine Datei namens `SendPushNotification.php`.
4. Füge folgenden Code ein (und passe ggf. die Entitätsnamen und die **n8n Webhook-URL** an):

```php
<?php
namespace Espo\Custom\Hooks\Schicht; // Muss mit dem echten Entitätsnamen übereinstimmen!

use Espo\ORM\Entity;

class SendPushNotification extends \Espo\Core\Hooks\Base
{
    public function afterSave(Entity $entity, array $options = [])
    {
        // Prüfe, ob das Feld assignedUserId geändert wurde und es nicht leer ist
        if ($entity->isAttributeChanged('assignedUserId') && $entity->get('assignedUserId')) {
            
            // Ersetze dies mit deiner N8N Webhook Test-/Production URL
            $webhookUrl = 'https://DEINE_N8N_URL/webhook/send-smartphone-push';
            
            // Lade den zugewiesenen Nutzer
            $user = $this->getEntityManager()->getEntity('User', $entity->get('assignedUserId'));
            if (!$user) return;

            // Hole das fcmToken des Nutzers (das in Schritt 1 angelegt wurde)
            $fcmToken = $user->get('cFcmToken');
            if (!$fcmToken) return;

            // Bereite die Daten für n8n vor
            $payload = json_encode([
                'cFcmToken' => $fcmToken,
                'title' => 'Neue Schicht zugewiesen!',
                'message' => 'Dir wurde die Schicht "' . $entity->get('name') . '" zugewiesen.'
            ]);

            // Sende den asynchronen/schnellen POST-Request an n8n per cURL
            $ch = curl_init($webhookUrl);
            curl_setopt($ch, CURLOPT_POSTFIELDS, $payload);
            curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type:application/json']);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_TIMEOUT, 2); // Sehr kurzer Timeout, blockiert Espo nicht!
            curl_exec($ch);
            curl_close($ch);
        }
    }
}
?>
### Option B: n8n überwacht das EspoCRM Notification-Center (Die Glocke) - Detailanleitung
Da deine Mitarbeiter über die EspoCRM-Rechteverwaltung (ACL) ohnehin System-Benachrichtigungen in ihrer internen "Glocke" oben rechts erhalten (z.B. Zuweisungen, Updates, Kommentare), lassen wir n8n einfach dort lauschen! 

*Hinweis zu deiner Besonderheit mit den ACL-Rechten:* Da die Nutzer teils auch Rand-Ereignisse mitbekommen, zeige ich dir in "Node 3", wie du bei Bedarf auch einen Filter einbauen kannst, falls das Smartphone sonst zu oft vibriert.

Für dieses Setup benötigst du einen festen API Key aus EspoCRM (Administration -> API Users). Baue deinen n8n Workflow exakt mit diesen 6 Nodes nach:

**1. Node: Schedule Trigger**
* Füge einen Node vom Typ `Schedule Trigger` hinzu.
* **Rule:** `Interval` -> **Value:** `5` -> **Unit:** `Minutes`.
* *Dieser Node feuert deinen Workflow nun alle 5 Minuten völlig automatisch ab.*

**2. Node: Date & Time**
* Füge danach den Node `Date & Time` hinzu.
* **Action:** `Subtract from Date`
* **Value:** `5`, **Unit:** `Minutes`.
* **Output format:** `Custom format` -> `yyyy-MM-dd HH:mm:ss`
* *Dies berechnet exakt die Uhrzeit "Vor 5 Minuten" für den Filter im nächsten Node.*

**3. Node: HTTP Request (System-Benachrichtigungen abfragen)**
* Verbinde dies mit einem `HTTP Request` Node.
* **Method:** `GET`
* **URL:** `https://DEINE_ESPO_URL/api/v1/Notification`
* **Authentication:** Wähle `Header Auth` und richte deine API-Credentials ein (**Header Name:** `X-Api-Key`, **Value:** `DeinEspoApiKey`).
* **Query Parameters:** Wir müssen verhindern, dass n8n alte Pushes verschickt:
    * Parameter 1: `where[0][attribute]` = `createdAt` / `where[0][type]` = `greaterThanOrEquals` / `where[0][value]` = `={{ $json.date }}` *(Ziehe per Drag & Drop das berechnete Datum aus Node 2 hier rein)*
    * *(Optionaler Filter für deine Rechteverwaltung!)* Wenn du merkst, dass es zu oft vibriert, füge Parameter 2 hinzu und zwinge n8n nur auf *Zuweisungen* zu reagieren: `where[1][attribute]` = `type` / `where[1][type]` = `equals` / `where[1][value]` = `Assign`. Liefere ihn sonst einfach weg.

**4. Node: Item Lists (Aufsplitten der Ergebnisse)**
* Die Antwort von EspoCRM ist eine Gesamtliste (im Feld `list`) mit allen Ereignissen der letzten 5 Minuten.
* Füge einen `Item Lists` Node hinzu.
* **Operation:** `Split Out Items`
* **Field To Split Out:** `list`
* *n8n verwandelt die Liste nun in eine Endlosschleife (Loop), sodass alles Folgende für jede einzelne Benachrichtigung einzeln durchlaufen wird.*

**5. Node: HTTP Request (Das Token des jeweiligen Nutzers holen)**
* In der Benachrichtigung gibt Espo das Feld `userId` mit – wir wissen also, bei wem die Glocke originally in EspoCRM geklingelt hat.
* Füge noch einen `HTTP Request` Node an.
* **Method:** `GET`
* **URL:** `https://DEINE_ESPO_URL/api/v1/User/={{ $json.userId }}` *(Ziehe die `userId` aus dem Output des vorherigen Nodes in das URL-Feld).*
* **Authentication:** Nutze deinen bereits angeigten Header Auth (X-Api-Key).
* *Output: Wir haben nun das Benutzerprofil geladen und Zugriff auf dessen `cFcmToken`!*

**6. Node: HTTP Request (Push an Firebase senden)**
* Zuletzt der Firebase HTTP-Request Node (wie in Kapitel 3 vorbereitet).
* **Method:** `POST`
* **URL:** `https://fcm.googleapis.com/v1/projects/DEINE_FIREBASE_PROJECT_ID/messages:send`
* **Body (JSON):**
```json
{
  "message": {
    "token": "={{ $json.cFcmToken }}",
    "notification": {
      "title": "Neues Ereignis in EspoCRM",
      "body": "Es gibt Neuigkeiten (Kategorie: {{ $('Item Lists').item.relatedType }}). Bitte öffne die App!"
    }
  }
}
```
*(Tipp zum Body: Du kannst per Drag & Drop Variablen in die Nachricht ziehen. `relatedType` gibt z.B. an, ob es aus "Schicht", "Wachbuch" oder Ähnliches kommt).*
> **Tipp:** Option A ist weitaus besser. Sie geschieht exakt ohne Zeitverzögerung (Echtzeit), belastet deinen EspoCRM Server deutlich weniger (keine API-Abfragen im Minutentakt) und ist deutlich einfacher in n8n aufzubauen.
## Gesamtsystem Übersicht

1. **Mitarbeiter öffnet App** ➔ Token wird an `User`-Entität (Feld `fcmToken`) gesendet.
2. **Disponent weist Schicht zu** ➔ EspoCRM bemerkt Zuweisung, triggert Webhook.
3. **EspoCRM an n8n** ➔ Schickt POST Request mit `{ fcmToken, title, message }`.
4. **n8n an Firebase** ➔ Wandelt den Body ins Format der Firebase API v1 um und nutzt Google-Auth.
5. **Firebase an App** ➔ Mitarbeiter erhält sofort eine Push-Benachrichtigung und sein Smartphone vibriert.
