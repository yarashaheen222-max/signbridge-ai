import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

void main() => runApp(const SignBridgeApp());

const _shareChannel = MethodChannel('org.signbridge.app/share');

enum UnitKind { verifiedSign, fingerspell, unavailable }

class MotionFrame {
  final double t;
  final Map<String, double> channels;
  const MotionFrame(this.t, this.channels);
}

class SignMotion {
  final String id;
  final bool verifiedPsl;
  final String source;
  final List<MotionFrame> frames;
  const SignMotion({required this.id, required this.verifiedPsl, required this.source, required this.frames});
}

class AvatarMotionEngine {
  // Prototype motion clips only. These values demonstrate the animation architecture; they are NOT PSL signs.
  static const Map<String, SignMotion> demo = {
    'DEMO_HELLO': SignMotion(id: 'DEMO_HELLO', verifiedPsl: false, source: 'software-demo', frames: [
      MotionFrame(0.0, {'rightArm': .20, 'rightHand': .10, 'fingers': .25, 'head': .0, 'face': .15}),
      MotionFrame(.5, {'rightArm': .75, 'rightHand': .85, 'fingers': .80, 'head': .08, 'face': .35}),
      MotionFrame(1.0, {'rightArm': .30, 'rightHand': .25, 'fingers': .35, 'head': .0, 'face': .15}),
    ]),
    'DEMO_THANK_YOU': SignMotion(id: 'DEMO_THANK_YOU', verifiedPsl: false, source: 'software-demo', frames: [
      MotionFrame(0.0, {'rightArm': .25, 'rightHand': .25, 'fingers': .65, 'head': .0, 'face': .20}),
      MotionFrame(.55, {'rightArm': .60, 'rightHand': .72, 'fingers': .75, 'head': .10, 'face': .35}),
      MotionFrame(1.0, {'rightArm': .38, 'rightHand': .40, 'fingers': .55, 'head': .04, 'face': .20}),
    ]),
  };

  SignMotion? forUnit(SignUnit unit) => demo[unit.gloss];
}


class SignUnit {
  final String source;
  final String gloss;
  final UnitKind kind;
  final double confidence;
  final String provenance;
  final String verification;
  const SignUnit(this.source, this.gloss, this.kind, this.confidence, {this.provenance = '—', this.verification = 'غير موثقة'});
}

class PalestineSignPack {
  static const id = 'psl-palestine-v0';
  static const displayName = 'لغة الإشارة الفلسطينية (PSL)';
  static const status = 'قيد البناء والتحقق المجتمعي';
  static const policy = 'لا تُعرض أي حركة كإشارة فلسطينية موثقة قبل وجود مصدر قابل للاستخدام ومراجعة بشرية.';
  static const sources = <String>[
    'مصادر أكاديمية فلسطينية مرخّصة/مسموح باستخدام بياناتها عند التحقق من شروط الترخيص',
    'مراجع مؤسساتية فلسطينية للتحقق فقط عندما لا يسمح الترخيص بإعادة النسخ',
    'مراجعة من مستخدمين صم/مختصين قبل الانتقال إلى Verified',
  ];
}


class DemoTranslationEngine {
  // SOFTWARE TEST DATA ONLY. These are NOT claimed Palestinian signs.
  static const verifiedDemo = <String, String>{
    'مرحبا': 'DEMO_HELLO',
    'شكرا': 'DEMO_THANK_YOU',
    'نعم': 'DEMO_YES',
    'لا': 'DEMO_NO',
  };

