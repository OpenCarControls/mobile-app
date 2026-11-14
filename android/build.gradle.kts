// reactive_ble_mobile 5.6.0 pins protobuf-gradle-plugin 0.9.4, which fails to
// configure with AGP 9.5 ("ProtoSourceSet with name 'debug' not found"). The
// root classpath wins over the plugin's own, so force the AGP 9 compatible
// release. Remove once flutter_reactive_ble ships a newer protobuf plugin.
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.protobuf:protobuf-gradle-plugin:0.10.1")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// thermion_flutter 0.7.0 compiles against android-33, but the AndroidX
// libraries Flutter 3.50 pulls in need 34 or later. Raise it after the
// plugin's own build.gradle has set it. Registered before
// evaluationDependsOn below, which evaluates the subprojects.
subprojects {
    if (name == "thermion_flutter") {
        afterEvaluate {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                compileSdk = 36
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
