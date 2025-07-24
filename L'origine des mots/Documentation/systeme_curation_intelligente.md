# Système de Curation Intelligente des Mots Remarquables

## Vue d'ensemble

Le système de curation intelligente utilise **Claude (Anthropic)** pour analyser automatiquement les mots récemment ajoutés à l'application et sélectionner ceux qui sont étymologiquement remarquables selon des critères spécifiques.

## Architecture

### Composants principaux

1. **`RemarkableWordsCurator`** - Service principal de curation
2. **`RemarkableWordsCurationView`** - Interface utilisateur pour la gestion
3. **`ClaudeService`** avec extension `analyzeCuration` - Analyse IA
4. **Intégration dans `ContentView`** - Bouton shuffle intelligent

## Fonctionnalités

### 1. Analyse automatique par Claude

Claude évalue les mots selon ces **critères de remarquabilité** :

#### ✅ Critères Positifs
- **Voyage géographique fascinant** : passages par plusieurs continents, routes commerciales
- **Évolution sémantique surprenante** : changements de sens radicaux
- **Langues "exotiques"** : sanskrit, arabe, nahuatl, chinois, perse, etc.
- **Histoire culturelle** : emprunts liés à des événements historiques
- **Anecdotes captivantes** : histoires étonnantes

#### ❌ Critères d'Exclusion
- Étymologies simples (français → latin → grec)
- Mots trop techniques ou spécialisés
- Évolutions prévisibles

### 2. Interface de curation

**Accès** : Bouton "cerveau" (🧠) dans la section des mots remarquables

**Fonctionnalités** :
- **Analyse seule** : Prévisualisation des suggestions de Claude
- **Curation automatique** : Analyse + ajout direct en base
- **Paramètres** : Période d'analyse (1-30 jours)
- **Sélection manuelle** : Validation individuelle des suggestions

### 3. Système de shuffle intelligent

Le bouton "shuffle" ne mélange plus simplement les positions, mais :
- Charge tous les mots remarquables de la base (stockés dans `allRemarkableWords`)
- Génère une **sélection diversifiée** de 20 mots via `generateRandomSelection()`
- Assure la **diversité par tags** (au moins un mot de chaque catégorie)
- Complète avec des mots aléatoires si nécessaire

## Utilisation

### Pour les utilisateurs

1. **Navigation** : L'écran principal affiche 20 mots sélectionnés intelligemment
2. **Shuffle** : Cliquer sur 🔀 pour une nouvelle sélection diversifiée
3. **Curation** : Cliquer sur 🧠 pour accéder à l'interface d'administration

### Pour les administrateurs

1. **Curation manuelle** :
   - Ouvrir l'interface de curation
   - Choisir la période d'analyse
   - "Analyse Seule" pour prévisualiser
   - Sélectionner/désélectionner les suggestions
   - "Ajouter la sélection" pour confirmer

2. **Curation automatique** :
   - "Analyse & Curation Automatique"
   - Claude analyse + ajoute directement
   - Notification du nombre de mots ajoutés

## Flux de traitement

```
Mots récents (base) → Claude analyse → Sélection remarquable → Validation → Ajout en base
                                           ↓
                               Génération tags + descriptions
```

### Prompt de Claude

Claude reçoit pour chaque mot :
- Le mot lui-même
- La chaîne étymologique complète : `mot (langue, période - traduction) → ...`
- Liste des langues disponibles en base

Claude répond avec :
```json
{
  "selected_words": [
    {
      "word": "café",
      "description": "De l'arabe قهوة via le turc jusqu'au français",
      "tags": ["alimentation", "arabe", "turc"]
    }
  ]
}
```

## Configuration

### Tags disponibles
- **Géographiques** : arabe, grec, latin, sanskrit, perse, chinois, nahuatl, turc
- **Thématiques** : alimentation, sciences, vêtements, objets, histoire, jeux, mathématiques, médecine, marine, religion, technique

### Paramètres par défaut
- **Période d'analyse** : 7 jours
- **Sélection affichée** : 20 mots
- **Limite de description** : 80 caractères
- **Maximum par analyse** : 5 mots remarquables

## Avantages du système

1. **Curation intelligente** : Claude comprend la nuance étymologique
2. **Évite la surcharge** : Sélection limitée et rotative
3. **Diversité garantie** : Répartition par catégories/tags
4. **Validation humaine** : Possibilité de contrôle manuel
5. **Évolutif** : Critères ajustables via le prompt

## Tests et maintenance

**Script de test** : `Scripts/test_curation.swift`
- Test d'analyse de mots récents
- Test de curation complète
- Test de génération de sélection intelligente

**Monitoring** : Les logs détaillent chaque étape du processus pour faciliter le debugging.

## Evolution future

- **Critères dynamiques** : Ajustement automatique selon les retours utilisateurs
- **Apprentissage** : Mémorisation des préférences de curation
- **Catégories personnalisées** : Tags adaptatifs selon le contenu
- **Planification** : Curation automatique quotidienne/hebdomadaire 