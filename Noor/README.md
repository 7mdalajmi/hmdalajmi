# نور — Noor

محرّر صور لـ iPhone و iPad بأسلوب Lightroom، مبني على قاعدة واحدة: **لا فقدان في الجودة**.
A Lightroom-style photo editor for iPhone and iPad built on one rule: **no quality loss**.

---

## بالعربي

### كيف يحافظ نور على الجودة
- **الأصل لا يُلمس أبدًا.** عند الاستيراد تُنسخ ملفات الصورة كما هي بايتًا ببايت (HEIC أو JPEG أو PNG أو TIFF أو RAW/ProRAW) من دون أي تحويل، ويُستخدم `preferredItemEncoding: .current` حتى لا يحوّل iOS الصورة إلى JPEG.
- **التعديل أرقام وليس بكسلات.** كل تعديل يُحفظ كوصفة (`EditRecipe`)، ثم تُرسم المعاينة والتصدير من الملف الأصلي في كل مرة.
- **معالجة عالية الدقة.** تتم المعالجة بـ Core Image على Metal بدقة half‑float خطية وبمدى ممتد (Extended Linear Display P3)، فلا يحدث قص للألوان أو للإضاءة قبل المرحلة الأخيرة. الحسابات داخل نوى Metal كلها بدقة 32‑bit.
- **RAW على مستوى الحسّاس.** في ملفات RAW وProRAW يُطبَّق توازن الأبيض والتعريض وتقليل التشويش داخل `CIRAWFilter` قبل منحنى النغمات، حيث لا تفقد البيانات شيئًا.
- **التصدير بأفضل جودة:**
  - «نفس الأصل»: إذا لم تُعدَّل الصورة يكون الملف المصدَّر **مطابقًا للأصل بايتًا ببايت**.
  - HEIF ‏10‑bit، أو TIFF/PNG ‏16‑bit بلا فقدان، أو JPEG بجودة 100.
  - الدقة كاملة دائمًا، ولا يُكبَّر حجم الصورة أبدًا.
  - تبقى بيانات EXIF والموقع (اختياريًا) وملف ألوان ICC، مع ضبط Orientation على 1 وتحديث أبعاد الصورة.
  - يبقى HDR عبر gain map على iOS 18 فما فوق.
  - القص بلا تدوير يكون على حدود البكسل تمامًا، أي بلا إعادة تحجيم.

### الأدوات
| الأداة | المحتوى |
|---|---|
| الإعدادات المسبقة | 18 إعدادًا مدمجًا في 5 مجموعات (طبيعي، فيلم، سينمائي، أبيض وأسود، ضوء الخليج)، ومنزلق «المقدار» من 0 إلى 200٪، وحفظ إعداداتك الخاصة، واستيراد إعدادات Lightroom ‏(`.xmp` و DNG presets) |
| القص | نسب جاهزة، وتدوير 90°، وقلب، واستقامة ±45° |
| الإضاءة | التعريض، التباين، الإضاءات العالية، الظلال، الأبيض، الأسود، ومنحنى النغمات (RGB/R/G/B) |
| الألوان | الحرارة، الصبغة، الحيوية، التشبع، الأبيض والأسود، ومزج الألوان (8 ألوان)، وتدرّج الألوان (ظلال، وسط، إضاءات، عام)، والمعايرة |
| التأثيرات | النسيج، الوضوح، إزالة الضباب، التظليل الطرفي، الحبيبات (Grain) |
| التفاصيل | الحدّة (مع نصف القطر والقناع)، وتقليل التشويش |

يوجد أيضًا:
- تراجع وإعادة.
- مقارنة قبل/بعد بالضغط المطوّل على الصورة.
- مدرّج تكراري (Histogram) حيّ.
- تكبير حتى 800٪، ويُرسم الجزء الظاهر من الملف الأصلي بدقته الكاملة.
- نسخ الإعدادات ولصقها بين الصور.
- واجهة كاملة بالعربية والإنجليزية مع دعم الكتابة من اليمين لليسار.

### أول تشغيل على الماك
1. افتح `Noor/Noor.xcodeproj` في **Xcode 26** أو أحدث.
2. من Signing & Capabilities اختر فريق التطوير (Team).
3. إذا ظهر خطأ «missing Metal Toolchain»، نزّله من Xcode ← Settings ← Components ← Metal Toolchain، أو بالأمر:
   `xcodebuild -downloadComponent metalToolchain`
4. شغّل على جهاز حقيقي أو على المحاكي (⌘R).

> ملاحظة: كُتب الكود وراجعته عدة وكلاء آليًا مراجعةً دقيقة، لكنه **لم يُبنَ بـ Xcode بعد**. أول بناء على الماك هو الاختبار الحقيقي.

---

## English

