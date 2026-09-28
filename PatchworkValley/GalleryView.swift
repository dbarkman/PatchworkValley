import SwiftUI
import UIKit
import ValleyCore

/// The player's saved valleys, newest first. Tap one to look it over; press and hold to delete.
struct GalleryView: View {
    let gallery: Gallery
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: GalleryEntry?
    @ScaledMetric private var cellWidth: CGFloat = 150

    var body: some View {
        NavigationStack {
            Group {
                if gallery.entries.isEmpty {
                    ContentUnavailableView(
                        "No valleys yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Finish a valley, tap View valley, then Save to Gallery.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: cellWidth), spacing: 16)], spacing: 20) {
                            ForEach(gallery.entries) { entry in
                                NavigationLink(value: entry) {
                                    GalleryCell(entry: entry, image: gallery.thumbnail(for: entry))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = entry }
                                }
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                            }
                        }
                        .padding()
                    }
                }
            }
            .animation(.snappy, value: gallery.entries)
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: GalleryEntry.self) { entry in
                GalleryDetail(entry: entry, gallery: gallery)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete this valley?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible,
                presenting: deleting
            ) { entry in
                Button("Delete Valley \(entry.valley)", role: .destructive) { gallery.delete(entry) }
            } message: { _ in
                Text("It will be gone from your gallery for good.")
            }
        }
    }
}

private struct GalleryCell: View {
    let entry: GalleryEntry
    let image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color(uiColor: Palette.board)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("Valley \(entry.valley)")
                .font(.headline)
            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One saved valley, full screen, with pinch to zoom.
private struct GalleryDetail: View {
    let entry: GalleryEntry
    let gallery: Gallery
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false
    /// The full picture, loaded once the page opens.
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(uiColor: Palette.board)
            if let image {
                ZoomableImage(image: image)
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: image != nil)
        .task { image = gallery.image(for: entry) }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Valley \(entry.valley)")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Label(
                    "\(entry.date.formatted(date: .abbreviated, time: .omitted)) · \(coinCount(entry.coins)) earned",
                    systemImage: "centsign.circle.fill"
                )
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                }
            }
            .confirmationDialog("Delete this valley?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Valley \(entry.valley)", role: .destructive) {
                    gallery.delete(entry)
                    dismiss()
                }
            } message: {
                Text("It will be gone from your gallery for good.")
            }
    }
}

/// A picture that pinches to zoom and pans when zoomed, like Photos.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        // Double-tap zooms in, and back out.
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            if scrollView.zoomScale > 1 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = recognizer.location(in: imageView)
                let size = CGSize(width: scrollView.bounds.width / 2.5, height: scrollView.bounds.height / 2.5)
                scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
        }
    }
}
