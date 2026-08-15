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
    // Set build directory
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // Namespace and CMake Fixes
    val fixCmakeAndNamespace = Action<Project> {
        val android = extensions.findByName("android")
        if (android != null) {
            try {
                val externalNativeBuild = android.javaClass.getMethod("getExternalNativeBuild").invoke(android)
                val cmake = externalNativeBuild.javaClass.getMethod("getCmake").invoke(externalNativeBuild)
                cmake.javaClass.getMethod("setVersion", String::class.java).invoke(cmake, "3.22.1")
            } catch (e: Exception) {
                // Ignore if the methods don't exist (not a native project)
            }
        }

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

    if (project.state.executed) {
        fixCmakeAndNamespace.execute(project)
    } else {
        project.afterEvaluate(fixCmakeAndNamespace)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
