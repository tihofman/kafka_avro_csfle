<script setup lang="ts">
// Bindet eine asciinema-Terminalaufzeichnung als steuerbaren Player ein.
// Vorteil gegenueber einem GIF: der Text bleibt gestochen scharf (echte
// Schrift statt Pixel) und laesst sich waehrend des Vortrags pausieren
// und zurueckspulen.
import { onMounted, onBeforeUnmount, ref, shallowRef } from 'vue'
import 'asciinema-player/dist/bundle/asciinema-player.css'

const props = withDefaults(defineProps<{
  /** Pfad zur .cast-Datei, relativ zu public/ */
  src: string
  /** Wiedergabegeschwindigkeit */
  speed?: number
  /** Laengere Pausen auf diesen Wert kuerzen (Sekunden) */
  idleTimeLimit?: number
  /** Sofort starten, sobald die Folie erscheint */
  autoplay?: boolean
  /** Schriftgroesse: 'small' | 'medium' | 'big' oder z.B. '16px' */
  fontSize?: string
  /** In Endlosschleife abspielen */
  loop?: boolean
  /** Maximale Hoehe auf der Folie, z.B. '360px' */
  maxHeight?: string
}>(), {
  speed: 1.5,
  idleTimeLimit: 1.5,
  autoplay: false,
  fontSize: 'small',
  loop: false,
  maxHeight: '',
})
const host = ref<HTMLElement | null>(null)
const player = shallowRef<{ dispose: () => void } | null>(null)

onMounted(async () => {
  if (!host.value) return
  // Dynamischer Import: der Player greift auf window zu und darf deshalb
  // beim statischen Build nicht auf dem Server ausgewertet werden.
  const AsciinemaPlayer = await import('asciinema-player')
  player.value = AsciinemaPlayer.create(props.src, host.value, {
    speed: props.speed,
    idleTimeLimit: props.idleTimeLimit,
    autoPlay: props.autoplay,
    loop: props.loop,
    // Ohne preload wird die Aufzeichnung erst beim Klick auf Play geladen -
    // das Terminal haette bis dahin die falsche Groesse (80x24 statt 120x32)
    // und im Vortrag gaebe es eine Ladeverzoegerung.
    preload: true,
    // Bei fester Hoehe skaliert der Player auf die Hoehe, sonst auf die Breite.
    fit: props.maxHeight ? 'height' : 'width',
    fontSize: props.fontSize,
    theme: 'dracula',
    controls: true,
  })
})

onBeforeUnmount(() => {
  // Ohne dispose() laeuft die Aufzeichnung im Hintergrund weiter,
  // wenn man die Folie wechselt.
  player.value?.dispose()
  player.value = null
})
</script>

<template>
  <div
    ref="host"
    class="asciinema-host"
    :style="maxHeight ? { height: maxHeight } : undefined"
  />
</template>

<style scoped>
.asciinema-host {
  width: 100%;
  display: flex;
  justify-content: center;
}

/* Der Player setzt seine Groesse per Inline-Style; hier nur Optik. */
.asciinema-host :deep(.ap-player) {
  border-radius: 0.5rem;
  overflow: hidden;
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.35);
}
</style>
