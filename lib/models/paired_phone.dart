import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';

/// One phone bonded to the device, as `ListPairedPhones` reports it.
class PairedPhoneInfo {
  /// The firmware's stable identifier for the phone.
  final List<int> deviceId;

  /// How far the device trusts it, for the identified car.
  final PhoneTrustLevel trust;

  /// This is the phone the app runs on. Only the device can tell, since the
  /// app doesn't know its own BLE address.
  final bool isThisPhone;

  const PairedPhoneInfo({
    required this.deviceId,
    required this.trust,
    required this.isThisPhone,
  });

  factory PairedPhoneInfo.fromProto(PairedPhone phone) => PairedPhoneInfo(
    deviceId: List.unmodifiable(phone.deviceId),
    trust: phone.trust,
    isThisPhone: phone.isRequester,
  );

  bool get isValidated => trust == PhoneTrustLevel.PHONE_TRUST_LEVEL_VALIDATED;
}
