import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:percent_indicator/percent_indicator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const SecondBrainApp());
}

// =============================================================
// BANCO DE DADOS
// =============================================================
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('second_brain_eng_comp_v9.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final dir = Directory(dbPath);
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        DELETE FROM grade_horarios
        WHERE id NOT IN (
          SELECT MIN(id)
          FROM grade_horarios
          GROUP BY dia_semana, hora
        )
      ''');
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_grade_horarios_dia_hora
        ON grade_horarios(dia_semana, hora)
      ''');
    }
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE usuario (
        matricula TEXT PRIMARY KEY,
        nome TEXT,
        periodo_ingresso TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE periodo_ativo (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        nome TEXT NOT NULL,
        inicio TEXT NOT NULL,
        fim TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE disciplinas_ativas (
        codigo TEXT PRIMARY KEY,
        status TEXT NOT NULL,
        cor_hex INTEGER NOT NULL,
        num_unidades INTEGER NOT NULL DEFAULT 3,
        meta_pontos REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE grade_horarios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo_disciplina TEXT NOT NULL,
        dia_semana INTEGER NOT NULL,
        hora TEXT NOT NULL,
        FOREIGN KEY (codigo_disciplina) REFERENCES disciplinas_ativas (codigo) ON DELETE CASCADE,
        UNIQUE (dia_semana, hora)
      )
    ''');
    await db.execute('''
      CREATE TABLE avaliacoes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo_disciplina TEXT,
        unidade INTEGER,
        tipo TEXT NOT NULL,
        nome TEXT NOT NULL,
        nota REAL,
        peso REAL DEFAULT 1.0,
        data TEXT NOT NULL,
        FOREIGN KEY (codigo_disciplina) REFERENCES disciplinas_ativas (codigo) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE faltas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo_disciplina TEXT NOT NULL,
        data TEXT NOT NULL,
        motivo TEXT NOT NULL,
        FOREIGN KEY (codigo_disciplina) REFERENCES disciplinas_ativas (codigo) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> resetDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'second_brain_eng_comp_v9.db');
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    await deleteDatabase(path);
  }
}

// =============================================================
// MATRIZ CURRICULAR OBRIGATÓRIA (P1 A P10)
// =============================================================
class Cadeira {
  final String codigo;
  final String nome;
  final int ch;
  final int periodo;
  final List<String> preReqs;

  Cadeira(this.codigo, this.nome, this.ch, this.periodo, this.preReqs);
}

final List<Cadeira> curriculoGlobal = [
  // 1º PERIODO
  Cadeira("GDSCO0025", "MATERIAIS PARA MICRO E NANO TECNOLOGIA", 60, 1, []),
  Cadeira("1103118", "CÁLCULO VETORIAL E GEOMETRIA ANALÍTICA", 60, 1, []),
  Cadeira("GDINF0107", "INTRODUÇÃO A PROGRAMAÇÃO PARA ENGENHARIA DE COMPUTAÇÃO", 60, 1, []),
  Cadeira("GDINF0101", "LABORATÓRIO DE INTRODUÇÃO A PROGRAMAÇÃO", 60, 1, []),
  Cadeira("1107248", "INTROD À ENGENHARIA DE COMPUTAÇÃO", 60, 1, []),
  Cadeira("1107201", "METODOLOGIA DO TRABALHO CIENTIFICO", 45, 1, []),
  Cadeira("1103177", "CÁLCULO DIFERENCIAL E INTEGRAL I", 60, 1, []),
  // 2º PERIODO
  Cadeira("1101171", "FÍSICA APLICADA À COMPUTAÇÃO I", 60, 2, ["1103177"]),
  Cadeira("1103178", "CÁLCULO DIFERENCIAL E INTEGRAL II", 60, 2, ["1103177", "1103118"]),
  Cadeira("GDINF0102", "LABORATORIO DE LINGUAGEM DE PROGRAMAÇÃO I", 60, 2, ["GDINF0107", "GDINF0101"]),
  Cadeira("GDINF0108", "LINGUAGEM DE PROGRAMAÇÃO I", 60, 2, ["GDINF0107", "GDINF0101"]),
  Cadeira("GDSCO0021", "CIRCUITOS LOGICOS I", 60, 2, ["1107248", "GDINF0107"]),
  Cadeira("GDSCO0023", "ELETRICIDADE E CIRCUITOS PARA COMPUTAÇÃO I", 60, 2, ["1103177", "1107248"]),
  Cadeira("GDSCO0046", "FÍSICA EXPERIMENTAL PARA COMPUTAÇÃO", 30, 2, []),
  // 3º PERIODO
  Cadeira("1103179", "INTRODUÇÃO À ÁLGEBRA LINEAR", 60, 3, ["1103118"]),
  Cadeira("1103232", "CÁLCULO DIFERENCIAL E INTEGRAL III", 60, 3, ["1103178"]),
  Cadeira("1107206", "PESQUISA APLICADA A COMPUTACAO", 45, 3, []),
  Cadeira("1108136", "CÁLCULO DAS PROBABILIDADES I", 60, 3, ["1103177"]),
  Cadeira("GDSCO0022", "CIRCUITOS LOGICOS II", 60, 3, ["GDSCO0021"]),
  Cadeira("GDSCO0024", "ELETRICIDADE E CIRCUITOS PARA COMPUTAÇÃO II", 60, 3, ["GDSCO0023", "1101171"]),
  Cadeira("GDSCO0059", "MECÂNICA PARA ENGENHARIA DA COMPUTAÇÃO", 60, 3, ["1101171"]),
  // 4º PERIODO
  Cadeira("1103180", "SÉRIES E EQUAÇÕES DIFERENCIAIS ORDINÁRIAS", 60, 4, ["1103178", "1103179"]),
  Cadeira("1107148", "LINGUAGEM DE PROGRAMAÇÃO II", 60, 4, ["GDINF0108", "GDINF0102"]),
  Cadeira("1107186", "ESTRUTURA DE DADOS", 60, 4, ["GDINF0108"]),
  Cadeira("GDSCO0026", "ELETRÔNICA APLICADA I", 60, 4, ["GDSCO0024"]),
  Cadeira("GDSCO0035", "ARQUITETURA DE COMPUTADORES", 60, 4, ["GDINF0107", "GDSCO0022"]),
  // 5º PERIODO
  Cadeira("1107180", "BANCO DE DADOS I", 60, 5, ["1107186"]),
  Cadeira("GDCOC0072", "CALCULO NUMERICO", 60, 5, ["1103180", "GDINF0107", "GDINF0101"]),
  Cadeira("GDCOC0076", "ANÁLISE E PROJETO DE ALGORITMOS", 60, 5, ["1107186"]),
  Cadeira("GDSCO0027", "ELETRONICA APLICADA II", 60, 5, ["GDSCO0026"]),
  Cadeira("GDSCO0052", "INTRODUÇÃO À MECÂNICA DOS FLUÍDOS", 30, 5, ["1103180", "GDINF0107", "GDINF0101"]),
  Cadeira("GDSCO0053", "INTRODUÇÃO À MICROELETRÔNICA", 60, 5, ["GDSCO0026", "GDSCO0022"]),
  // 6º PERIODO
  Cadeira("1107128", "ENGENHARIA DE SOFTWARE", 60, 6, []),
  Cadeira("5101003", "MICROCONTROLADORES", 60, 6, ["GDSCO0035", "GDSCO0027"]),
  Cadeira("5102007", "PESQUISA OPERACIONAL", 60, 6, ["1103179"]),
  Cadeira("GDSCO0062", "REDES DE COMPUTADORES I", 60, 6, []),
  Cadeira("GDSCO0064", "SINAIS E SISTEMAS DINÂMICOS", 60, 6, ["1103180"]),
  Cadeira("GDSCO0068", "SISTEMAS OPERACIONAIS I", 60, 6, ["1107148"]),
  // 7º PERIODO
  Cadeira("5101001", "AVALIAÇÃO DE DESEMPENHO DE SISTEMAS OPERACIONAIS", 60, 7, ["GDSCO0062"]),
  Cadeira("GDSCO0032", "REDES SEM FIO", 60, 7, ["GDSCO0062"]),
  Cadeira("GDSCO0051", "INTRODUÇÃO À COMPUTAÇÃO GRÁFICA", 60, 7, ["1103179", "1107186"]),
  Cadeira("GDSCO0055", "INTRODUÇÃO AO PROCESSAMENTO DIGITAL DE IMAGENS", 60, 7, ["1108136"]),
  Cadeira("GDSCO0065", "SISTEMAS E CONTROLE DE AUTOMAÇÃO", 60, 7, ["GDSCO0064", "GDSCO0059", "GDSCO0024"]),
  Cadeira("GDSCO0081", "SISTEMAS EMBARCADOS I", 60, 7, ["5101003"]),
  // 8º PERIODO
  Cadeira("1107191", "INTRODUCAO A INTELIGENCIA ARTIFICIAL", 60, 8, ["1107186"]),
  Cadeira("GDSCO0028", "ROBOTICA", 60, 8, ["GDSCO0065"]),
  Cadeira("GDSCO0040", "CONCEPÇÃO ESTRUTURADA DE CIRCUITOS INTEGRADOS", 60, 8, ["5101003"]),
  Cadeira("GDSCO0054", "INTRODUÇÃO À TEORIA DA INFORMAÇÃO", 60, 8, ["1103179"]),
  // 9º PERIODO
  Cadeira("1201126", "ECONOMIA I", 60, 9, []),
  Cadeira("1204172", "ADMINISTRAÇÃO PARA ENGENHARIA", 45, 9, []),
  Cadeira("GDINF0106", "COMPUTADORES E SOCIEDADE", 60, 9, []),
  Cadeira("GDSCO0029", "TRABALHO DE CONCLUSÃO DE CURSO I - ENG. DE COMPUTAÇÃO", 30, 9, []),
  // 10º PERIODO
  Cadeira("GDSCO0030", "TRABALHO DE CONCLUSÃO DE CURSO II - ENG. DE COMPUTAÇÃO", 30, 10, ["GDSCO0029"]),
  Cadeira("GDSCO0031", "ESTAGIO SUPERVISIONADO - ENGENHARIA DA COMPUTAÇÃO", 300, 10, []),
];

final List<int> paletaCoresDisciplinas = [
  0xFF00E5FF, 0xFFFFB300, 0xFF7C4DFF, 0xFF00E676,
  0xFFFF5252, 0xFFFF4081, 0xFF40C4FF, 0xFFFF9100,
  0xFFE040FB, 0xFF69F0AE, 0xFF3F51B5, 0xFFFFEB3B,
];

