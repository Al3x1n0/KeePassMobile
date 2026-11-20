# ML Kit instantiates manifest-declared registrars through reflection.
-keep class com.google.mlkit.** implements com.google.firebase.components.ComponentRegistrar {
    public <init>();
}
