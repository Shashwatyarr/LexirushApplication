class QuestionModel {
  final String id;
  final int no;
  final String difficulty;
  final String word;
  final String pos;
  final String meaning;
  final List<String> synonyms;
  final List<String> antonyms;

  QuestionModel({
    required this.id,
    required this.no,
    required this.difficulty,
    required this.word,
    required this.pos,
    required this.meaning,
    required this.synonyms,
    required this.antonyms,
  });

  factory QuestionModel.fromJson(Map<String, dynamic> json) {
    final questionData = json['question'] ?? {};
    return QuestionModel(
      id: json['_id'] ?? '',
      no: json['no'] ?? 0,
      difficulty: questionData['difficulty'] ?? 'easy',
      word: questionData['word'] ?? '',
      pos: questionData['pos'] ?? '',
      meaning: questionData['meaning'] ?? '',
      synonyms: List<String>.from(questionData['synonym'] ?? []),
      antonyms: List<String>.from(questionData['antonym'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'no': no,
      'question': {
        'difficulty': difficulty,
        'word': word,
        'pos': pos,
        'meaning': meaning,
        'synonym': synonyms,
        'antonym': antonyms,
      }
    };
  }
}