  List<SignUnit> translate(String text) {
    final cleaned = text
        .replaceAll(RegExp(r'[ًٌٍَُِّْـ]'), '')
        .replaceAll(RegExp(r'[^\u0600-\u06FFa-zA-Z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return const [];
    return cleaned.split(' ').map((word) {
      final demo = verifiedDemo[word];
      if (demo != null) return SignUnit(word, demo, UnitKind.verifiedSign, .99, provenance: 'بيانات اختبار برمجية', verification: 'اختبار فقط — ليست PSL');
      if (RegExp(r'^[a-zA-Z]+$').hasMatch(word)) {
        return SignUnit(word, word.toUpperCase().split('').join(' · '), UnitKind.fingerspell, .95, provenance: 'Fallback', verification: 'تهجئة تجريبية');
      }
      return SignUnit(word, 'بانتظار إشارة فلسطينية موثّقة', UnitKind.unavailable, 0, provenance: PalestineSignPack.id, verification: 'غير متوفرة');
    }).toList();
  }
}

class SignBridgeApp extends StatelessWidget {
  const SignBridgeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'SignBridge AI',
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B66)),
          scaffoldBackgroundColor: const Color(0xFFF7FAF9),
          cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
        ),
        home: const Directionality(textDirection: TextDirection.rtl, child: HomeScreen()),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override void initState() {
    super.initState();
    _shareChannel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText' && call.arguments is String) _openSharedText(call.arguments as String);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try { final text = await _shareChannel.invokeMethod<String>('getInitialSharedText'); if (text != null && text.trim().isNotEmpty) _openSharedText(text); } catch (_) {}
    });
  }
  void _openSharedText(String text) {
    if (!mounted || text.trim().isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: TextTranslateScreen(initialText: text.trim()))));
  }
  @override
  Widget build(BuildContext context) {
    final items = <_Feature>[
      const _Feature('ترجمة النص', 'اكتب أو الصق نصًا لترجمته إلى لغة الإشارة', Icons.text_fields, TextTranslateScreen()),
      const _Feature('ترجمة الكلام المباشر', 'استمع للكلام وحوّله إلى لغة الإشارة', Icons.mic_none_rounded, LiveSpeechScreen()),
      const _Feature('ترجمة صورة', 'التقط صورة أو اختر لقطة شاشة واستخرج النص', Icons.document_scanner_outlined, ImageTranslateScreen()),
      const _Feature('محادثة', 'تواصل بين شخص أصم وشخص سامع', Icons.forum_outlined, ComingSoonScreen(title: 'المحادثة')),
      const _Feature('اختيار لغة الإشارة', 'حدد المجتمع أو لغة الإشارة التي تفهمها', Icons.sign_language_outlined, SignLanguageScreen()),
      const _Feature('السجل', 'أعد تشغيل الترجمات التي اخترت حفظها', Icons.history, ComingSoonScreen(title: 'السجل')),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('SignBridge AI', style: TextStyle(fontWeight: FontWeight.w800))),
      body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(18, 10, 18, 28), children: [
        Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(24)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.sign_language_rounded, size: 44), SizedBox(height: 12), Text('افهم بطريقتك', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)), SizedBox(height: 7), Text('العربية → لغة الإشارة الفلسطينية، مع مصدر وحالة تحقق لكل وحدة.', style: TextStyle(fontSize: 16, height: 1.5))])),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.black12)), child: const Row(children: [Icon(Icons.verified_user_outlined), SizedBox(width: 10), Expanded(child: Text('PSL Pack: قيد البناء والتحقق. لن يخترع التطبيق إشارة غير موثقة.'))])),
        const SizedBox(height: 18),
        ...items.map((item) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), child: InkWell(borderRadius: BorderRadius.circular(20), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: item.page))), child: Padding(padding: const EdgeInsets.all(17), child: Row(children: [CircleAvatar(radius: 25, child: Icon(item.icon, size: 27)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(item.subtitle, style: TextStyle(color: Colors.grey.shade700, height: 1.35))])), const Icon(Icons.chevron_left)]))))),
        const Text('يمكن مشاركة نص من تطبيق آخر إلى SignBridge مباشرة على Android.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
      ])),
    );
  }
}

class TextTranslateScreen extends StatefulWidget {
  final String initialText;
  const TextTranslateScreen({super.key, this.initialText = ''});
  @override State<TextTranslateScreen> createState() => _TextTranslateScreenState();
}

