// lib/features/fun/domain/rire_data.dart
//
// Catalogue « Coffres d'étoiles » : blagues et devinettes ORIGINALES
// écrites pour MonTotem. Style de comédie courte qui fait rire partout :
// punchline en 2 lignes, folklore scolaire « Toto », devinettes à réponse
// évidente. Ton famille — les plus petits peuvent répondre aux devinettes
// de niveau « enfant ».

/// Type de contenu d'un coffre.
enum RireType { blague, devinette }

/// Public conseillé.
enum RireNiveau { enfant, grand }

/// Un élément de rire : blague courte ou devinette question/réponse.
class ItemRire {
  const ItemRire(
    this.id,
    this.type,
    this.categorie,
    this.avant,
    this.reponse, {
    this.motsAcceptes = const <String>[],
    this.niveau = RireNiveau.grand,
  });

  /// Identifiant stable (pour ne pas retomber deux fois sur le même).
  final String id;
  final RireType type;

  /// Catégorie : École, Zémidjan, Animaux, Loufoque, Futé.
  final String categorie;

  /// Question de devinette, ou début de blague.
  final String avant;

  /// Réponse de la devinette, ou chute.
  final String reponse;

  /// Devinette : un de ces mots (minuscules, sans accents) valide la
  /// réponse du joueur. Vide pour une blague.
  final List<String> motsAcceptes;

  final RireNiveau niveau;

  String get etiquette => type == RireType.devinette ? 'Devinette' : 'Blague';
}

