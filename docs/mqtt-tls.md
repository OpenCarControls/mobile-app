# MQTT over TLS (mTLS)

The remote link goes through a broker on the internet. With `tls = true` in `[broker]` the app connects to it over TLS and checks that the broker's certificate chains to your CA and names the broker's `host`. With `auth_mode = "mtls"` the app also presents a certificate of its own, and sends no username or password. The device does the same with its own certificate; the certificates, the CA and the broker's settings are described in the firmware's `docs/mqtt-tls.md`.

TLS protects the link to the broker, not the commands: the device still refuses MQTT commands until they are signed per phone (contracts#8, mobile-app#24). Over MQTT the app sees state only.

## Configuration

`[broker]` in `config.toml`:

```toml
[broker]
host      = "broker.example.com"   # the name in the broker's certificate
port      = 8883
tls       = true
auth_mode = "mtls"                 # or "basic": username and password inside TLS
ca_cert_file     = "certs/ca.pem"
client_cert_file = "certs/phone-michael.pem"
client_key_file  = "certs/phone-michael.key"
```

The files are PEM, relative to the app's root, under `certs/` (gitignored). `dart run build_runner build` reads them into `lib/config/mqtt_broker_config.g.dart` (also gitignored) and fails on `mtls` without `tls`, an unknown `auth_mode`, or a missing file. Re-run it after changing a certificate.

| `tls` | `auth_mode` | What the app does |
|---|---|---|
| `false` | `basic` | Plain TCP with the username and password. Only on a network you trust. |
| `true` | `basic` | TLS, verifies the broker, then sends the username and password. |
| `true` | `mtls` | TLS, verifies the broker, presents the phone's certificate. No password is compiled in. |

The app trusts only `ca_cert_file`, not the phone's system CAs, and never accepts a certificate that fails verification. If the PEM files don't load, MQTT stays off rather than falling back to plain TCP (logged as `TLS settings rejected`).

## The phone's certificate

Give each phone its own certificate from your CA, with CN `phone-<name>`, made like the device's (firmware `docs/mqtt-tls.md`, "Making certificates"). With Mosquitto's `use_identity_as_username`, the CN is the phone's username in the broker's ACL, which lists the cars it may reach:

```conf
user phone-michael
topic write opencar/my-car/cmd
topic read  opencar/my-car/data
```

The key is compiled into the APK, so anyone with the APK can extract it. That's why each phone gets its own: if a phone or an APK is lost, remove its user from the broker's ACL (or stop trusting the certificate) without touching the cars or the other phones.

## Later

The setup wizard will provision the credentials instead of compiling them in. For the app, that means:

*   Keeping the phone's key in the platform keystore (Android Keystore, iOS Keychain), ideally generated there and never exported: the app makes a CSR and gets back the signed certificate and the CA.
*   Passing the device its own certificate over BLE (firmware `docs/mqtt-tls.md`, "Where the certificates live").
*   Reading `host`, `port` and the CA from the pairing (`PairedVehicleConfig` has room for broker settings) instead of `mqtt_broker_config.g.dart`.
