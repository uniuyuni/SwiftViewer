# SwiftViewer

SwiftViewer is a high-performance media viewer for macOS, designed for photographers and creative professionals. It offers fast browsing, advanced filtering, and efficient management of large image collections.

![Screenshot](screenshot.png)

## Features

### High-Performance Browsing
- **Folders Mode**: Browse your file system directly with real-time folder monitoring.
- **Catalog Mode**: Import folders into a database-backed catalog for persistent management.
- **Photos Library Mode**: Browse Apple Photos Libraries directly, including RAW files and sidecar assets.
- **Grid View**: Resizable thumbnails (50px-300px) with lazy loading for smooth scrolling.
- **Sidebar**: Tree-based navigation with drag & drop support for folders, catalogs, and libraries.

### Advanced Filtering
- **Text Search**: Filter by filename.
- **Star Rating**: Filter by rating (0-5 stars).
- **Color Labels**: Filter by 7 color labels (Red, Orange, Yellow, Green, Blue, Purple, Gray).
- **Favorites**: Show only favorited items.
- **Flag Status**: Filter by Pick/Reject/Unflagged status.
- **Metadata Filters** (Multi-selection support):
  - **Maker**: Camera manufacturer
  - **Camera Model**: Specific camera body
  - **Lens Model**: Lens used
  - **ISO**: ISO sensitivity values
  - **Date**: Capture date
  - **File Type**: Image/video formats
  - **Shutter Speed**: Exposure time
  - **Aperture**: F-number values
  - **Focal Length**: Lens focal length

### Image Viewing
- **Wide Format Support**: RAW (CR2, NEF, RAF, ARW, DNG, etc.), JPG, PNG, HEIC, TIFF, GIF, WEBP.
- **RAW Processing**: 
  - ExifTool integration for professional RAW metadata extraction.
  - Embedded preview extraction for fast thumbnails.
  - Correct orientation handling for all file types.
  - XMP rating takes priority over Exif composite tags.
- **Preview**: Large preview with zoom (scroll wheel/pinch gesture/double-click) and pan capabilities.
- **Zoom Persistence**: Zoom scale and center position are preserved when navigating between images.
- **Full Screen Preview**: Toggle immersive full screen mode with `F` key (supports arrow keys navigation).
- **Sub View**: `Option+F` to open a synchronized full screen preview on a secondary display.
- **Video Playback**: AVPlayer-based video playback with seek controls.
- **Cursor RGB**: Real-time RGB color value display at the cursor position.

### File Management
- **Drag & Drop**: Move or copy files within the app or to external applications (Finder, Mail, etc.).
- **Context Menu**: Quick access to:
  - Rating (0-5 stars)
  - Color Labels (7 colors)
  - Favorite toggle
  - Flag status (Pick/Reject)
  - "Move to Trash"
  - "Show in Finder"
  - "Add to Collection" / "Remove from Collection"
- **Collections**: Group images virtually within a catalog without moving files.
- **Smart Filtering**: Combine multiple filter criteria for precise file selection.

### Metadata Editing
- **Rating**: 0-5 stars editable in Inspector and context menu.
- **Color Labels**: 7 colors editable in Inspector and context menu.
- **Favorites**: Toggle in Inspector and context menu.
- **Flag Status**: Pick/Reject/None editable in Inspector and context menu.
- **Lens Metadata**: Lens make and lens model editable directly in the Inspector (catalog mode).

### Performance Optimizations
- **Dual-Layer Caching**:
  - **Memory Cache**: NSCache for instant access to recently viewed thumbnails.
  - **Disk Cache**: Persistent thumbnail storage for fast app launches.
- **Asynchronous Processing**: Swift Concurrency (async/await, Actor) for smooth UI.
- **Lazy Loading**: Thumbnails generated only for visible grid items.
- **File System Monitoring**: Real-time detection of file changes and unmounted volumes.

## Architecture

SwiftViewer follows a clean 3-layer architecture:

### Presentation Layer
- **ViewModels**: `MainViewModel`, `CatalogViewModel`, `AdvancedCopyViewModel`
- **Views**: 14 SwiftUI components (Grid, Detail, Inspector, Sidebar, Filter, SubPreview, etc.)
- **MVVM Pattern**: Reactive UI updates via `@Published` properties

### Domain Layer
- **Models**: `FileItem`, `FilterCriteria`, `ExifMetadata`
- **Services**: `FileSortService`, `ThumbnailGenerationService`
- **Business Logic**: Filtering, sorting, and validation rules

### Infrastructure & Data Layer
- **CoreData**: Persistent storage for catalogs, media items, EXIF data, collections
- **Image Processing**: `ExifReader`, `ThumbnailGenerator`, `RawImageLoader`, `EmbeddedPreviewExtractor`
- **Caching**: `ThumbnailCacheService`, `ImageCacheService`
- **File System**: `FileSystemService`, `FileSystemMonitor`, `FileOperationService`
- **Logging**: Centralized `Logger` service

## Requirements

- **macOS**: 13.0 (Ventura) or later.
- **Architecture**: Apple Silicon (M1/M2/M3) recommended.
- **ExifTool**: Required for RAW file metadata (install via Homebrew: `brew install exiftool`).

## Building the Project

This project uses Swift Package Manager.

### Build SwiftViewer (Main App)
```bash
./create_app.sh
```
This will create `SwiftViewer.app` in the project root.
To create a distributable zip file:
```bash
zip -r SwiftViewer.app.zip SwiftViewer.app
```

### Testing
To run the automated test suite:
```bash
./run_tests.sh
```

Test coverage includes:
- EXIF reading (RAW files, batch processing, orientation)
- Thumbnail generation and caching
- Repository operations
- Specification compliance
- Filter criteria and persistence
- Flag and favorite feature behavior
- Metadata filtering and editing
- Regression tests

## Development

- **Language**: Swift 5.9+
- **Frameworks**: SwiftUI, AppKit, Core Data, AVFoundation, MapKit, QuickLook, ImageIO
- **Architecture**: MVVM (Model-View-ViewModel)
- **Concurrency**: Swift Concurrency (async/await, Task, Actor, MainActor)
- **Package Structure**:
  - `SwiftViewerCore`: Core library (53 Swift files)
  - `SwiftViewer`: Executable target
  - `SwiftViewerTests`: Test suite (35 test files)

## License

MIT License. Copyright (c) 2025 uniuyuni.

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `F` | Toggle Full Screen |
| `Option + F` | Toggle Sub View (Multi-Display) |
| `I` | Toggle Inspector |
| `Space` | Quick Look |
| `Command + R` | Refresh Current View |
| `Command + Shift + R` | Reveal in Finder |
| `Command + Shift + K` | Advanced Copy |
| `←` / `→` | Previous / Next file |
| `0`–`5` | Set Rating |
| `L` | Toggle Favorite |
| `A` | Set Pick Flag |
| `X` | Set Reject Flag |
| `U` | Unflag |
| `Esc` | Exit Full Screen |
