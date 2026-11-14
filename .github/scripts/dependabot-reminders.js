// Reminders posted on Dependabot PRs by .github/workflows/dependabot-reminders.yml.
//
// A rule matches when any dependency name matches `deps` or any changed file
// matches `files`. Optional `ecosystems` (e.g. 'pub', 'npm_and_yarn', 'gradle',
// 'github_actions', 'submodules') and `updateTypes` ('major', 'minor', 'patch')
// narrow it further. A rule with neither `deps` nor `files` matches on those
// filters alone. `message` is one Markdown checklist item.
module.exports = [
  {
    id: 'protoc-plugin',
    deps: [/^protoc_plugin$/],
    message: `**protoc_plugin** is also pinned in \`.github/workflows/ci.yml\` (twice), \`.github/workflows/release.yml\` and \`.devcontainer/Dockerfile\` (\`dart pub global activate protoc_plugin <version>\`). Update all four to the same version in this PR, then regenerate and check the app still builds.`,
  },
  {
    id: 'contracts',
    files: [/^contracts$/],
    message: `**contracts submodule**: run \`dart run build_runner build\`, handle any new fields or commands, and keep the firmware's pin in step.`,
  },
  {
    id: 'ble',
    deps: [/^flutter_reactive_ble$/, /^permission_handler/],
    message: `**BLE / permissions**: CI can't test these. Install the APK on a phone and run the pairing wizard, reconnect and a command end to end. Check \`AndroidManifest.xml\` permissions against the changelog.`,
  },
  {
    id: 'mqtt',
    deps: [/^mqtt5_client$/],
    message: `**mqtt5_client**: test the MQTT transport against a broker (connect, state, a command); CI doesn't.`,
  },
  {
    id: 'android-build',
    files: [/^android\//],
    message: `**Android build**: the Android Gradle plugin, Kotlin and Gradle versions must be supported by the Flutter version in \`.flutter-version\`. Check Flutter's compatibility notes, and that the release (minified) APK still works on a device.`,
  },
  {
    id: 'node',
    deps: [/^actions\/setup-node$/, /devcontainers\/features\/node/],
    message: `**Node**: only two things use it. The release workflow runs semantic-release on \`node-version: '22'\`, and the dev container's Node feature runs \`tool/compress_model.sh\` (\`npx\`). Check both still work.`,
  },
  {
    id: 'major',
    updateTypes: ['major'],
    message: `**Major update**: read the changelog for breaking changes, and update \`docs/\` if behaviour changes.`,
  },
];
