# Debug des kilomètres totaux

## Problème
Les kilomètres totaux ne s'affichent pas dans `AppFooterView`.

## Points à vérifier

### 1. Service getTotalKilometers
```swift
// Dans SupabaseService.swift ligne 642
func getTotalKilometers() async throws -> Double
```

**À vérifier :**
- La fonction est-elle appelée ?
- Retourne-t-elle 0 ou une valeur > 0 ?
- Y a-t-il des erreurs dans les logs ?

### 2. Cache KilometersCache
```swift
// Dans KilometersCache.swift
@Published var totalKilometers: Double = 0.0
@Published var isLoading: Bool = false
```

**À vérifier :**
- `loadTotalKilometers()` est-elle appelée ?
- Le cache se met-il à jour ?
- Les @Published déclenchent-ils la mise à jour de l'UI ?

### 3. AppFooterView
```swift
// Dans AppFooterView.swift ligne 3
@StateObject private var kilometersCache = KilometersCache.shared
```

**À vérifier :**
- `AppFooterView` s'affiche-t-elle dans `ContentView` ? ✅ (ligne 580)
- Les valeurs du cache sont-elles observées correctement ?

### 4. Base de données
**À vérifier :**
- Les mots ont-ils des valeurs dans `distance_km` ?
- La requête SQL fonctionne-t-elle ?

## Tests à faire

1. **Lancer l'app et chercher dans les logs Xcode :**
   ```
   🔍 Calcul du total des kilomètres...
   📊 Nombre total de mots en base : X
   📊 Mots avec distance : Y
   ```

2. **Si les logs n'apparaissent pas :**
   - `AppFooterView.onAppear` n'est pas déclenché
   - Vérifier que le footer s'affiche bien en bas de `ContentView`

3. **Si distance_km est toujours NULL :**
   - Lancer `syncDistancesToNewColumn()` pour migrer les données
   - Vérifier que les nouveaux mots sont sauvés avec `distance_km`

## Solution probable
Le problème est probablement que :
1. Les mots existants n'ont pas de `distance_km` (NULL en base)
2. Il faut migrer les données ou créer de nouveaux mots pour tester

## Action immédiate
Ajouter des logs dans `AppFooterView.onAppear` pour confirmer que le chargement est déclenché. 