enum EtymologyPrompts {
    static let etymologyAnalysis = """
    Tu es un expert en étymologie. Analyse ce texte et réponds UNIQUEMENT avec un objet JSON valide.

    🚫 INTERDICTIONS ABSOLUES :
    - JAMAIS "NEW_LANGUAGE"
    - JAMAIS "Langue africaine non spécifiée"
    - JAMAIS "langue inconnue" ou variants
    - JAMAIS de noms vagues
    - JAMAIS deux entrées avec la même langue ET le même mot
    - JAMAIS de répétitions inutiles (ex: "france" → "france" → "france")

    ✅ RÈGLES IMPORTANTES POUR LA CHAÎNE ÉTYMOLOGIQUE :
    - Une seule entrée par combinaison langue+mot (évite les vrais doublons)
    - PERMET le même mot dans différentes langues si géographiquement pertinent
    - PERMET différents mots dans la même langue si évolution temporelle
    - Inclus TOUTES les étapes géographiques mentionnées (ex: Espagnol → Taïno)
    - RESPECTE les langues mentionnées dans le texte (ne pas tout mettre en français)
    
    📋 EXEMPLES DE TRAITEMENT :
    - "du français france, du latin francia" → 2 entrées: Français:france + Latin:francia
    - "français france attesté en 1200, puis france en 1300" → 1 entrée: Français:france
    - "espagnol hamaca, du taïno hamaca" → 2 entrées: Espagnol:hamaca + Taïno:hamaca
    - "1533 italien amacca, 1525 français amache" → 2 entrées: Italien:amacca + Français:amache
    - "français hamac, hamaca (1545), italien amacca (1533)" → 3 entrées distinctes
    
    ⚠️ ATTENTION SPÉCIALE :
    - Si le texte mentionne "italien amacca" → utilise "Italien" (pas Français)
    - Si le texte mentionne "espagnol hamaca" → utilise "Espagnol" (pas Français)  
    - Une SEULE entrée par langue (pas "Français" répété 4 fois)
    - Privilégie les vrais changements linguistiques ET géographiques

    🧩 DÉTECTION INTELLIGENTE DES MOTS COMPOSÉS :
    - Analyse le texte pour détecter les expressions comme :
      * "Composé de X et de Y"
      * "Composé de X, de Y et de Z" (pour 3+ composants)
      * "formé de X et Y"
      * "formé de X, Y et Z"
      * "Dérivé de X et Y"
      * "de l'élément préf. X et de Y"
      * "préf. X et Y"
      * Tout autre pattern indiquant une composition
    - Si c'est un mot composé, ajoute un champ "is_composed_word" : true
    - Ajoute un champ "components" : ["composant1", "composant2", "composant3", ...] avec TOUS les mots de base nettoyés
    - Pour les mots avec traits d'union (ex: "arc-en-ciel"), analyse s'ils forment une expression idiomatique composée
    - Continue l'analyse étymologique normalement pour le mot principal

    ✅ AUTRES RÈGLES :
    - Utilise les langues connues en priorité
    - Pour les nouvelles langues, utilise des noms précis et réels
    - Descriptions courtes (max 100 caractères)
    - Ordre chronologique : du plus récent au plus ancien

    Texte à analyser :
    {etymology_text}

    Langues connues (utilise exactement ces noms) :
    {known_languages}

    FORMAT DE RÉPONSE ATTENDU :
    {{
        "etymology": {{
            "chain": [
                {{"period": "période", "language": "langue", "sourceWord": "mot", "translation": "sens", "originalScript": null}}
            ]
        }},
        "is_composed_word": false,
        "components": [],
        "new_languages": [
            {{"name": "nom_langue", "description": "ville_principale", "latitude": 0.0, "longitude": 0.0, "period_start": "début", "period_end": "fin", "reason": "justification_courte"}}
        ]
    }}

    INSTRUCTIONS :
    - Analyse d'abord si c'est un mot composé (vérifie tous les patterns de composition)
    - Si composé, extraie les composants ET continue l'analyse étymologique
    - Identifie UNIQUEMENT les vrais changements linguistiques (évolution de forme)
    - Ignore les répétitions du même mot dans la même langue
    - Une seule entrée par langue ET par forme de mot
    - Utilise les langues connues quand possible
    - Pour les nouvelles langues, fournis des coordonnées précises
    - Respecte l'ordre chronologique (du plus récent au plus ancien)
    - Garde les descriptions courtes (max 100 caractères)
    """
    
    static let languageAnalysis = """
    Analyse la langue {language} et génère une réponse au format JSON avec :
    - type: classification linguistique (ex: "indo-européen", "sémitique", etc.)
    - name: nom normalisé de la langue
    - description: ville ou région historique principale
    - periodStart: début de la période d'utilisation
    - periodEnd: fin de la période ou "présent"
    """
    
    static let newLanguageAnalysis = """
    Analyse cette nouvelle langue pour le mot '{word}' :
    
    Mot source : {source_word}
    Texte source : {source_text}
    Première attestation : {first_attestation}
    Chaîne étymologique : {etymology_chain}
    
    Langues déjà connues :
    {known_languages}
    
    Génère une réponse JSON avec les informations historiques et géographiques.
    """

    static let historicalLanguages = """
    Tu es un expert en linguistique historique et géographie. Analyse ces langues et fournis leurs centres historiques avec des coordonnées précises.

    🎯 OBJECTIF : Créer une base de données fiable des langues historiques avec leurs localisations géographiques.

    📋 LANGUES À ANALYSER :
    {languages}

    ✅ RÈGLES STRICTES :
    - Coordonnées précises à 4 décimales minimum
    - Villes historiquement pertinentes (centres culturels/politiques)
    - Périodes en siècles romains (ex: "IVe siècle", "Xe-XIIe siècles")
    - Justifications historiques concises (max 100 caractères)
    - JAMAIS de coordonnées 0,0 ou approximatives

    📍 EXEMPLES DE QUALITÉ :
    - Sanskrit → Varanasi (25.3176, 82.9739) - Centre spirituel et intellectuel
    - Latin → Rome (41.9028, 12.4964) - Capitale de l'Empire romain
    - Grec ancien → Athènes (37.9838, 23.7275) - Berceau de la philosophie

    FORMAT DE RÉPONSE ATTENDU (JSON uniquement) :
    [
        {{
            "name": "nom_langue",
            "description": "ville_historique",
            "latitude": 00.0000,
            "longitude": 00.0000,
            "period_start": "début_période",
            "period_end": "fin_période",
            "reason": "justification_historique"
        }}
    ]

    INSTRUCTIONS :
    - Une entrée par langue
    - Coordonnées du centre historique le plus pertinent
    - Périodes d'apogée ou d'usage principal
    - Justifications basées sur des faits historiques
    - Réponse JSON valide uniquement
    """

    // ... autres prompts ...
} 