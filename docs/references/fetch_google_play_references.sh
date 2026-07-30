#!/usr/bin/env bash
set -euo pipefail

destination="${1:-./downloaded-google-play-references}"
mkdir -p "$destination"

download() {
  local filename="$1"
  local expected="$2"
  local source="$3"
  curl --fail --location --silent --show-error "${source}=w1600-h2844" --output "$destination/$filename"
  printf '%s  %s\n' "$expected" "$destination/$filename" | sha256sum --check --status
  printf 'verified %s\n' "$destination/$filename"
}

download \
  google-play-01-home.png \
  bc8da4d9f092ec9169c10528af993f5423ac836227e335117ed69225a98ad97c \
  https://play-lh.googleusercontent.com/Piorkz8d0Rv0-PkxtDpJKi29oSUtsfnJy6MJxPHEJS9IAzwuYpE5y-EmdQw-vqlCw69kAENT32GT9r5UW2ndfg

download \
  google-play-02-clean-play.png \
  2d5badfe54ad0d66f747de86341ef41d2ad3f3342cb16d0826ca78c0fe3e0be6 \
  https://play-lh.googleusercontent.com/5XYThRdyHBQZaQVs6q7JMI5x6rc2VWiyK504qb8G_syifYJ1e1wJj8P5yLAOYxUcJ1auDFHMU3PTrAgmhzeIlQ

download \
  google-play-03-themes.png \
  92944b13cdd2168ffe094563b050e07297cb1a89b210469385c340cc864eee51 \
  https://play-lh.googleusercontent.com/txbOKDa5HKmHh8idtPlKGmJg9Qze4ZB-qjlq3ybHjK21kheu39SY3aLSfyAJ4jy6ThqksPOysrFLI5SG9xEW

download \
  google-play-04-post-game.png \
  a29f736b1eb2b6526d65cf47009c8a70a2f6429edf33c3548de248014eb6dd89 \
  https://play-lh.googleusercontent.com/O3iT0a7LAf-T7PdB1gj7ygxUwF5jfFIISSwX-okVay5AMXkRaq2-DIXDADgB8p1aTejFLEt96ygkNeEjzBwDUg

download \
  google-play-05-settings.png \
  db98a35ffc96713b54ab64d0028566bd24b87aabb4cb010c79ae1e74e5b2941f \
  https://play-lh.googleusercontent.com/5mRQ4mYsYWQO5Y_jvSaJ5OtOc3HYzQ86U-4EBIyuJ3DkOaqHPCMfNrTp8xUhEaApMZFFRz-M2I2mYloWd-eblnI

download \
  google-play-06-times.png \
  76a44fd70a5f05246a43d9ddd1597741541e8c5487b4c7bc7cbdb15c94642cc9 \
  https://play-lh.googleusercontent.com/Z7dZ9JTUwR9ffEgOE-B4a97HeK2iBR6-TcvfU8w9Q8awN0-wcrFt0QQacaIuG4ZZkTbCah2-3hguRTaB-IHS
