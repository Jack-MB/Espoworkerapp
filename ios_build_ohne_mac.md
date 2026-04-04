# iOS App entwickeln und ausliefern (Ohne eigenen Mac)

Du kannst deine Flutter-App absolut für iOS-Nutzer (iPhones) bereitstellen, ohne dir physisch einen Mac oder ein MacBook kaufen zu müssen. Flutter ist plattformunabhängig, aber Apple erzwingt, dass die App auf dem Betriebssystem macOS kompiliert (gebaut) wird.

Hier ist der bewährte Workflow, wie du das als Windows-Nutzer über die Cloud löst:

---

## 1. Was du zwingend brauchst (Kosten)

Auch wenn du dir keinen Mac kaufst, führt an einer Sache kein Weg vorbei:
* **Apple Developer Account:** Apple verlangt jährlich ca. 99 $, damit du Apps überhaupt signieren und in den App Store oder an Tester verteilen darfst. Ohne diesen Account kannst du die App nicht auf die iPhones deiner Mitarbeiter bringen.

## 2. Der Build-Prozess in der Cloud (Codemagic)

Da du auf deinem Windows-PC kein `.ipa` (das Gegenstück zum Android `.apk`) bauen kannst, nutzt du einen CI/CD (Continuous Integration) Anbieter, der das für dich auf seinen Apple-Servern übernimmt.

**Ein extrem beliebter Anbieter für Flutter ist "Codemagic":**
1. Du legst deinen Code in ein git-Repository (z.B. bei GitHub oder GitLab).
2. Du erstellst dir einen (meist kostenlosen) Account bei [Codemagic.io](https://codemagic.io/).
3. Du verbindest Codemagic mit deinem GitHub Repository und deinem Apple Developer Account.
4. **Vorteil:** Codemagic übernimmt das lästige Erstellen der Apple-Zertifikate (Provisioning Profiles) vollautomatisch.
5. Du klickst in Codemagic auf "Build". Ein Cloud-Mac lädt deinen Code, kompiliert ihn und spuckt am Ende die fertige iOS-App-Datei aus.

*(Alternativen zu Codemagic wären GitHub Actions (benötigt mehr eigene Konfiguration) oder Appcircle).*

## 3. Die App an die Mitarbeiter verteilen (TestFlight)

Die fertige iOS-App-Datei lädst du (bzw. Codemagic macht das direkt automatisch für dich) zu **App Store Connect** (dem Dashboard von Apple) hoch.

Anstatt die App direkt für die ganze Welt in den offiziellen App Store zu stellen, nutzt du **TestFlight**:
1. TestFlight ist Apples offizielle App für Beta-Testing.
2. Du trägst im Apple-Dashboard einfach die E-Mail-Adressen deiner Mitarbeiter ein oder generierst einen offenen Einladungs-Link.
3. Die Mitarbeiter laden sich die "TestFlight" App aus dem App Store herunter, klicken auf den Link und haben deine EspoCRM Worker App auf dem Handy.

## 4. Wie testest du das Interface ohne Mac?

Du hast das Problem, dass du keine iPhones auf deinem Windows-PC simulieren kannst. Das meiste hast du in Android schon getestet, aber manchmal sehen Schriften auf dem iPhone anders aus.

* **Wenn du kleine Anpassungen blind machst:** Du änderst Code, lässt Codemagic bauen und bittest einen Mitarbeiter mit iPhone, dir Screenshots der TestFlight-App zu schicken.
* **Wenn das zu mühsam wird:** Du kannst dir zeitweise einen Cloud-Mac mieten, z. B. bei [MacinCloud](https://www.macincloud.com/). Das kostet oft nur ca. 1-2 $ pro Stunde ("Pay-As-You-Go"). Du verbindest dich per Windows-Remotedesktop auf den Mac in der Cloud, öffnest dort den iOS-Simulator und kannst in Echtzeit prüfen, wie sich deine Flutter-App auf iOS verhält. Für den Notfall ist das deutlich günstiger als ein 1000 € MacBook.

---

## Zusammenfassung der Schritte für dich:
1. Besorge dir eine Kreditkarte und registriere dich für das **Apple Developer Program**.
2. Richte ein Konto bei **Codemagic** ein.
3. Lade deinen Code zu GitHub hoch.
4. Verknüpfe Codemagic, lass den Build laufen und leite das Ergebnis direkt an **TestFlight** weiter.
5. Lade deine iOS-Mitarbeiter über TestFlight ein.