class _TextTranslateScreenState extends State<TextTranslateScreen> {
  final controller = TextEditingController();
  final engine = DemoTranslationEngine();
  List<SignUnit> units = const [];
  @override void initState() { super.initState(); if (widget.initialText.isNotEmpty) { controller.text = widget.initialText; WidgetsBinding.instance.addPostFrameCallback((_) => translate()); } }
  @override void dispose() { controller.dispose(); super.dispose(); }
  void translate() => setState(() => units = engine.translate(controller.text));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ترجمة النص')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      const Text('اكتب أو الصق النص', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)), const SizedBox(height: 10),
      TextField(controller: controller, minLines: 4, maxLines: 8, decoration: InputDecoration(hintText: 'جرّب: مرحبا شكرا HODA', border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)))),
      const SizedBox(height: 14),
      SizedBox(height: 54, child: FilledButton.icon(onPressed: translate, icon: const Icon(Icons.sign_language), label: const Text('ترجمة إلى لغة الإشارة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)))),
      if (units.isNotEmpty) ...[
        const SizedBox(height: 18),
        const _SafetyBanner(), const SizedBox(height: 12),
        AvatarPlayer(units: units), const SizedBox(height: 16),
        const Text('مسار الترجمة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
        ...units.map((u) => _UnitTile(unit: u)),
      ]
    ]),
  );
}

class AvatarPlayer extends StatefulWidget {
  final List<SignUnit> units;
  const AvatarPlayer({super.key, required this.units});
  @override State<AvatarPlayer> createState() => _AvatarPlayerState();
}

class _AvatarPlayerState extends State<AvatarPlayer> {
  Timer? timer; int index = 0; bool playing = false; double speed = 1; double motionProgress = 0;
  final motionEngine = AvatarMotionEngine();
  SignUnit get current => widget.units[index.clamp(0, widget.units.length - 1)];
  @override void didUpdateWidget(covariant AvatarPlayer oldWidget) { super.didUpdateWidget(oldWidget); stop(); index = 0; }
  @override void dispose() { timer?.cancel(); super.dispose(); }
  void play() {
    timer?.cancel(); setState(() => playing = true);
    timer = Timer.periodic(Duration(milliseconds: (100 / speed).round()), (_) {
      motionProgress += .08;
      if (motionProgress >= 1) {
        motionProgress = 0;
        if (index >= widget.units.length - 1) { stop(); return; }
        setState(() => index++);
      } else { setState(() {}); }
    });
  }
  void stop() { timer?.cancel(); if (mounted) setState(() => playing = false); }
  void replay() { stop(); setState(() { index = 0; motionProgress = 0; }); play(); }
  void cycleSpeed() { setState(() { speed = speed == .75 ? 1 : speed == 1 ? 1.25 : speed == 1.25 ? 1.5 : .75; }); if (playing) play(); }
  @override
  Widget build(BuildContext context) {
    final u = current;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFF15201F), borderRadius: BorderRadius.circular(24)),
      child: Column(children: [
        Row(children: [
          const Expanded(child: Text('AI Avatar Player • Prototype', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
          Text('${index + 1}/${widget.units.length}', style: const TextStyle(color: Colors.white70)),
        ]),
        const SizedBox(height: 20),
        AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: Container(
          key: ValueKey(index), height: 185, width: double.infinity,
          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            PrototypeAvatarBody(unit: u, progress: motionProgress, motion: motionEngine.forUnit(u)),
            const SizedBox(height: 8), Text(u.source, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 3), Text(u.gloss, textAlign: TextAlign.center, style: TextStyle(color: u.kind == UnitKind.unavailable ? Colors.orange.shade200 : Colors.white70)),
          ]),
        )),
        const SizedBox(height: 14),
        LinearProgressIndicator(value: (index + 1) / widget.units.length), const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          IconButton.filledTonal(onPressed: replay, icon: const Icon(Icons.replay), tooltip: 'إعادة'),
          IconButton.filledTonal(onPressed: playing ? stop : play, icon: Icon(playing ? Icons.pause : Icons.play_arrow), tooltip: playing ? 'إيقاف مؤقت' : 'تشغيل'),
          FilledButton.tonal(onPressed: cycleSpeed, child: Text('${speed}x')),
          IconButton.filledTonal(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: FullscreenAvatar(units: widget.units)))), icon: const Icon(Icons.fullscreen), tooltip: 'ملء الشاشة'),
        ]),
      ]),
    );
  }
}

