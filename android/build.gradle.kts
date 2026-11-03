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

// Một số plugin (vd. tflite_flutter) đặt Java target 11 nhưng không đặt
// jvmTarget cho Kotlin → Gradle dừng build vì "Inconsistent JVM Target Compatibility".
// Đồng bộ jvmTarget của mỗi task Kotlin theo targetCompatibility của task Java cùng variant.
subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
        val javaTaskName = name.replace("Kotlin", "JavaWithJavac")
        compilerOptions.jvmTarget.set(
            project.provider {
                val javaTask = project.tasks.findByName(javaTaskName) as? JavaCompile
                org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(
                    javaTask?.targetCompatibility ?: "17",
                )
            },
        )
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
