package dev.softwarevault.mixtape

import com.ryanheise.audioservice.AudioServiceActivity

// The app's window shares its Flutter engine with the music service (audio_service), so the music and
// the screens are one and the same app, also when the window comes back after the service ran alone.
class MainActivity : AudioServiceActivity()
