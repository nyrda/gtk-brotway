# Keymasq AppImage overlay

This is the single supported binary output for embedding GTK Brotway in the
Keymasq AppImage. It is deliberately built against current Arch Linux, just like
the AppImage itself. It is not a distribution package and must not be installed
over the system GTK.

Build inside `archlinux:base-devel` after installing the packages listed in the
GitHub Actions workflow:

```sh
./packaging/keymasq/build-overlay.sh
```

The output is `dist/gtk4-brotway-keymasq-$(uname -m).tar.zst`. Its archive root
contains the private `lib/gtk4-brotway` overlay, its license, and `manifest.json`
source/build provenance. The launcher resolves that private prefix from its own
location and also accepts an explicit `BROTWAY_PREFIX`.

Verify an existing bundle, including a real `gtk4-broadwayd` HTTP startup:

```sh
./packaging/keymasq/verify-overlay.sh dist/gtk4-brotway-keymasq-x86_64.tar.zst
```

The repository's maintained packaging branch is `ci`. Push a tag named
`keymasq-vN` at a reviewed `ci` commit to build and publish an immutable release
containing the tarball and its checksum. Keymasq should pin both that tag's asset
URL and the published SHA-256; it must never consume a moving workflow artifact.
