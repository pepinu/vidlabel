//
//  UndoManager.swift
//  VidLabel
//
//  Undo/Redo system for annotations
//

import Foundation

/// Represents an undoable action
protocol UndoAction {
    func undo(viewModel: AnnotationViewModel)
    func redo(viewModel: AnnotationViewModel)
    var description: String { get }
}

/// Action: Add annotation
struct AddAnnotationAction: UndoAction {
    let objectId: UUID
    let frameNumber: Int
    let boundingBox: BoundingBox

    func undo(viewModel: AnnotationViewModel) {
        viewModel.removeAnnotation(at: frameNumber, objectId: objectId)
    }

    func redo(viewModel: AnnotationViewModel) {
        viewModel.addAnnotation(boundingBox: boundingBox, frameNumber: frameNumber, objectId: objectId)
    }

    var description: String {
        "Add annotation at frame \(frameNumber)"
    }
}

/// Action: Remove annotation
struct RemoveAnnotationAction: UndoAction {
    let objectId: UUID
    let frameNumber: Int
    let boundingBox: BoundingBox

    func undo(viewModel: AnnotationViewModel) {
        viewModel.addAnnotation(boundingBox: boundingBox, frameNumber: frameNumber, objectId: objectId)
    }

    func redo(viewModel: AnnotationViewModel) {
        viewModel.removeAnnotation(at: frameNumber, objectId: objectId)
    }

    var description: String {
        "Remove annotation at frame \(frameNumber)"
    }
}

/// Action: Add object
struct AddObjectAction: UndoAction {
    let object: TrackedObject

    func undo(viewModel: AnnotationViewModel) {
        viewModel.deleteObject(id: object.id)
    }

    func redo(viewModel: AnnotationViewModel) {
        viewModel.addExistingObject(object)
    }

    var description: String {
        "Add object '\(object.label)'"
    }
}

/// Action: Delete object
struct DeleteObjectAction: UndoAction {
    let object: TrackedObject

    func undo(viewModel: AnnotationViewModel) {
        viewModel.addExistingObject(object)
    }

    func redo(viewModel: AnnotationViewModel) {
        viewModel.deleteObject(id: object.id)
    }

    var description: String {
        "Delete object '\(object.label)'"
    }
}

/// Action: Batch add annotations (for tracking/interpolation)
struct BatchAddAnnotationsAction: UndoAction {
    let objectId: UUID
    let annotations: [Int: BoundingBox] // frame -> box

    func undo(viewModel: AnnotationViewModel) {
        for frame in annotations.keys {
            viewModel.removeAnnotation(at: frame, objectId: objectId)
        }
    }

    func redo(viewModel: AnnotationViewModel) {
        for (frame, box) in annotations {
            viewModel.addAnnotation(boundingBox: box, frameNumber: frame, objectId: objectId)
        }
    }

    var description: String {
        "Add \(annotations.count) annotations"
    }
}

/// Action: Trim annotations
struct TrimAnnotationsAction: UndoAction {
    let objectId: UUID
    let removedAnnotations: [Int: BoundingBox]
    let isBefore: Bool
    let cutFrame: Int

    func undo(viewModel: AnnotationViewModel) {
        for (frame, box) in removedAnnotations {
            viewModel.addAnnotation(boundingBox: box, frameNumber: frame, objectId: objectId)
        }
    }

    func redo(viewModel: AnnotationViewModel) {
        if isBefore {
            viewModel.trimAnnotationsBefore(objectId: objectId, frameNumber: cutFrame)
        } else {
            viewModel.trimAnnotationsAfter(objectId: objectId, frameNumber: cutFrame)
        }
    }

    var description: String {
        let direction = isBefore ? "before" : "after"
        return "Trim \(removedAnnotations.count) annotations \(direction) frame \(cutFrame)"
    }
}

/// Manages undo/redo history
class UndoRedoManager: ObservableObject {
    @Published var undoStack: [UndoAction] = []
    @Published var redoStack: [UndoAction] = []

    private let maxHistorySize = 100

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    func recordAction(_ action: UndoAction) {
        undoStack.append(action)
        redoStack.removeAll() // Clear redo stack on new action

        // Limit history size
        if undoStack.count > maxHistorySize {
            undoStack.removeFirst()
        }

        print("📝 Recorded: \(action.description) (undo stack: \(undoStack.count))")
    }

    func undo(viewModel: AnnotationViewModel) {
        guard let action = undoStack.popLast() else { return }
        action.undo(viewModel: viewModel)
        redoStack.append(action)
        print("↩️ Undo: \(action.description)")
    }

    func redo(viewModel: AnnotationViewModel) {
        guard let action = redoStack.popLast() else { return }
        action.redo(viewModel: viewModel)
        undoStack.append(action)
        print("↪️ Redo: \(action.description)")
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
