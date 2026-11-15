import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
// `@preconcurrency` : Vision est antérieur à la concurrence stricte, et ses
// types (`VNImageRequestHandler`, `VNDetectBarcodesRequest`) ne sont pas
// déclarés `Sendable` alors qu'ils traversent une closure `@Sendable`. C'est la
// suppression que recommande le compilateur ; elle ne change rien à
// l'exécution, la détection restant confinée à une seule tâche.
@preconcurrency import Vision

/// Génération + détection du QR code intégré au cahier de suivi.
///
/// **Génération** : `BookletQR.image(for: schema, size:)` produit un `UIImage`
/// contenant le payload JSON du schéma.
///
/// **Détection** : `BookletQR.detect(in: image)` utilise Vision
/// (`VNDetectBarcodesRequest`) pour trouver le QR et son cadre dans l'image
/// scannée — la position du QR sert d'ancrage pour calculer toutes les
/// positions des cases à cocher.
enum BookletQR {

    // MARK: - Generation

    /// Finesse du QR dans le PDF, en pixels par point.
    ///
    /// 4 px/pt ≈ 288 dpi. La version précédente utilisait `UIScreen.main.scale`
    /// — la densité de l'écran du téléphone, qui n'a rien à voir avec une page
    /// imprimée : le cahier sortait à 2 px/pt depuis un iPhone non Plus, et
    /// la qualité du QR dépendait donc du modèle qui l'avait généré.
    private static let pixelsParPoint: CGFloat = 4

