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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