// =============================================================
// APP THEME
// =============================================================
class SecondBrainApp extends StatelessWidget {
  const SecondBrainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Second Brain - Engenharia da Computação',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF05050A),
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyanAccent,
          surface: Color(0xFF111119),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// =============================================================
// AUTENTICAÇÃO
// =============================================================
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with SingleTickerProviderStateMixin {
  bool _loading = true;
  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _discAtivasAuth = [];
  final _matController = TextEditingController();
  final _nomeController = TextEditingController();

  late AnimationController _colorAnimController;
  late Animation<Color?> _corDinamica;

  @override
  void initState() {
    super.initState();
    _checkAuth();

    _colorAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _corDinamica = TweenSequence<Color?>([
      TweenSequenceItem(
        weight: 1.0,
        tween: ColorTween(begin: const Color(0xFF00E5FF), end: const Color(0xFFB388FF)),
      ),
      TweenSequenceItem(
        weight: 1.0,
        tween: ColorTween(begin: const Color(0xFFB388FF), end: const Color(0xFF00E676)),
      ),
      TweenSequenceItem(
        weight: 1.0,
        tween: ColorTween(begin: const Color(0xFF00E676), end: const Color(0xFF00E5FF)),
      ),
    ]).animate(CurvedAnimation(
      parent: _colorAnimController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _colorAnimController.dispose();
    _matController.dispose();
    _nomeController.dispose();
    super.dispose();
  }

  Future<void> _checkAuth() async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.query('usuario');
    if (res.isNotEmpty) _user = res.first;
    _discAtivasAuth = await db.query('disciplinas_ativas');
    setState(() => _loading = false);
  }

  Future<void> _login() async {
    if (_matController.text.trim().isEmpty) return;
    final db = await DatabaseHelper.instance.database;

    if (_user == null) {
      if (_nomeController.text.trim().isEmpty) return;
      await db.insert('usuario', {
        'matricula': _matController.text.trim(),
        'nome': _nomeController.text.trim(),
        'periodo_ingresso': '2024.1',
      });
      await _checkAuth();
    } else {
      if (_matController.text.trim() == _user!['matricula']) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainWorkspace()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Matrícula incorreta. Acesso Negado.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return AnimatedBuilder(
      animation: _corDinamica,
      builder: (context, _) {
        final corAtual = _corDinamica.value ?? Colors.cyanAccent;

        return Scaffold(
          body: Stack(
            children: [
              // Fundo do Grafo Orbital 3D com opacidade sutil
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.35,
                    child: HexagonalGraphView(
                      discAtivas: _discAtivasAuth,
                      onRefresh: () {},
                      isBackgroundMode: true,
                    ),
                  ),
                ),
              ),

              // Modal Central com Transparência e Blur
              Center(
                child: SingleChildScrollView(
                  child: Container(
                    width: 420,
                    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    padding: const EdgeInsets.all(36),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0F1A).withOpacity(0.82),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: corAtual.withOpacity(0.40), width: 1.4),
                      boxShadow: [
                        BoxShadow(
                          color: corAtual.withOpacity(0.12),
                          blurRadius: 36,
                          spreadRadius: 4,
                        ),
                        const BoxShadow(
                          color: Colors.black54,
                          blurRadius: 24,
                          spreadRadius: 8,
                        )
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.travel_explore,
                          size: 64,
                          color: corAtual,
                          shadows: [
                            Shadow(color: corAtual.withOpacity(0.8), blurRadius: 18),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _user == null
                              ? 'REGISTRO DE DISCENTE'
                              : 'AGENDA\n-ENGENHARIA DA COMPUTAÇÃO-',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.2,
                            height: 1.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _user == null
                              ? 'Cadastre sua matrícula para vincular o sistema.'
                              : 'Autentique sua matrícula para continuar.',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
                        if (_user == null) ...[
                          TextField(
                            controller: _nomeController,
                            decoration: InputDecoration(
                              labelText: 'Nome Completo',
                              filled: true,
                              fillColor: const Color(0xFF141422).withOpacity(0.65),
                              border: const OutlineInputBorder(),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: corAtual, width: 1.8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextField(
                          controller: _matController,
                          decoration: InputDecoration(
                            labelText: 'Matrícula',
                            filled: true,
                            fillColor: const Color(0xFF141422).withOpacity(0.65),
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.fingerprint),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: corAtual, width: 1.8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: corAtual,
                            foregroundColor: Colors.black,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                            elevation: 6,
                            shadowColor: corAtual.withOpacity(0.5),
                          ),
                          onPressed: _login,
                          child: const Text(
                            'ENTRAR NO SISTEMA',
                            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================
// WORKSPACE PRINCIPAL
// =============================================================
class MainWorkspace extends StatefulWidget {
  const MainWorkspace({super.key});

  @override
  State<MainWorkspace> createState() => _MainWorkspaceState();
}

class _MainWorkspaceState extends State<MainWorkspace> with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _periodo;
  List<Map<String, dynamic>> _disciplinasAtivas = [];
  List<Map<String, dynamic>> _gradeHorarios = [];
  List<Map<String, dynamic>> _avaliacoes = [];
  List<Map<String, dynamic>> _faltas = [];
  bool _loading = true;

  late AnimationController _colorAnimController;
  late Animation<Color?> _corDinamica;

  @override
  void initState() {
    super.initState();
    _loadData();

    _colorAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _corDinamica = TweenSequence<Color?>([
      TweenSequenceItem(
        weight: 1.0,
        tween: ColorTween(begin: const Color(0xFF00E5FF), end: const Color(0xFFB388FF)),
      ),
      TweenSequenceItem(
        weight: 1.0,
        tween: ColorTween(begin: const Color(0xFFB388FF), end: const Color(0xFF00E676)),
      ),
      TweenSequenceItem(
        weight: 1.0,
        tween: ColorTween(begin: const Color(0xFF00E676), end: const Color(0xFF00E5FF)),
      ),
    ]).animate(CurvedAnimation(
      parent: _colorAnimController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _colorAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final uRes = await db.query('usuario');
      if (uRes.isNotEmpty) _user = uRes.first;

      final pRes = await db.query('periodo_ativo', where: 'id = 1');
      _periodo = pRes.isNotEmpty ? pRes.first : null;

      _disciplinasAtivas = await db.query('disciplinas_ativas');
      _gradeHorarios = await db.query('grade_horarios');
      _avaliacoes = await db.query('avaliacoes');
      _faltas = await db.query('faltas');
    } catch (e) {
      debugPrint("Erro ao carregar dados: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _abrirModalPerfil(Color corDinamica) {
    final cursadasCH = _disciplinasAtivas
        .where((d) => d['status'] == 'aprovado')
        .fold(0, (sum, d) => sum + (curriculoGlobal.firstWhere((c) => c.codigo == d['codigo'], orElse: () => Cadeira("", "", 0, 0, [])).ch));
    final totalCH = curriculoGlobal.fold(0, (a, b) => a + b.ch);
    final double progresso = totalCH > 0 ? (cursadasCH / totalCH).clamp(0.0, 1.0) : 0.0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF14141E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: corDinamica.withOpacity(0.3)),
        ),
        contentPadding: const EdgeInsets.all(24),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: corDinamica.withOpacity(0.3)),
                    ),
                    child: Image.asset(
                      'assets/brasao_ufpb.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(Icons.account_balance, color: corDinamica, size: 28),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _user?['nome']?.toUpperCase() ?? 'DISCENTE',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: corDinamica, letterSpacing: 1.1),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text('MATRÍCULA: ${_user?['matricula'] ?? 'N/A'}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 28, color: Colors.white10),
              Row(
                children: [
                  const Icon(Icons.school, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text('Ingresso: ${_user?['periodo_ingresso'] ?? 'N/A'}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.rocket_launch, size: 16, color: Colors.amberAccent),
                  const SizedBox(width: 8),
                  Text('Período Vigente: ${_periodo?['nome'] ?? 'Não Definido'}', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('CARGA HORÁRIA CUMPRIDA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.grey)),
                  Text('$cursadasCH / $totalCH h (${(progresso * 100).toStringAsFixed(1)}%)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: corDinamica)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progresso,
                  minHeight: 8,
                  backgroundColor: Colors.white10,
                  color: corDinamica,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Fechar', style: TextStyle(color: corDinamica)),
          )
        ],
      ),
    );
  }

  Future<void> _modalConfiguracoes(Color corDinamica) async {
    final nomeController = TextEditingController(text: _user?['nome'] ?? '');
    final ingressoController = TextEditingController(text: _user?['periodo_ingresso'] ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF14141E),
        title: Row(
          children: [
            Icon(Icons.settings, color: corDinamica),
            const SizedBox(width: 10),
            const Text('Configurações do Perfil', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Matrícula: ${_user?['matricula'] ?? 'N/A'}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 16),
              TextField(
                controller: nomeController,
                decoration: const InputDecoration(labelText: 'Nome Completo', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ingressoController,
                decoration: const InputDecoration(labelText: 'Período de Ingresso (Ex: 2024.1)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 24),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),
              const Text('ÁREA DE RISCO', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  minimumSize: const Size(double.infinity, 42),
                ),
                icon: const Icon(Icons.power_settings_new, size: 18),
                label: const Text('Trancar Matrícula (Reset Total)'),
                onPressed: () async {
                  final conf = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      backgroundColor: const Color(0xFF161622),
                      title: const Text('⚠️ CONFIRMAR RESET TOTAL', style: TextStyle(color: Colors.redAccent)),
                      content: const Text('Isso apagará permanentemente todos os registros, nós do grafo, notas e faltas cadastradas. Deseja prosseguir?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Confirmar Trancamento'),
                        )
                      ],
                    ),
                  );

                  if (conf == true) {
                    Navigator.pop(ctx);
                    await DatabaseHelper.instance.resetDatabase();
                    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AuthGate()));
                  }
                },
              )
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: corDinamica, foregroundColor: Colors.black),
            onPressed: () async {
              final db = await DatabaseHelper.instance.database;
              await db.update(
                'usuario',
                {
                  'nome': nomeController.text.trim(),
                  'periodo_ingresso': ingressoController.text.trim(),
                },
                where: 'matricula = ?',
                whereArgs: [_user?['matricula']],
              );
              await _loadData();
              Navigator.pop(ctx);
            },
            child: const Text('Salvar Alterações', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return AnimatedBuilder(
      animation: _corDinamica,
      builder: (context, _) {
        final corAtual = _corDinamica.value ?? Colors.cyanAccent;

        return Scaffold(
          body: Row(
            children: [
              Container(
                width: 80,
                color: const Color(0xFF0B0B10),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Tooltip(
                      message: 'Perfil Discente UFPB',
                      child: InkWell(
                        onTap: () => _abrirModalPerfil(corAtual),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 48,
                          height: 48,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: corAtual.withOpacity(0.4)),
                          ),
                          child: Image.asset(
                            'assets/brasao_ufpb.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(Icons.account_balance, color: corAtual, size: 28),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    _buildNavBtn(Icons.auto_awesome, 0, 'Grafo Orbital 3D', corAtual),
                    _buildNavBtn(Icons.dashboard_customize, 1, 'Período Letivo', corAtual),
                    _buildNavBtn(Icons.calendar_month, 2, 'Radar Acadêmico', corAtual),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Configurações do Perfil',
                      icon: const Icon(Icons.settings_outlined, color: Colors.grey, size: 26),
                      onPressed: () => _modalConfiguracoes(corAtual),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    if (_currentIndex != 0)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: 0.22,
                            child: HexagonalGraphView(
                              discAtivas: _disciplinasAtivas,
                              onRefresh: () {},
                              isBackgroundMode: true,
                            ),
                          ),
                        ),
                      ),
                    IndexedStack(
                      index: _currentIndex,
                      children: [
                        HexagonalGraphView(discAtivas: _disciplinasAtivas, onRefresh: _loadData),
                        PeriodoLetivoView(
                          periodo: _periodo,
                          discAtivas: _disciplinasAtivas,
                          gradeHorarios: _gradeHorarios,
                          avaliacoes: _avaliacoes,
                          faltas: _faltas,
                          onRefresh: _loadData,
                          corDinamica: corAtual,
                        ),
                        PanoramicCalendarView(
                          periodo: _periodo,
                          avaliacoes: _avaliacoes,
                          discAtivas: _disciplinasAtivas,
                          onRefresh: _loadData,
                          corDinamica: corAtual,
                        ),
                      ],
                    ),
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavBtn(IconData icon, int index, String tooltip, Color corDinamica) {
    final isSel = _currentIndex == index;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(
        icon,
        color: isSel ? corDinamica : Colors.grey.withOpacity(0.4),
        size: 28,
        shadows: isSel ? [Shadow(color: corDinamica.withOpacity(0.6), blurRadius: 10)] : null,
      ),
      onPressed: () => setState(() => _currentIndex = index),
    );
  }
}

// =============================================================
// TAB 1: GRAFO ORBITAL 3D
// =============================================================
class HexagonalGraphView extends StatefulWidget {
  final List<Map<String, dynamic>> discAtivas;
  final VoidCallback onRefresh;
  final bool isBackgroundMode;

  const HexagonalGraphView({
    super.key,
    required this.discAtivas,
    required this.onRefresh,
    this.isBackgroundMode = false,
  });

  @override
  State<HexagonalGraphView> createState() => _HexagonalGraphViewState();
}

class _OrbitalNodeData {
  final Cadeira cadeira;
  final double radius;
  final double baseAngle;
  final double yOffset;
  final double speed;
  final double ringTiltX;
  final double ringTiltZ;

  _OrbitalNodeData({
    required this.cadeira,
    required this.radius,
    required this.baseAngle,
    required this.yOffset,
    required this.speed,
    required this.ringTiltX,
    required this.ringTiltZ,
  });
}

class _ProjectedNode {
  final _OrbitalNodeData node;
  final Offset screenPos;
  final double zDepth;
  final double renderRadius;
  final Color color;
  final String status;
  final bool isHovered;

  _ProjectedNode({
    required this.node,
    required this.screenPos,
    required this.zDepth,
    required this.renderRadius,
    required this.color,
    required this.status,
    this.isHovered = false,
  });
}

class _Star3D {
  final double x, y, z;
  _Star3D(this.x, this.y, this.z);
}

class _OrbitalRenderState {
  double time = 0.0;
  double theta = 0.6;
  double phi = 1.15;
  double zoom = 620.0;
}

class _HexagonalGraphViewState extends State<HexagonalGraphView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  final Stopwatch _clock = Stopwatch();
  final _OrbitalRenderState _renderState = _OrbitalRenderState();

  // Posição inicial oficial do grafo — igual ao enquadramento bonito de abertura.
  static const double _initialTheta = 0.6;
  static const double _initialPhi = 1.15;
  static const double _initialZoom = 620.0;

  double _targetTheta = _initialTheta;
  double _targetPhi = _initialPhi;
  double _targetZoom = _initialZoom;
  int _idleFrames = 0;

  // Controle de clique simples x duplo.
  // O clique simples é ligeiramente adiado para que um segundo clique
  // possa ser reconhecido sem alterar o estado de uma cadeira.
  Timer? _singleTapTimer;
  DateTime? _lastTapTime;
  Offset? _lastTapPosition;
  static const Duration _doubleTapWindow = Duration(milliseconds: 280);
  static const double _doubleTapDistance = 24.0;

  Offset? _hoverPos;
  _ProjectedNode? _hoveredNode;
  List<_ProjectedNode> _lastProjectedNodes = const [];

  final List<_OrbitalNodeData> _orbitalNodes = [];
  final List<_Star3D> _stars = [];
  final Map<String, String> _statusCache = <String, String>{};

  static const double ringBaseRadius = 55.0;
  static const double ringSpacing = 42.0;

  @override
  void initState() {
    super.initState();
    _initOrbitalSystem();
    _initStarfield();
    _rebuildStatusCache();

    _clock.start();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(days: 999),
    )..addListener(_onTick);

    _ticker.forward();
  }

  @override
  void didUpdateWidget(covariant HexagonalGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameDiscData(oldWidget.discAtivas, widget.discAtivas)) {
      _rebuildStatusCache();
    }
  }

  bool _sameDiscData(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;

    final Map<String, String> aMap = <String, String>{
      for (final d in a)
        '${d['codigo']}': '${d['status']}',
    };
    for (final d in b) {
      final code = '${d['codigo']}';
      if (aMap[code] != '${d['status']}') return false;
    }
    return true;
  }

  void _rebuildStatusCache() {
    final approved = <String>{};
    final cursando = <String>{};

    for (final d in widget.discAtivas) {
      final codigo = d['codigo']?.toString();
      final status = d['status']?.toString();
      if (codigo == null) continue;

      if (status == 'aprovado') {
        approved.add(codigo);
      } else if (status == 'cursando') {
        cursando.add(codigo);
      }
    }

    _statusCache.clear();

    for (final c in curriculoGlobal) {
      if (cursando.contains(c.codigo)) {
        _statusCache[c.codigo] = 'cursando';
      } else if (approved.contains(c.codigo)) {
        _statusCache[c.codigo] = 'aprovado';
      } else {
        final available = c.preReqs.every(approved.contains);
        _statusCache[c.codigo] = available ? 'disponivel' : 'bloqueado';
      }
    }
  }

  void _initStarfield() {
    final rand = math.Random(42);
    // O HTML original usa 900 estrelas; no Flutter mantemos uma densidade
    // visual muito boa com metade disso, reduzindo trabalho da CPU por frame.
    for (int i = 0; i < 450; i++) {
      _stars.add(_Star3D(
        (rand.nextDouble() - 0.5) * 2600,
        (rand.nextDouble() - 0.5) * 2600,
        (rand.nextDouble() - 0.5) * 2600,
      ));
    }
  }

  void _initOrbitalSystem() {
    final Map<int, List<Cadeira>> byPeriodo = {};
    for (final c in curriculoGlobal) {
      byPeriodo.putIfAbsent(c.periodo, () => []).add(c);
    }

    final periodos = byPeriodo.keys.toList()..sort();
    final rand = math.Random(1337);

    for (int idx = 0; idx < periodos.length; idx++) {
      final pNum = periodos[idx];
      final cadeiras = byPeriodo[pNum]!;
      final double r = ringBaseRadius + idx * ringSpacing;

      // Mantém a mesma velocidade angular do protótipo HTML.
      final double speed =
          (0.09 / math.sqrt(idx + 1)) *
          (idx.isEven ? 1 : -1) *
          0.35;

      final double tiltX = (rand.nextDouble() - 0.5) * 0.18;
      final double tiltZ = (rand.nextDouble() - 0.5) * 0.10;
      final double angleOffset = rand.nextDouble() * math.pi * 2;

      for (int i = 0; i < cadeiras.length; i++) {
        final double angle =
            angleOffset +
            (i / cadeiras.length) * math.pi * 2 +
            (rand.nextDouble() - 0.5) * 0.12;

        final double jitterR =
            r + (rand.nextDouble() - 0.5) * (ringSpacing * 0.28);

        final double y = (rand.nextDouble() - 0.5) * 6.0;

        _orbitalNodes.add(
          _OrbitalNodeData(
            cadeira: cadeiras[i],
            radius: jitterR,
            baseAngle: angle,
            yOffset: y,
            speed: speed,
            ringTiltX: tiltX,
            ringTiltZ: tiltZ,
          ),
        );
      }
    }
  }

  void _onTick() {
    final elapsedSeconds = _clock.elapsedMicroseconds / Duration.microsecondsPerSecond;
    final dt = (_ticker.lastElapsedDuration?.inMicroseconds ?? 0) /
        Duration.microsecondsPerSecond;

    _renderState.time = elapsedSeconds;
    _idleFrames++;

    if (_idleFrames > 90) {
      // Mais suave que o protótipo original: reduz a sensação de câmera
      // "nervosa" quando o usuário fica parado.
      _targetTheta += 0.00035;
    }

    // Interpolação baseada em tempo: não depende do FPS.
    final double smooth = 1.0 - math.exp(-(dt.clamp(0.0, 0.05)) * 9.5);

    _renderState.theta += (_targetTheta - _renderState.theta) * smooth;
    _renderState.phi += (_targetPhi - _renderState.phi) * smooth;
    _renderState.zoom += (_targetZoom - _renderState.zoom) * smooth;
    _renderState.phi =
        _renderState.phi.clamp(0.25, math.pi - 0.25);

    // Não chama setState(): o CustomPainter repinta diretamente pelo
    // Listenable (_ticker), evitando reconstruir toda a árvore Flutter.
    //
    // Mantemos esta variável para documentação/debug e para impedir que
    // analíticos eliminem o valor em builds agressivos.
    if (elapsedSeconds.isNaN) {
      _renderState.time = 0.0;
    }
  }

  @override
  void dispose() {
    _singleTapTimer?.cancel();
    _clock.stop();
    _ticker.dispose();
    super.dispose();
  }

  bool isAprovado(String cod) => _statusCache[cod] == 'aprovado';

  bool isCursando(String cod) => _statusCache[cod] == 'cursando';

  bool isDisponivel(Cadeira c) => _statusCache[c.codigo] == 'disponivel';

  String _getNodeStatus(Cadeira c) =>
      _statusCache[c.codigo] ?? 'bloqueado';

  Color _getNodeColor(String status) {
    switch (status) {
      case 'aprovado':
        return const Color(0xFF00E5FF);
      case 'cursando':
        return const Color(0xFFB388FF);
      case 'disponivel':
        return const Color(0xFFFFB300);
      case 'bloqueado':
      default:
        return const Color(0xFFFF5252);
    }
  }

  Future<void> _alternarStatusDisciplina(String codigo) async {
    if (widget.isBackgroundMode) return;
    final db = await DatabaseHelper.instance.database;

    if (isCursando(codigo)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Disciplina em curso — gerencie o status em "Período Letivo".',
          ),
        ),
      );
      return;
    }

    if (isAprovado(codigo)) {
      await db.delete(
        'disciplinas_ativas',
        where: 'codigo = ?',
        whereArgs: [codigo],
      );
      widget.onRefresh();
      return;
    }

    final cadeira = curriculoGlobal.firstWhere(
      (c) => c.codigo == codigo,
      orElse: () => Cadeira('', '', 0, 0, const []),
    );

    if (cadeira.codigo.isEmpty || !isDisponivel(cadeira)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Disciplina bloqueada: conclua todos os pré-requisitos antes de marcá-la como aprovada.',
          ),
        ),
      );
      return;
    }

    await db.insert('disciplinas_ativas', {
      'codigo': codigo,
      'status': 'aprovado',
      'cor_hex': 0xFF00E5FF,
      'num_unidades': 3,
      'meta_pontos': 21.0,
    });
    widget.onRefresh();
  }

  void _cancelPendingTap() {
    _singleTapTimer?.cancel();
    _singleTapTimer = null;
    _lastTapTime = null;
    _lastTapPosition = null;
  }

  void _resetViewToInitialPosition() {
    _cancelPendingTap();
    _idleFrames = 0;

    // Apenas a câmera é resetada. Nenhum dado da matriz e nenhum estado
    // de cadeira é alterado. O retorno é suave para preservar a fluidez.
    _targetTheta = _initialTheta;
    _targetPhi = _initialPhi;
    _targetZoom = _initialZoom;
  }

  void _processSingleTap(Offset clickPos) {
    if (widget.isBackgroundMode || !mounted) return;

    _ProjectedNode? closest;
    double minDist = 22.0;

    for (final pNode in _lastProjectedNodes) {
      final dist = (pNode.screenPos - clickPos).distance;
      if (dist < minDist) {
        minDist = dist;
        closest = pNode;
      }
    }

    if (closest != null) {
      _alternarStatusDisciplina(closest.node.cadeira.codigo);
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.isBackgroundMode) return;

    final now = DateTime.now();
    final pos = details.localPosition;
    final previousTime = _lastTapTime;
    final previousPos = _lastTapPosition;

    final isDoubleTap =
        previousTime != null &&
        previousPos != null &&
        now.difference(previousTime) <= _doubleTapWindow &&
        (pos - previousPos).distance <= _doubleTapDistance;

    if (isDoubleTap) {
      // O segundo clique cancela o clique simples pendente e faz SOMENTE
      // o reset da câmera. Nenhuma cadeira é aprovada/desaprovada.
      _resetViewToInitialPosition();
      return;
    }

    _singleTapTimer?.cancel();
    _lastTapTime = now;
    _lastTapPosition = pos;

    _singleTapTimer = Timer(_doubleTapWindow, () {
      final tapPos = _lastTapPosition;
      _singleTapTimer = null;
      _lastTapTime = null;
      _lastTapPosition = null;
      if (tapPos != null) _processSingleTap(tapPos);
    });
  }

  void _onPointerHover(PointerEvent event) {
    if (widget.isBackgroundMode) return;

    _idleFrames = 0;
    _hoverPos = event.localPosition;

    _ProjectedNode? closest;
    double minDist = 18.0;

    for (final pNode in _lastProjectedNodes) {
      final dist = (pNode.screenPos - _hoverPos!).distance;
      if (dist < minDist) {
        minDist = dist;
        closest = pNode;
      }
    }

    if (closest?.node.cadeira.codigo ==
        _hoveredNode?.node.cadeira.codigo) {
      return;
    }

    setState(() {
      _hoveredNode = closest;
    });
  }

  @override
  Widget build(BuildContext context) {
    final int total = curriculoGlobal.length;
    final int apr = curriculoGlobal.where((c) => isAprovado(c.codigo)).length;
    final int cur = curriculoGlobal.where((c) => isCursando(c.codigo)).length;
    final int disp = curriculoGlobal.where((c) => isDisponivel(c)).length;

    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerSignal: (pointerSignal) {
              if (pointerSignal is PointerScrollEvent && !widget.isBackgroundMode) {
                _cancelPendingTap();
                _idleFrames = 0;
                setState(() {
                  _targetZoom = (_targetZoom + pointerSignal.scrollDelta.dy * 0.75).clamp(160.0, 1600.0);
                });
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleUpdate: (details) {
                if (widget.isBackgroundMode) return;
                _cancelPendingTap();
                _idleFrames = 0;
                if (details.scale != 1.0) {
                  _targetZoom = (_targetZoom / details.scale).clamp(160.0, 1600.0);
                } else {
                  _targetTheta -= details.focalPointDelta.dx * 0.005;
                  _targetPhi -= details.focalPointDelta.dy * 0.005;
                }
              },
              onTapUp: _onTapUp,
              child: MouseRegion(
                onHover: _onPointerHover,
                onExit: (_) => setState(() => _hoveredNode = null),
                child: CustomPaint(
                  painter: _Orbital3DPainter(
                    repaint: _ticker,
                    renderState: _renderState,
                    nodes: _orbitalNodes,
                    stars: _stars,
                    hoveredNodeCode: _hoveredNode?.node.cadeira.codigo,
                    getStatus: _getNodeStatus,
                    getColor: _getNodeColor,
                    onProjected: (projected) => _lastProjectedNodes = projected,
                  ),
                ),
              ),
            ),
          ),
        ),

        if (!widget.isBackgroundMode) ...[
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xE605050A), Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFF00E5FF),
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Color(0xFF00E5FF), blurRadius: 8)],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'GRAFO CI · SECOND BRAIN',
                              style: TextStyle(
                                color: Color(0xFFE8FAFF),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'SISTEMA ORBITAL POR PERÍODO — PROTÓTIPO 3D',
                          style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1),
                        ),
                      ],
                    ),
                    const Text(
                      'arraste = girar · scroll = zoom · clique = aprovar/desaprovar',
                      style: TextStyle(color: Colors.white38, fontSize: 10.5, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 18,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F18).withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLegendItem('Aprovado', const Color(0xFF00E5FF)),
                  const SizedBox(height: 7),
                  _buildLegendItem('Cursando', const Color(0xFFB388FF)),
                  const SizedBox(height: 7),
                  _buildLegendItem('Disponível', const Color(0xFFFFB300)),
                  const SizedBox(height: 7),
                  _buildLegendItem('Bloqueado', const Color(0xFFFF5252)),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: 18,
            right: 20,
            child: Container(
              width: 170,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F18).withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 10.5, color: Colors.white70),
                      children: [
                        TextSpan(
                          text: '$total ',
                          style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(text: 'disciplinas'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildStatRow('Aprovadas', '$apr'),
                  const SizedBox(height: 4),
                  _buildStatRow('Cursando', '$cur'),
                  const SizedBox(height: 4),
                  _buildStatRow('Disponíveis', '$disp'),
                ],
              ),
            ),
          ),

          if (_hoveredNode != null && _hoverPos != null)
            Positioned(
              left: (_hoverPos!.dx - 120).clamp(10.0, MediaQuery.of(context).size.width - 250),
              top: (_hoverPos!.dy - 120).clamp(10.0, MediaQuery.of(context).size.height - 130),
              child: IgnorePointer(
                child: Container(
                  width: 230,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xE00A0A10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                    boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 24)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _hoveredNode!.node.cadeira.codigo,
                        style: const TextStyle(color: Colors.white38, fontSize: 9.5, letterSpacing: 1),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _hoveredNode!.node.cadeira.nome,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5, height: 1.25),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text('${_hoveredNode!.node.cadeira.ch}h', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                          const SizedBox(width: 10),
                          Text('${_hoveredNode!.node.cadeira.periodo}º período', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _hoveredNode!.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: _hoveredNode!.color.withOpacity(0.4)),
                        ),
                        child: Text(
                          _hoveredNode!.status.toUpperCase(),
                          style: TextStyle(color: _hoveredNode!.color, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color, blurRadius: 6)],
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.white70, letterSpacing: 0.3)),
      ],
    );
  }

  Widget _buildStatRow(String title, String val) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 10, color: Colors.white54)),
        Text(val, style: const TextStyle(fontSize: 10, color: Colors.white)),
      ],
    );
  }
}

