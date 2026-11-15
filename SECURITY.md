# Politique de sécurité

*English: please report security issues privately, never in a public issue. See below.*

RettApp traite des données de santé d'enfants. Une faille y est prise au sérieux, et
la manière de la signaler compte.

## Signaler une vulnérabilité

**N'ouvrez pas d'*issue* publique** et ne publiez pas de détail technique avant
qu'un correctif existe.

- Si l'onglet **Security** de ce dépôt propose « Report a vulnerability », utilisez-le.
- Sinon, écrivez à **contact@afsr.fr** avec l'objet « Sécurité RettApp ».

Indiquez la version de l'application, le matériel (iPhone, iOS), les étapes pour
reproduire, et l'effet constaté. **N'incluez jamais de données réelles** d'un enfant
ou d'une famille : un exemple fabriqué suffit.

L'AFSR est une association : aucun délai de réponse n'est garanti.

## Périmètre

| Concerné | Où |
|---|---|
| L'application iOS | Ce dépôt |
| Le site afsr.fr, l'API de l'espace adhérent, l'annuaire des lieux | Dépôt `AFSR/website` — même canal de signalement |

## Ce qui n'est pas une faille

Ces points sont connus et décrits dans [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) :

- **Le jeton qui identifie l'application auprès du site est extractible du binaire.**
  C'est assumé : il filtre le bruit, il ne garantit pas qui appelle. La protection
  réelle est côté serveur.
- **L'association n'a pas accès aux données de suivi** et ne peut donc ni les lire
  ni les effacer : elles restent sur l'appareil et dans l'iCloud de la famille.

Si vous trouvez un moyen de faire sortir ces données de l'appareil, ou de lire le
texte des avis sans être adhérent à jour de cotisation, **c'est en revanche une
faille**.

## Versions concernées

La dernière version publiée sur l'App Store.

## Audit

L'audit de sécurité du code, avec ses limites et ses points ouverts, est dans
[`docs/AUDIT_SECURITE.md`](docs/AUDIT_SECURITE.md).
