class Animal {
  final String id;
  final String earTag;
  final String? name;
  final String category;
  final String breed;
  final String sex;
  final String? photoPath;
  final DateTime createdAt;

  const Animal({
    required this.id,
    required this.earTag,
    this.name,
    required this.category,
    required this.breed,
    required this.sex,
    this.photoPath,
    required this.createdAt,
  });
}