// =============================================================
// MOTOR 3D CUSTOM PAINTER
// =============================================================
//
// Esta versão mantém o visual do protótipo, mas foi otimizada para Flutter:
// - repaint via AnimationController, sem setState por frame;
// - status pré-calculado no State;
// - projeção matemática sem criação de List<double> por ponto;
// - menos segmentos nos anéis;
// - glow feito com círculos concêntricos, sem criar RadialGradient por nó/frame;
// - tempo orbital real, independente de FPS;
// - câmera com suavização baseada em dt.
//
class _Orbital3DPainter extends CustomPainter {
  final _OrbitalRenderState renderState;
  final List<_OrbitalNodeData> nodes;
  final List<_Star3D> stars;
  final String? hoveredNodeCode;
  final String Function(Cadeira) getStatus;
  final Color Function(String) getColor;
  final void Function(List<_ProjectedNode>) onProjected;

  _Orbital3DPainter({
    required Listenable repaint,
    required this.renderState,
    required this.nodes,
    required this.stars,
    required this.hoveredNodeCode,
    required this.getStatus,
    required this.getColor,
    required this.onProjected,
  }) : super(repaint: repaint);

  static const double _worldTilt = -0.55;
  static const double _fov = 750.0;
  static const int _ringSegments = 64;

  static final List<double> _unitCos = List<double>.generate(
    _ringSegments + 1,
    (i) => math.cos((i / _ringSegments) * math.pi * 2),
  );

