import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';

/// What the app says about a way of validating a phone. The device only sends
/// the method's id and kind: all the text lives here.
class PhoneValidationMethodText {
  const PhoneValidationMethodText({
    required this.title,
    required this.description,
    this.codeHint = '',
    this.instructions = const [],
  });

  final String title;

  /// One sentence on the method's card, including what the method needs.
  final String description;

  /// Code entry: where to look for the code.
  final String codeHint;

  /// In-car action: what to do, step by step.
  final List<String> instructions;
}

const _knownMethods = <String, PhoneValidationMethodText>{
  'egmp.cluster_code': PhoneValidationMethodText(
    title: 'Code on the instrument cluster',
    description:
        'With the car on and media playing (Android Auto, radio…), the '
        'cluster shows a code. You type it here.',
    codeHint: 'Look at the instrument cluster, where the track title shows.',
  ),
  'virtual_car.cluster_code': PhoneValidationMethodText(
    title: 'Code on the simulated cluster',
    description: 'The virtual car shows a code. You type it here.',
    codeHint: 'The code is sent on CAN frame 0x500 and written to the log.',
  ),
  'virtual_car.button': PhoneValidationMethodText(
    title: 'Simulated button',
    description: "Press the virtual car's validation button.",
    instructions: ['Send CAN frame 0x400 with its first byte set to 01.'],
  ),
};

const _genericCodeEntry = PhoneValidationMethodText(
  title: 'Code shown in the car',
  description: 'The car shows a code. You type it here.',
  codeHint: 'Look for the code in the car.',
);

const _genericInCarAction = PhoneValidationMethodText(
  title: 'Action in the car',
  description: 'You do something only someone in the car can do.',
  instructions: ['Switch the car on.', 'Follow what the car asks you to do.'],
);

/// The text for [methodId], or a generic one for its [kind] when this app
/// doesn't know the method (a newer firmware).
PhoneValidationMethodText phoneValidationMethodText(
  String methodId,
  PhoneValidationMethodKind kind,
) =>
    _knownMethods[methodId] ??
    (kind == PhoneValidationMethodKind.PHONE_VALIDATION_METHOD_KIND_CODE_ENTRY
        ? _genericCodeEntry
        : _genericInCarAction);
