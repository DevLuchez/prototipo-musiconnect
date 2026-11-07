# Diagrama de classes do aplicativo MusiConnect

Complemento da seção [10. Diagrama de classes](../../README.md#10-diagrama-de-classes) do README. O diagrama apresenta as principais classes do aplicativo Flutter, organizadas nas camadas do padrão MVVM, com os atributos e métodos mais relevantes de cada uma.

```mermaid
classDiagram
    direction LR

    class ChangeNotifier {
        <<Flutter>>
        +addListener()
        +notifyListeners()
    }

    class ViewModel {
        <<abstract>>
        -bool _disposed
        +bool isDisposed
        +notifyListeners()
        +dispose()
    }

    class DashboardViewModel {
        +OpportunityModel? bestMatch
        +Map~String,int~ typeCounts
        +List~OpportunityModel~ urgentSaved
        +load() Future
    }

    class MapExplorerViewModel {
        +List~PlaceModel~ places
        +List~CityOpportunities~ cities
        +List~PlaceModel~ searchResults
        +initialLoad() Future
        +loadNearby(lat, lng, radiusM) Future
        +applyFilters()
        +onSearchChanged(text)
        +opportunitiesOfInstitution(osmId) Future
    }

    class OpportunityBrowserViewModel {
        +String? lockedType
        +List~OpportunityModel~ opportunities
        +List~CategoryPreview~ categories
        +String query
        +start() Future
        +search(text)
        +applyFilters()
        +openDrill(typeKey, label)
    }

    class ProfileViewModel {
        +AuthUser user
        +String matchCountLabel
        +setNotification(newMatches, deadlines, appUpdates) Future
        +setUsageDataEnabled(enabled) Future
        +profileEdited(updated)
        +deleteAccount(password) Future
    }

    class AuthService {
        +signup() Future
        +login(email, password) Future~AuthUser~
        +forgotPassword(email) Future
        +updateProfile() Future~AuthUser~
        +changePassword() Future
        +acceptPrivacyPolicy() Future~AuthUser~
        +logout() Future
        +deleteAccount(password) Future
    }

    class OpportunitiesService {
        +fetchOpportunities() Future~OpportunitiesResult~
        +fetchFilterOptions() Future~FilterOptions~
        +fetchCities() Future
        +fetchById(id) Future~OpportunityModel~
    }

    class MusicConnectApiService {
        +fetchNearby(lat, lng, radius) Future
        +search(query) Future
        +fetchById(osmId) Future~PlaceModel~
        +fetchStats() Future
    }

    class DashboardService {
        +fetch() Future~DashboardData~
    }

    class FavoritesService {
        +load() Future
        +toggleOpportunity(id) Future~bool~
        +toggleInstitution(osmId) Future~bool~
        +fetchSavedOpportunities() Future
        +fetchFavoriteInstitutions() Future
    }

    class NotificationsService {
        +registerDevice(token) Future
        +updatePreferences() Future~AuthUser~
    }

    class MatchCountService {
        +int? count
        +refresh() Future
    }

    class AuthUser {
        +int id
        +String email
        +String name
        +List~String~ instruments
        +bool isStudent
        +bool isProfessional
        +String? country
        +String? state
        +String? city
        +bool notifyNewMatches
        +bool notifyDeadlines
        +bool isVisitor
    }

    class OpportunityModel {
        +int id
        +String title
        +String? type
        +String? description
        +List~String~ instruments
        +String? city
        +String? country
        +bool isRemote
        +DateTime? deadline
        +double llmConfidence
        +int? matchPercentage
        +String? sourceUrl
    }

    class MatchBreakdown {
        +int instrument
        +int affinity
        +int location
        +int confidence
    }

    class PlaceModel {
        +String id
        +String name
        +String category
        +double lat
        +double lng
        +String? address
        +String? website
        +String? email
        +int activeOpportunitiesCount
    }

    ChangeNotifier <|-- ViewModel
    ChangeNotifier <|-- FavoritesService
    ChangeNotifier <|-- MatchCountService
    ViewModel <|-- DashboardViewModel
    ViewModel <|-- MapExplorerViewModel
    ViewModel <|-- OpportunityBrowserViewModel
    ViewModel <|-- ProfileViewModel

    DashboardViewModel --> DashboardService
    DashboardViewModel --> FavoritesService
    MapExplorerViewModel --> MusicConnectApiService
    MapExplorerViewModel --> OpportunitiesService
    OpportunityBrowserViewModel --> OpportunitiesService
    ProfileViewModel --> AuthService
    ProfileViewModel --> FavoritesService
    ProfileViewModel --> MatchCountService
    ProfileViewModel --> NotificationsService

    OpportunitiesService ..> OpportunityModel : cria
    MusicConnectApiService ..> PlaceModel : cria
    AuthService ..> AuthUser : cria
    OpportunityModel *-- MatchBreakdown
```

>**Legenda:** a seta com ponta triangular vazada indica herança; a seta contínua, dependência entre classes (o ViewModel utiliza o serviço); a seta tracejada, que o serviço cria instâncias do modelo a partir das respostas da API; e o losango preenchido, composição (o detalhamento do match faz parte da oportunidade).
