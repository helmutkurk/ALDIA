# Flutter's Gradle plugin supplies Flutter engine/embedding rules. Android plugins
# supply their own consumer rules. Keep R8 enabled; add only narrowly scoped rules
# if a release-device test demonstrates a reflection/JNI problem.
-keepattributes SourceFile,LineNumberTable
