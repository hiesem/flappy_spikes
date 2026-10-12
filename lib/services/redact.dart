/// PRD-2.2 §4 diagnostics (QA S7-18): credentials never reach a log line or
/// an analytics parameter.
///
/// Plugin exceptions can carry secrets in their message: a failed Play Games
/// ↔ Firebase link reports `http://localhost?access_token=…&providerId=…`,
/// and other auth errors may echo id tokens (JWTs), OAuth access tokens
/// (`ya29.…`), server auth codes (`4/0…`) or `Bearer` headers. [redactSecrets]
/// strips all of them while keeping the readable part of the message (error
/// code, host, path, provider-free text) for diagnosis.
library;

const String redacted = '<redacted>';

/// Query strings / fragments of any URL (`scheme://host/path?…` / `#…`).
final RegExp _urlQuery = RegExp(
  r'([a-zA-Z][a-zA-Z0-9+.\-]*://[^\s?#"]*)[?#][^\s"]*',
);

/// `key=value` / `key: value` / `"key":"value"` for credential-like keys,
/// anywhere in the text (also outside a URL).
final RegExp _keyValue = RegExp(
  r'''(["']?\b[\w\-]*(?:token|secret|password|passwd|credential|api[_\-]?key|auth[_\-]?code|server[_\-]?auth|signature|assertion|cookie|sig)\b["']?\s*[=:]\s*)("[^"]*"|'[^']*'|[^\s&,;}\]"']+)''',
  caseSensitive: false,
);

/// JSON Web Tokens (Firebase / Google id tokens, App Check tokens).
final RegExp _jwt = RegExp(
  r'\beyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]*',
);

/// Google OAuth access tokens and server auth codes.
final RegExp _googleToken = RegExp(
  r'\b(?:ya29\.[A-Za-z0-9_\-.]+|4/0[A-Za-z0-9_\-]{10,})',
);

/// `Bearer <token>` authorization values.
final RegExp _bearer = RegExp(
  r'\b(Bearer)\s+[A-Za-z0-9_\-.=+/]+',
  caseSensitive: false,
);

/// [value] (`toString()` of an exception, a message, …) with every
/// credential replaced by [redacted].
String redactSecrets(Object? value) {
  var s = '$value';
  s = s.replaceAllMapped(_urlQuery, (m) => '${m[1]}?$redacted');
  s = s.replaceAllMapped(_keyValue, (m) => '${m[1]}$redacted');
  s = s.replaceAll(_jwt, redacted);
  s = s.replaceAll(_googleToken, redacted);
  s = s.replaceAllMapped(_bearer, (m) => '${m[1]} $redacted');
  return s;
}

/// [parameters] with every String value passed through [redactSecrets]
/// (analytics events).
Map<String, Object>? redactParams(Map<String, Object>? parameters) =>
    parameters == null
    ? null
    : {
        for (final e in parameters.entries)
          e.key: e.value is String ? redactSecrets(e.value) : e.value,
      };