  static final List<double> _unitSin = List<double>.generate(
    _ringSegments + 1,
    (i) => math.sin((i / _ringSegments) * math.pi * 2),
  );

  final Paint _starPaint = Paint()
    ..color = Colors.white.withOpacity(0.35);

  final Paint _ringPaint = Paint()
    ..color = const Color(0xFF6FA8C9).withOpacity(0.075)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.70;

  final Paint _whitePaint = Paint()..color = Colors.white;

  final Map<int, Paint> _corePaints = <int, Paint>{};

  Paint _paintForColor(Color color) {
    final key = color.value;
    return _corePaints.putIfAbsent(
      key,
      () => Paint()..color = color,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;

    final zoom = renderState.zoom;
    final theta = renderState.theta;
    final phi = renderState.phi;
    final time = renderState.time;

    final sinPhi = math.sin(phi);
    final cosPhi = math.cos(phi);
    final sinTheta = math.sin(theta);
    final cosTheta = math.cos(theta);

    final camX = zoom * sinPhi * cosTheta;
    final camY = zoom * cosPhi;
    final camZ = zoom * sinPhi * sinTheta;

    // Vetores da câmera apontando para a origem.
    final invCam = zoom == 0 ? 0.0 : 1.0 / zoom;
    final fx = -camX * invCam;
    final fy = -camY * invCam;
    final fz = -camZ * invCam;

    // right = normalize(forward x Y)
    double rx = fz;
    double ry = 0.0;
    double rz = -fx;

    final rightLen = math.sqrt(rx * rx + ry * ry + rz * rz);
    if (rightLen > 1e-9) {
      rx /= rightLen;
      rz /= rightLen;
    }

    // up = right x forward
    final ux = ry * fz - rz * fy;
    final uy = rz * fx - rx * fz;
    final uz = rx * fy - ry * fx;

    // -------------------------------------------------------------
    // ESTRELAS
    // -------------------------------------------------------------
    for (final s in stars) {
      final p = _projectPoint(
        s.x, s.y, s.z,
        camX, camY, camZ,
        fx, fy, fz,
        rx, ry, rz,
        ux, uy, uz,
        cx, cy,
      );

      if (p != null) {
        canvas.drawCircle(p, 1.0, _starPaint);
      }
    }

    // -------------------------------------------------------------
    // ANÉIS
    // -------------------------------------------------------------
    // IMPORTANTE: no HTML cada anel é um THREE.Group independente.
    // O grupo recebe rotation.x / rotation.z e tanto a linha da órbita
    // quanto os planetas são filhos desse mesmo grupo.
    // Portanto, no Flutter a linha do anel precisa passar exatamente
    // pelas mesmas transformações usadas pelos planetas.
    for (int pNum = 1; pNum <= 10; pNum++) {
      final r = 55.0 + (pNum - 1) * 42.0;
      final path = Path();

      _OrbitalNodeData? ringReference;
      for (final node in nodes) {
        if (node.cadeira.periodo == pNum) {
          ringReference = node;
          break;
        }
      }

      final ringTiltX = ringReference?.ringTiltX ?? 0.0;
      final ringTiltZ = ringReference?.ringTiltZ ?? 0.0;
      final sinX = math.sin(ringTiltX);
      final cosX = math.cos(ringTiltX);
      final sinZ = math.sin(ringTiltZ);
      final cosZ = math.cos(ringTiltZ);
      final sinWorld = math.sin(_worldTilt);
      final cosWorld = math.cos(_worldTilt);

      for (int i = 0; i <= _ringSegments; i++) {
        final lx = _unitCos[i] * r;
        final ly = 0.0;
        final lz = _unitSin[i] * r;

        // THREE.js Euler padrão XYZ: X -> Y -> Z.
        // Como Y = 0, aplicamos X primeiro e depois Z.
        final x1 = lx;
        final y1 = ly * cosX - lz * sinX;
        final z1 = ly * sinX + lz * cosX;

        final x2 = x1 * cosZ - y1 * sinZ;
        final y2 = x1 * sinZ + y1 * cosZ;
        final z2 = z1;

        // worldGroup.rotation.x = -0.55 no HTML.
        final wx = x2;
        final wy = y2 * cosWorld - z2 * sinWorld;
        final wz = y2 * sinWorld + z2 * cosWorld;

        final point = _projectPoint(
          wx, wy, wz,
          camX, camY, camZ,
          fx, fy, fz,
          rx, ry, rz,
          ux, uy, uz,
          cx, cy,
        );

        if (point != null) {
          if (i == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
      }

      canvas.drawPath(path, _ringPaint);
    }

    // -------------------------------------------------------------
    // SOL CENTRAL
    // -------------------------------------------------------------
    final sunCenter = _projectPoint(
      0, 0, 0,
      camX, camY, camZ,
      fx, fy, fz,
      rx, ry, rz,
      ux, uy, uz,
      cx, cy,
    );

    if (sunCenter != null) {
      final sunPulse = 1.0 + math.sin(time * 1.5) * 0.045;
      final glowPulse = 1.0 + math.sin(time * 1.5) * 0.055;

      final scale = (600.0 / zoom).clamp(0.65, 1.5);
      final rSun = (6.0 * scale * sunPulse).clamp(2.0, 10.0);
      final rGlow = (30.0 * scale * glowPulse).clamp(8.0, 42.0);

      // Glow barato: círculos concêntricos.
      final glow1 = Paint()..color = Colors.white.withOpacity(0.06);
      final glow2 = Paint()..color = Colors.white.withOpacity(0.12);
      final glow3 = Paint()..color = Colors.white.withOpacity(0.26);

      canvas.drawCircle(sunCenter, rGlow, glow1);
      canvas.drawCircle(sunCenter, rGlow * 0.58, glow2);
      canvas.drawCircle(sunCenter, rGlow * 0.28, glow3);
      canvas.drawCircle(sunCenter, rSun, _whitePaint);
    }

    // -------------------------------------------------------------
    // PLANETAS
    // -------------------------------------------------------------
    final projectedList = <_ProjectedNode>[];

    for (final node in nodes) {
      final curAngle = node.baseAngle + node.speed * time * 0.6;
      final sinA = math.sin(curAngle);
      final cosA = math.cos(curAngle);

      final lx = cosA * node.radius;
      final lz = sinA * node.radius;
      final ly = node.yOffset;

      final sinX = math.sin(node.ringTiltX);
      final cosX = math.cos(node.ringTiltX);
      final sinZ = math.sin(node.ringTiltZ);
      final cosZ = math.cos(node.ringTiltZ);

      // Mesma ordem de rotação do THREE.Group do HTML (Euler XYZ):
      // primeiro X, depois Z.
      final x1 = lx;
      final y1 = ly * cosX - lz * sinX;
      final z1 = ly * sinX + lz * cosX;

      final x2 = x1 * cosZ - y1 * sinZ;
      final y2 = x1 * sinZ + y1 * cosZ;
      final z2 = z1;

      // worldGroup.rotation.x = -0.55.
      final sinWorld = math.sin(_worldTilt);
      final cosWorld = math.cos(_worldTilt);
      final wx = x2;
      final wy = y2 * cosWorld - z2 * sinWorld;
      final wz = y2 * sinWorld + z2 * cosWorld;

      final projected = _projectWithDepth(
        wx, wy, wz,
        camX, camY, camZ,
        fx, fy, fz,
        rx, ry, rz,
        ux, uy, uz,
        cx, cy,
      );

      if (projected == null) continue;

      final distDx = wx - camX;
      final distDy = wy - camY;
      final distDz = wz - camZ;
      final dist = math.sqrt(
        distDx * distDx +
        distDy * distDy +
        distDz * distDz,
      );

      final status = getStatus(node.cadeira);
      final color = getColor(status);
      final hovered =
          hoveredNodeCode == node.cadeira.codigo;

      final baseR = status == 'bloqueado' ? 2.1 : 3.1;
      final renderR =
          (baseR * (600.0 / dist)).clamp(1.2, 8.0) *
          (hovered ? 1.6 : 1.0);

      projectedList.add(
        _ProjectedNode(
          node: node,
          screenPos: projected.offset,
          zDepth: projected.depth,
          renderRadius: renderR,
          color: color,
          status: status,
          isHovered: hovered,
        ),
      );
    }

    // Mantém ordenação visual por profundidade, mas só sobre os nós.
    projectedList.sort(
      (a, b) => b.zDepth.compareTo(a.zDepth),
    );

    // -------------------------------------------------------------
    // GLOW DOS PLANETAS
    // -------------------------------------------------------------
    for (final pNode in projectedList) {
      final isDim = pNode.status == 'bloqueado';
      final r = pNode.renderRadius;

      // 3 círculos em vez de compilar um RadialGradient novo a cada nó.
      final outerOpacity = isDim ? 0.06 : 0.09;
      final midOpacity = isDim ? 0.12 : 0.18;
      final innerOpacity = isDim ? 0.20 : 0.34;

      canvas.drawCircle(
        pNode.screenPos,
        r * (isDim ? 3.6 : 4.8),
        Paint()..color = pNode.color.withOpacity(outerOpacity),
      );

      canvas.drawCircle(
        pNode.screenPos,
        r * (isDim ? 2.3 : 3.0),
        Paint()..color = pNode.color.withOpacity(midOpacity),
      );

      canvas.drawCircle(
        pNode.screenPos,
        r * (isDim ? 1.45 : 1.65),
        Paint()..color = pNode.color.withOpacity(innerOpacity),
      );

      canvas.drawCircle(
        pNode.screenPos,
        r,
        _paintForColor(pNode.color),
      );
    }

    onProjected(projectedList);
  }

  _ProjectionResult? _projectWithDepth(
    double x,
    double y,
    double z,
    double camX,
    double camY,
    double camZ,
    double fx,
    double fy,
    double fz,
    double rx,
    double ry,
    double rz,
    double ux,
    double uy,
    double uz,
    double cx,
    double cy,
  ) {
    final vx = x - camX;
    final vy = y - camY;
    final vz = z - camZ;

    final depth = vx * fx + vy * fy + vz * fz;
    if (depth <= 1.0) return null;

    return _ProjectionResult(
      Offset(
        cx + ((vx * rx + vy * ry + vz * rz) * _fov) / depth,
        cy - ((vx * ux + vy * uy + vz * uz) * _fov) / depth,
      ),
      depth,
    );
  }

  Offset? _projectPoint(
    double x,
    double y,
    double z,
    double camX,
    double camY,
    double camZ,
    double fx,
    double fy,
    double fz,
    double rx,
    double ry,
    double rz,
    double ux,
    double uy,
    double uz,
    double cx,
    double cy,
  ) {
    final vx = x - camX;
    final vy = y - camY;
    final vz = z - camZ;

    final depth = vx * fx + vy * fy + vz * fz;
    if (depth <= 1.0) return null;

    return Offset(
      cx + ((vx * rx + vy * ry + vz * rz) * _fov) / depth,
      cy - ((vx * ux + vy * uy + vz * uz) * _fov) / depth,
    );
  }

  @override
  bool shouldRepaint(covariant _Orbital3DPainter old) {
    // O repaint é controlado diretamente pelo Listenable do painter.
    return old.nodes != nodes ||
        old.stars != stars ||
        old.hoveredNodeCode != hoveredNodeCode ||
        old.renderState != renderState;
  }
}

class _ProjectionResult {
  final Offset offset;
  final double depth;

  const _ProjectionResult(this.offset, this.depth);
}

// TAB 2: PERÍODO LETIVO & DASHBOARD COMPLETO
// =============================================================
class PeriodoLetivoView extends StatelessWidget {
  final Map<String, dynamic>? periodo;
  final List<Map<String, dynamic>> discAtivas;
  final List<Map<String, dynamic>> gradeHorarios;
  final List<Map<String, dynamic>> avaliacoes;
  final List<Map<String, dynamic>> faltas;
  final VoidCallback onRefresh;
  final Color corDinamica;

  const PeriodoLetivoView({
    super.key,
    required this.periodo,
    required this.discAtivas,
    required this.gradeHorarios,
    required this.avaliacoes,
    required this.faltas,
    required this.onRefresh,
    required this.corDinamica,
  });

  @override
  Widget build(BuildContext context) {
    if (periodo == null) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: () => _iniciarPeriodo(context),
          icon: const Icon(Icons.rocket_launch),
          label: const Text('Iniciar Período Acadêmico'),
        ),
      );
    }

    final ini = DateTime.parse(periodo!['inicio']);
    final fim = DateTime.parse(periodo!['fim']);
    final hoje = DateTime.now();
    final diasTotal = fim.difference(ini).inDays;
    final diasRest = fim.difference(hoje).inDays.clamp(0, diasTotal);

    final cursando = discAtivas.where((d) => d['status'] == 'cursando').toList();
    final avisos = avaliacoes.where((a) => a['tipo'] == 'Aviso').toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PERÍODO VIGENTE: ${periodo!['nome']}',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: corDinamica),
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Editar Datas'),
                    onPressed: () => _editarPeriodo(context, periodo!['nome'], ini, fim),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Adicionar Disciplina na Grade'),
                    onPressed: () => _modalAdicionarNaGrade(context),
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 20),

