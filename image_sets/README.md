# Page image sets

The app renders the Qur'an from one set of 602 `page_*.webp` images. Two sets
exist, but **only one is bundled into the app at a time** (to keep the build
small). The bundled set lives in [`assets/images/`](../assets/images) next to the
app icons; the other set is parked here, un-bundled.

| Set | Size | Notes |
|-----|------|-------|
| `high_fidelity` | ~92 MB | Less compressed, sharper. **Ships by default**, no download needed. |
| `standard` | ~24 MB | Lighter. Used by the legacy "download the HQ pack on demand" model. |

`.active_set` records which set is currently bundled.

## Switching sets

Two coupled things must change together — the **image files** and the
**`kBundleHighFidelityImages` flag** in
[`lib/config/image_config.dart`](../lib/config/image_config.dart):

### Ship high-fidelity built-in (current default)
```powershell
pwsh tools/use_high_fidelity.ps1     # moves HQ pages into assets/images
# then set: const kBundleHighFidelityImages = true;
```
Result: app bundles the ~92 MB set, the quality picker defaults to level 3,
and level 3 renders the bundled images with no download.

### Revert to the standard + download model
```powershell
pwsh tools/use_standard.ps1          # moves the lighter pages into assets/images
# then set: const kBundleHighFidelityImages = false;
```
Result: app bundles the ~24 MB set, the picker defaults to level 1, and level 3
becomes the one-time download from the GitHub release again.

After switching, run `flutter clean` before building so the asset bundle is
regenerated.
