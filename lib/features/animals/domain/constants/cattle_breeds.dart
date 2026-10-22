/// Suggestions only: animals continue to store unrestricted breed text.
class CattleBreedOption {
  const CattleBreedOption(this.name, {this.aliases = const []});

  final String name;
  final List<String> aliases;
}

/// Product catalog: 30 breeds or varieties and one unspecified option.
/// Suggestions are not a certification of breed or presence in Peru.
const cattleBreeds = <CattleBreedOption>[
  CattleBreedOption('Holstein', aliases: ['Holstein Friesian']),
  CattleBreedOption('Brown Swiss', aliases: ['Pardo Suizo']),
  CattleBreedOption('Jersey'),
  CattleBreedOption('Ayrshire'),
  CattleBreedOption('Guernsey'),
  CattleBreedOption('Brahman'),
  CattleBreedOption('Brahman Rojo'),
  CattleBreedOption('Brahman Gris'),
  CattleBreedOption('Nelore', aliases: ['Nellore']),
  CattleBreedOption('Nelore Mocho'),
  CattleBreedOption('Gyr', aliases: ['Gir']),
  CattleBreedOption('Guzerat', aliases: ['Guzerá']),
  CattleBreedOption('Indubrasil'),
  CattleBreedOption('Sahiwal'),
  CattleBreedOption('Angus', aliases: ['Aberdeen Angus']),
  CattleBreedOption('Hereford'),
  CattleBreedOption('Brangus'),
  CattleBreedOption('Braford'),
  CattleBreedOption('Charolais'),
  CattleBreedOption('Limousin'),
  CattleBreedOption('Simmental', aliases: ['Simmenthal']),
  CattleBreedOption('Fleckvieh'),
  CattleBreedOption('Braunvieh'),
  CattleBreedOption('Normando'),
  CattleBreedOption('Senepol'),
  CattleBreedOption('Santa Gertrudis'),
  CattleBreedOption('Beefmaster'),
  CattleBreedOption('Girolando'),
  CattleBreedOption('Criollo', aliases: ['Criollo peruano', 'Chusco']),
  CattleBreedOption('Wagyu'),
  // An independent unspecified value, never a fallback for unmatched text.
  CattleBreedOption(
    'Raza no especificada',
    aliases: ['Desconocida', 'Sin especificar'],
  ),
];
