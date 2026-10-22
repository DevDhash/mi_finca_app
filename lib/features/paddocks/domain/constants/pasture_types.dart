/// Suggestions only; paddocks continue to store unrestricted pasture text.
class PastureTypeOption {
  const PastureTypeOption(this.name, {this.aliases = const []});

  final String name;
  final List<String> aliases;
}

/// Species, cultivars and common names remain independent suggestions.
/// Aliases are search keys, not a botanical identification of saved records.
// Botanical references (catalog only; no runtime network access):
// https://www.tropicalforages.info/text/entities/urochloa_brizantha.htm
// https://www.tropicalforages.info/text/entities_app/urochloa_humidicola.htm
// https://repositorio.inia.gob.pe/items/bef5ee02-c3d9-4bdc-86f7-5c1cdbb105a6
// https://repositorio.serfor.gob.pe/bitstream/SERFOR/983/3/Reporte%20especies%20palatables%20para%20vicunas.pdf
// Broad genera and ambiguous regional/trade names intentionally have no species alias.
// Alphabetical by primary name, ignoring accents and case (ñ follows n).
const pastureTypes = <PastureTypeOption>[
  PastureTypeOption('Agrostis'),
  PastureTypeOption('Alfalfa', aliases: ['Medicago sativa']),
  PastureTypeOption(
    'Aruana',
    aliases: ['Panicum maximum cv. Aruana', 'Megathyrsus maximus cv. Aruana'],
  ),
  PastureTypeOption('Avena forrajera', aliases: ['Avena sativa']),
  PastureTypeOption('Brachiaria', aliases: ['Pasto Brachiaria']),
  PastureTypeOption('Brachiaria brizantha', aliases: ['Urochloa brizantha']),
  PastureTypeOption('Brachiaria decumbens', aliases: ['Urochloa decumbens']),
  PastureTypeOption(
    'Brachiaria dictyoneura',
    aliases: ['Urochloa dictyoneura'],
  ),
  PastureTypeOption('Brachiaria humidicola', aliases: ['Urochloa humidicola']),
  PastureTypeOption(
    'Brachiaria ruziziensis',
    aliases: ['Urochloa ruziziensis'],
  ),
  PastureTypeOption('Bromus'),
  PastureTypeOption('Bromus lanatus'),
  PastureTypeOption('Calamagrostis'),
  PastureTypeOption('Calamagrostis rigida'),
  PastureTypeOption('Calopogonio', aliases: ['Calopogonium mucunoides']),
  PastureTypeOption('Camerún', aliases: ['Cameroon', 'Pasto Camerún']),
  PastureTypeOption('Caña forrajera'),
  PastureTypeOption('Carex'),
  PastureTypeOption(
    'Cayman',
    aliases: ['Brachiaria híbrida Cayman', 'Urochloa híbrida Cayman'],
  ),
  PastureTypeOption('Cebada forrajera', aliases: ['Hordeum vulgare']),
  PastureTypeOption(
    'Cebadilla criolla',
    aliases: ['Bromus catharticus', 'Bromus unioloides'],
  ),
  PastureTypeOption('Centeno forrajero', aliases: ['Secale cereale']),
  PastureTypeOption('Centrosema', aliases: ['Centrosema spp.']),
  PastureTypeOption('Centrosema macrocarpum'),
  // Common/scientific duplicate: Festuca dolichophylla is searchable here.
  PastureTypeOption('Chillihua', aliases: ['Festuca dolichophylla']),
  PastureTypeOption(
    'Coastcross',
    aliases: ['Coastcross-1', 'Cynodon híbrido Coastcross'],
  ),
  PastureTypeOption(
    'Cobra',
    aliases: ['Brachiaria híbrida Cobra', 'Urochloa híbrida Cobra'],
  ),
  // Traditional type name retained separately from the general Guinea suggestion.
  PastureTypeOption('Colonião', aliases: ['Capim Colonião']),
  // Traditional Andean name: do not assert a unique botanical identity.
  PastureTypeOption('Crespillo'),
  PastureTypeOption('CT-115', aliases: ['Cuba CT-115', 'CT 115']),
  PastureTypeOption('CT-169', aliases: ['Cuba CT-169', 'CT 169']),
  PastureTypeOption('Cuba 22', aliases: ['Pasto Cuba 22', 'Cuba22']),
  // Do not assume that locally named Cuba 22 is this verified clone.
  PastureTypeOption('Cuba OM-22', aliases: ['OM-22', 'Cuba OM 22']),
  PastureTypeOption('Dactylis glomerata', aliases: ['Dáctilo', 'Pasto ovillo']),
  PastureTypeOption('Desmodium intortum', aliases: ['Greenleaf desmodium']),
  // Taxonomic treatments vary; retain the requested traditional forage name.
  PastureTypeOption(
    'Desmodium ovalifolium',
    aliases: ['Desmodium heterocarpon subsp. ovalifolium'],
  ),
  PastureTypeOption('Desmodium uncinatum', aliases: ['Silverleaf desmodium']),
  PastureTypeOption('Distichia'),
  PastureTypeOption('Elefante morado', aliases: ['Pasto Elefante morado']),
  PastureTypeOption('Eleocharis'),
  // General genus suggestion; Harding below identifies the more specific material.
  PastureTypeOption('Falaris', aliases: ['Phalaris']),
  PastureTypeOption(
    'Falaris Harding',
    aliases: ['Pasto Harding', 'Phalaris aquatica', 'Phalaris tuberosa'],
  ),
  PastureTypeOption('Festuca', aliases: ['Pasto Festuca']),
  PastureTypeOption(
    'Festuca alta',
    aliases: [
      'Festuca arundinacea',
      'Schedonorus arundinaceus',
      'Lolium arundinaceum',
    ],
  ),
  PastureTypeOption(
    'Festuca de pradera',
    aliases: ['Festuca pratensis', 'Schedonorus pratensis', 'Lolium pratense'],
  ),
  PastureTypeOption('Festuca orthophylla'),
  PastureTypeOption(
    'Gatton Panic',
    aliases: ['Panicum maximum cv. Gatton', 'Megathyrsus maximus cv. Gatton'],
  ),
  // Regional common name: no single botanical identity asserted.
  PastureTypeOption('Grama dulce'),
  PastureTypeOption('Holcus'),
  // Traditional Andean group name: do not assign a single species.
  PastureTypeOption('Ichu'),
  PastureTypeOption('Juncus'),
  PastureTypeOption(
    'Kikuyo',
    aliases: ['Cenchrus clandestinus', 'Pennisetum clandestinum'],
  ),
  PastureTypeOption('King Grass', aliases: ['Kinggrass', 'Pasto King Grass']),
  PastureTypeOption(
    'Kudzu tropical',
    aliases: ['Pueraria phaseoloides', 'Neustanthus phaseoloides'],
  ),
  PastureTypeOption('Lablab', aliases: ['Lablab purpureus', 'Dolichos lablab']),
  PastureTypeOption('Lachemilla'),
  // Cultivar of U. humidicola, historically sold as B. dictyoneura.
  // The true U. dictyoneura species remains a separate suggestion.
  PastureTypeOption(
    'Llanero',
    aliases: [
      'Brachiaria humidicola cv. Llanero',
      'Urochloa humidicola cv. Llanero',
      'Brachiaria dictyoneura cv. Llanero',
    ],
  ),
  PastureTypeOption('Lotus corniculatus'),
  PastureTypeOption('Lotus pedunculatus', aliases: ['Lotus uliginosus']),
  PastureTypeOption('Maíz chala', aliases: ['Zea mays']),
  // Rastrero is descriptive, not evidence of a distinct species or cultivar.
  PastureTypeOption(
    'Maní forrajero',
    aliases: ['Maní de forraje', 'Arachis pintoi', 'Maní forrajero rastrero'],
  ),
  PastureTypeOption('Maralfalfa', aliases: ['Pasto Maralfalfa']),
  PastureTypeOption(
    'Marandú',
    aliases: [
      'Brachiaria brizantha cv. Marandu',
      'Urochloa brizantha cv. Marandu',
    ],
  ),
  // Forage cultivar; sources differ on hybrid treatment. Do not infer parentage.
  PastureTypeOption(
    'Massai',
    aliases: ['Panicum maximum cv. Massai', 'Megathyrsus maximus cv. Massai'],
  ),
  PastureTypeOption(
    'Mavuno',
    aliases: ['Brachiaria híbrida Mavuno', 'Urochloa híbrida Mavuno'],
  ),
  PastureTypeOption(
    'Mombasa',
    aliases: [
      'Mombaça',
      'Panicum maximum cv. Mombasa',
      'Megathyrsus maximus cv. Mombasa',
    ],
  ),
  PastureTypeOption('Muhlenbergia'),
  PastureTypeOption('Muhlenbergia fastigiata'),
  PastureTypeOption(
    'Mulato',
    aliases: ['Brachiaria híbrida Mulato', 'Urochloa híbrida Mulato'],
  ),
  PastureTypeOption(
    'Mulato II',
    aliases: ['Brachiaria híbrida Mulato II', 'Urochloa híbrida Mulato II'],
  ),
  PastureTypeOption('Nassella'),
  PastureTypeOption(
    'Paiaguás',
    aliases: [
      'BRS Paiaguás',
      'Brachiaria brizantha cv. Paiaguas',
      'Urochloa brizantha cv. Paiaguas',
    ],
  ),
  PastureTypeOption('Pasto Alemán', aliases: ['Echinochloa polystachya']),
  PastureTypeOption('Pasto Angleton', aliases: ['Dichanthium aristatum']),
  // Regional common name: no single botanical identity asserted.
  PastureTypeOption('Pasto Azul'),
  PastureTypeOption('Pasto Bahía', aliases: ['Paspalum notatum']),
  PastureTypeOption('Pasto Bermuda', aliases: ['Bermuda', 'Cynodon dactylon']),
  PastureTypeOption(
    'Pasto Carimagua',
    aliases: ['Carimagua 1', 'Andropogon gayanus cv. Carimagua 1'],
  ),
  PastureTypeOption(
    'Pasto Elefante',
    aliases: [
      'Elefante',
      'Napier',
      'Cenchrus purpureus',
      'Pennisetum purpureum',
    ],
  ),
  PastureTypeOption(
    'Pasto Estrella',
    aliases: ['Estrella', 'Estrella africana'],
  ),
  PastureTypeOption('Pasto Gordura', aliases: ['Melinis minutiflora']),
  // Regional common name: no single botanical identity asserted.
  PastureTypeOption('Pasto Gramalote'),
  PastureTypeOption(
    'Pasto Guatemala',
    aliases: ['Hierba de Guatemala', 'Tripsacum andersonii'],
  ),
  PastureTypeOption(
    'Pasto Guinea',
    aliases: ['Guinea', 'Panicum maximum', 'Megathyrsus maximus'],
  ),
  PastureTypeOption('Pasto Jaragua', aliases: ['Hyparrhenia rufa']),
  PastureTypeOption(
    'Pasto Pangola',
    aliases: ['Pangola', 'Digitaria decumbens'],
  ),
  PastureTypeOption(
    'Pasto Pará',
    aliases: ['Brachiaria mutica', 'Urochloa mutica'],
  ),
  PastureTypeOption(
    'Pasto Tanner',
    aliases: ['Brachiaria arrecta', 'Urochloa arrecta'],
  ),
  PastureTypeOption(
    'Pastura no especificada',
    aliases: ['Sin especificar', 'Pastura desconocida'],
  ),
  PastureTypeOption(
    'Piatã',
    aliases: [
      'BRS Piatã',
      'Brachiaria brizantha cv. Piata',
      'Urochloa brizantha cv. Piata',
    ],
  ),
  PastureTypeOption('Plantago rigida'),
  PastureTypeOption('Poa altoandina'),
  PastureTypeOption('Poa candamoana'),
  // Local ecotype; no species identification inferred from its name.
  PastureTypeOption(
    'Ryegrass Cajamarquino',
    aliases: ['Ryegrass ecotipo Cajamarquino', 'Raigrás Cajamarquino'],
  ),
  PastureTypeOption(
    'Ryegrass híbrido',
    aliases: [
      'Raigrás híbrido',
      'Raygrass híbrido',
      'Lolium hybridum',
      'Lolium x boucheanum',
    ],
  ),
  PastureTypeOption(
    'Ryegrass inglés',
    aliases: ['Raigrás inglés', 'Raygrass inglés', 'Lolium perenne'],
  ),
  PastureTypeOption(
    'Ryegrass italiano',
    aliases: ['Raigrás italiano', 'Raygrass italiano', 'Lolium multiflorum'],
  ),
  // INIA 910 cultivar; keep separate from the general Cajamarquino ecotype.
  PastureTypeOption(
    'Ryegrass Kumymarca',
    aliases: ['INIA 910 - KUMYMARCA', 'INIA 910 Kumymarca'],
  ),
  PastureTypeOption(
    'Ryegrass Nui',
    aliases: ['Grasslands Nui', 'Lolium perenne cv. Nui'],
  ),
  PastureTypeOption(
    'Ryegrass Tama',
    aliases: ['Grasslands Tama', 'Lolium multiflorum cv. Tama'],
  ),
  PastureTypeOption('Scirpus'),
  PastureTypeOption('Setaria', aliases: ['Pasto Setaria', 'Setarea']),
  PastureTypeOption(
    'Setaria Kazungula',
    aliases: ['Setaria sphacelata cv. Kazungula'],
  ),
  PastureTypeOption('Setaria Narok', aliases: ['Setaria sphacelata cv. Narok']),
  PastureTypeOption('Siratro', aliases: ['Macroptilium atropurpureum']),
  PastureTypeOption('Sorgo forrajero', aliases: ['Sorghum bicolor']),
  PastureTypeOption('Sorgo Sudán', aliases: ['Sorghum sudanense']),
  PastureTypeOption(
    'Stylosanthes',
    aliases: ['Estilosantes', 'Stylosanthes spp.'],
  ),
  PastureTypeOption('Stylosanthes capitata'),
  PastureTypeOption('Stylosanthes guianensis'),
  PastureTypeOption('Stylosanthes macrocephala'),
  PastureTypeOption(
    'Tanzania',
    aliases: [
      'Tanzânia',
      'Panicum maximum cv. Tanzania',
      'Megathyrsus maximus cv. Tanzania',
    ],
  ),
  PastureTypeOption(
    'Tifton 85',
    aliases: ['Tifton85', 'Cynodon híbrido Tifton 85'],
  ),
  PastureTypeOption(
    'Tobiatã',
    aliases: ['Panicum maximum cv. Tobiata', 'Megathyrsus maximus cv. Tobiata'],
  ),
  PastureTypeOption(
    'Trébol alejandrino',
    aliases: ['Trifolium alexandrinum', 'Berseem'],
  ),
  PastureTypeOption('Trébol blanco', aliases: ['Trifolium repens']),
  PastureTypeOption('Trébol persa', aliases: ['Trifolium resupinatum']),
  PastureTypeOption('Trébol rojo', aliases: ['Trifolium pratense']),
  PastureTypeOption('Trébol subterráneo', aliases: ['Trifolium subterraneum']),
  PastureTypeOption('Trigo forrajero', aliases: ['Triticum aestivum']),
  PastureTypeOption('Triticale', aliases: ['Triticosecale']),
  PastureTypeOption(
    'Tully',
    aliases: [
      'Brachiaria humidicola cv. Tully',
      'Urochloa humidicola cv. Tully',
    ],
  ),
  PastureTypeOption('Vicia común', aliases: ['Vicia sativa']),
  PastureTypeOption('Vicia vellosa', aliases: ['Vicia villosa']),
  PastureTypeOption('Werneria'),
  // Toledo and Xaraés name the same CIAT 26110 accession; retain both search names.
  PastureTypeOption(
    'Xaraés',
    aliases: [
      'Xaraes',
      'Toledo',
      'Brachiaria brizantha cv. Xaraes',
      'Urochloa brizantha cv. Xaraes',
      'Brachiaria brizantha cv. Toledo',
      'Urochloa brizantha cv. Toledo',
    ],
  ),
  PastureTypeOption(
    'Zuri',
    aliases: [
      'BRS Zuri',
      'Panicum maximum cv. Zuri',
      'Megathyrsus maximus cv. Zuri',
    ],
  ),
];
