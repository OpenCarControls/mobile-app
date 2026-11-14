import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_car_app/transport/mqtt_tls.dart';

// A throwaway CA certificate (public part only), for parsing.
const _caPem = '''
-----BEGIN CERTIFICATE-----
MIIBpDCCAUmgAwIBAgIUH++3iV6E6ol+sknbqgA9wwt28d8wCgYIKoZIzj0EAwIw
HzEdMBsGA1UEAwwUT3BlbiBDYXIgQ29udHJvbHMgQ0EwHhcNMjYxMTE0MjIyMzQ2
WhcNMzYxMTExMjIyMzQ2WjAfMR0wGwYDVQQDDBRPcGVuIENhciBDb250cm9scyBD
QTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABIcaPsGdKsL60lfrpoYxDJEY6V+w
xJaMkWEQ7CfKAE7fuP5s2p8WxrPwtvSBkWbRzaEpe0wmq8YJvtyDxsYzPPOjYzBh
MB0GA1UdDgQWBBRF5KpbtjW0nvV0g8dxmj3zWDrooTAfBgNVHSMEGDAWgBRF5Kpb
tjW0nvV0g8dxmj3zWDrooTAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIB
BjAKBggqhkjOPQQDAgNJADBGAiEAsr1+8Yc+/qS5ObhSfvwalNLNXlUMlmNGgGMG
xl2TJmACIQCsJHF/yFy5imJ7HCUnHI/QRjsG/S/MoJFOxwMeg/4OnA==
-----END CERTIFICATE-----
''';

void main() {
  test('a CA alone makes a context that trusts it', () {
    expect(mqttSecurityContext(caPem: _caPem), isA<SecurityContext>());
  });

  test('a CA that is not PEM is rejected', () {
    expect(
      () => mqttSecurityContext(caPem: 'not a certificate'),
      throwsA(isA<TlsException>()),
    );
  });

  test('a client certificate without a valid key is rejected', () {
    expect(
      () => mqttSecurityContext(
        caPem: _caPem,
        clientCertPem: _caPem,
        clientKeyPem: 'not a key',
      ),
      throwsA(isA<TlsException>()),
    );
  });
}
