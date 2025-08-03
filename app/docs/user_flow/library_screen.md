# Library Screen

## Layout
- **Header**: Current user name, logout button, online indicator
- **Tab Bar**: "PLAYLISTS" and "SAMPLES"
- **Content**: Tab-based content area

## Tab Actions
- **PLAYLISTS**: Shows "Coming soon" placeholder
- **SAMPLES**: Shows "Coming soon" placeholder

## Flow
```mermaid
graph TD
    A[Library Screen] --> B[Tab Selection]
    B --> C[PLAYLISTS Tab]
    B --> D[SAMPLES Tab]
    C --> E[Coming Soon]
    D --> F[Coming Soon]
```

## Key Features
- Clean tab-based navigation
- Consistent header with other screens
- Placeholder content for future features 