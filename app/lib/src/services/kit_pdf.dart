import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../crypto/recovery.dart';

/// The printed recovery kit (design C6, `Recovery Kit.dc.html`): one page,
/// pure black-on-white so it photocopies, twelve words in a 4×3 grid inside
/// a heavy border, how-to and good-to-know columns, and a dashed tear-off
/// strip with a QR of the same words.
Future<void> printRecoveryKit({
  required RecoveryKit kit,
  required int accountCount,
  String? ownerHint,
}) async {
  final kitId = await kit.kitId();
  final now = DateTime.now();
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];
  final printedOn = '${now.day} ${months[now.month - 1]} ${now.year}';

  const ink = PdfColor.fromInt(0xFF000000);
  const ink70 = PdfColor.fromInt(0xB3000000);
  const ink55 = PdfColor.fromInt(0x8C000000);

  final doc = pw.Document(title: 'Purr recovery kit');
  // Bundled fonts — the kit must print on a plane, and nothing loads from
  // the network at runtime.
  Future<pw.Font> bundled(String file) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/$file'));
  final sans = await bundled('InstrumentSans-Regular.ttf');
  final sansSemi = await bundled('InstrumentSans-SemiBold.ttf');
  final sansBold = await bundled('InstrumentSans-Bold.ttf');
  final mono = await bundled('JetBrainsMono-Medium.ttf');
  // The white paw mark, shown inside the green masthead tile.
  final mark = pw.MemoryImage(
      (await rootBundle.load('assets/brand/purr_mark.png')).buffer.asUint8List());

  pw.Widget step(int n, String text, {bool green = false}) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 15,
            height: 15,
            decoration: const pw.BoxDecoration(
              color: ink,
              shape: pw.BoxShape.circle,
            ),
            alignment: pw.Alignment.center,
            child: pw.Text('$n',
                style: pw.TextStyle(
                    font: sansBold, fontSize: 8, color: PdfColors.white)),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(text,
                style: pw.TextStyle(
                    font: sans, fontSize: 9.5, lineSpacing: 2, color: ink70)),
          ),
        ],
      );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.symmetric(
          horizontal: .68 * PdfPageFormat.inch,
          vertical: .62 * PdfPageFormat.inch),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Masthead
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 12),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: ink, width: 2)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 30,
                  height: 30,
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFF2F6F5B),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  alignment: pw.Alignment.center,
                  child: pw.Image(mark, width: 19, height: 19),
                ),
                pw.SizedBox(width: 11),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Your recovery kit',
                          style: pw.TextStyle(font: sansBold, fontSize: 19)),
                      pw.SizedBox(height: 2),
                      pw.Text(
                          'Purr${ownerHint == null ? '' : ' · $ownerHint'} · printed $printedOn',
                          style: pw.TextStyle(
                              font: sans, fontSize: 9.5, color: ink55)),
                    ],
                  ),
                ),
                pw.Text('Keep this on paper.\nDon\'t photograph it.',
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                        font: sans, fontSize: 8, lineSpacing: 2, color: ink55)),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          // What this sheet is
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('This one sheet can bring your accounts back.',
                        style: pw.TextStyle(font: sansSemi, fontSize: 11.5)),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'If you lose your phone, your key, and every computer '
                      'you own, the twelve words below are still enough to '
                      'restore all your codes onto a new device. Nobody at '
                      "Purr has a copy — that's the point, and it's also "
                      'why losing this sheet without a backup means starting '
                      'over.',
                      style: pw.TextStyle(
                          font: sans,
                          fontSize: 9.3,
                          lineSpacing: 2.4,
                          color: ink70),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Container(
                width: 145,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: const PdfColor.fromInt(0x29000000)),
                  borderRadius: pw.BorderRadius.circular(7),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('WHERE TO PUT IT',
                        style: pw.TextStyle(
                            font: sansBold,
                            fontSize: 7,
                            letterSpacing: .6,
                            color: ink55)),
                    pw.SizedBox(height: 5),
                    pw.Text(
                        'A drawer at home, a file with your passport, or a '
                        'safe. Not your wallet, not your desk at work.',
                        style: pw.TextStyle(
                            font: sans,
                            fontSize: 8.8,
                            lineSpacing: 2,
                            color: ink70)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          // The twelve words
          pw.Container(
            padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: ink, width: 2),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Your twelve words',
                        style: pw.TextStyle(font: sansBold, fontSize: 12.5)),
                    pw.Text("Type them in this order. Capitals don't matter.",
                        style: pw.TextStyle(
                            font: sans, fontSize: 8.5, color: ink55)),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (var i = 0; i < kit.words.length; i++)
                      pw.Container(
                        width: 108,
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 7),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                              color: const PdfColor.fromInt(0x2E000000)),
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.SizedBox(
                              width: 11,
                              child: pw.Text('${i + 1}',
                                  style: pw.TextStyle(
                                      font: sansSemi,
                                      fontSize: 7.5,
                                      color: const PdfColor.fromInt(
                                          0x66000000))),
                            ),
                            pw.SizedBox(width: 5),
                            pw.Text(kit.words[i],
                                style:
                                    pw.TextStyle(font: mono, fontSize: 11)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 13),
          // How to use it / Good to know
          pw.Expanded(
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('How to use it',
                          style: pw.TextStyle(font: sansBold, fontSize: 11)),
                      pw.SizedBox(height: 7),
                      step(1, 'Install Purr on your new phone and open it.'),
                      pw.SizedBox(height: 6),
                      step(2,
                          'Tap "Bring my codes back", then "My recovery kit".'),
                      pw.SizedBox(height: 6),
                      step(3,
                          'Type the twelve words. Your accounts come back in about a minute.'),
                      pw.SizedBox(height: 6),
                      step(4,
                          'Print a fresh kit. This sheet stops working the moment you use it.'),
                    ],
                  ),
                ),
                pw.Container(
                    width: 1,
                    height: 110,
                    margin: const pw.EdgeInsets.symmetric(horizontal: 13),
                    color: const PdfColor.fromInt(0x1F000000)),
                pw.SizedBox(
                  width: 175,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Good to know',
                          style: pw.TextStyle(font: sansBold, fontSize: 11)),
                      pw.SizedBox(height: 7),
                      pw.Text(
                          'These words are not a password. Nobody can use '
                          'them to sign in to your accounts — they only '
                          'unscramble your own backup.',
                          style: pw.TextStyle(
                              font: sans,
                              fontSize: 8.8,
                              lineSpacing: 2,
                              color: ink70)),
                      pw.SizedBox(height: 6),
                      pw.Text(
                          'Anyone holding this sheet can restore your codes '
                          'onto their device. Treat it like a spare house key.',
                          style: pw.TextStyle(
                              font: sans,
                              fontSize: 8.8,
                              lineSpacing: 2,
                              color: ink70)),
                      pw.SizedBox(height: 6),
                      pw.Text(
                          'Lost the sheet? Print another from Security → '
                          'Recovery kit while you still have your phone.',
                          style: pw.TextStyle(
                              font: sans,
                              fontSize: 8.8,
                              lineSpacing: 2,
                              color: ink70)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Tear-off strip
          pw.Container(
            padding: const pw.EdgeInsets.only(top: 11),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(
                    color: PdfColor.fromInt(0x47000000),
                    width: .8,
                    style: pw.BorderStyle.dashed),
              ),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 78,
                  height: 78,
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(
                        color: const PdfColor.fromInt(0x29000000)),
                    borderRadius: pw.BorderRadius.circular(7),
                  ),
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: 'purr-kit:${kit.words.join('-')}',
                    color: ink,
                  ),
                ),
                pw.SizedBox(width: 13),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('The same twelve words, as a square',
                          style: pw.TextStyle(font: sansBold, fontSize: 10)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                          "Scanning this is faster than typing, and it's the "
                          'same secret — so it deserves the same drawer. If '
                          "you'd rather not have a scannable copy lying "
                          'around, cut this corner off; the words above still '
                          'work on their own.',
                          style: pw.TextStyle(
                              font: sans,
                              fontSize: 8.6,
                              lineSpacing: 2,
                              color: ink70)),
                    ],
                  ),
                ),
                pw.SizedBox(width: 13),
                pw.SizedBox(
                  width: 108,
                  child: pw.RichText(
                    textAlign: pw.TextAlign.right,
                    text: pw.TextSpan(
                      style: pw.TextStyle(
                          font: sans,
                          fontSize: 8,
                          lineSpacing: 2.2,
                          color: ink55),
                      children: [
                        const pw.TextSpan(text: 'Kit ID '),
                        pw.TextSpan(
                            text: kitId,
                            style: pw.TextStyle(font: mono, fontSize: 8)),
                        pw.TextSpan(
                            text:
                                '\nCovers $accountCount account${accountCount == 1 ? '' : 's'}\nReplaces all earlier kits'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  await Printing.layoutPdf(
    name: 'Purr recovery kit',
    onLayout: (_) => doc.save(),
  );
}
