# Sources et attributions

Les décisions de routage Git et les scénarios de régression se réfèrent au checkout local de **RTK 0.49.0**, `Rust/rtk/src/cmds/git/git_cmd.rs`, Copyright RTK AI Labs, sous Apache License 2.0. La licence est conservée dans `licenses/RTK.Apache-2.0.txt`. Les empreintes et les quatorze commandes spécialisées inspectées sont dans `provenance/git-source.json`.

Cette adaptation remplace les captures complètes des wrappers RTK par des parsers de records en flux et des objets métier. Les formats explicitement demandés ne sont pas confondus avec les formats par défaut. Les valeurs d’options et les séparateurs sont analysés par la grammaire Git. Le type d’un objet `show` est demandé à Git, sans supposer qu’une expression avec deux-points désigne forcément un blob.

Aucun code de `rtk-engine` n’est copié ou lié. Ce composant possède une licence distincte de celle de l’enveloppe CLI et n’est pas une dépendance de QuietCli2.

Le parseur porcelain initial, le tokenizer d’arguments et les métadonnées Git proviennent également du module FrenchExDev QuietCli Git précédent. Les transports et l’adaptateur SQLite du moteur proviennent de QuietCli Core précédent. Leurs fichiers restent préservés ; les adaptations résident dans les nouveaux dépôts.

Les fixtures RTK adaptées sont conservées uniquement dans le module de tests compagnon, avec leur provenance propre. Aucun résultat des nouveaux parsers n’est utilisé pour fabriquer les attentes de ces tests.