class PrototypeAvatarBody extends StatelessWidget {
  final SignUnit unit;
  final double progress;
  final SignMotion? motion;
  const PrototypeAvatarBody({super.key, required this.unit, required this.progress, required this.motion});

  Map<String,double> get pose {
    if (motion == null || motion!.frames.isEmpty) return const {};
    final fs = motion!.frames;
    MotionFrame a = fs.first, b = fs.last;
    for (var i=0; i<fs.length-1; i++) { if (progress >= fs[i].t && progress <= fs[i+1].t) { a=fs[i]; b=fs[i+1]; break; } }
    final span = (b.t-a.t).abs() < .001 ? 1.0 : b.t-a.t;
    final x = ((progress-a.t)/span).clamp(0.0,1.0);
    final keys = {...a.channels.keys, ...b.channels.keys};
    return {for (final k in keys) k: (a.channels[k] ?? 0) + ((b.channels[k] ?? 0)-(a.channels[k] ?? 0))*x};
  }

  @override Widget build(BuildContext context) {
    final p=pose; final arm=p['rightArm']??.15; final hand=p['rightHand']??.15; final face=p['face']??.1;
    if (unit.kind == UnitKind.unavailable) return const Icon(Icons.help_outline, color: Colors.white, size: 82);
    return SizedBox(height: 112, width: 150, child: Stack(alignment: Alignment.topCenter, children:[
      Transform.translate(offset: Offset(0, face*3), child: Container(width:48,height:48,decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:Colors.white,width:3)), child: Icon(face>.25?Icons.sentiment_satisfied_alt:Icons.sentiment_neutral,color:Colors.white,size:28))),
      Positioned(top:48, child: Container(width:62,height:58,decoration:BoxDecoration(border:Border.all(color:Colors.white,width:3),borderRadius:BorderRadius.circular(22)))),
      Positioned(top:55,left:12+arm*12,child:Transform.rotate(angle:-.9+arm*.9,alignment:Alignment.topRight,child:Container(width:55,height:8,decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(8)),child:Align(alignment:Alignment.centerLeft,child:Transform.scale(scale:.8+hand*.35,child:const Icon(Icons.back_hand,color:Colors.white,size:24))))))),
      Positioned(top:55,right:16,child:Transform.rotate(angle:.55,alignment:Alignment.topLeft,child:Container(width:48,height:8,decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(8))))),
      if (motion != null) Positioned(bottom:0,child:Text(motion!.verifiedPsl?'PSL VERIFIED':'MOTION DEMO • NOT PSL',style:TextStyle(color:motion!.verifiedPsl?Colors.greenAccent:Colors.orangeAccent,fontSize:10,fontWeight:FontWeight.bold))),
    ]));
  }
}

class FullscreenAvatar extends StatelessWidget {
  final List<SignUnit> units;
  const FullscreenAvatar({super.key, required this.units});
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: const Color(0xFF0D1514), appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white, title: const Text('المترجم')), body: Center(child: Padding(padding: const EdgeInsets.all(16), child: AvatarPlayer(units: units))));
}

class _SafetyBanner extends StatelessWidget {
  const _SafetyBanner();
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.amber.shade200)), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.verified_user_outlined), SizedBox(width: 10), Expanded(child: Text('نسخة اختبار تقنية: أسماء الحركات التجريبية ليست قاموس لغة إشارة فلسطينية. أي كلمة بلا إشارة موثّقة لا يتم اختراع إشارة لها.'))]));
}