const List<ItemRire> kItemsRire = <ItemRire>[
  // ── École (folklore « Toto », saveur MonTotem) ──────────────────────
  ItemRire(
    'b001', RireType.blague, 'École',
    'La maîtresse : « Toto, fais une phrase avec « bientôt ». »\nToto : « L\'inspecteur arrive bientôt, il faut courir ! »',
    'Le plan de révision, lui, est resté assis.',
  ),
  ItemRire(
    'b002', RireType.blague, 'École',
    'La maîtresse : « Qui a inventé la lampe qui éclaire le monde ? »\nToto : « Mon papa, madame. Sans sa lampe torche, je ne retrouve jamais mon cahier. »',
    'La maîtresse a arrêté de poser des questions d\'inventeurs.',
  ),
  ItemRire(
    'b003', RireType.blague, 'École',
    'Toto : « Madame, on est puni pour quelque chose qu\'on n\'a pas fait ? »\nLa maîtresse : « Non, bien sûr que non. »',
    'Toto : « Tant mieux, madame : je n\'ai pas fait mes devoirs. »',
  ),
  ItemRire(
    'b004', RireType.blague, 'École',
    'Le maître : « Toto, donne deux exemples de transport lent. »\nToto : « La pirogue quand le vent tourne le dos… et moi quand il faut aller à l\'école. »',
    'Toute la classe a applaudi la franchise.',
  ),
  ItemRire(
    'b005', RireType.blague, 'École',
    'Maman : « Toto, arrête de courir après le chien, va réviser ! »\nToto : « C\'est une leçon de course, maman : s\'il me rattrape, c\'est lui qui a bien révisé. »',
    'Maman a renoncé à comprendre le programme.',
  ),
  ItemRire(
    'b006', RireType.blague, 'École',
    'Papa : « Combien font deux et deux ? »\nToto : « Je garde la réponse pour le prochain contrôle, papa. »',
    'Papa : « Et le devoir de ce soir ? » Toto : « Il sera livré en retard. »',
  ),
  ItemRire(
    'b007', RireType.blague, 'École',
    'La maîtresse : « Toto, où sont tes cahiers ? »\nToto : « En sécurité, madame. Mon cousin les garde chez lui. »',
    'Le cousin, lui, n\'a rien demandé.',
  ),
  ItemRire(
    'b008', RireType.blague, 'École',
    'La maîtresse : « Toto, montre-moi le Bénin sur la carte. »\nToto : « Le voilà, madame. Il n\'a pas bougé depuis hier. »',
    'La géographie a remercié la précision.',
  ),
  ItemRire(
    'b009', RireType.blague, 'École',
    'La maîtresse : « Si 3 poules pondent 3 œufs en 3 jours, combien en pondent 6 poules ? »\nToto : « Aucune, madame : les 3 premières gardent les nids. »',
    'La maîtresse n\'a pas osé contester la poule.',
  ),
  ItemRire(
    'b010', RireType.blague, 'École',
    'La maîtresse : « Toto, récite ta leçon ! »\nToto : « Je connais tout par cœur, madame. »\nLa maîtresse : « Alors récite ! »',
    'Toto : « C\'est ça le problème : mon cœur est sorti en récré. »',
  ),
  ItemRire(
    'b011', RireType.blague, 'École',
    'Toto, très fier : « Papa ! Je suis le seul à ne pas avoir eu zéro au devoir ! »\nPapa : « Il a dit quoi, ton maître ? »',
    '« Mathieu zéro, Kofi zéro, Ama zéro… et Toto : idem ! »',
  ),
  ItemRire(
    'b012', RireType.blague, 'École',
    'La maîtresse : « Toto, ferme la fenêtre, il y a un courant d\'air ! »\nToto : « Impossible, madame : l\'électricité n\'est pas passée aujourd\'hui. »',
    'La classe a ri, la fenêtre aussi.',
  ),
  // ── Zémidjan / route ────────────────────────────────────────────────
  ItemRire(
    'z001', RireType.blague, 'Zémidjan',
    'Le client : « Zem, tu connais un raccourci ? »\nLe zémidjan : « Oui, moi oui. Toi, tu vas te perdre. »',
    'Le client est arrivé par le raccourci… du zémidjan.',
  ),
  ItemRire(
    'z002', RireType.blague, 'Zémidjan',
    'Le passager : « Deux cents ? Tu me prends pour un riche ? »\nLe zem : « Non. Un passager avec deux mains dans ses poches. »',
    'Les poches ont confirmé : vide.',
  ),
  ItemRire(
    'z003', RireType.blague, 'Zémidjan',
    'Le client : « Pourquoi klaxonner ? Il n\'y a personne ! »\nLe zem : « On salue le silence : c\'est lui qui a la priorité ici. »',
    'Le silence, vexé, n\'a pas répondu.',
  ),
  ItemRire(
    'z004', RireType.blague, 'Zémidjan',
    'Un kloboto chargé de sacs s\'arrête. Un corbeau observe. Un sac tombe.\nLe conducteur : « Heureux, hein ? »',
    'Le corbeau s\'envole : trop de respect pour un collègue en carrosserie jaune.',
  ),
  ItemRire(
    'z005', RireType.blague, 'Zémidjan',
    'Le client : « Tu peux rouler plus vite ? »\nLe zem : « Le pneu de secours est encore à la maison. Au moindre souci, on finit à pied. »',
    'Le client a redéfini sa notion de « vite ».',
  ),
  ItemRire(
    'z006', RireType.blague, 'Zémidjan',
    'Un touriste : « Ta moto, c\'est quelle marque ? »\nLe zem : « Demande au bonhomme du carrefour, c\'est lui qui connaît son prénom. »',
    'La moto a gardé son mystère — et sa réputation.',
  ),
  ItemRire(
    'z007', RireType.blague, 'Zémidjan',
    'Le client : « Tu es sûr de connaître ce quartier ? »\nLe zem : « Peut-être. Si on tombe sur une impasse, on dira qu\'elle nous attendait. »',
    'Le quartier a joué la diversion.',
  ),
  ItemRire(
    'z008', RireType.blague, 'Zémidjan',
    'Le passager : « Première fois que je prends un cloboto ! »\nLe conducteur : « Nous aussi, c\'est la première fois que ce cloboto va dans ce sens. »',
    'Le cloboto a choisi la pente sans consulter.',
  ),
  ItemRire(
    'z009', RireType.blague, 'Zémidjan',
    'Le client : « Tu vas m\'attendre au marché ? »\nLe zem : « Bien sûr. Le marché aussi m\'attend : j\'y ai laissé ma monnaie. »',
    'Deux bazars plus tard, tout le monde était d\'accord.',
  ),
  ItemRire(
    'z010', RireType.blague, 'Zémidjan',
    'Le client : « Zem, tu connais la musique ? »\nLe zem : « Oui : elle s\'appelle moto et elle chante chaque matin à 5 h. »',
    'Le voisinage connaît le refrain par cœur.',
  ),
  // ── Animaux ────────────────────────────────────────────────────────────
  ItemRire(
    'a001', RireType.blague, 'Animaux',
    'Le lézard du mur a tout vu, tout entendu, tout su.',
    'Mais il ne témoigne jamais : il lâche la queue et il s\'enfuit avant la question suivante.',
  ),
  ItemRire(
    'a002', RireType.blague, 'Animaux',
    'La chèvre : « Je ne mange que l\'herbe du champ, je te jure. »\nLe champ : « Et mon linge étendu, c\'était de l\'herbe ? »',
    'Elle a avalé l\'excuse en même temps que la chemise.',
  ),
  ItemRire(
    'a003', RireType.blague, 'Animaux',
    'Deux poules discutent. La première : « On dit que le maïs tombe du ciel. »\nLa deuxième lève les yeux vers le grenier.',
    '« Alors le ciel a un toit ? » Elle a arrêté de croire ce jour-là.',
  ),
  ItemRire(
    'a004', RireType.blague, 'Animaux',
    'Le chat dort dix heures sur le canapé, puis réclame du poisson frais.',
    'Sa défense : « Je ne dormais pas, je gardais le canapé pendant qu\'il ne bougeait pas. »',
  ),
  ItemRire(
    'a005', RireType.blague, 'Animaux',
    'Le mouton compte les humains qui passent pour s\'endormir.',
    'À trois cents, il a abandonné : sur cette route, la nuit ne se vide jamais vraiment.',
  ),
  ItemRire(
    'a006', RireType.blague, 'Animaux',
    'Le margouillat reste collé au mur chaud toute l\'après-midi, sans bouger.',
    'Lui, il appelle ça un jacuzzi gratuit. Le mur n\'a rien dit : il est d\'accord.',
  ),
  ItemRire(
    'a007', RireType.blague, 'Animaux',
    'Un pigeon traverse le carrefour sans regarder. Le zém freine, klaxonne, parle tout seul.',
    'Le pigeon claque des ailes : « Tranquille. Ici, c\'est moi l\'ancien. »',
  ),
  ItemRire(
    'a008', RireType.blague, 'Animaux',
    'Le chien aboie toute la nuit. Le quartier dit qu\'il protège le quartier.',
    'En vérité, il répond à son propre écho : lui aussi, la nuit, il a besoin de parler.',
  ),
  ItemRire(
    'a009', RireType.blague, 'Animaux',
    'Le chef des fourmis crie : « En avant pour le maïs ! » et se met la main sur la hanche.',
    'Il n\'a rien porté, mais c\'est lui qui signe toutes les photos.',
  ),
  ItemRire(
    'a010', RireType.blague, 'Animaux',
    'Le perroquet du marché a appris un mot nouveau chaque jour de la semaine.',
    'Le dimanche, il récite tout le marché d\'un seul souffle — disputes comprises.',
  ),
  ItemRire(
    'a011', RireType.blague, 'Animaux',
    'Le crapaud traverse sans se mouiller : trois flaques, trois sauts, aucune goutte.',
    'La flaque a demandé pourquoi. « Pour l\'exercice », il a répondu.',
  ),
  ItemRire(
    'a012', RireType.blague, 'Animaux',
    'L\'âne braie chaque matin à cinq heures, à la seconde près.',
    '« Debout ! Le foin ne se mangera pas tout seul pendant que vous dormez. »',
  ),
  ItemRire(
    'a013', RireType.blague, 'Animaux',
    'Le poisson du marché raconte qu\'il a nagé très, très loin avant d\'arriver là.',
    'Il a fini dans le même bassine que les autres : au marché, on ne discute pas les distances.',
  ),
  ItemRire(
    'a014', RireType.blague, 'Animaux',
    'La poule picore déjà dans la cour avant même le lever du soleil.',
    'Elle n\'a jamais lu le mot « grasse matinée » : elle est sa propre horloge.',
  ),
  // ── Loufoque (jeux de mots) ────────────────────────────────────────────
  ItemRire(
    'l001', RireType.blague, 'Loufoque',
    'Pourquoi le marteau gagne toujours les débats ?',
    'Parce qu\'il clou le bec à tout le monde.',
  ),
  ItemRire(
    'l002', RireType.blague, 'Loufoque',
    'Pourquoi le réfrigérateur ne s\'énerve jamais ?',
    'Parce qu\'il garde toujours la tête froide.',
  ),
  ItemRire(
    'l003', RireType.blague, 'Loufoque',
    'Pourquoi la pendule est arrivée dernière à la grande course ?',
    'Parce qu\'elle a commencé par se donner le temps.',
  ),
  ItemRire(
    'l004', RireType.blague, 'Loufoque',
    'Que fait la porte quand elle est vraiment en colère ?',
    'Elle claque la porte, évidemment.',
  ),
  ItemRire(
    'l005', RireType.blague, 'Loufoque',
    'Pourquoi le parapluie rit quand il pleut ?',
    'C\'est le seul moment où tout le monde le trouve important.',
  ),
  ItemRire(
    'l006', RireType.blague, 'Loufoque',
    'Pourquoi le cahier est toujours en paix avec tous ?',
    'Parce qu\'il règle les problèmes ligne par ligne.',
  ),
  ItemRire(
    'l007', RireType.blague, 'Loufoque',
    'Pourquoi la tomate a-t-elle rougi au repas ?',
    'Elle a vu la salade se déshabiller.',
  ),
  ItemRire(
    'l008', RireType.blague, 'Loufoque',
    'L\'escargot s\'est inscrit à la course de quartier. On lui a demandé pourquoi.',
    '« Je ne suis pas lent : c\'est ma maison qui est lourde de souvenirs. »',
  ),
  ItemRire(
    'l009', RireType.blague, 'Loufoque',
    'Pourquoi le poisson ne joue jamais à se cacher ?',
    'Dès qu\'il ouvre la bouche, les bulles le dénoncent.',
  ),
  ItemRire(
    'l010', RireType.blague, 'Loufoque',
    'Quel est le comble pour un œuf ?',
    'Se prendre au sérieux avant même d\'être cuit.',
  ),
  ItemRire(
    'l011', RireType.blague, 'Loufoque',
    'Pourquoi la poêle connaît toutes les nouvelles du quartier ?',
    'Le matin, tout ce qui frit finit chez elle.',
  ),
  ItemRire(
    'l012', RireType.blague, 'Loufoque',
    'Le maïs du grillot raconte toujours la même histoire.',
    'Dès qu\'il chauffe, il éclate — et tout le quartier écoute.',
  ),
  // ── Futé (mini-récits) ─────────────────────────────────────────────────
  ItemRire(
    'f001', RireType.blague, 'Futé',
    'Un client monte et dit : « Vite, vite, mon neveu a besoin de toi ! »\nLe zém roule comme le vent, casque et klaxon.',
    'Ils sont arrivés… chez le coiffeur. Le neveu avait une photo demain matin.',
  ),
  ItemRire(
    'f002', RireType.blague, 'Futé',
    'Le kloboto livre un pot de sauce pimentée. Le client goûte sur place et tousse.',
    '« C\'est vraiment le piment promis. » Puis il a commandé deux pots pour sa voisine.',
  ),
  ItemRire(
    'f003', RireType.blague, 'Futé',
    'La station essence ouvre à cinq heures. Le premier client arrive en moto et dit : « Le plein. »',
    'Ensuite il a demandé si le café était prêt. C\'était le gérant lui-même.',
  ),
  ItemRire(
    'f004', RireType.blague, 'Futé',
    'Le chauffeur d\'eau porte un bidon de vingt litres sur la tête, trois étages, sans souffler.',
    'En haut, il a demandé la seule chose qui compte : « C\'est tout, ou tu en veux deux ? »',
  ),
  ItemRire(
    'f005', RireType.blague, 'Futé',
    'Le mécanicien écoute le moteur trois secondes sans rien dire.',
    '« Ce n\'est pas le moteur que j\'ai entendu. C\'est ton portefeuille qui pleure un peu. »',
  ),
  ItemRire(
    'f006', RireType.blague, 'Futé',
    'Le client : « Tu me répare la roue en dix minutes ? »\nLe vulcanisateur : « Dix minutes, oui — mais d\'abord, laisse-moi finir mon thé paisiblement. »',
    'La roue a très bien imité le thé : elle aussi a pris son temps.',
  ),
  ItemRire(
    'f007', RireType.blague, 'Futé',
    'Un passager ouvre la négociation : « Tu me prends deux cents ? »\nLe conducteur : « Deux cents, c\'est pour la moto. Moi, je suis en plus. »',
    'Les deux cents ont payé la moto. Le conducteur marchait derrière.',
  ),
  ItemRire(
    'f008', RireType.blague, 'Futé',
    'Le garçon de garage compte les outils après le travail : il en manque un.',
    'Le propriétaire a retrouvé la clé à molette dans sa propre poche. Le garçon n\'a rien dit pendant une semaine.',
  ),
  ItemRire(
    'f009', RireType.blague, 'Futé',
    'Le voisin demande au conducteur du tricycle fret pourquoi il prend toujours la longue route.',
    '« La longue route, elle est fatigante. Mais elle aussi est fatiguée — donc on se comprend. »',
  ),
  ItemRire(
    'f010', RireType.blague, 'Futé',
    'Un client oublie son téléphone dans le transport. Le zem roule comme s\'il était suivi.',
    'Deux rues plus loin, il fait demi-tour sous la pluie et rend le téléphone. La pluie n\'a rien dit, mais elle a applaudi.',
  ),
  // ── Devinettes « enfants » (réponse facile à taper) ───────────────────
  ItemRire(
    'd001', RireType.devinette, 'Enfants',
    'Je suis jaune, je roule dans les rues de Cotonou et je porte un passager derrière un casque. Qui suis-je ?',
    'Le zémidjan ! On l\'appelle aussi zem, ou moto-taxi.',
    motsAcceptes: <String>['zem', 'moto', 'zemidjan'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd002', RireType.devinette, 'Enfants',
    'Je suis blanc, je viens de la poule et on me mange au petit-déjeuner. Qui suis-je ?',
    'L\'œuf !',
    motsAcceptes: <String>['oeuf', 'un oeuf', 'l oeuf'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd003', RireType.devinette, 'Enfants',
    'J\'ai plein de trous, mais je retiens l\'eau du seau. Qui suis-je ?',
    'L\'éponge !',
    motsAcceptes: <String>['eponge', 'l eponge', 'une eponge'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd004', RireType.devinette, 'Enfants',
    'J\'ai des dents partout et pourtant je ne mâche rien. Qui suis-je ?',
    'Le peigne !',
    motsAcceptes: <String>['peigne', 'un peigne', 'le peigne'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd005', RireType.devinette, 'Enfants',
    'Plus on m\'enlève de la terre, plus je deviens grand. Qui suis-je ?',
    'Le trou !',
    motsAcceptes: <String>['trou', 'un trou', 'le trou'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd006', RireType.devinette, 'Enfants',
    'J\'ai des marches et je te fais monter et descendre sans bouger de ma place. Qui suis-je ?',
    'L\'escalier !',
    motsAcceptes: <String>['escalier', 'l escalier', 'un escalier'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd007', RireType.devinette, 'Enfants',
    'Plus je suis chaud, plus je suis frais. On me mange au petit-déjeuner. Qui suis-je ?',
    'Le pain !',
    motsAcceptes: <String>['pain', 'le pain', 'un pain'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd008', RireType.devinette, 'Enfants',
    'Grâce à moi la maison est propre, mais c\'est moi qui finis sale. Qui suis-je ?',
    'Le balai (ou la serpillière) !',
    motsAcceptes: <String>['balai', 'le balai', 'serpilliere', 'la serpilliere'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd009', RireType.devinette, 'Enfants',
    'Je brille dans le ciel la nuit et je change de forme chaque soir. Qui suis-je ?',
    'La lune !',
    motsAcceptes: <String>['lune', 'la lune'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd010', RireType.devinette, 'Enfants',
    'J\'ai un long cou mais pas de tête, et on me secoue pour me faire parler. Qui suis-je ?',
    'La bouteille !',
    motsAcceptes: <String>['bouteille', 'la bouteille', 'une bouteille'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd011', RireType.devinette, 'Enfants',
    'Le matin, les enfants me remplissent de cahiers et me portent à l\'école. Qui suis-je ?',
    'Le cartable !',
    motsAcceptes: <String>['cartable', 'le cartable', 'sac a dos', 'sac'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd012', RireType.devinette, 'Enfants',
    'Je pousse sans arrêt, on me coupe régulièrement, et ça ne fait jamais mal. Qui suis-je ?',
    'Les cheveux !',
    motsAcceptes: <String>['cheveux', 'cheveu', 'les cheveux'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd013', RireType.devinette, 'Enfants',
    'Je tombe du ciel et j\'arrose toute la ville, sans jamais me faire mal. Qui suis-je ?',
    'La pluie !',
    motsAcceptes: <String>['pluie', 'la pluie', 'l eau de pluie'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd014', RireType.devinette, 'Enfants',
    'Je suis la maison que l\'escargot promène partout sur son dos. Qui suis-je ?',
    'La coquille !',
    motsAcceptes: <String>['coquille', 'la coquille', 'sa coquille'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd015', RireType.devinette, 'Enfants',
    'Je pousse au champ, je passe au feu du grillot et j\'éclate. Qui suis-je ?',
    'Le maïs !',
    motsAcceptes: <String>['mais', 'le mais', 'epi de mais', 'epi'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd016', RireType.devinette, 'Enfants',
    'Je grossis quand il pleut et les enfants sautent autour de moi. Qui suis-je ?',
    'La flaque d\'eau !',
    motsAcceptes: <String>['flaque', 'la flaque', 'flaque d eau', 'eau'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd017', RireType.devinette, 'Enfants',
    'J\'ai quatre roues, un compteur et un klaxon : dis-moi où tu vas et j\'y conduis. Qui suis-je ?',
    'Le taxi !',
    motsAcceptes: <String>['taxi', 'le taxi', 'un taxi'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd018', RireType.devinette, 'Enfants',
    'J\'ai un très long nez (on dit une trompe) et des grandes oreilles. Qui suis-je ?',
    'L\'éléphant !',
    motsAcceptes: <String>['elephant', 'l elephant', 'un elephant'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd019', RireType.devinette, 'Enfants',
    'Je nage toute la journée et je finis trop souvent frit ou braisé. Qui suis-je ?',
    'Le poisson !',
    motsAcceptes: <String>['poisson', 'le poisson', 'un poisson'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd020', RireType.devinette, 'Enfants',
    'Je suis tout petit, très fort en goût, et je fais tomber les larmes. Qui suis-je ?',
    'Le piment !',
    motsAcceptes: <String>['piment', 'le piment', 'un piment'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd021', RireType.devinette, 'Enfants',
    'Je suis ronde, j\'ai de l\'eau douce dedans et je tombe du palmier. Qui suis-je ?',
    'La noix de coco !',
    motsAcceptes: <String>['coco', 'noix de coco', 'la noix de coco', 'noix'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd022', RireType.devinette, 'Enfants',
    'On m\'ouvre seulement quand le ciel dégouline ; sinon, je dors dans le coin. Qui suis-je ?',
    'Le parapluie !',
    motsAcceptes: <String>['parapluie', 'un parapluie', 'le parapluie'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd023', RireType.devinette, 'Enfants',
    'Toto pose la question : « Mon papa a trois fils. Le premier s\'appelle Kofi, le deuxième Koku. Comment s\'appelle le troisième ? »',
    'Toto ! C\'est Toto lui-même qui parle.',
    motsAcceptes: <String>['toto'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd024', RireType.devinette, 'Enfants',
    'Je suis noir, et pourtant je rends tout blanc à chaque leçon. Qui suis-je ?',
    'Le tableau !',
    motsAcceptes: <String>['tableau', 'le tableau', 'tableau noir', 'ardoise', 'l ardoise'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd025', RireType.devinette, 'Enfants',
    'J\'ai des oreilles qui écoutent le vent, mais je n\'entends rien du tout. Qui suis-je ?',
    'L\'épi de maïs !',
    motsAcceptes: <String>['epi', 'epi de mais', 'l epi'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd026', RireType.devinette, 'Enfants',
    'Le soir, je remplis toute la pièce sans peser presque rien. Qui suis-je ?',
    'La lumière !',
    motsAcceptes: <String>['lumiere', 'la lumiere', 'l ampoule', 'ampoule'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd027', RireType.devinette, 'Enfants',
    'Je monte très haut sans ailes et on me perd de vue. Qui suis-je ?',
    'La fumée !',
    motsAcceptes: <String>['fumee', 'la fumee'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd028', RireType.devinette, 'Enfants',
    'On me lance dans l\'eau juste pour me ramasser après. Qui suis-je ?',
    'Le filet de pêche !',
    motsAcceptes: <String>['filet', 'le filet', 'filet de peche'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd029', RireType.devinette, 'Enfants',
    'Je pleure sans avoir d\'yeux, je change d\'humeur et je vole sans ailes. Qui suis-je ?',
    'Le nuage !',
    motsAcceptes: <String>['nuage', 'le nuage', 'un nuage'],
    niveau: RireNiveau.enfant,
  ),
  ItemRire(
    'd030', RireType.devinette, 'Enfants',
    'Chaque matin je me lève avec tout le monde, mais personne ne peut me regarder longtemps dans les yeux. Qui suis-je ?',
    'Le soleil !',
    motsAcceptes: <String>['soleil', 'le soleil'],
    niveau: RireNiveau.enfant,
  ),
  // ── Devinettes « grands » : un peu plus réfléchies ────────────────
  ItemRire(
    'g001', RireType.devinette, 'Futé',
    'J\'ai des villes sans maisons, des forêts sans arbres et des rivières sans eau. Qui suis-je ?',
    'Une carte ! Bien joué en géographie.',
    motsAcceptes: <String>['carte', 'la carte', 'une carte', 'plan', 'le plan'],
  ),
  ItemRire(
    'g002', RireType.devinette, 'Futé',
    'Je te montre le monde entier sans que tu quittes ta table. Qui suis-je ?',
    'L\'écran ! Télévision ou téléphone, on accepte tout ce qui éclaire un écran.',
    motsAcceptes: <String>[
      'television', 'tele', 'tv', 'telephone', 'portable', 'ecran', 'l ecran',
    ],
  ),
  ItemRire(
    'g003', RireType.devinette, 'Futé',
    'Un papa a sept filles, et chacune de ses filles a un frère. Combien de filles et de garçons au total ?',
    'Huit enfants : sept filles et un seul frère commun aux sept.',
    motsAcceptes: <String>['huit', '8', 'huit enfants'],
  ),
  ItemRire(
    'g004', RireType.devinette, 'Futé',
    'Un grand-père, son fils et son petit-fils pêchent ensemble. Chacun attrape un poisson — et pourtant il n\'y a que deux pères et deux fils. Comment ?',
    'Il n\'y a que trois personnes : le père est à la fois fils du grand-père et père du petit-fils.',
    motsAcceptes: <String>['trois', '3', 'trois personnes'],
  ),
  ItemRire(
    'g005', RireType.devinette, 'Futé',
    'Je fais le tour du monde entier tout en restant collé au même coin. Qui suis-je ?',
    'Le timbre !',
    motsAcceptes: <String>['timbre', 'le timbre', 'un timbre'],
  ),
  ItemRire(
    'g006', RireType.devinette, 'Futé',
    'Je suis à toi, mais tout le monde s\'en sert bien plus que toi. Qui suis-je ?',
    'Ton prénom ! (Ton nom, on accepte aussi.)',
    motsAcceptes: <String>['prenom', 'nom', 'mon prenom', 'mon nom', 'votre prenom', 'le prenom'],
  ),
  ItemRire(
    'g007', RireType.devinette, 'Futé',
    'Je suis toujours devant toi, mais personne n\'a jamais réussi à me voir. Qui suis-je ?',
    'L\'avenir !',
    motsAcceptes: <String>['avenir', 'futur', 'l avenir', 'le futur'],
  ),
  ItemRire(
    'g008', RireType.devinette, 'Futé',
    'Tu cries vers moi, je renvoie exactement pareil. Je n\'ai ni bouche ni oreilles. Qui suis-je ?',
    'L\'écho !',
    motsAcceptes: <String>['echo', 'l echo', 'un echo'],
  ),
  ItemRire(
    'g009', RireType.devinette, 'Futé',
    'Tout le monde m\'attend, et pourtant je n\'arrive jamais vraiment. Qui suis-je ?',
    'Demain !',
    motsAcceptes: <String>['demain', 'lendemain'],
  ),
  ItemRire(
    'g010', RireType.devinette, 'Futé',
    'Je t\'accompagne partout sous le soleil, mais je disparais dès que la nuit tombe. Qui suis-je ?',
    'Ton ombre !',
    motsAcceptes: <String>['ombre', 'l ombre', 'mon ombre', 'ton ombre', 'une ombre'],
  ),
  ItemRire(
    'g011', RireType.devinette, 'Futé',
    'J\'ai des branches toute l\'année, mais jamais de fruits ni de feuilles. Qui suis-je ?',
    'La banque !',
    motsAcceptes: <String>['banque', 'la banque', 'une banque'],
  ),
  ItemRire(
    'g012', RireType.devinette, 'Futé',
    'J\'ai beaucoup de touches, mais pas une seule porte. Qui suis-je ?',
    'Le piano ! (Le clavier a aussi des touches : on accepte.)',
    motsAcceptes: <String>['piano', 'clavier', 'le piano', 'un clavier'],
  ),
  ItemRire(
    'g013', RireType.devinette, 'Futé',
    'J\'ai un chapeau mais aucune tête, et je pousse après la pluie. Qui suis-je ?',
    'Le champignon !',
    motsAcceptes: <String>['champignon', 'le champignon', 'un champignon'],
  ),
  ItemRire(
    'g014', RireType.devinette, 'Futé',
    'Le soir je suis plein, le matin je suis vide — et personne ne m\'en veut. Qui suis-je ?',
    'L\'assiette !',
    motsAcceptes: <String>['assiette', 'l assiette', 'une assiette'],
  ),
  ItemRire(
    'g015', RireType.devinette, 'Futé',
    'Pourquoi le poulet traverse la grand-route à côté de Cotonou ?',
    'Pour aller de l\'autre côté ! (La chute la plus ancienne du monde.)',
    motsAcceptes: <String>['autre cote', 'de l autre cote', 'l autre cote', 'traverser'],
  ),
  ItemRire(
    'g016', RireType.devinette, 'Futé',
    'Tout le monde me traverse, et pourtant je ne couche personne. Qui suis-je ?',
    'Le pont !',
    motsAcceptes: <String>['pont', 'le pont', 'un pont'],
  ),
  ItemRire(
    'g017', RireType.devinette, 'Futé',
    'Plus il y en a de moi, moins on voit quelque chose. Qui suis-je ?',
    'L\'obscurité !',
    motsAcceptes: <String>['obscurite', 'l obscurite', 'tenebres', 'noir', 'le noir'],
  ),
  ItemRire(
    'g018', RireType.devinette, 'Futé',
    'Tu peux me casser sans me toucher : juste en parlant. Qui suis-je ?',
    'Le silence !',
    motsAcceptes: <String>['silence', 'le silence', 'un silence'],
  ),
  ItemRire(
    'g019', RireType.devinette, 'Futé',
    'J\'ai une tête et une queue, mais aucun corps. Qui suis-je ?',
    'La pièce de monnaie !',
    motsAcceptes: <String>['piece de monnaie', 'monnaie', 'la piece', 'piece'],
  ),
  ItemRire(
    'g020', RireType.devinette, 'Futé',
    'J\'ai deux aiguilles qui tournent toute la journée sans jamais piquer. Qui suis-je ?',
    'L\'horloge !',
    motsAcceptes: <String>['horloge', 'l horloge', 'une horloge', 'pendule', 'la pendule', 'montre', 'la montre'],
  ),
];

/// Tire [n] éléments au hasard, en évitant au maximum ceux déjà vus.
/// Si tout le catalogue a été vu, on re-pioche dans les anciens.
List<ItemRire> tirerItems(int n, Set<String> dejaVus) {
  final melangees = List<ItemRire>.of(kItemsRire)..shuffle();
  final fraiches = <ItemRire>[];
  final dejaVues = <ItemRire>[];
  for (final item in melangees) {
    if (dejaVus.contains(item.id)) {
      dejaVues.add(item);
    } else {
      fraiches.add(item);
    }
  }
  final choisies = fraiches.take(n).toList();
  for (final item in dejaVues) {
    if (choisies.length >= n) break;
    choisies.add(item);
  }
  return choisies;
}
