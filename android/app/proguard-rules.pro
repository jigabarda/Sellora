# R8 rules for the release build.
#
# The text recognition plugin names a recogniser class per script — Chinese,
# Devanagari, Japanese, Korean — but each one lives in its own dependency and
# this app ships only the Latin bundle. Those references are dead code here, and
# R8 will not shrink a build that still points at classes it cannot find, so the
# release build fails outright on the four it cannot resolve.
#
# `-dontwarn` rather than adding the other bundles: pulling in four more script
# models to satisfy a reference nothing calls would add tens of megabytes to an
# APK meant for cheap phones on metered data. A sari-sari store in Sampaloc is
# not scanning Devanagari.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
