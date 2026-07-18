# packaging

Distro packaging for the brotway GTK fork.

| Dir | What | Used by |
|-----|------|---------|
| `keymasq/` | Minimal, relocatable Arch-built overlay tarball | Keymasq AppImage; `.github/workflows/build.yml` |
| `debian/` | Legacy `.deb` control template + `postinst` | Retained for the older distro-package flow |
| `arch/` | Legacy `PKGBUILD` for a local Arch/CachyOS install | Manual (`makepkg -si`), **not** wired into CI |
| `docker/` | `Dockerfile` for the app-agnostic base image (stock Ubuntu GTK runtime + the `.deb` installed into its private prefix, `LD_LIBRARY_PATH` pre-set) | `.github/workflows/image.yml` (downloads the release `.debs`, pushes `ghcr.io/<owner>/gtk-brotway`) |

Both paths install the fork conflict-free into the private prefix `/usr/lib/gtk4-brotway`
(never replacing the system GTK). The Debian path is the shipped artifact; the Arch
path builds from source for local dev - see `arch/PKGBUILD`.
