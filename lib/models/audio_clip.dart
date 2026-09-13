/// One playable piece of recitation.
///
/// Every reciter ultimately resolves a displayed ayah to a list of these. For
/// the per-ayah mirrors (Al-Husary, al-Naihi, قنيوه, al-Hudaifi, الدوكالي) a clip
/// is a whole MP3 and [start]/[end] are null — byte for byte the behaviour the
/// app has always had. For a [AudioScheme.timedSurah] reciter the file is the
/// whole surah and the clip is a slice of it.
///
/// The point of the abstraction is that everything above it — repeat ayah,
/// repeat page, repeat ثمن, repeat مقطع, next/previous — never learns which kind
/// it is playing. `just_audio`'s `ClippingAudioSource` reports a clip's end as
/// `ProcessingState.completed`, exactly as a whole file does, so the completion
/// handler that drives all of those features needs no knowledge of clipping.
class AudioClip {
  /// File name relative to the reciter's `audioBaseUrl`, e.g. `002015.mp3` for
  /// a per-ayah mirror or `002.mp3` for a whole-surah one.
  final String file;

  /// Where this ayah starts inside [file]. Null means "from the beginning",
  /// which is the per-ayah case.
  final Duration? start;

  /// Where this ayah ends inside [file]. Null means "to the end of the file".
  final Duration? end;

  const AudioClip(this.file, {this.start, this.end});

  /// A clip that is an entire file — the per-ayah mirrors' only shape.
  const AudioClip.whole(this.file)
      : start = null,
        end = null;

  /// Whether this clip is a slice rather than a whole file. Only slices need a
  /// `ClippingAudioSource`; whole files take the cheaper plain source, which
  /// keeps the existing reciters on exactly the code path they had before.
  bool get isClipped => start != null || end != null;

  /// How long this clip plays for, when both bounds are known.
  Duration? get duration =>
      (start != null && end != null) ? end! - start! : null;

  @override
  bool operator ==(Object other) =>
      other is AudioClip &&
      other.file == file &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(file, start, end);

  @override
  String toString() => isClipped
      ? '$file[${start?.inMilliseconds ?? 0}..${end?.inMilliseconds ?? -1}]'
      : file;
}