### How Noor keeps quality
- **Originals are never touched.** Imports copy the exact file bytes (HEIC/JPEG/PNG/TIFF/RAW/ProRAW). The Photos picker uses `preferredItemEncoding: .current`, so iOS never transcodes to JPEG.
- **Edits are numbers, not pixels.** An edit is an `EditRecipe` value. Preview, thumbnails and export all re-render the original through the same recipe.
- **Precision pipeline.**
  - Core Image on Metal, working in half-float, linear, extended-range Display P3. Nothing is clipped until the final output stage.
  - Custom Metal kernels compute in fp32.
  - RAW white balance, exposure and noise reduction run inside `CIRAWFilter`, before the tone curve.
- **Export:**
  - *Same as original*: an unedited photo is a **byte-identical copy**.
  - Formats: HEIF 10-bit, lossless TIFF/PNG 16-bit, or JPEG at quality 1.0.
  - Always full resolution, never upscaled.
  - EXIF (and location, if you choose), the ICC profile and wide colour are kept. Orientation is reset to 1 and pixel dimensions are updated.
  - HDR is kept via gain map on iOS 18+.
  - A crop without straightening is pixel-exact, with no resampling.

### Features
| Tool | Controls |
|---|---|
| Presets | 18 built-ins in 5 groups (Natural, Film, Cinematic, B&W, Gulf Light). Amount 0–200 %. Save your own. Import Lightroom `.xmp` and DNG presets (local masks, lens and profile LUTs are ignored, with a note) |
| Crop | Aspect ratios, rotate 90°, flip, straighten ±45° |
| Light | Exposure, Contrast, Highlights, Shadows, Whites, Blacks; tone curve (RGB/R/G/B) |
| Color | Temp, Tint, Vibrance, Saturation, B&W; Color Mixer (8 bands, B&W mix); Color Grading (3-way + global); Calibration |
| Effects | Texture, Clarity, Dehaze, post-crop Vignette, film Grain |
| Detail | Sharpening (radius, masking), Noise Reduction, Color Noise Reduction |

Also included:
- Undo and redo.
- Press-and-hold before/after.
- Live histogram.
- Zoom to 800 %, rendering the visible region of the full-resolution original.
- Copy and paste settings.
- Full English and Arabic UI with right-to-left layout.

### Requirements and first build
- Xcode 26+ (iOS 26 SDK). The deployment target is iOS 17.0. No third-party packages.
- Open `Noor/Noor.xcodeproj` and choose your Team under *Signing & Capabilities*.
- If the build reports *missing Metal Toolchain*, install it: Xcode → Settings → Components, or `xcodebuild -downloadComponent metalToolchain`.
- The Core Image kernels in `Engine/Kernels.metal` are built with `MTL_COMPILER_FLAGS = -fcikernel` and `MTLLINKER_FLAGS = -cikernel`. These settings are already in the project.
- The project uses Xcode 16's synchronized folder format. Any file you add under `Noor/Noor/` is built automatically, so keep docs out of that folder.

### Architecture
```
Noor/Noor/
├── App/        NoorApp (root, open-in routing), AppModel + settings
├── Models/     EditRecipe, Geometry (crop/rotate maths), CurveMath (the one curve evaluator)
├── Engine/     RenderEngine (CIContexts), PhotoDocument (decode, RAW, HDR, proxies),
│               RecipeRenderer (the pipeline), NoorKernels + Kernels.metal,
│               PreviewRenderer + Viewport (CAMetalLayer canvas), Histogram, ThumbnailRenderer
├── Export/     Exporter (formats, passthrough, HDR), MetadataWriter, PhotoLibrarySaver
├── Presets/    Preset (+ Amount blending), XMPPresetImporter (Lightroom), PresetLibrary, BuiltInPresets.json
├── Library/    LibraryStore (projects on disk), ImportedOriginal (byte-exact import)
├── Views/      Editor (model, canvas, panels), Library, Presets, Export, Settings, Components, Theme
└── Resources/  Assets, Localizable.xcstrings (en + ar), InfoPlist.xcstrings, PrivacyInfo.xcprivacy
```
Pipeline order (`RecipeRenderer`):
1. Noise reduction (non-RAW)
2. Dehaze
3. White balance (non-RAW)
4. Tone (exposure, highlights/shadows, contrast, whites, blacks)
5. Clarity / texture
6. Tone curve
7. Calibration
8. HSL + vibrance/saturation, or the B&W mix
9. Color grading
10. Sharpening
11. Geometry (exact 90° turns and flips, bicubic straighten, crop)
12. Vignette
13. Grain

Every size-dependent effect is expressed relative to the full-resolution image, so the preview proxy and the export match.

### Check on a device
These behaviours are documented but not yet confirmed on hardware:
- The canvas orientation through `CIRenderDestination`.
- Whether the HEIF/PNG/TIFF writers accept the RGBX formats.
- Whether `.hdrImage` works with HEIF 10-bit (there is a fallback).
- Whether `CGImageDestinationCopyImageSource` supports HEIC (there is a fallback).
- Which file `PhotosPicker` returns for RAW+JPEG pairs.
- The tint direction of `CITemperatureAndTint`.
- Peak memory when exporting 48 MP images to 16-bit TIFF.
