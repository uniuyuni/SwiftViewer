# SwiftViewer

SwiftViewer is a high-performance media viewer for macOS, designed for photographers and creative professionals. It offers fast browsing, advanced filtering, and efficient management of large image collections.

## Features

- **High-Performance Browsing**:
  - **Folders Mode**: Browse your file system directly.
  - **Catalog Mode**: Import folders into a database-backed catalog for persistent management.
  - **Grid View**: Resizable thumbnails with lazy loading for smooth scrolling.
  - **Sidebar**: Tree-based navigation with drag & drop support.

- **Advanced Filtering**:
  - Filter by **Text** (Filename).
  - Filter by **Star Rating** (0-5).
  - Filter by **Color Label** (Red, Orange, Yellow, Green, Blue, Purple, Gray).
  - Filter by **Metadata** (Camera, Lens, ISO, Aperture, Shutter Speed, Date).

- **Image Viewing**:
  - Support for **RAW**, JPG, PNG, HEIC, TIFF, GIF, WEBP.
  - **Correct Orientation**: Automatically handles Exif orientation for all file types.
  - **Preview**: Large preview with zoom and pan capabilities.

- **File Management**:
  - **Drag & Drop**: Move or copy files within the app or to external applications (Finder, Mail, etc.).
  - **Context Menu**: Quick access to Rating, Color Labels, and "Move to Trash".
  - **Collections**: Group images virtually without moving files.



## Requirements

- **macOS**: 14.0 (Sonoma) or later.
- **Architecture**: Apple Silicon (M1/M2/M3) recommended.

## Building the Project

This project includes shell scripts to build the applications easily.

### Build SwiftViewer (Main App)
```bash
./create_app.sh
```
This will create `SwiftViewer.app` in the project root.

### Testing
To run the automated test suite:
```bash
./run_tests.sh
```
This executes unit tests for core components (Repositories, ExifReader, etc.).

## Development

- **Language**: Swift 5.9+
- **Frameworks**: SwiftUI, AppKit, Core Data, QuickLookThumbnailing, ImageIO.
- **Architecture**: MVVM (Model-View-ViewModel).

## License

Copyright (c) 2025. All rights reserved.
