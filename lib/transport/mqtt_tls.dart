import 'dart:convert';
import 'dart:io';

/// The TLS context of the MQTT connection. It trusts only [caPem], the CA the
/// broker's certificate must chain to, not the phone's system roots. With
/// [clientCertPem] and [clientKeyPem] the app also presents its own
/// certificate (mTLS). All PEM.
///
/// Throws a [TlsException] when a PEM doesn't parse or the key doesn't match.
SecurityContext mqttSecurityContext({
  required String caPem,
  String clientCertPem = '',
  String clientKeyPem = '',
}) {
  final context = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(utf8.encode(caPem));
  if (clientCertPem.isNotEmpty) {
    context
      ..useCertificateChainBytes(utf8.encode(clientCertPem))
      ..usePrivateKeyBytes(utf8.encode(clientKeyPem));
  }
  return context;
}
