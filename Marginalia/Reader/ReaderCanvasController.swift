import PDFKit
import SwiftUI
import UIKit

/// Hosts the PDFView. Everything that needs fine-grained UIKit control (Pencil overlays,
/// edit menus, gestures) lives here; SwiftUI only draws chrome on top.
final class ReaderCanvasController: UIViewController {
    let model: ReaderModel
    let pdfView = ReaderPDFView()
    private(set) lazy var inkLayer = InkLayer(model: model)
    private lazy var markMenu = UIEditMenuInteraction(delegate: self)
    private var didRestorePosition = false

    /// Live PDFKit annotations for each stored mark, and the reverse lookup for hit-testing.
    private var annotationsByMark: [String: [PDFAnnotation]] = [:]
    private var markByAnnotation: [ObjectIdentifier: String] = [:]

    init(model: ReaderModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // PencilKit and our mark actions share one undo stack per document.
    override var undoManager: UndoManager? { model.undoManager }

    override func viewDidLoad() {
        super.viewDidLoad()
        model.canvas = self

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.backgroundColor = Theme.backgroundUI
        pdfView.pageShadowsEnabled = false
        pdfView.displaysPageBreaks = true
        pdfView.pageBreakMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        view.addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: view.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // The overlay provider must be installed before the document is set.
        // Ink canvases sit above each page and receive Pencil input. They also sit above PDFKit's own
        // text-selection gestures, so finger selection and link taps are handled here instead.
        pdfView.pageOverlayViewProvider = inkLayer
        pdfView.isInMarkupMode = true
        pdfView.selectionMenuItems = { [weak self] in self?.selectionMenuItems() ?? [] }

        apply(layout: model.layout)
        pdfView.document = model.pdf
        model.highlights.values.forEach(render)

        NotificationCenter.default.addObserver(
            self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)

        pdfView.addInteraction(markMenu)
        installGestures()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didRestorePosition, pdfView.bounds.width > 0 else { return }
        didRestorePosition = true
        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
        restorePosition()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        let destination = pdfView.currentDestination
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else { return }
            pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
            if let destination { pdfView.go(to: destination) }
        }
    }

    // MARK: Navigation commands

    var currentDestination: PDFDestination? { pdfView.currentDestination }

    func go(toPage index: Int) {
        guard let page = model.pdf.page(at: index) else { return }
        pdfView.go(to: page)
    }

    func go(to destination: PDFDestination) {
        pdfView.go(to: destination)
    }

    func apply(layout: ReaderLayout) {
        let destination = pdfView.document == nil ? nil : pdfView.currentDestination
        switch layout {
        case .continuous:
            pdfView.displayMode = .singlePageContinuous
            pdfView.displaysAsBook = false
        case .singlePage:
            pdfView.displayMode = .singlePage
            pdfView.displaysAsBook = false
        case .twoUp:
            pdfView.displayMode = .twoUp
            pdfView.displaysAsBook = model.document.kind == .book
        }
        pdfView.displayDirection = .vertical
        pdfView.autoScales = true
        if let destination { pdfView.go(to: destination) }
    }

    private func restorePosition() {
        let (pageIndex, y) = model.resumeDestination
        guard let page = model.pdf.page(at: pageIndex) else { return }
        if let y, pageIndex > 0 || y < page.bounds(for: pdfView.displayBox).maxY - 1 {
            pdfView.go(to: PDFDestination(page: page, at: CGPoint(x: 0, y: y)))
        } else if pageIndex > 0 {
            pdfView.go(to: page)
        }
    }

    // MARK: Marks

    func render(_ mark: Highlight) {
        removeMark(id: mark.id)
        guard let page = model.pdf.page(at: mark.page) else { return }
        let annotations = MarkRenderer.annotations(for: mark, on: page)
        for annotation in annotations {
            page.addAnnotation(annotation)
            markByAnnotation[ObjectIdentifier(annotation)] = mark.id
        }
        annotationsByMark[mark.id] = annotations
    }

    func removeMark(id: String) {
        guard let annotations = annotationsByMark.removeValue(forKey: id) else { return }
        for annotation in annotations {
            annotation.page?.removeAnnotation(annotation)
            markByAnnotation[ObjectIdentifier(annotation)] = nil
        }
    }

    private func selectionMenuItems() -> [UIMenuElement] {
        guard let selection = pdfView.currentSelection, !(selection.string ?? "").isEmpty else { return [] }

        func mark(_ style: MarkStyle, flag: MarkFlag? = nil, editNote: Bool = false) {
            let created = model.addMark(from: selection, style: style, flag: flag)
            pdfView.clearSelection()
            if editNote, let first = created.first { model.editingHighlight = first }
        }

        return [
            UIAction(title: "Highlight", image: UIImage(systemName: "highlighter")) { _ in mark(.highlight) },
            UIAction(title: "Underline", image: UIImage(systemName: "underline")) { _ in mark(.underline) },
            UIAction(title: "Note", image: UIImage(systemName: "text.bubble")) { _ in mark(.highlight, editNote: true) },
            UIAction(title: "Question", image: UIImage(systemName: "questionmark")) { _ in mark(.highlight, flag: .question) },
            UIMenu(title: "More", image: UIImage(systemName: "ellipsis"), children: [
                UIAction(title: "Strike Through", image: UIImage(systemName: "strikethrough")) { _ in mark(.strikethrough) },
                UIAction(title: "Look Up Later", image: UIImage(systemName: "arrow.right")) { _ in mark(.underline, flag: .lookup) },
            ]),
        ]
    }

    private static let selectionMenuID = "selection" as NSString

    private func showSelectionMenu(at point: CGPoint) {
        let config = UIEditMenuConfiguration(identifier: Self.selectionMenuID, sourcePoint: point)
        markMenu.presentEditMenu(with: config)
    }

