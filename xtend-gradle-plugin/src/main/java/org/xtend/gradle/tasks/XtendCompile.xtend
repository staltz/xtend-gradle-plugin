package org.xtend.gradle.tasks

import de.oehme.xtend.contrib.Property
import java.io.File
import java.net.URLClassLoader
import java.util.List
import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.file.FileCollection
import org.gradle.api.file.SourceDirectorySet
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputFiles
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskAction
import org.gradle.internal.classloader.FilteringClassLoader

import static extension org.xtend.gradle.GradleExtensions.*

class XtendCompile extends DefaultTask {
	@InputFiles @Property SourceDirectorySet srcDirs
	@InputFiles @Property FileCollection classpath
	@OutputDirectory @Property File targetDir
	@Input @Property String encoding
	@InputFiles @Property FileCollection xtendClasspath
	@Input @Property Boolean fork
	@Input @Property Boolean useDaemon
	@Input @Property Integer daemonPort

	@TaskAction
	def compile() {
		val sourcePath = getSrcDirs.srcDirTrees.map[dir.absolutePath].join(File.pathSeparator)
		val compilerArguments = #[
			"-cp",
			getClasspath.asPath,
			"-d",
			project.file(getTargetDir).absolutePath,
			"-encoding",
			getEncoding,
			"-td",
			new File(project.buildDir, "xtend-temp").absolutePath,
			sourcePath
		]
		if (getFork) {
			if (getUseDaemon) {
				compileWithDaemon(compilerArguments)
			} else {
				compileWithoutDaemon(compilerArguments)
			}
		} else {
			compileNonForked(compilerArguments)
		}
	}

	def compileNonForked(List<String> arguments) {
		System.setProperty("org.eclipse.emf.common.util.ReferenceClearingQueue", "false")
		val contextClassLoader = Thread.currentThread.contextClassLoader
		val classLoader = new URLClassLoader(getXtendClasspathWithoutLog4j.map[absoluteFile.toURI.toURL], loggingBridgeClassLoader)
		try {
			Thread.currentThread.contextClassLoader = classLoader
			val main = classLoader.loadClass("org.xtend.compiler.batch.Main")
			val mainMethod = main.getMethod("main", typeof(String[]))
			mainMethod.invoke(null, #[arguments as String[]])
		} finally {
			Thread.currentThread.contextClassLoader = contextClassLoader
		}
	}

	def getXtendClasspathWithoutLog4j() {
		getXtendClasspath.filter[!name.contains("log4j")]
	}

	def loggingBridgeClassLoader() {
		new FilteringClassLoader(class.classLoader) => [
			allowPackage("org.slf4j")
			allowPackage("org.apache.log4j")
		]
	}

	def compileWithDaemon(List<String> arguments) {
		val compiler = new XtendCompilerClient(getDaemonPort)
		compiler.requireServer(getXtendClasspath.asPath)
		if (!compiler.compile(arguments)) {
			throw new GradleException("Xtend Compilation failed");
		}
	}

	def compileWithoutDaemon(List<String> arguments) {
		val result = project.javaexec [
			main = "org.xtend.compiler.batch.Main"
			it.classpath = getXtendClasspath //Bug, shouldn't it take precedence?
			setArgs(arguments)
		]
		if (result.exitValue != 0) {
			throw new GradleException("Xtend Compilation failed");
		}
	}
}