class _UnitTile extends StatelessWidget {
  final SignUnit unit; const _UnitTile({required this.unit});
  @override Widget build(BuildContext context) {
    final (icon, label) = switch (unit.kind) { UnitKind.verifiedSign => (Icons.verified_outlined, 'حركة اختبار موجودة'), UnitKind.fingerspell => (Icons.back_hand_outlined, 'تهجئة بالأصابع'), UnitKind.unavailable => (Icons.warning_amber_rounded, 'غير متاحة') };
    return Card(child: ListTile(leading: Icon(icon), title: Text(unit.source, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${unit.gloss} • $label\n${unit.verification} • ${unit.provenance}'), trailing: unit.confidence > 0 ? Text('${(unit.confidence * 100).round()}%') : null));
  }
}


class LiveSpeechScreen extends StatefulWidget {
  const LiveSpeechScreen({super.key});
  @override State<LiveSpeechScreen> createState() => _LiveSpeechScreenState();
}

class _LiveSpeechScreenState extends State<LiveSpeechScreen> {
  final stt.SpeechToText speech = stt.SpeechToText();
  final engine = DemoTranslationEngine();
  bool ready = false, listening = false;
  String heard = '';
  String status = 'اضغط على الميكروفون للبدء';
  List<SignUnit> units = const [];

  Future<void> toggle() async {
    if (listening) {
      await speech.stop();
      if (mounted) setState(() { listening = false; status = 'تم إيقاف الاستماع'; });
      return;
    }
    final ok = ready || await speech.initialize(
      onStatus: (s) { if (mounted && (s == 'done' || s == 'notListening')) setState(() => listening = false); },
      onError: (e) { if (mounted) setState(() { listening = false; status = 'تعذر استخدام الميكروفون: ${e.errorMsg}'; }); },
    );
    if (!ok) { if (mounted) setState(() => status = 'التعرّف على الكلام غير متاح على هذا الجهاز'); return; }
    ready = true;
    setState(() { listening = true; status = 'أستمع الآن…'; });
    await speech.listen(
      localeId: 'ar',
      partialResults: true,
      onResult: (r) {
        final text = r.recognizedWords.trim();
        if (!mounted) return;
        setState(() { heard = text; units = engine.translate(text); status = r.finalResult ? 'تم التعرّف على الكلام' : 'أستمع الآن…'; });
      },
    );
  }

  @override void dispose() { speech.stop(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ترجمة الكلام المباشر')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(18)), child: const Text('الخصوصية: يحتاج هذا الوضع إلى إذن الميكروفون. لا يحفظ SignBridge التسجيل الصوتي داخل التطبيق. قد يعتمد التعرف على الكلام على خدمات الجهاز/النظام.', style: TextStyle(height: 1.5))),
      const SizedBox(height: 20),
      Center(child: InkWell(onTap: toggle, borderRadius: BorderRadius.circular(60), child: CircleAvatar(radius: 48, child: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded, size: 48)))),
      const SizedBox(height: 12), Text(status, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 22), const Text('النص الذي تم سماعه', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
      Container(minHeight: 90, padding: const EdgeInsets.all(15), decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(16)), child: Text(heard.isEmpty ? 'سيظهر الكلام العربي هنا…' : heard, style: const TextStyle(fontSize: 18, height: 1.5))),
      if (units.isNotEmpty) ...[const SizedBox(height: 18), const _SafetyBanner(), const SizedBox(height: 12), AvatarPlayer(units: units)],
    ]),
  );
}


class ImageTranslateScreen extends StatefulWidget {
  const ImageTranslateScreen({super.key});
  @override State<ImageTranslateScreen> createState() => _ImageTranslateScreenState();
}

class _ImageTranslateScreenState extends State<ImageTranslateScreen> {
  final picker = ImagePicker();
  final controller = TextEditingController();
  final engine = DemoTranslationEngine();
  List<SignUnit> units = const [];
  String? imagePath;
  bool busy = false;
  String status = 'اختر صورة أو التقط صورة بالكاميرا.';

  Future<void> pick(ImageSource source) async {
    try {
      final image = await picker.pickImage(source: source, imageQuality: 92);
      if (image == null) return;
      setState(() { imagePath = image.path; busy = true; status = 'جارٍ استخراج النص على الجهاز…'; units = const []; });
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final result = await recognizer.processImage(InputImage.fromFilePath(image.path));
        controller.text = result.text.trim();
        if (!mounted) return;
        setState(() {
          busy = false;
          status = controller.text.isEmpty
              ? 'لم يتم العثور على نص واضح. يمكنك كتابة النص يدويًا في الحقل أدناه.'
              : 'تم استخراج نص تجريبي. راجعه وصححه قبل الترجمة.';
        });
      } finally {
        await recognizer.close();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { busy = false; status = 'تعذر قراءة الصورة على هذا الجهاز. يمكنك إدخال النص يدويًا.'; });
    }
  }

