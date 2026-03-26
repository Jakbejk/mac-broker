plugins {
    id("java")
}

group = "cz.tipsport"
version = "1.0-SNAPSHOT"

repositories {
    mavenCentral()
}

dependencies {
    implementation("net.java.dev.jna:jna:5.14.0")
    implementation("com.microsoft.azure:msal4j:1.24.0")
    // TODO REMOVE
    implementation("com.microsoft.azure:msal4j-brokers:1.0.3-beta")
    testImplementation(platform("org.junit:junit-bom:5.10.0"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.test {
    useJUnitPlatform()
}