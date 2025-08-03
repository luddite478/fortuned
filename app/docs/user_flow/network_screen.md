# Network Screen

## Layout
- **Header**: Current user name, logout button, online indicator
- **Search Bar**: User search functionality
- **User List**: List of users with online status indicators

## User Actions
- **Search**: Filter users by name
- **User Tile**: Click → Opens User Profile Screen
- **Online Indicators**: 
  - Green dot: User online
  - Gray dot: User offline

## Flow
```mermaid
graph TD
    A[Network Screen] --> B[Search Users]
    A --> C[User List]
    B --> C
    C --> D[Click User]
    D --> E[User Profile Screen]
    E --> F[Back Button]
    F --> A
```

## Key Features
- Real-time online status
- Search functionality
- Navigation to user profiles
- Consistent header design 