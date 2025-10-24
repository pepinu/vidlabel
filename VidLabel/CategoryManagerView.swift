//
//  CategoryManagerView.swift
//  VidLabel
//
//  Category management interface for creating, editing, and deleting categories
//

import SwiftUI

struct CategoryManagerView: View {
    @ObservedObject var annotationVM: AnnotationViewModel
    @Environment(\.dismiss) var dismiss

    @State private var showAddSheet = false
    @State private var editingCategory: ObjectCategory?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Categories")
                    .font(.headline)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Categories list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(annotationVM.categories) { category in
                        CategoryRowView(
                            category: category,
                            onEdit: {
                                editingCategory = category
                            },
                            onDelete: {
                                annotationVM.deleteCategory(id: category.id)
                            }
                        )
                    }
                }
                .padding()
            }

            Divider()

            // Bottom buttons
            HStack(spacing: 12) {
                Button(action: {
                    annotationVM.resetCategoriesToDefault()
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset to Defaults")
                    }
                }
                .buttonStyle(.bordered)
                .help("Reset to default 8 categories")

                Spacer()

                Button(action: {
                    showAddSheet = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Category")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 500, height: 400)
        .sheet(isPresented: $showAddSheet) {
            CategoryEditSheet(
                category: nil,
                existingCategories: annotationVM.categories,
                onSave: { name, supercategory, color in
                    annotationVM.addCategory(name: name, supercategory: supercategory, color: color)
                    showAddSheet = false
                },
                onCancel: {
                    showAddSheet = false
                }
            )
        }
        .sheet(item: $editingCategory) { category in
            CategoryEditSheet(
                category: category,
                existingCategories: annotationVM.categories,
                onSave: { name, supercategory, color in
                    annotationVM.updateCategory(id: category.id, name: name, supercategory: supercategory, color: color)
                    editingCategory = nil
                },
                onCancel: {
                    editingCategory = nil
                }
            )
        }
    }
}

struct CategoryRowView: View {
    let category: ObjectCategory
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Color indicator
            Circle()
                .fill(Color(red: category.color.red,
                          green: category.color.green,
                          blue: category.color.blue))
                .frame(width: 20, height: 20)

            // Name and supercategory
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.body)
                    .fontWeight(.medium)

                if let supercategory = category.supercategory {
                    Text("Supercategory: \(supercategory)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Edit button
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Edit category")

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Delete category")
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

struct CategoryEditSheet: View {
    let category: ObjectCategory? // nil for new category
    let existingCategories: [ObjectCategory]
    let onSave: (String, String?, CodableColor) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var supercategory: String
    @State private var selectedColor: Color

    init(category: ObjectCategory?, existingCategories: [ObjectCategory], onSave: @escaping (String, String?, CodableColor) -> Void, onCancel: @escaping () -> Void) {
        self.category = category
        self.existingCategories = existingCategories
        self.onSave = onSave
        self.onCancel = onCancel

        _name = State(initialValue: category?.name ?? "")
        _supercategory = State(initialValue: category?.supercategory ?? "")
        _selectedColor = State(initialValue: category != nil ?
            Color(red: category!.color.red, green: category!.color.green, blue: category!.color.blue) :
            Color.blue)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(category == nil ? "Add New Category" : "Edit Category")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                // Name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Category Name:")
                        .font(.subheadline)
                    TextField("e.g., Bicycle", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                // Supercategory
                VStack(alignment: .leading, spacing: 4) {
                    Text("Supercategory (optional):")
                        .font(.subheadline)
                    TextField("e.g., Vehicle", text: $supercategory)
                        .textFieldStyle(.roundedBorder)
                }

                // Color picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Color:")
                        .font(.subheadline)
                    ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                        .labelsHidden()
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])

                Button(category == nil ? "Add" : "Save") {
                    guard !name.isEmpty else { return }

                    let components = selectedColor.cgColor?.components ?? [0.5, 0.5, 0.5, 1.0]
                    let codableColor = CodableColor(
                        red: Double(components[0]),
                        green: Double(components[1]),
                        blue: Double(components[2])
                    )

                    let finalSupercategory = supercategory.isEmpty ? nil : supercategory
                    onSave(name, finalSupercategory, codableColor)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(24)
        .frame(width: 400, height: 300)
    }
}