          LayoutBuilder(builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - (3 * 16)) / 4;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildStatBlock(
                  width: cardWidth,
                  icon: Icons.play_arrow_rounded,
                  iconBg: const Color(0xFF1E3A8A).withOpacity(0.5),
                  iconColor: const Color(0xFF3B82F6),
                  title: 'Início do Período',
                  value: '${ini.day}/${ini.month}/${ini.year}',
                ),
                _buildStatBlock(
                  width: cardWidth,
                  icon: Icons.flag_rounded,
                  iconBg: const Color(0xFF581C87).withOpacity(0.5),
                  iconColor: const Color(0xFFA855F7),
                  title: 'Término do Período',
                  value: '${fim.day}/${fim.month}/${fim.year}',
                ),
                _buildStatBlock(
                  width: cardWidth,
                  icon: Icons.grid_view_rounded,
                  iconBg: const Color(0xFF78350F).withOpacity(0.5),
                  iconColor: const Color(0xFFF59E0B),
                  title: 'Duração Total',
                  value: '$diasTotal dias',
                ),
                _buildStatBlock(
                  width: cardWidth,
                  icon: Icons.hourglass_top_rounded,
                  iconBg: const Color(0xFF064E3B).withOpacity(0.5),
                  iconColor: const Color(0xFF10B981),
                  title: 'Dias Restantes',
                  value: '$diasRest dias',
                ),
              ],
            );
          }),

          const SizedBox(height: 28),
          const Text('🗓️ CRONOGRAMA SEMANAL DE HORÁRIOS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
          const SizedBox(height: 12),
          _buildGradeSemanalTable(),

          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orangeAccent.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('📌 MURAL DE AVISOS (Feriados, Suspensões, Recessos)', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 14, color: Colors.orangeAccent),
                      label: const Text('Novo Aviso', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                      onPressed: () => _modalNovoAviso(context, ini, fim),
                    )
                  ],
                ),
                if (avisos.isEmpty)
                  const Text('Nenhum aviso registrado.', style: TextStyle(color: Colors.white54, fontSize: 12))
                else
                  Column(
                    children: avisos.map((a) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.notification_important, color: Colors.orangeAccent, size: 18),
                      title: Text(a['nome']),
                      subtitle: Text('Data: ${DateTime.parse(a['data']).day}/${DateTime.parse(a['data']).month}/${DateTime.parse(a['data']).year}'),
                      trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 16), onPressed: () => _removerAvaliacao(a['id'])),
                    )).toList(),
                  )
              ],
            ),
          ),

          const SizedBox(height: 32),
          const Text('📚 DESEMPENHO ACADÊMICO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
          const SizedBox(height: 16),
          if (cursando.isEmpty)
            const Center(child: Text('Nenhuma cadeira sendo cursada. Adicione à grade acima.', style: TextStyle(color: Colors.white54)))
          else
            Wrap(
              spacing: 20,
              runSpacing: 20,
              children: cursando.map((dc) => _buildCadeiraCard(context, dc, ini, fim)).toList(),
            )
        ],
      ),
    );
  }

  Widget _buildStatBlock({
    required double width,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Container(
      width: width.clamp(200.0, double.infinity),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF14141E).withOpacity(0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildGradeSemanalTable() {
    final horariosLinhas = [
      "08:00 - 10:00",
      "10:00 - 12:00",
      "14:00 - 16:00",
      "16:00 - 18:00",
      "19:00 - 20:40",
      "20:40 - 22:20"
    ];
    final dias = ["Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF14141E).withOpacity(0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Table(
          border: TableBorder.all(
            color: Colors.white.withOpacity(0.05),
            width: 1,
          ),
          columnWidths: const {0: FixedColumnWidth(130)},
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFF191926)),
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                  child: Text('Horários', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                ),
                ...dias.map((d) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                      child: Center(
                        child: Text(d, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                      ),
                    )),
              ],
            ),
            ...horariosLinhas.map((h) {
              return TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    child: Text(h, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                  ),
                  ...List.generate(6, (indexDia) {
                    final diaNumero = indexDia + 1;
                    final match = gradeHorarios.firstWhere(
                      (g) => g['dia_semana'] == diaNumero && g['hora'] == h,
                      orElse: () => {},
                    );

                    if (match.isNotEmpty) {
                      final cod = match['codigo_disciplina'];
                      final discInfo = curriculoGlobal.firstWhere(
                        (c) => c.codigo == cod,
                        orElse: () => Cadeira(cod, cod, 0, 0, []),
                      );
                      final dc = discAtivas.firstWhere(
                        (d) => d['codigo'] == cod,
                        orElse: () => {'cor_hex': 0xFF00E5FF},
                      );

                      final Color cardColor = Color(dc['cor_hex'] as int);

                      return Container(
                        margin: const EdgeInsets.all(4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        decoration: BoxDecoration(
                          color: cardColor.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              discInfo.nome,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              cod,
                              style: const TextStyle(
                                fontSize: 8.5,
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox(
                      height: 52,
                      child: Center(
                        child: Text('---', style: TextStyle(color: Colors.white12, fontSize: 11)),
                      ),
                    );
                  }),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCadeiraCard(BuildContext context, Map<String, dynamic> dc, DateTime ini, DateTime fim) {
    final curInfo = curriculoGlobal.firstWhere((c) => c.codigo == dc['codigo'], orElse: () => Cadeira(dc['codigo'], dc['codigo'], 0, 0, []));
    final int numUnidades = (dc['num_unidades'] as num?)?.toInt() ?? 3;
    final avaliacoesDisc = avaliacoes.where((a) => a['codigo_disciplina'] == dc['codigo'] && a['tipo'] != 'Aviso').toList();
    final faltasDisc = faltas.where((f) => f['codigo_disciplina'] == dc['codigo']).toList();

    double somaTotalPontos = 0.0;
    int unidadesPreenchidas = 0;
    Map<int, double> notasPorUnidade = {};

    for (int u = 1; u <= numUnidades; u++) {
      final avsDaUnidade = avaliacoesDisc.where((a) => a['unidade'] == u).toList();
      if (avsDaUnidade.isNotEmpty && avsDaUnidade.any((a) => a['nota'] != null)) {
        unidadesPreenchidas++;
        double somaPonderada = 0.0;
        double somaPesos = 0.0;

        for (final a in avsDaUnidade) {
          final nota = (a['nota'] as num?)?.toDouble();
          if (nota == null) continue;
          final peso = ((a['peso'] as num?)?.toDouble() ?? 1.0);
          if (peso <= 0) continue;
          somaPonderada += nota * peso;
          somaPesos += peso;
        }

        final totalUnidade = somaPesos > 0
            ? (somaPonderada / somaPesos).clamp(0.0, 10.0)
            : 0.0;

        notasPorUnidade[u] = totalUnidade;
        somaTotalPontos += totalUnidade;
      }
    }

    final double metaAprovacao = numUnidades * 7.0;
    final double metaFinal = numUnidades * 4.0;
    final double mediaAtual = somaTotalPontos / numUnidades;

    Color gColor = Colors.orangeAccent;
    String gTexto = "Em Andamento";
    String gFeedback = "";

    bool todasConcluidas = unidadesPreenchidas == numUnidades;

    if (todasConcluidas) {
      if (mediaAtual >= 7.0) {
        gColor = Colors.greenAccent;
        gTexto = "Aprovado por Média";
        gFeedback = "🎉 APROVADO DIRETO! Média: ${mediaAtual.toStringAsFixed(1)}";
      } else if (mediaAtual >= 4.0) {
        gColor = Colors.orangeAccent;
        gTexto = "Na Final";
        double nf = (50.0 - 6.0 * mediaAtual) / 4.0;
        gFeedback = "Nota Mínima na Final: ${nf.toStringAsFixed(1)} (Total: ${somaTotalPontos.toStringAsFixed(1)} pts)";
      } else {
        gColor = Colors.redAccent;
        gTexto = "Reprovado";
        gFeedback = "Média ${mediaAtual.toStringAsFixed(1)} (< 4.0). Não atinge a Prova Final.";
      }
    } else {
      double faltamParaAprovacao = (metaAprovacao - somaTotalPontos).clamp(0.0, metaAprovacao);
      double faltamParaFinal = (metaFinal - somaTotalPontos).clamp(0.0, metaFinal);

      if (somaTotalPontos >= metaAprovacao) {
        gColor = Colors.greenAccent;
        gTexto = "Aprovado Garantido";
        gFeedback = "🎉 Meta atingida (${somaTotalPontos.toStringAsFixed(1)} pts acumulados)!";
      } else {
        gColor = corDinamica;
        gTexto = "Acumulado: ${somaTotalPontos.toStringAsFixed(1)} pts";
        gFeedback = "Faltam ${faltamParaAprovacao.toStringAsFixed(1)} pts p/ Aprovar (${faltamParaFinal.toStringAsFixed(1)} pts p/ Final)";
      }
    }

    final Color badgeColor = Color(dc['cor_hex'] as int);

    return Container(
      width: 530,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111119).withOpacity(0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: badgeColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(curInfo.nome, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
              IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20), onPressed: () => _removerCursando(dc['codigo']))
            ],
          ),
          Text('${curInfo.codigo} • ${curInfo.ch}h • $numUnidades Unidades', style: const TextStyle(color: Colors.grey, fontSize: 11)),
          const Divider(height: 28, color: Colors.white10),
          Row(
            children: [
              CircularPercentIndicator(
                radius: 46.0,
                lineWidth: 8.0,
                animation: true,
                percent: (somaTotalPontos / metaAprovacao).clamp(0.0, 1.0),
                center: Text(somaTotalPontos.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                circularStrokeCap: CircularStrokeCap.round,
                progressColor: gColor,
                backgroundColor: Colors.white10,
                footer: Padding(
                  padding: const EdgeInsets.only(top: 6.0),
                  child: Text(gTexto, style: TextStyle(color: gColor, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(gFeedback, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: gColor)),
                    const SizedBox(height: 12),
                    const Text('UNIDADES AVALIATIVAS:', style: TextStyle(fontSize: 9.5, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(numUnidades, (index) {
                        final uNum = index + 1;
                        final notaU = notasPorUnidade[uNum];
                        final hasNota = notaU != null;

                        return InkWell(
                          onTap: () => _modalGerenciarUnidade(context, dc['codigo'], uNum, ini, fim),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: hasNota ? const Color(0xFF1E2638) : const Color(0xFF181822),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: hasNota ? corDinamica.withOpacity(0.5) : Colors.white12),
                            ),
                            child: Column(
                              children: [
                                Text('Unidade $uNum', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70)),
                                const SizedBox(height: 2),
                                Text(
                                  hasNota ? notaU.toStringAsFixed(1) : '--',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: hasNota ? corDinamica : Colors.white30,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('FALTAS: ${faltasDisc.length} / 15', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
              Row(
                children: [
                  TextButton(onPressed: () => _modalVerHistoricoFaltas(context, curInfo.nome, faltasDisc), child: Text('Histórico', style: TextStyle(fontSize: 11, color: corDinamica))),
                  TextButton(onPressed: () => _modalRegistrarFalta(context, dc['codigo'], ini, fim), child: const Text('+ Registrar', style: TextStyle(fontSize: 11, color: Colors.orangeAccent))),
                ],
              )
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _iniciarPeriodo(BuildContext context) async {
    final nomeC = TextEditingController(text: '2026.2');
    DateTime i = DateTime.now(), f = DateTime.now().add(const Duration(days: 120));
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      title: const Text('NOVO PERÍODO LETIVO'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nomeC, decoration: const InputDecoration(labelText: 'PERÍODO')),
        ListTile(title: const Text('Data de Início'), subtitle: Text('${i.day}/${i.month}/${i.year}'), onTap: () async { final d = await showDatePicker(context: ctx, initialDate: i, firstDate: DateTime(2024), lastDate: DateTime(2030)); if (d != null) setS(() => i = d); }),
        ListTile(title: const Text('Data de Término'), subtitle: Text('${f.day}/${f.month}/${f.year}'), onTap: () async { final d = await showDatePicker(context: ctx, initialDate: f, firstDate: DateTime(2024), lastDate: DateTime(2030)); if (d != null) setS(() => f = d); }),
      ]),
      actions: [ElevatedButton(onPressed: () async {
        if (nomeC.text.trim().isEmpty) return;
        final db = await DatabaseHelper.instance.database;
        await db.insert('periodo_ativo', {'id': 1, 'nome': nomeC.text, 'inicio': i.toIso8601String(), 'fim': f.toIso8601String()});
        onRefresh(); Navigator.pop(ctx);
      }, child: const Text('Iniciar'))],
    )));
  }

  Future<void> _editarPeriodo(BuildContext context, String nm, DateTime i, DateTime f) async {
    final nomeC = TextEditingController(text: nm);
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      title: const Text('Editar Datas do Período'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nomeC, decoration: const InputDecoration(labelText: 'Nome')),
        ListTile(title: const Text('Início'), subtitle: Text('${i.day}/${i.month}/${i.year}'), onTap: () async { final d = await showDatePicker(context: ctx, initialDate: i, firstDate: DateTime(2024), lastDate: DateTime(2030)); if (d != null) setS(() => i = d); }),
        ListTile(title: const Text('Término'), subtitle: Text('${f.day}/${f.month}/${f.year}'), onTap: () async { final d = await showDatePicker(context: ctx, initialDate: f, firstDate: DateTime(2024), lastDate: DateTime(2030)); if (d != null) setS(() => f = d); }),
      ]),
      actions: [ElevatedButton(onPressed: () async {
        if (nomeC.text.trim().isEmpty) return;
        final db = await DatabaseHelper.instance.database;
        await db.update('periodo_ativo', {'nome': nomeC.text, 'inicio': i.toIso8601String(), 'fim': f.toIso8601String()}, where: 'id = 1');
        onRefresh(); Navigator.pop(ctx);
      }, child: const Text('Salvar'))],
    )));
  }

  Future<void> _modalAdicionarNaGrade(BuildContext context) async {
    final cadeirasDisponiveis = curriculoGlobal.where((c) {
      final ativa = discAtivas.any((d) => d['codigo'] == c.codigo);
      final prerequisitosOk = c.preReqs.every((req) =>
          discAtivas.any((d) => d['codigo'] == req && d['status'] == 'aprovado'));
      return !ativa && prerequisitosOk;
    }).toList();

    if (cadeirasDisponiveis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Todas as disciplinas disponíveis já foram adicionadas!')));
      return;
    }

    String selCod = cadeirasDisponiveis.first.codigo;
    int numUnidades = 3;
    int corSelecionada = paletaCoresDisciplinas[discAtivas.length % paletaCoresDisciplinas.length];
    final List<int> diasSel = [];
    final horariosLinhas = [
      "08:00 - 10:00",
      "10:00 - 12:00",
      "14:00 - 16:00",
      "16:00 - 18:00",
      "19:00 - 20:40",
      "20:40 - 22:20"
    ];
    String horarioSel = horariosLinhas.first;
    String? erro;

    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      title: const Text('Adicionar Disciplina & Configuração'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: selCod,
                items: cadeirasDisponiveis.map((c) => DropdownMenuItem(value: c.codigo, child: Text('${c.nome} (${c.codigo})', overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setS(() => selCod = v!),
                decoration: const InputDecoration(labelText: 'Disciplina'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: numUnidades,
                items: const [
                  DropdownMenuItem(value: 2, child: Text('2 Unidades (Meta: 14.0 pts)')),
                  DropdownMenuItem(value: 3, child: Text('3 Unidades (Meta: 21.0 pts)')),
                  DropdownMenuItem(value: 4, child: Text('4 Unidades (Meta: 28.0 pts)')),
                ],
                onChanged: (v) => setS(() => numUnidades = v!),
                decoration: const InputDecoration(labelText: 'Quantidade de Unidades Avaliativas'),
              ),
              const SizedBox(height: 16),
              const Text('Cor de Identificação:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: paletaCoresDisciplinas.map((corHex) {
                  final bool isSelected = corSelecionada == corHex;
                  return GestureDetector(
                    onTap: () => setS(() => corSelecionada = corHex),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Color(corHex),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: isSelected ? const Icon(Icons.check, size: 18, color: Colors.black) : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: horarioSel,
                items: horariosLinhas.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
                onChanged: (v) => setS(() => horarioSel = v!),
                decoration: const InputDecoration(labelText: 'Faixa de Horário'),
              ),
              const SizedBox(height: 16),
              const Text('Dias da Semana:'),
              Wrap(
                spacing: 6,
                children: [
                  {"d": 1, "n": "Seg"}, {"d": 2, "n": "Ter"}, {"d": 3, "n": "Qua"},
                  {"d": 4, "n": "Qui"}, {"d": 5, "n": "Sex"}, {"d": 6, "n": "Sáb"},
                ].map((item) {
                  final dN = item['d'] as int;
                  final sel = diasSel.contains(dN);
                  return FilterChip(
                    label: Text(item['n'] as String),
                    selected: sel,
                    onSelected: (val) => setS(() => val ? diasSel.add(dN) : diasSel.remove(dN)),
                  );
                }).toList(),
              ),
              if (erro != null) Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(erro!, style: const TextStyle(color: Colors.redAccent, fontSize: 11))),
            ],
          ),
        ),
      ),
      actions: [ElevatedButton(onPressed: () async {
        if (diasSel.isEmpty) { setS(() => erro = 'Selecione ao menos um dia.'); return; }

        for (var d in diasSel) {
          if (gradeHorarios.any((g) => g['dia_semana'] == d && g['hora'] == horarioSel)) {
            setS(() => erro = 'CHOQUE DETECTADO! Já existe uma disciplina nesse horário.');
            return;
          }
        }

        final db = await DatabaseHelper.instance.database;
        try {
          await db.transaction((txn) async {
            await txn.insert('disciplinas_ativas', {
              'codigo': selCod,
              'status': 'cursando',
              'cor_hex': corSelecionada,
              'num_unidades': numUnidades,
              'meta_pontos': numUnidades * 7.0,
            });

            for (final d in diasSel) {
              await txn.insert('grade_horarios', {
                'codigo_disciplina': selCod,
                'dia_semana': d,
                'hora': horarioSel,
              });
            }
          });

          onRefresh();
          Navigator.pop(ctx);
        } catch (e) {
          setS(() => erro = 'Erro ao cadastrar disciplina.');
        }
      }, child: const Text('Confirmar'))],
    )));
  }

  Future<void> _modalGerenciarUnidade(BuildContext context, String cod, int unidade, DateTime ini, DateTime fim) async {
    final itensDaUnidade = avaliacoes.where((a) => a['codigo_disciplina'] == cod && a['unidade'] == unidade).toList();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          double totalCalc = 0.0;
          for (var item in itensDaUnidade) {
            if (item['nota'] != null) totalCalc += (item['nota'] as num).toDouble();
          }

          return AlertDialog(
            title: Text('Gerenciar Unidade $unidade • Total: ${totalCalc.clamp(0.0, 10.0).toStringAsFixed(1)} / 10.0'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (itensDaUnidade.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Nenhum item avaliativo cadastrado.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      )
                    else
                      ...itensDaUnidade.map((item) => ListTile(
                            dense: true,
                            title: Text('${item['tipo']}: ${item['nome']}'),
                            subtitle: Text('Nota: ${item['nota'] != null ? (item['nota'] as num).toDouble().toStringAsFixed(1) : "--"}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                              onPressed: () async {
                                final db = await DatabaseHelper.instance.database;
                                await db.delete('avaliacoes', where: 'id = ?', whereArgs: [item['id']]);
                                onRefresh();
                                Navigator.pop(ctx);
                              },
                            ),
                          )),
                    const Divider(height: 24),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 38)),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Novo Item / Prova / Extra'),
                      onPressed: () async {
                        await _modalCriarItemUnidade(context, cod, unidade, ini, fim);
                        Navigator.pop(ctx);
                      },
                    )
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _modalCriarItemUnidade(BuildContext context, String cod, int unidade, DateTime ini, DateTime fim) async {
    final descC = TextEditingController();
    final notaC = TextEditingController();
    String tipo = 'Prova';
    DateTime d = DateTime.now().isBefore(ini) ? ini : (DateTime.now().isAfter(fim) ? fim : DateTime.now());

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Novo Item - Unidade $unidade'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                isExpanded: true,
                value: tipo,
                items: ['Prova', 'Trabalho', 'Lista', 'Laboratório', 'Ponto Extra', 'Final']
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setS(() => tipo = v!),
              ),
              TextField(controller: descC, decoration: const InputDecoration(labelText: 'Descrição')),
              TextField(controller: notaC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Nota (Opcional)')),
              ListTile(
                title: const Text('Data'),
                subtitle: Text('${d.day}/${d.month}/${d.year}'),
                onTap: () async {
                  final dx = await showDatePicker(context: ctx, initialDate: d, firstDate: ini, lastDate: fim);
                  if (dx != null) setS(() => d = dx);
                },
              )
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final db = await DatabaseHelper.instance.database;
                final parsedNota = notaC.text.trim().isEmpty ? null : double.tryParse(notaC.text.replaceAll(',', '.'));
                await db.insert('avaliacoes', {
                  'codigo_disciplina': cod,
                  'unidade': unidade,
                  'tipo': tipo,
                  'nome': descC.text.isEmpty ? 'Avaliação' : descC.text,
                  'nota': parsedNota,
                  'peso': 1.0,
                  'data': d.toIso8601String(),
                });
                onRefresh();
                Navigator.pop(ctx);
              },
              child: const Text('Salvar Item'),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _removerCursando(String cod) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('disciplinas_ativas', where: 'codigo = ?', whereArgs: [cod]);
    onRefresh();
  }

  Future<void> _modalNovoAviso(BuildContext context, DateTime ini, DateTime fim) async {
    final nomeC = TextEditingController();
    DateTime d = DateTime.now().isBefore(ini) ? ini : (DateTime.now().isAfter(fim) ? fim : DateTime.now());
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      title: const Text('Novo Aviso Geral'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nomeC, decoration: const InputDecoration(labelText: 'Descrição (Ex: Feriado)')),
        ListTile(
          title: const Text('Data'),
          subtitle: Text('${d.day}/${d.month}/${d.year}'),
          onTap: () async {
            final dx = await showDatePicker(context: ctx, initialDate: d, firstDate: ini, lastDate: fim);
            if (dx != null) setS(() => d = dx);
          },
        )
      ]),
      actions: [ElevatedButton(onPressed: () async {
        if (nomeC.text.trim().isEmpty) return;
        final db = await DatabaseHelper.instance.database;
        await db.insert('avaliacoes', {'codigo_disciplina': null, 'unidade': null, 'tipo': 'Aviso', 'nome': nomeC.text, 'data': d.toIso8601String()});
        onRefresh(); Navigator.pop(ctx);
      }, child: const Text('Salvar'))],
    )));
  }

  Future<void> _modalRegistrarFalta(BuildContext context, String cod, DateTime ini, DateTime fim) async {
    final motC = TextEditingController();
    DateTime d = DateTime.now().isBefore(ini) ? ini : (DateTime.now().isAfter(fim) ? fim : DateTime.now());
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      title: const Text('Registrar Falta'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: motC, decoration: const InputDecoration(labelText: 'Motivo')),
        ListTile(
          title: const Text('Data'),
          subtitle: Text('${d.day}/${d.month}/${d.year}'),
          onTap: () async {
            final dx = await showDatePicker(context: ctx, initialDate: d, firstDate: ini, lastDate: fim);
            if (dx != null) setS(() => d = dx);
          },
        )
      ]),
      actions: [ElevatedButton(onPressed: () async {
        if (motC.text.trim().isEmpty) return;
        final db = await DatabaseHelper.instance.database;
        await db.insert('faltas', {'codigo_disciplina': cod, 'data': d.toIso8601String(), 'motivo': motC.text});
        onRefresh(); Navigator.pop(ctx);
      }, child: const Text('Salvar Falta'))],
    )));
  }

  void _modalVerHistoricoFaltas(BuildContext context, String nomeDisc, List<Map<String, dynamic>> faltasDisc) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('Histórico de Faltas: $nomeDisc'),
      content: SizedBox(
        width: 400,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: faltasDisc.length,
          itemBuilder: (ctx, i) {
            final f = faltasDisc[i];
            final d = DateTime.parse(f['data']);
            return ListTile(
              dense: true,
              leading: const Icon(Icons.event_busy, color: Colors.orangeAccent),
              title: Text(f['motivo']),
              subtitle: Text('${d.day}/${d.month}/${d.year}'),
              trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 16), onPressed: () async {
                final db = await DatabaseHelper.instance.database;
                await db.delete('faltas', where: 'id = ?', whereArgs: [f['id']]);
                onRefresh(); Navigator.pop(ctx);
              }),
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
    ));
  }

  Future<void> _removerAvaliacao(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('avaliacoes', where: 'id = ?', whereArgs: [id]);
    onRefresh();
  }
}

