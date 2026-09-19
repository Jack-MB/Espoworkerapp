/**
 * MB Security – WebAuthn Bridge
 * 
 * Ermöglicht biometrische Anmeldung in der PWA über die Web Authentication API.
 * Unterstützt: Touch ID (iOS/macOS), Face ID (iOS), Windows Hello, Android Fingerprint/Face.
 * 
 * Sicherheitskonzept: WebAuthn verifiziert die Identität des Benutzers lokal auf dem Gerät.
 * Die gespeicherten Zugangsdaten (username/password) werden nur nach erfolgreicher
 * biometrischer Verifikation freigegeben. Der private Schlüssel verlässt nie das Gerät.
 */

window.mbWebAuthn = {

  /**
   * Prüft ob der Browser WebAuthn grundsätzlich unterstützt.
   */
  isSupported: function () {
    return typeof window.PublicKeyCredential !== 'undefined' &&
      typeof navigator.credentials !== 'undefined' &&
      typeof navigator.credentials.create !== 'undefined' &&
      typeof navigator.credentials.get !== 'undefined';
  },

  /**
   * Prüft ob ein Plattform-Authenticator (Biometrie) verfügbar ist.
   * Gibt ein Promise<boolean> zurück.
   */
  isPlatformAvailable: function () {
    if (!window.mbWebAuthn.isSupported()) {
      return Promise.resolve(false);
    }
    return PublicKeyCredential
      .isUserVerifyingPlatformAuthenticatorAvailable()
      .then(function (result) { return result; })
      .catch(function () { return false; });
  },

  /**
   * Prüft ob Biometrie bereits eingerichtet wurde (Credential ID vorhanden).
   */
  isBiometricEnabled: function () {
    return localStorage.getItem('mb_biometric_enabled') === 'true' &&
      !!localStorage.getItem('mb_webauthn_credential_id');
  },

  /**
   * Registriert einen neuen biometrischen Credential.
   * Wird nach dem ersten manuellen Login aufgerufen.
   * @param {string} userId - eindeutige User-ID (z.B. EspoCRM user ID)
   * @param {string} username - Benutzername für Anzeige
   * @returns {Promise<string|null>} Credential ID (base64) oder null bei Fehler
   */
  register: async function (userId, username) {
    if (!window.mbWebAuthn.isSupported()) return null;

    // Zufälligen Challenge generieren
    const challenge = new Uint8Array(32);
    crypto.getRandomValues(challenge);

    // User-ID als Bytes codieren
    const userIdBytes = new TextEncoder().encode(userId);

    try {
      const credential = await navigator.credentials.create({
        publicKey: {
          challenge: challenge,
          rp: {
            name: 'MB Security',
            id: window.location.hostname,
          },
          user: {
            id: userIdBytes,
            name: username,
            displayName: username,
          },
          pubKeyCredParams: [
            { type: 'public-key', alg: -7 },   // ES256 (ECDSA)
            { type: 'public-key', alg: -257 },  // RS256 (RSA)
          ],
          authenticatorSelection: {
            authenticatorAttachment: 'platform',  // Nur Gerät-integrierte Biometrie
            userVerification: 'required',          // Biometrie zwingend erforderlich
            requireResidentKey: false,
          },
          timeout: 60000,
          attestation: 'none',  // Kein Attestation-Zertifikat nötig
        },
      });

      if (credential && credential.rawId) {
        // Credential ID in Base64 speichern
        const rawIdArray = new Uint8Array(credential.rawId);
        const credIdB64 = btoa(String.fromCharCode.apply(null, rawIdArray));

        localStorage.setItem('mb_webauthn_credential_id', credIdB64);
        localStorage.setItem('mb_biometric_enabled', 'true');
        console.log('[WebAuthn] Biometrie erfolgreich registriert.');
        return credIdB64;
      }
    } catch (e) {
      console.warn('[WebAuthn] Registrierung fehlgeschlagen:', e.name, e.message);
    }
    return null;
  },

  /**
   * Authentifiziert per Biometrie mit dem zuvor registrierten Credential.
   * @returns {Promise<boolean>} true bei Erfolg, false bei Fehler/Abbruch
   */
  authenticate: async function () {
    if (!window.mbWebAuthn.isSupported()) return false;

    const credIdB64 = localStorage.getItem('mb_webauthn_credential_id');
    if (!credIdB64) return false;

    // Base64 → Uint8Array
    const credIdBytes = Uint8Array.from(
      atob(credIdB64),
      function (c) { return c.charCodeAt(0); }
    );

    // Zufälligen Challenge generieren (verhindert Replay-Angriffe)
    const challenge = new Uint8Array(32);
    crypto.getRandomValues(challenge);

    try {
      const assertion = await navigator.credentials.get({
        publicKey: {
          challenge: challenge,
          allowCredentials: [{
            id: credIdBytes,
            type: 'public-key',
            transports: ['internal'],  // Nur internes Gerät (keine USB-Keys)
          }],
          userVerification: 'required',
          timeout: 60000,
        },
      });

      if (assertion) {
        console.log('[WebAuthn] Biometrie-Authentifizierung erfolgreich.');
        return true;
      }
    } catch (e) {
      if (e.name !== 'NotAllowedError') {
        // NotAllowedError = User hat abgebrochen, kein echter Fehler
        console.warn('[WebAuthn] Authentifizierung fehlgeschlagen:', e.name, e.message);
      }
    }
    return false;
  },

  /**
   * Entfernt die biometrische Anmeldung.
   */
  clear: function () {
    localStorage.removeItem('mb_webauthn_credential_id');
    localStorage.removeItem('mb_biometric_enabled');
    console.log('[WebAuthn] Biometrie-Daten gelöscht.');
  },
};