    /// Génère un UIImage contenant le QR code du schéma, à la taille demandée
    /// (en pixels). Renvoie `nil` si l'encodage échoue.
    static func image(for schema: BookletSchema, sizeInPoints: CGFloat) -> UIImage? {
        guard let payload = schema.encodedJSON(),
              let data = payload.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        // Correction d'erreur M (15 %), et non H (30 %) comme auparavant.
        //
        // H était un réflexe — « le papier s'abîme, prenons de la marge » —
        // mais ici le facteur qui limite la lecture n'est pas l'usure, c'est
        // la taille d'un module. Le QR fait 21,2 mm, et un cahier courant
        // (trois médicaments en deux prises, six symptômes) pèse ~312 octets :
        //
        //   H → version 19, 93 modules → 0,23 mm/module → 2,2 px sur la photo
        //   M → version 13, 69 modules → 0,31 mm/module → 2,9 px sur la photo
        //
        // En dessous d'environ 3 px par module, le lecteur ne distingue plus
        // les modules et aucun taux de correction ne le rattrape : la
        // redondance de H ne sert à rien si l'image ne porte plus
        // l'information. Les deux tiers manquants, eux, sont du module gagné.
        //
        // Le niveau est inscrit dans le QR lui-même : les pages déjà
        // imprimées en H restent lisibles, rien à migrer.
        filter.correctionLevel = "M"
        guard let ciImage = filter.outputImage else { return nil }

        // Core Image rend **un pixel par module**. L'agrandissement doit donc
        // être un facteur ENTIER et sans interpolation, sans quoi un module
        // tombe à cheval sur deux pixels et ses bords virent au gris.
        //
        // C'est ce qui se passait : le commentaire d'origine annonçait « sans
        // interpolation », mais `transformed(by:)` interpole, et le facteur
        // calculé n'était presque jamais entier. Les modules sortaient flous
        // de la génération, avant même l'impression et la photo — et un QR
        // dense (le payload porte les noms de médicaments) devenait illisible.
        let modules = ciImage.extent.width
        guard modules > 0 else { return nil }
        let facteur = max(1, (sizeInPoints * pixelsParPoint / modules).rounded(.up))

        let agrandi = ciImage
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: facteur, y: facteur))
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(agrandi, from: agrandi.extent) else { return nil }
        // Le `scale` ramène le bitmap à `sizeInPoints` une fois dessiné : la
        // taille du QR sur la page ne bouge pas — et elle ne doit pas bouger,
        // toute la grille de cases étant positionnée par rapport à lui.
        return UIImage(cgImage: cgImage,
                       scale: CGFloat(cgImage.width) / sizeInPoints,
                       orientation: .up)
    }

    // MARK: - Detection

    /// Résultat de détection du QR dans une image scannée.
    struct DetectionResult {
        let schema: BookletSchema
        /// Cadre du QR dans l'image (origine bas-gauche, normalisé 0..1).
        let normalizedBounds: CGRect
        /// Cadre du QR dans l'image en pixels (origine haut-gauche).
        let pixelBounds: CGRect
    }

    /// L'issue d'une tentative de lecture.
    ///
    /// Les deux échecs sont distingués parce qu'ils appellent des gestes
    /// opposés : refaire la photo, ou changer de page. L'app disait
    /// « QR code introuvable » dans les deux cas, y compris quand le QR avait
    /// été parfaitement lu.
    enum Detection {
        case trouve(DetectionResult)
        /// Aucun QR vu dans l'image.
        case illisible
        /// Un QR a été lu, mais son contenu n'est pas un cahier RettApp.
        case contenuEtranger
    }

    /// Tente de détecter et de décoder le QR dans l'image fournie.
    static func detect(in image: UIImage) async -> Detection {
        guard let cgImage = image.cgImage else { return .illisible }
        let taille = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))

        var qrVu = false
        switch await lire(cgImage) {
        case .decode(let schema, let cadre):
            return .trouve(resultat(schema: schema, cadre: cadre,
                                    zoneOrigine: .zero, zoneTaille: taille,
                                    imageTaille: taille))
        case .qrEtranger: qrVu = true
        case .rien:       break
        }

        // Seconde passe sur le haut-droit de la page.
        //
        // Vision sous-échantillonne une grande image avant d'y chercher un
        // code : sur une photo de 4 000 px de large, les modules d'un QR de
        // 21 mm passent sous son seuil et il ne voit rien — alors que le même
        // QR, recadré, occupe assez de pixels pour être lu. On sait où il est,
        // le générateur le pose toujours au même endroit et la page sort
        // rectifiée de `VNDocumentCameraViewController`.
        let zone = CGRect(x: (taille.width * 0.50).rounded(.down),
                          y: 0,
                          width: (taille.width * 0.50).rounded(.down),
                          height: (taille.height * 0.35).rounded(.down))
        if zone.width > 1, zone.height > 1, let recadre = cgImage.cropping(to: zone) {
            switch await lire(recadre) {
            case .decode(let schema, let cadre):
                return .trouve(resultat(schema: schema, cadre: cadre,
                                        zoneOrigine: zone.origin, zoneTaille: zone.size,
                                        imageTaille: taille))
            case .qrEtranger: qrVu = true
            case .rien:       break
            }
        }

        return qrVu ? .contenuEtranger : .illisible
    }

    /// Ce qu'a donné la lecture d'un tampon d'image.
    private enum Lecture {
        /// Schéma décodé, et cadre normalisé **dans le tampon lu**.
        case decode(BookletSchema, CGRect)
        case qrEtranger
        case rien
    }

    private static func lire(_ tampon: CGImage) async -> Lecture {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(cgImage: tampon, options: [:])
        return await withCheckedContinuation { (cont: CheckedContinuation<Lecture, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    cont.resume(returning: .rien)
                    return
                }
                // `results` est déjà un `[VNBarcodeObservation]?` : le
                // conditionnel ne convertissait rien et le compilateur le
                // signalait. Seul le dépliage de l'optionnel sert ici.
                guard let observations = request.results else {
                    cont.resume(returning: .rien); return
                }
                var qrVu = false
                for obs in observations where obs.symbology == .qr {
                    qrVu = true
                    guard let payload = obs.payloadStringValue,
                          let schema = BookletSchema.decode(payload) else { continue }
                    cont.resume(returning: .decode(schema, obs.boundingBox))
                    return
                }
                cont.resume(returning: qrVu ? .qrEtranger : .rien)
            }
        }
    }

    /// Replace un cadre lu dans une zone recadrée au sein de l'image entière.
    private static func resultat(schema: BookletSchema,
                                 cadre: CGRect,
                                 zoneOrigine: CGPoint,
                                 zoneTaille: CGSize,
                                 imageTaille: CGSize) -> DetectionResult {
        // Vision rend des coordonnées normalisées 0..1, origine bas-gauche,
        // relatives à la ZONE qu'on lui a remise. `cropping(to:)` travaille
        // lui en origine haut-gauche : le décalage s'ajoute donc après la
        // conversion, et pas avant.
        let pixels = CGRect(
            x: zoneOrigine.x + cadre.minX * zoneTaille.width,
            y: zoneOrigine.y + (1.0 - cadre.maxY) * zoneTaille.height,
            width: cadre.width * zoneTaille.width,
            height: cadre.height * zoneTaille.height
        )
        return DetectionResult(
            schema: schema,
            normalizedBounds: CGRect(
                x: pixels.minX / imageTaille.width,
                y: 1.0 - pixels.maxY / imageTaille.height,
                width: pixels.width / imageTaille.width,
                height: pixels.height / imageTaille.height
            ),
            pixelBounds: pixels
        )
    }
}
