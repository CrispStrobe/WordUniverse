import os
# Stelle sicher, dass dieser Import *vor* dem Import von phonemize steht
from phonemizer.backend.espeak.wrapper import EspeakWrapper

# Definiere den Pfad zur Homebrew-Bibliothek
# Dies ist der Standardpfad für Apple Silicon (arm64) Macs
espeak_lib_path = '/opt/homebrew/lib/libespeak-ng.dylib'

# Setze den Bibliothekspfad
EspeakWrapper.set_library(espeak_lib_path)

# --- Dein bisheriger Code beginnt hier ---
from phonemizer import phonemize

text = "Das ist ein beliebiges Wort, wie zum Beispiel 'Basisgraphem'."
phonemes = phonemize(text, language='de', backend='espeak')

print(phonemes)
