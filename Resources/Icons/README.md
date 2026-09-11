# Waypoint macOS app icon

The original blue Waypoint direction: midnight-blue tile, cyan window, and integrated navigation pointer.

- `Waypoint-master.png`: transparent high-resolution raster master.
- `AppIcon.icns`: compiled macOS icon used by `script/stage_bundle.py`.
- `AppIcon.iconset/`: the 10 standard macOS PNG representations, 16–1024 physical pixels.
- `Assets.xcassets/AppIcon.appiconset/`: matching Xcode asset catalog, including all macOS 1x and 2x slots.

Rebuild with `python3 script/generate_icons.py` on macOS. The script uses Apple’s `sips` and `iconutil`; no Python dependencies are required. Run `./script/build.sh` to stage and sign the app with the icon. The app's Info.plist references `AppIcon.icns` through `CFBundleIconFile`.

## Artwork provenance

Prepared using the built-in imagegen tool from the approved original blue Waypoint concept. This is a raster extraction/refinement, not a vector source. The app icon is intended for Finder, Dock, Command–Tab, and other bundle-icon surfaces; it is not a monochrome menu-bar template image.

Generation prompt: Extract the original blue Waypoint large macOS app icon from the approved concept sheet. Preserve the midnight navy rounded-square tile, cyan luminous rounded window outline, three circular cutouts and integrated upward navigation chevron. Remove presentation text, small symbol and white halo; center the icon with transparent margins. Follow-up: remove the checkerboard background with actual RGBA transparency, preserving the blue tile and cyan artwork.
