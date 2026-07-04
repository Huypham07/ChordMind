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

// Some plugin AAR modules (e.g. :onnxruntime) pin compileSdk to 33 inside their
// own android{} block, but their androidx deps require 36. Override each plugin
// subproject to 36 in its afterEvaluate (runs after the plugin's android{} block,
// still during configuration so it isn't "too late to set compileSdk"). Skip
// :app, which evaluationDependsOn(":app") above may already have evaluated
// (afterEvaluate on an evaluated project throws).
subprojects {
    if (name != "app") {
        afterEvaluate {
            (extensions.findByName("android") as? com.android.build.gradle.BaseExtension)
                ?.compileSdkVersion(36)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