  void translate() => setState(() => units = engine.translate(controller.text));
  @override void dispose() { controller.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ترجمة صورة')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(18)), child: const Text('الخصوصية: في هذا النموذج تتم محاولة OCR داخل الجهاز ولا يرفع SignBridge الصورة إلى خادم. دعم OCR العربي المحلي ما زال تجريبيًا، لذلك يجب مراجعة النص قبل تحويله إلى لغة الإشارة.', style: TextStyle(height: 1.5))),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: FilledButton.tonalIcon(onPressed: busy ? null : () => pick(ImageSource.camera), icon: const Icon(Icons.camera_alt_outlined), label: const Text('الكاميرا'))),
        const SizedBox(width: 10),
        Expanded(child: FilledButton.tonalIcon(onPressed: busy ? null : () => pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('المعرض'))),
      ]),
      if (imagePath != null) ...[
        const SizedBox(height: 14),
        ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.file(File(imagePath!), height: 190, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink())),
      ],
      const SizedBox(height: 14),
      if (busy) const LinearProgressIndicator(),
      const SizedBox(height: 8), Text(status, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4)),
      const SizedBox(height: 16), const Text('النص المستخرج — راجعه أولًا', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
      TextField(controller: controller, minLines: 4, maxLines: 9, decoration: InputDecoration(hintText: 'سيظهر النص هنا، ويمكنك تصحيحه يدويًا…', border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)))),
      const SizedBox(height: 12),
      SizedBox(height: 52, child: FilledButton.icon(onPressed: busy ? null : translate, icon: const Icon(Icons.sign_language), label: const Text('ترجمة النص بعد المراجعة', style: TextStyle(fontWeight: FontWeight.w800)))),
      if (units.isNotEmpty) ...[const SizedBox(height: 18), const _SafetyBanner(), const SizedBox(height: 12), AvatarPlayer(units: units), const SizedBox(height: 14), ...units.map((u) => _UnitTile(unit: u))],
    ]),
  );
}

class SignLanguageScreen extends StatelessWidget {
  const SignLanguageScreen({super.key});
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('لغة الإشارة')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      const Text(PalestineSignPack.displayName, style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
      const SizedBox(height: 6), const Text('الحزمة الأساسية للنسخة الأولى'), const SizedBox(height: 18),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
        Text('الحالة', style: TextStyle(fontWeight: FontWeight.w900)), SizedBox(height: 4), Text(PalestineSignPack.status), SizedBox(height: 14),
        Text('سياسة التحقق', style: TextStyle(fontWeight: FontWeight.w900)), SizedBox(height: 4), Text(PalestineSignPack.policy, style: TextStyle(height: 1.5)),
      ]))),
      const SizedBox(height: 14), const Text('مصادر التحقق', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
      ...PalestineSignPack.sources.map((s) => ListTile(leading: const Icon(Icons.source_outlined), title: Text(s))),
      const Divider(height: 30),
      const Text('ASL / BSL / KSL ولغات مجتمعات أخرى ستضاف كحزم مستقلة لاحقًا، ولن تُخلط مع PSL.', style: TextStyle(height: 1.5)),
    ]),
  );
}

class ComingSoonScreen extends StatelessWidget {
  final String title; const ComingSoonScreen({super.key, required this.title});
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), body: Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.engineering_outlined, size: 70), const SizedBox(height: 16), Text('نعمل على $title', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 8), const Text('هذه الشاشة موجودة في بنية التطبيق وستُربط بمحرك الترجمة في المرحلة التالية.', textAlign: TextAlign.center)]))));
}

class _Feature { final String title, subtitle; final IconData icon; final Widget page; const _Feature(this.title, this.subtitle, this.icon, this.page); }
