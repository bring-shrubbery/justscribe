#!/bin/bash
# Prints the Sparkle appcast for one release: a single <item> whose enclosure is the
# signed zip. Every field is an argument so the release workflow stays declarative and
# this file is testable. The feed URL in <link> is where installed apps read it.
#
# The release notes go in the item's <description>, as HTML (release-notes.sh writes it),
# so the update prompt shows them at once rather than loading a web page; the GitHub
# release page is linked as the full notes.
#
#   release-appcast.sh --version 1.0.2 --build 17 --tag v1.0.2 \
#       --url https://github.com/.../JustScribe-v1.0.2-macos-arm64.zip \
#       --length 4271794 --signature <base64 EdDSA> \
#       --notes-file build/release-notes.html \
#       --notes-link https://github.com/.../releases/tag/v1.0.2 \
#       --date "Sun, 20 Sep 2026 19:19:22 +0000" > appcast.xml
set -euo pipefail

FEED_URL="https://justscribe.quassum.com/appcast.xml"
MINIMUM_SYSTEM="26.2"

version="" build="" tag="" url="" length="" signature="" notes_file="" notes_link="" date=""
while [ $# -gt 0 ]; do
    case "$1" in
        --version)    version=${2-};    shift 2 ;;
        --build)      build=${2-};      shift 2 ;;
        --tag)        tag=${2-};        shift 2 ;;
        --url)        url=${2-};        shift 2 ;;
        --length)     length=${2-};     shift 2 ;;
        --signature)  signature=${2-};  shift 2 ;;
        --notes-file) notes_file=${2-}; shift 2 ;;
        --notes-link) notes_link=${2-}; shift 2 ;;
        --date)       date=${2-};       shift 2 ;;
        *) echo "error: unknown option $1" >&2; exit 1 ;;
    esac
done

for name in version build tag url length signature notes_file notes_link date; do
    if [ -z "${!name}" ]; then
        echo "error: --${name//_/-} is required" >&2
        exit 1
    fi
done

# The values are versions, URLs, numbers and base64: no XML metacharacters. Guard anyway.
for name in version build tag url length signature notes_link date; do
    case "${!name}" in
        *[\<\>\&\"]*) echo "error: --${name//_/-} contains an XML metacharacter" >&2; exit 1 ;;
    esac
done

# The notes are HTML and go in a CDATA section; the one sequence that would end it is split.
notes=$(sed 's/]]>/]]]]><![CDATA[>/g' "$notes_file")
if [ -z "$notes" ]; then
    echo "error: $notes_file is empty" >&2
    exit 1
fi

cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>JustScribe</title>
    <link>$FEED_URL</link>
    <description>Releases of JustScribe, on-device voice dictation for macOS.</description>
    <language>en</language>
    <item>
      <title>JustScribe $tag</title>
      <pubDate>$date</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM_SYSTEM</sparkle:minimumSystemVersion>
      <description><![CDATA[
$notes
      ]]></description>
      <sparkle:fullReleaseNotesLink>$notes_link</sparkle:fullReleaseNotesLink>
      <enclosure url="$url" length="$length" type="application/octet-stream" sparkle:edSignature="$signature" />
    </item>
  </channel>
</rss>
XML