// =============================================================
// TAB 3: CALENDÁRIO MENSAL & RADAR ACADÊMICO
// =============================================================
class PanoramicCalendarView extends StatelessWidget {
  final Map<String, dynamic>? periodo;
  final List<Map<String, dynamic>> avaliacoes;
  final List<Map<String, dynamic>> discAtivas;
  final VoidCallback onRefresh;
  final Color corDinamica;

  const PanoramicCalendarView({
    super.key,
    required this.periodo,
    required this.avaliacoes,
    required this.discAtivas,
    required this.onRefresh,
    required this.corDinamica,
  });

  List<DateTime> _obterMesesDoPeriodo(DateTime ini, DateTime fim) {
    List<DateTime> meses = [];
    DateTime cursor = DateTime(ini.year, ini.month, 1);
    final limite = DateTime(fim.year, fim.month, 1);

    while (!cursor.isAfter(limite)) {
      meses.add(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    return meses;
  }

  String _getNomeMes(int mes) {
    const meses = [
      "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
      "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"
    ];
    return meses[mes - 1];
  }

  @override
  Widget build(BuildContext context) {
    if (periodo == null) return const Center(child: Text('Nenhum período ativo.'));

    final ini = DateTime.parse(periodo!['inicio']);
    final fim = DateTime.parse(periodo!['fim']);
    final totalEventos = avaliacoes.length;

    final hoje = DateTime.now();
    final hojeZero = DateTime(hoje.year, hoje.month, hoje.day);
    final proximas = avaliacoes.where((a) {
      final d = DateTime.parse(a['data']);
      return !d.isBefore(hojeZero);
    }).toList()..sort((a, b) => DateTime.parse(a['data']).compareTo(DateTime.parse(b['data'])));

    final mesesList = _obterMesesDoPeriodo(ini, fim);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF14141E).withOpacity(0.92),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.purpleAccent, size: 18),
                          const SizedBox(width: 10),
                          Text(
                            'DIAS LETIVOS: ${ini.day}/${ini.month}/${ini.year} até ${fim.day}/${fim.month}/${fim.year}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                      Text(
                        '$totalEventos eventos cadastrados',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      )
                    ],
                  ),
                  const Divider(height: 24, color: Colors.white10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: mesesList.length,
                      itemBuilder: (ctx, idx) {
                        final mesAtual = mesesList[idx];
                        return _buildMonthCalendar(context, mesAtual, ini, fim, hojeZero);
                      },
                    ),
                  )
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),

          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF14141E).withOpacity(0.92),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.radar, color: Colors.amberAccent, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Radar Acadêmico',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: proximas.isEmpty
                        ? const Center(child: Text('Nenhum compromisso pendente!', style: TextStyle(color: Colors.white38, fontSize: 12)))
                        : ListView.builder(
                            itemCount: proximas.length,
                            itemBuilder: (ctx, i) {
                              final a = proximas[i];
                              final d = DateTime.parse(a['data']);
                              final diff = d.difference(hojeZero).inDays;
                              String prazoTexto = diff == 0 ? "HOJE" : (diff == 1 ? "Amanhã" : "Daqui a $diff dias");

                              final dc = discAtivas.firstWhere(
                                (elem) => elem['codigo'] == a['codigo_disciplina'],
                                orElse: () => {'cor_hex': 0xFF00E5FF},
                              );

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1B1B26),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Color(dc['cor_hex'] as int).withOpacity(0.4)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('${a['tipo']}: ${a['nome']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                        Text(prazoTexto, style: const TextStyle(color: Colors.tealAccent, fontSize: 10.5, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text('Data: ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMonthCalendar(BuildContext context, DateTime monthDate, DateTime ini, DateTime fim, DateTime hojeZero) {
    final diasSemana = ["dom.", "seg.", "ter.", "qua.", "qui.", "sex.", "sáb."];
    final primeiroDiaMes = DateTime(monthDate.year, monthDate.month, 1);
    final int diasNoMes = DateTime(monthDate.year, monthDate.month + 1, 0).day;
    final int offsetInicio = primeiroDiaMes.weekday % 7;
    final int diasMesAnterior = DateTime(monthDate.year, monthDate.month, 0).day;
    final totalCelulas = ((offsetInicio + diasNoMes) / 7).ceil() * 7;

    return Container(
      margin: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '${_getNomeMes(monthDate.month).toUpperCase()} ${monthDate.year}',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: corDinamica, letterSpacing: 1.1),
          ),
          const SizedBox(height: 14),
          Row(
            children: diasSemana.map((d) => Expanded(
              child: Center(
                child: Text(d, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
            )).toList(),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.3,
            ),
            itemCount: totalCelulas,
            itemBuilder: (ctx, i) {
              DateTime dataDia;
              bool isOutroMes = false;

              if (i < offsetInicio) {
                final diaNum = diasMesAnterior - offsetInicio + i + 1;
                dataDia = DateTime(monthDate.year, monthDate.month - 1, diaNum);
                isOutroMes = true;
              } else if (i >= offsetInicio + diasNoMes) {
                final diaNum = i - (offsetInicio + diasNoMes) + 1;
                dataDia = DateTime(monthDate.year, monthDate.month + 1, diaNum);
                isOutroMes = true;
              } else {
                final diaNum = i - offsetInicio + 1;
                dataDia = DateTime(monthDate.year, monthDate.month, diaNum);
              }

              final bool dentroDoPeriodo = !dataDia.isBefore(DateTime(ini.year, ini.month, ini.day)) &&
                  !dataDia.isAfter(DateTime(fim.year, fim.month, fim.day));

              final bool isDiaLetivo = dentroDoPeriodo && (dataDia.weekday >= DateTime.monday && dataDia.weekday <= DateTime.friday);
              final bool isFimDeSemana = (dataDia.weekday == DateTime.saturday || dataDia.weekday == DateTime.sunday);

              final evs = avaliacoes.where((a) {
                final aD = DateTime.parse(a['data']);
                return aD.year == dataDia.year && aD.month == dataDia.month && aD.day == dataDia.day;
              }).toList();

              final bool isHoje = dataDia.year == hojeZero.year && dataDia.month == hojeZero.month && dataDia.day == hojeZero.day;

              Color corFundo = Colors.transparent;
              if (!isOutroMes && isDiaLetivo) {
                corFundo = corDinamica.withOpacity(0.08);
              }

              return Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isHoje ? corDinamica.withOpacity(0.25) : corFundo,
                  borderRadius: BorderRadius.circular(8),
                  border: isHoje
                      ? Border.all(color: corDinamica, width: 1.5)
                      : (evs.isNotEmpty
                          ? Border.all(color: Colors.purpleAccent.withOpacity(0.6))
                          : (isDiaLetivo ? Border.all(color: corDinamica.withOpacity(0.20)) : null)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${dataDia.day}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isHoje || evs.isNotEmpty || isDiaLetivo ? FontWeight.bold : FontWeight.normal,
                        color: isOutroMes || !dentroDoPeriodo
                            ? Colors.white24
                            : (isFimDeSemana
                                ? Colors.white38
                                : (isHoje ? corDinamica : (evs.isNotEmpty ? Colors.amberAccent : Colors.white))),
                      ),
                    ),
                    if (evs.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: evs.take(3).map((e) => Container(
                          width: 4,
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: const BoxDecoration(color: Colors.amberAccent, shape: BoxShape.circle),
                        )).toList(),
                      )
                    ]
                  ],
                ),
              );
            },
          )
        ],
      ),
    );
  }
}