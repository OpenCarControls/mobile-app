FROM mcr.microsoft.com/devcontainers/base:ubuntu

ARG CMDLINE_TOOLS_VERSION="14742923"
ARG ANDROID_COMPILE_SDK="36"
ARG ANDROID_BUILD_TOOLS="36.0.0"

RUN apt-get update && export DEBIAN_FRONTEND=noninteractive && \
    apt-get install -y curl git git-lfs unzip xz-utils zip libglu1-mesa openjdk-21-jdk protobuf-compiler && \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

USER vscode
WORKDIR /home/vscode

ENV ANDROID_HOME=/home/vscode/android-sdk
ENV FLUTTER_HOME=/home/vscode/flutter
ENV PATH="$PATH:$FLUTTER_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:/home/vscode/.pub-cache/bin"

# Install Android SDK Command Line Tools
RUN mkdir -p $ANDROID_HOME/cmdline-tools && \
    curl -sL https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip -o cmdline-tools.zip && \
    unzip -q cmdline-tools.zip -d $ANDROID_HOME/cmdline-tools && \
    rm -rf cmdline-tools.zip && \
    mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest

RUN yes | sdkmanager --licenses && \
    sdkmanager "platform-tools" "platforms;android-${ANDROID_COMPILE_SDK}" "build-tools;${ANDROID_BUILD_TOOLS}"

# Install Flutter
COPY .flutter-version /tmp/.flutter-version
RUN FLUTTER_VERSION=$(cat /tmp/.flutter-version) && \
    git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" $FLUTTER_HOME && \
    flutter config --no-analytics && \
    flutter precache --android && \
    dart pub global activate protoc_plugin 21.1.2

WORKDIR /workspace