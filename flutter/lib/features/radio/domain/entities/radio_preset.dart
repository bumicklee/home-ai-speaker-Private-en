import 'package:equatable/equatable.dart';

import '../../../devices/domain/entities/device_status.dart';

/// One preset. `{name, url, genre}` from firmware `/storage/presets.json` (genre is comma-separated tags)
class RadioPreset extends Equatable {
  const RadioPreset({required this.name, required this.url, this.genre = ''});

  factory RadioPreset.fromJson(Map<String, dynamic> j) => RadioPreset(
        name: j['name'] as String? ?? '',
        url: j['url'] as String? ?? '',
        genre: j['genre'] as String? ?? '',
      );

  final String name;
  final String url;
  final String genre;

  /// Lowercase tags (empty ones removed)
  List<String> get tags =>
      genre.split(',').map((t) => t.trim().toLowerCase()).where((t) => t.isNotEmpty).toList(growable: false);

  /// Tags shown on screen. korean and english are left out because they only decide the group (design "kpop · pop")
  List<String> get displayTags => tags.where((t) => t != 'korean' && t != 'english').toList(growable: false);

  Map<String, dynamic> toJson() => {'name': name, 'url': url, 'genre': genre};

  RadioPreset copyWith({String? name, String? url, String? genre}) =>
      RadioPreset(name: name ?? this.name, url: url ?? this.url, genre: genre ?? this.genre);

  @override
  List<Object?> get props => [name, url, genre];
}

/// `/media/now`, WS `media_state`. [preset] only when played from a preset (firmware `radio_now_json`)
class RadioNow extends Equatable {
  const RadioNow({this.media = const MediaNow(), this.preset});

  final MediaNow media;
  final int? preset;

  bool get isRadio => media.source == 'radio' && media.isActive;

  /// Whether to show the pause button (playing or connecting)
  bool get canPause => media.state == 'playing' || media.state == 'buffering';

  @override
  List<Object?> get props => [media, preset];
}

/// A Radio-Browser search result the speaker can play
class RadioStation extends Equatable {
  const RadioStation({
    required this.name,
    required this.url,
    this.codec = '',
    this.bitrate = 0,
    this.country = '',
    this.tags = '',
  });

  final String name;

  /// `url_resolved` (the actual stream URL with the playlist unpacked)
  final String url;
  final String codec;
  final int bitrate;
  final String country;
  final String tags;

  @override
  List<Object?> get props => [name, url, codec, bitrate, country, tags];
}
