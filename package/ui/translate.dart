import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:dynamic_parallel_queue/dynamic_parallel_queue.dart';
import 'package:intl/intl.dart' show toBeginningOfSentenceCase;

import 'bin/caches.dart';
import 'bin/core.dart';
import 'bin/ui.dart';

const input = './bin/ui.dart';
const output = './lib/ui.dart';

final queue = Queue(parallel: 8);

late Map<String, String> caches;

void main(List<String> args) async {
  caches = await readCaches();
  print('缓存词条数量 ${caches.length}');

  ///
  final languagesName = await languagesMap();

  /// 需要进行翻译的语言代码
  final targetLanguages = [
    "sq",
    "ar",
    "am",
    "as",
    "az",
    "ee",
    "ay",
    "ga",
    "et",
    "or",
    "om",
    "eu",
    "be",
    "bm",
    "bg",
    "is",
    "pl",
    "bs",
    "fa",
    "bho",
    "af",
    "tt",
    "da",
    "de",
    "dv",
    "ti",
    "doi",
    "ru",
    "fr",
    "sa",
    "tl",
    "fi",
    "fy",
    "km",
    "ka",
    "gom",
    "gu",
    "gn",
    "kk",
    "ht",
    "ko",
    "ha",
    "nl",
    "ky",
    "gl",
    "ca",
    "cs",
    "kn",
    "co",
    "kri",
    "hr",
    "qu",
    "ku",
    "ckb",
    "la",
    "lv",
    "lo",
    "lt",
    "ln",
    "lg",
    "lb",
    "rw",
    "ro",
    "mg",
    "mt",
    "mr",
    "ml",
    "ms",
    "mk",
    "mai",
    "mi",
    "mni-Mtei",
    "mn",
    "bn",
    "lus",
    "my",
    "hmn",
    "xh",
    "zu",
    "ne",
    "no",
    "pa",
    "pt",
    "ps",
    "ny",
    "ak",
    "ja",
    "sv",
    "sm",
    "sr",
    "nso",
    "st",
    "si",
    "eo",
    "sk",
    "sl",
    "sw",
    "gd",
    "ceb",
    "so",
    "tg",
    "te",
    "ta",
    "th",
    "tr",
    "tk",
    "cy",
    "ug",
    "ur",
    "uk",
    "uz",
    "es",
    "iw",
    "el",
    "haw",
    "sd",
    "hu",
    "sn",
    "hy",
    "ig",
    "ilo",
    "it",
    "yi",
    "hi",
    "su",
    "id",
    "jw",
    "en",
    "yo",
    "vi",
    "zh-TW",
    "ts"
  ];

  final text = StringBuffer();
  text.writeln('///');
  text.writeln('/// This file is automatically generated by translate.dart');
  text.writeln('///');
  text.writeln('import "package:get/get.dart";');
  text.writeln('class UI implements Translations {');

  final queue = Queue(parallel: 20);

  /// 制作静态变量
  final keys = zh.keys;
  for (var key in keys) {
    text.writeln('  static const ${key.replaceAll(' ', '')} = \'$key\';');
  }

  /// 预先排序
  final rankedLanguages = <String, String>{
    'en': '',
    'zh-CN': '',
    'zh-TW': '',
    'ja': '',
    'ko': '',
    'id': '',
    'es': '',
    'fr': '',
    'ru': '',
  };
  final sourceLanguage = "zh-CN";

  /// 通过code匹配语种名称
  for (var value in rankedLanguages.keys) {
    rankedLanguages[value] = languagesName[value]!.last;
  }
  for (var value in targetLanguages) {
    if (languagesName.containsKey(value)) {
      if (rankedLanguages.containsKey(value)) continue;
      rankedLanguages[value] = languagesName[value]!.last;
    }
  }
  text.writeln(
      '  static const languages = ${JsonEncoder.withIndent('  ').convert(rankedLanguages)};');
  print('完成 翻译语言名词');

  int failedCount = 0;
  final languages = {'zh_CN': zh};
  for (var targetLanguage in rankedLanguages.keys) {
    if (targetLanguage.toLowerCase() == 'zh-cn') continue;
    final data = <String, String>{};
    for (var key in zh.keys) {
      final rawText = zh[key]!;
      if (key == 'findUp') {
        data[key] = 'Find Up!';
        continue;
      }
      queue.add(() async {
        if (rawText.isEmpty) {
          data[key] = rawText;
          return;
        }
        if (fix[targetLanguage]?[key] != null) {
          data[key] = fix[targetLanguage]![key]!;
          return;
        }
        final md5 = toMD5('$targetLanguage-${rawText}');
        if (caches.containsKey(md5)) {
          data[key] = toBeginningOfSentenceCase(caches[md5]!);
        } else {
          String text;
          try {
            text = await translate(
              rawText,
              sourceLanguage: sourceLanguage,
              targetLanguage: targetLanguage,
            ).then((value) =>
                toBeginningOfSentenceCase(value.replaceAll('"', '')));

            if (text.isNotEmpty) {
              caches[md5] = text;
              await writeCaches();
            } else {
              failedCount++;
            }
            // print('翻译成功 $targetLanguage: $rawText => $text');
          } catch (e) {
            failedCount++;
            text = '';
            print(e);
            // print('翻译失败 $targetLanguage: ${zh[key]}');
          }
          data[key] = text;
          print('剩余任务数量 ${queue.pending}, 翻译失败次数 $failedCount');
        }
      });
    }

    languages[targetLanguage.replaceAll('-', '_')] = data;
  }
  await queue.whenComplete();
  print('翻译失败次数 $failedCount');
  await writeCaches();
  text
    ..writeln('@override')
    ..writeln(
        '  Map<String, Map<String, String>> get keys => ${JsonEncoder.withIndent('  ').convert(languages)};')
    ..writeln('}');
  await File(output).writeAsString(text.toString());

  /// 创建csv表文件，直观检查翻译质量
  try {
    final csvConverter = ListToCsvConverter();
    final csvData = <List<String>>[];
    final keyIndex = zh.keys.toList();
    csvData.add(['key']);
    languages.forEach((language, value) {
      csvData.first.add(language);
      value.forEach((key, value) {
        final index = keyIndex.indexOf(key) + 1;
        if (language == sourceLanguage) {
          csvData.add([key, value]);
        } else {
          csvData[index].add(value);
        }
      });
    });
    await File('ui.csv').writeAsString(csvConverter.convert(csvData));
  } catch (e) {
    print(e);
  }
  exit(0);
}
