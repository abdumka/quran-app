# Android TV — Play Console submission pack

Everything the TV form factor needs that the phone listing does not already
supply. Written for whoever is sitting in front of Play Console; the code-side
notes live in the `android-tv-support` memory and in `lib/widgets/tv/`.

## Assets

| Play Console field | File | Spec |
| --- | --- | --- |
| TV banner | `store_assets/tv_banner_1280x720.png` | 1280×720 PNG, required |
| TV screenshots | `store_assets/screenshots/tv/*.png` | 1920×1080 PNG, 16:9, 1–8 required |

Screenshots for the other form factors sit beside the TV ones, one folder and
filename prefix each, so a file is never ambiguous about where it belongs:

| Play slot | Folder | Size |
| --- | --- | --- |
| Phone | `store_assets/screenshots/phone/` | 1080×2160 (2:1, Play's aspect cap) |
| 7-inch tablet | `store_assets/screenshots/tablet7/` | 1920×1200 landscape |
| 10-inch tablet | `store_assets/screenshots/tablet10/` | 2560×1600 landscape |
| Android TV | `store_assets/screenshots/tv/` | 1920×1080 |

**`store_assets/screenshots/` and `tools/capture_store_screenshots.py` are
gitignored.** This repo is public, the PNGs are ~30 MB of regenerable output,
and they go stale as soon as the UI moves. They are on the machine that built
them; regenerate rather than hunting through git history. The capture script's
own docstring has the emulator recipe.

The in-app launcher banner is a different asset and is already shipped:
`android/app/src/main/res/drawable-xhdpi/tv_banner.png`, exactly 320×180.
Rebuild either with `tools/make_tv_store_banner.py` / `tools/make_tv_banner.py`.

## Listing copy

Play shares the title and descriptions with the phone listing unless a custom
store listing is created. If you do add a TV-specific one, this copy leads with
what is different on a television.

### Short description (80 characters max)

```
المصحف الجامع برواية قالون — قراءة وتلاوة على شاشة التلفاز بجهاز التحكم
```

### Full description

```
المصحف الجامع على تلفازك

مصحف كامل برواية الإمام قالون عن نافع وبالرسم العثماني، بصفحات مصورة بجودة
عالية، مهيّأ للعرض على الشاشات الكبيرة ويُدار بالكامل بجهاز التحكم عن بعد.

التنقل بجهاز التحكم
• الأسهم للتنقل، زر الاختيار للفتح، زر الرجوع للخروج
• دليل مصوّر للأزرار داخل التطبيق في أي وقت
• لا حاجة إلى لمس الشاشة أو إلى فأرة

القراءة
• عرض صفحة واحدة أو صفحتين متجاورتين
• الفهرس كاملاً: السور، الأجزاء، الأحزاب والأثمان، الصفحات، السجدات
• العلامات المرجعية والانتقال السريع إلى أي صفحة
• الوضع الليلي وتغيير لون الصفحة

التلاوة
• تلاوات متعددة لمشاهير القراء
• تكرار الآية أو المقطع أو الصفحة أو الثمن
• تنزيل السور للاستماع دون اتصال بالإنترنت
• إخفاء شريط التلاوة تلقائياً أثناء الاستماع

التفسير
• عدة تفاسير معتمدة، منها ابن كثير والطبري والقرطبي وزاد المسير

التطبيق مجاني بالكامل وبدون إعلانات.
```

### English full description (if the listing is bilingual)

```
Al-Mushaf Al-Jame on your television

The complete Qur'an in the riwayah of Imam Qalun from Nafi', in the Uthmani
script, as high-resolution page images — laid out for the big screen and driven
entirely from the remote.

Remote control
• Arrows to move, Select to open, Back to leave
• An illustrated button guide inside the app, available at any time
• No touchscreen and no mouse required

Reading
• One page or a facing-page spread
• Full index: surahs, juz', hizbs and athman, pages, sajdas
• Bookmarks and jump-to-page
• Night mode and page tinting

Recitation
• A choice of well-known reciters
• Repeat an ayah, a range, a page or a thumn
• Download surahs for offline listening
• The recitation bar hides itself while you listen

Tafsir
• Several established works, including Ibn Kathir, al-Tabari, al-Qurtubi and
  Zad al-Masir

Free, with no advertising.
```

## Manifest declarations Play checks

Already in `android/app/src/main/AndroidManifest.xml`; listed here so a future
change does not silently drop the app off TV.

- `android.intent.category.LEANBACK_LAUNCHER` on `MainActivity`
- `android:banner="@drawable/tv_banner"` on `<application>`
- `<uses-feature android:name="android.software.leanback" android:required="false"/>`
- `<uses-feature android:name="android.hardware.touchscreen" android:required="false"/>`
- `<uses-feature android:name="android.hardware.microphone" android:required="false"/>`
  — `RECORD_AUDIO` (Tasmee) would otherwise imply a required microphone and hide
  the app from TV boxes

Play assumes `required="true"` for a feature it infers from a permission, so
every such feature has to be spelled out.