    private func markMenu(for mark: Highlight) -> UIMenu {
        let id = mark.id
        let styles = MarkStyle.allCases.map { style in
            UIAction(title: style.title, image: UIImage(systemName: style.symbol),
                     state: mark.style == style ? .on : .off) { [weak self] _ in
                guard var current = self?.model.highlights[id] else { return }
                current.style = style
                self?.model.update(current)
            }
        }
        let flags = MarkFlag.allCases.map { flag in
            UIAction(title: flag.title, image: UIImage(systemName: flag.symbol),
                     state: mark.flag == flag ? .on : .off) { [weak self] _ in
                guard var current = self?.model.highlights[id] else { return }
                current.flag = current.flag == flag ? nil : flag
                self?.model.update(current)
            }
        }
        return UIMenu(children: [
            UIAction(title: mark.hasNote ? "Edit Note" : "Add Note", image: UIImage(systemName: "text.bubble")) { [weak self] _ in
                self?.model.editingHighlight = self?.model.highlights[id]
            },
            UIMenu(title: "Style", image: UIImage(systemName: "textformat"), children: styles),
            UIMenu(title: "Mark As", image: UIImage(systemName: "flag"), children: flags),
            UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = mark.text
            },
            UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.model.deleteMark(id: id)
            },
        ])
    }

    // MARK: Gestures

    private func installGestures() {
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        press.minimumPressDuration = 0.35
        press.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
        press.delegate = self
        pdfView.addGestureRecognizer(press)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        tap.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
        pdfView.addGestureRecognizer(tap)

        let undo = UITapGestureRecognizer(target: self, action: #selector(undoTap))
        undo.numberOfTouchesRequired = 2
        undo.delegate = self
        pdfView.addGestureRecognizer(undo)

        let redo = UITapGestureRecognizer(target: self, action: #selector(redoTap))
        redo.numberOfTouchesRequired = 3
        redo.delegate = self
        pdfView.addGestureRecognizer(redo)
    }

    @objc private func undoTap() { if model.undoManager.canUndo { model.undoManager.undo() } }
    @objc private func redoTap() { if model.undoManager.canRedo { model.undoManager.redo() } }

    @objc private func pageChanged() {
        guard let page = pdfView.currentPage else { return }
        model.canvasDidChangePage(to: model.pdf.index(for: page))
    }

    /// Long-press selects the word under the finger; dragging extends the selection, across pages too.
    private var selectionAnchor: (page: PDFPage, point: CGPoint)?

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        let location = gesture.location(in: pdfView)
        guard let page = pdfView.page(for: location, nearest: true) else { return }
        let point = pdfView.convert(location, to: page)

        switch gesture.state {
        case .began:
            markMenu.dismissMenu()
            selectionAnchor = (page, point)
            if let word = page.selectionForWord(at: point), !(word.string ?? "").isEmpty {
                pdfView.setCurrentSelection(word, animate: false)
            }
        case .changed:
            guard let anchor = selectionAnchor else { return }
            if let selection = model.pdf.selection(from: anchor.page, at: anchor.point, to: page, at: point),
               !(selection.string ?? "").isEmpty {
                pdfView.setCurrentSelection(selection, animate: false)
            }
        case .ended:
            selectionAnchor = nil
            if pdfView.currentSelection != nil { showSelectionMenu(at: location) }
        default:
            selectionAnchor = nil
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: pdfView)
        if let page = pdfView.page(for: location, nearest: false),
           let annotation = page.annotation(at: pdfView.convert(location, to: page)) {
            if let id = markByAnnotation[ObjectIdentifier(annotation)] {
                let config = UIEditMenuConfiguration(identifier: id as NSString, sourcePoint: location)
                markMenu.presentEditMenu(with: config)
                return
            }
            if follow(annotation) { return }
        }
        // A tap that dismisses a text selection shouldn't also toggle chrome.
        if pdfView.currentSelection != nil {
            pdfView.clearSelection()
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) { model.toggleChrome() }
    }

    /// Follows link annotations (internal references and web links).
    private func follow(_ annotation: PDFAnnotation) -> Bool {
        if let destination = annotation.destination {
            pdfView.go(to: destination)
            return true
        }
        switch annotation.action {
        case let goTo as PDFActionGoTo:
            pdfView.go(to: goTo.destination)
            return true
        case let link as PDFActionURL:
            if let url = link.url { UIApplication.shared.open(url) }
            return true
        default:
            if let url = annotation.url {
                UIApplication.shared.open(url)
                return true
            }
            return false
        }
    }
}

extension ReaderCanvasController: UIEditMenuInteractionDelegate {
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let id = configuration.identifier as? String else { return nil }
        if id == Self.selectionMenuID as String {
            guard let selection = pdfView.currentSelection else { return nil }
            let copy = UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = selection.string
            }
            return UIMenu(children: selectionMenuItems() + [copy])
        }
        guard let mark = model.highlights[id] else { return nil }
        return markMenu(for: mark)
    }
}

extension ReaderCanvasController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// PDFView that adds our actions to the text-selection edit menu.
final class ReaderPDFView: PDFView {
    var selectionMenuItems: () -> [UIMenuElement] = { [] }

    override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)
        let items = selectionMenuItems()
        guard !items.isEmpty else { return }
        builder.insertChild(UIMenu(options: .displayInline, children: items), atStartOfMenu: .root)
    }
}

struct ReaderCanvas: UIViewControllerRepresentable {
    let model: ReaderModel

    func makeUIViewController(context: Context) -> ReaderCanvasController {
        ReaderCanvasController(model: model)
    }

    func updateUIViewController(_ controller: ReaderCanvasController, context: Context) {}
}
