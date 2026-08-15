import org.gradle.api.Action

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

subprojects {
    val fixNamespace = Action<Project> {
        val androidExt = extensions.findByName("android") ?: return@Action

        val getNamespace = androidExt.javaClass.methods.find {
            it.name == "getNamespace" && it.parameterCount == 0
        } ?: return@Action

        val currentNamespace = getNamespace.invoke(androidExt) as? String
        if (!currentNamespace.isNullOrBlank()) return@Action

        // Fallback for legacy plugins that still declare only manifest package.
        val manifestFile = file("src/main/AndroidManifest.xml")
        if (!manifestFile.exists()) return@Action

        val packageName =
            Regex("""package=\"([^\"]+)\"""")
                .find(manifestFile.readText())?.groupValues?.get(1) ?: return@Action

        val setNamespace = androidExt.javaClass.methods.find {
            it.name == "setNamespace" && it.parameterCount == 1
        } ?: return@Action

        setNamespace.invoke(androidExt, packageName)
    }

    if (state.executed) {
        fixNamespace.execute(this)
    } else {
        afterEvaluate(fixNamespace)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
